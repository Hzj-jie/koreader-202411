--[[--
This module is responsible for reading and writing `metadata.lua` files
in the so-called sidecar directory
([Wikipedia definition](https://en.wikipedia.org/wiki/Sidecar_file)).
]]

local CachedTable = require("cachedtable")
local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")
local dump = require("dump")
local ffiutil = require("ffi/util")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local util = require("util")

local DocSettings = LuaSettings:extend({})

local HISTORY_DIR = DataStorage:getHistoryDir()
local DOCSETTINGS_DIR = DataStorage:getDocSettingsDir()
local DOCSETTINGS_HASH_DIR = DataStorage:getDocSettingsHashDir()
local custom_metadata_filename = "custom_metadata.lua"

function DocSettings.getSidecarStorage(location)
  if location == "dir" then
    return DOCSETTINGS_DIR
  elseif location == "hash" then
    return DOCSETTINGS_HASH_DIR
  else
    assert(false, "Invalid sidecar storage location: " .. tostring(location))
  end
end

local is_history_location_enabled = util.directoryExists(HISTORY_DIR)

local doc_hash_cache = {}

function DocSettings.isHashLocationEnabled()
  return util.directoryExists(DOCSETTINGS_HASH_DIR)
end

--- Cleans up DOCSETTINGS_HASH_DIR if it contains no files.
-- Uses util.isDirContainingFiles to probe for any files in the tree.
-- If no files exist in the tree at all, removes the empty directory tree bottom-up.
function DocSettings.cleanHashLocationIfEmpty()
  if not util.isDirContainingFiles(DOCSETTINGS_HASH_DIR) then
    local ok, err = util.removeEmptyTree(DOCSETTINGS_HASH_DIR)
    if not ok and err then
      logger.warn("DocSettings: failed to clean empty hash directory:", err)
    end
  end
end

-- Lazily requires UI components to prevent cyclic dependencies when DocSettings
-- is loaded early or in headless environments.
-- String literals are kept directly inside gettext() calls here so that
-- xgettext (update-po.sh) can statically extract them into translation templates.
local function notifyUser(reason)
  local gettext = require("gettext")

  local text
  if reason == "tmp" then
    text = gettext(
      "Storage is read-only. Reading progress for this book will be saved to temporary storage and may be lost."
    )
  elseif reason == "fallback" then
    text = gettext(
      "The selected storage for book settings is read-only. Settings for this book will be saved to an alternate storage location instead."
    )
  elseif reason == "readonly" then
    text = gettext(
      "Storage is completely read-only. Reading progress for this book cannot be saved to disk."
    )
  else
    text = reason
  end
  require("ui/uimanager"):show(
    require("ui/widget/notification"):new({ text = text })
  )
end

function DocSettings.getSidecarFilename(doc_path)
  local suffix = doc_path:match(".*%.(.+)") or "_"
  return "metadata." .. suffix .. ".lua"
end

function DocSettings:getHistoryPath(doc_path)
  if doc_path == nil or doc_path == "" then
    return ""
  end
  return HISTORY_DIR
    .. "/["
    .. doc_path:gsub("(.*/)([^/]+)", "%1] %2"):gsub("/", "#")
    .. ".lua"
end

function DocSettings:getPathFromHistory(hist_name)
  if hist_name == nil or hist_name == "" then
    return ""
  end
  if hist_name:sub(-4) ~= ".lua" then
    return ""
  end -- ignore .lua.old backups
  -- 1. select everything included in brackets
  local s = string.match(hist_name, "%b[]")
  if s == nil or s == "" then
    return ""
  end
  -- 2. crop the bracket-sign from both sides
  -- 3. and finally replace decorative signs '#' to dir-char '/'
  return string.gsub(string.sub(s, 2, -3), "#", "/")
end

function DocSettings:getNameFromHistory(hist_name)
  if hist_name == nil or hist_name == "" then
    return ""
  end
  if hist_name:sub(-4) ~= ".lua" then
    return ""
  end -- ignore .lua.old backups
  local s = string.match(hist_name, "%b[]")
  if s == nil or s == "" then
    return ""
  end
  -- at first, search for path length
  -- and return the rest of string without 4 last characters (".lua")
  return string.sub(hist_name, string.len(s) + 2, -5)
end

function DocSettings:getFileFromHistory(hist_name)
  local path = self:getPathFromHistory(hist_name)
  if path ~= "" then
    local name = self:getNameFromHistory(hist_name)
    if name ~= "" then
      return ffiutil.joinPath(path, name)
    end
  end
end

local function getCandidates(doc_path)
  if not doc_path or doc_path == "" then
    return {}
  end

  local stem = doc_path:match("(.*)%.") or doc_path -- file path without the last suffix
  local sidecar_filename = DocSettings.getSidecarFilename(doc_path)

  local doc_dir = stem .. ".sdr"
  local doc_cand = {
    file = doc_dir .. "/" .. sidecar_filename,
    dir = doc_dir,
    location = "doc",
  }
  local dir_dir = DOCSETTINGS_DIR .. stem .. ".sdr"
  local dir_cand = {
    file = dir_dir .. "/" .. sidecar_filename,
    dir = dir_dir,
    location = "dir",
  }
  local preferred_location = G_named_settings.document_metadata_folder()
  local hash_cand
  if preferred_location == "hash" or DocSettings.isHashLocationEnabled() then
    hash_cand = CachedTable:new(function()
      local hsh = doc_hash_cache[doc_path]
      if not hsh then
        hsh = util.partialMD5(doc_path)
        if hsh then
          doc_hash_cache[doc_path] = hsh
          logger.dbg(
            "DocSettings: Caching new partial MD5 hash for",
            doc_path,
            "as",
            hsh
          )
        end
      else
        logger.dbg(
          "DocSettings: Using cached partial MD5 hash for",
          doc_path,
          "as",
          hsh
        )
      end
      if hsh then
        -- converts b3fb8f4f8448160365087d6ca05c7fa2 to b3/ to avoid too many files in one dir
        local subpath = string.format("/%s/", hsh:sub(1, 2))
        local hash_dir = DOCSETTINGS_HASH_DIR .. subpath .. hsh .. ".sdr"
        return {
          file = hash_dir .. "/" .. sidecar_filename,
          dir = hash_dir,
        }
      end
    end, { location = "hash" })
  end

  local candidates
  if preferred_location == "hash" then
    candidates = hash_cand and { hash_cand, dir_cand, doc_cand }
      or { dir_cand, doc_cand }
  elseif preferred_location == "dir" then
    candidates = hash_cand and { dir_cand, hash_cand, doc_cand }
      or { dir_cand, doc_cand }
  else
    candidates = hash_cand and { doc_cand, dir_cand, hash_cand }
      or { doc_cand, dir_cand }
  end

  -- Legacy sidecar format: early KOReader versions stored settings as
  -- `<stem>.sdr/<basename>.lua` before standardizing on `metadata.<ext>.lua`.
  -- This legacy format only ever existed directly next to the document.
  -- If doc_path is named metadata.<ext>, basename.lua is identical to
  -- metadata.<ext>.lua, so omit doc_legacy_file to prevent duplicates.
  local doc_legacy_file = doc_dir .. "/" .. ffiutil.basename(doc_path) .. ".lua"
  if doc_legacy_file ~= doc_cand.file then
    table.insert(candidates, {
      file = doc_legacy_file,
      -- Note: without `dir`, the candidate is read-only.
      location = "doc",
    })
  end

  -- Note: "hist", "kpdfview", and "tmp" are internal location identifiers
  -- used for code clarity and diagnostics, not configurable user options in G_named_settings.
  if is_history_location_enabled then
    table.insert(candidates, {
      file = DocSettings:getHistoryPath(doc_path),
      location = "hist",
    })
  end
  table.insert(candidates, {
    file = doc_path .. ".kpdfview.lua",
    location = "kpdfview",
  })
  local base_tmp = DataStorage:getTmpDir()
  if base_tmp and base_tmp ~= DataStorage:getDataDir() then
    local tmp_dir = base_tmp
      .. "/docsettings"
      .. (stem:sub(1, 1) == "/" and stem or ("/" .. stem))
      .. ".sdr"
    table.insert(candidates, {
      file = tmp_dir .. "/" .. sidecar_filename,
      dir = tmp_dir,
      location = "tmp",
    })
  end

  local seen_files = {}
  for _, cand in ipairs(candidates) do
    if cand.location ~= "hash" then
      assert(
        cand.file and cand.file ~= "",
        "DocSettings: candidate file must not be nil or empty"
      )
      assert(
        not seen_files[cand.file],
        "DocSettings: duplicate candidate file: " .. tostring(cand.file)
      )
      seen_files[cand.file] = true
    end
  end

  return candidates
end

-- TODO: For testing purposes only, should be removed once external tests are migrated.
function DocSettings:getSidecarDir(doc_path)
  local cands = getCandidates(doc_path)
  return cands[1] and cands[1].dir
end

--- Returns `true` if there is a `metadata.lua` file.
-- @string doc_path path to the document (e.g., `/foo/bar.pdf`)
-- @treturn bool
function DocSettings:hasSidecarFile(doc_path)
  return self:findSidecarFile(doc_path) and true or false
end

--- Returns path of sidecar file if it exists, or nil.
-- @string doc_path path to the document (e.g., `/foo/bar.pdf`)
-- @treturn string (or nil on failure)
-- @treturn string location identifier
function DocSettings:findSidecarFile(doc_path)
  if doc_path == nil or doc_path == "" then
    return
  end
  for _, cand in ipairs(getCandidates(doc_path)) do
    if util.fileExists(cand.file) then
      return cand.file, cand.location
    end
  end
end

function DocSettings.isSidecarFileNotInPreferredLocation(doc_path)
  local _, location = DocSettings:findSidecarFile(doc_path)
  return location ~= nil
    and location ~= G_named_settings.document_metadata_folder()
end

--- Opens a document's individual settings (font, margin, dictionary, etc.)
-- @string doc_path path to the document (e.g., `/foo/bar.pdf`)
-- @treturn DocSettings object
function DocSettings:open(doc_path)
  -- NOTE: Beware, our new instance is new, but self is still DocSettings!
  local new = DocSettings:extend({})

  if not doc_path or doc_path == "" then
    new.data = {}
    new.candidates = {}
    return new
  end

  new.doc_path = doc_path
  new.sidecar_filename = DocSettings.getSidecarFilename(doc_path)
  new.candidates = getCandidates(doc_path)

  local existing = {}
  for i, cand in ipairs(new.candidates) do
    if util.fileExists(cand.file) then
      local mtime = lfs.attributes(cand.file, "modification")
      table.insert(existing, {
        cand = cand,
        mtime = mtime,
        prio = i,
      })
    end
  end

  -- MRU sort, tie breaker is insertion order (higher priority locations were inserted first).
  table.sort(existing, function(l, r)
    if l.mtime == r.mtime then
      return l.prio < r.prio
    else
      return l.mtime > r.mtime
    end
  end)

  local candidate_path, ok, stored
  for _, t in ipairs(existing) do
    candidate_path = t.cand.file
    stored, ok = LuaSettings:load(candidate_path)
    -- Ignore empty tables
    if ok and next(stored) ~= nil then
      logger.dbg("DocSettings: data is read from", candidate_path)
      break
    end
    logger.dbg("DocSettings:", candidate_path, "is invalid, removed.")
    os.remove(candidate_path)
  end
  if ok and next(stored) then
    new.data = stored
    new.file = candidate_path
  else
    new.data = {}
  end
  new.data.doc_path = doc_path

  return new
end

--- Light version of open(). Opens a sidecar file or a custom metadata file.
-- Returned object cannot be used to save changes to the sidecar file (flush()).
-- Must be used to save changes to the custom metadata file (flushCustomMetadata()).
function DocSettings.openSettingsFile(sidecar_file)
  local new = DocSettings:extend({})
  local ok, stored
  if sidecar_file then
    ok, stored = pcall(dofile, sidecar_file)
  end
  if ok and next(stored) ~= nil then
    new.data = stored
  else
    new.data = {}
  end
  new.file = sidecar_file
  new.candidates = {}
  return new
end

--- Serializes settings and writes them to `metadata.lua`.
function DocSettings:flush(data, no_custom_metadata)
  data = data or self.data
  local preferred_location = G_named_settings.document_metadata_folder()
  local ser_data = dump(data)

  -- Always refresh candidates so order reflects current settings
  self.candidates = getCandidates(self.doc_path)

  for _, cand in ipairs(self.candidates) do
    if cand.dir and util.isDirRW(cand.dir, true) then
      logger.dbg("DocSettings: Writing to", cand.file)
      if util.writeToFile(ser_data, cand.file, true) then
        if
          cand.location ~= preferred_location and not self.fallback_notified
        then
          notifyUser(cand.location == "tmp" and "tmp" or "fallback")
          self.fallback_notified = true
        end

        -- move custom cover file and custom metadata file to the metadata file location
        if not no_custom_metadata then
          local sidecar_dir_slash = cand.dir .. "/"
          local metadata_file, filepath, filename
          -- custom cover
          metadata_file = self:getCustomCoverFile()
          if metadata_file then
            filepath, filename = util.splitFilePathName(metadata_file)
            if filepath ~= sidecar_dir_slash then
              ffiutil.copyFile(metadata_file, sidecar_dir_slash .. filename)
              os.remove(metadata_file)
              self:getCustomCoverFile(true) -- reset cache
            end
          end
          -- custom metadata
          metadata_file = self:getCustomMetadataFile()
          if metadata_file then
            filepath, filename = util.splitFilePathName(metadata_file)
            if filepath ~= sidecar_dir_slash then
              ffiutil.copyFile(metadata_file, sidecar_dir_slash .. filename)
              os.remove(metadata_file)
              self:getCustomMetadataFile(true) -- reset cache
            end
          end
        end

        self:purge(cand.file) -- remove old candidates and empty sidecar folders

        return cand.dir
      end
    end
  end

  if not self.fallback_notified then
    notifyUser("readonly")
    self.fallback_notified = true
  end
  return nil
end

--- Purges (removes) sidecar directory.
function DocSettings:purge(sidecar_to_keep, data_to_purge)
  local custom_cover_file, custom_metadata_file
  if sidecar_to_keep == nil then
    custom_cover_file = self:getCustomCoverFile()
    custom_metadata_file = self:getCustomMetadataFile()
  end
  if data_to_purge == nil then -- purge all
    data_to_purge = {
      doc_settings = true,
      custom_cover_file = custom_cover_file,
      custom_metadata_file = custom_metadata_file,
    }
  end

  -- Remove any of the old ones we may consider as candidates in DocSettings:open()
  if data_to_purge.doc_settings then
    for _, cand in ipairs(self.candidates) do
      if util.fileExists(cand.file) then
        if not sidecar_to_keep or cand.file ~= sidecar_to_keep then
          os.remove(cand.file)
          logger.dbg("DocSettings: purged:", cand.file)
        end
      end
    end
  end

  -- Remove custom
  if data_to_purge.custom_cover_file then
    os.remove(data_to_purge.custom_cover_file)
    self:getCustomCoverFile(true) -- reset cache
  end
  if data_to_purge.custom_metadata_file then
    os.remove(data_to_purge.custom_metadata_file)
    self:getCustomMetadataFile(true) -- reset cache
  end

  -- Remove empty sidecar dirs
  if
    data_to_purge.doc_settings
    or data_to_purge.custom_cover_file
    or data_to_purge.custom_metadata_file
  then
    for _, cand in ipairs(self.candidates) do
      if cand.dir then
        DocSettings.removeSidecarDir(cand.dir)
      end
    end
  end
end

--- Removes sidecar dir iff empty.
function DocSettings.removeSidecarDir(dir)
  if dir and util.directoryExists(dir) then
    if
      util.stringStartsWith(dir, DOCSETTINGS_DIR)
      or util.stringStartsWith(dir, DOCSETTINGS_HASH_DIR)
    then
      util.removePath(dir) -- remove empty parent folders
    else
      os.remove(dir) -- keep parent folders
    end
  end
end

--- Updates sdr location for file rename/copy/move/delete operations.
function DocSettings.updateLocation(doc_path, new_doc_path, copy)
  local has_sidecar_file = DocSettings:hasSidecarFile(doc_path)
  local custom_cover_file = DocSettings:findCustomCoverFile(doc_path)
  local custom_metadata_file = DocSettings:findCustomMetadataFile(doc_path)
  if not (has_sidecar_file or custom_cover_file or custom_metadata_file) then
    return
  end

  local doc_settings = DocSettings:open(doc_path)
  local do_purge

  if new_doc_path then -- copy/rename/move
    if G_named_settings.document_metadata_folder() ~= "hash" then -- keep hash location unchanged
      local new_sidecar_dir
      if has_sidecar_file then
        local new_doc_settings = DocSettings:open(new_doc_path)
        doc_settings.data.doc_path = new_doc_path
        new_sidecar_dir = new_doc_settings:flush(doc_settings.data, true) -- without custom
      end
      if not new_sidecar_dir then
        for _, cand in ipairs(getCandidates(new_doc_path)) do
          if cand.dir and util.isDirRW(cand.dir, true) then
            new_sidecar_dir = cand.dir
            break
          end
        end
      end
      if new_sidecar_dir then
        if custom_cover_file then
          local _, filename = util.splitFilePathName(custom_cover_file)
          ffiutil.copyFile(
            custom_cover_file,
            new_sidecar_dir .. "/" .. filename
          )
        end
        if custom_metadata_file then
          ffiutil.copyFile(
            custom_metadata_file,
            new_sidecar_dir .. "/" .. custom_metadata_filename
          )
        end
        do_purge = not copy
      else
        local InfoMessage = require("ui/widget/infomessage")
        local UIManager = require("ui/uimanager")
        local gettext = require("gettext")
        UIManager:show(InfoMessage:new({
          text = gettext(
            "Failed to save book settings to the new location. Original settings have been preserved."
          ),
          icon = "notice-warning",
        }))
      end
    end
  else -- delete
    if has_sidecar_file then
      local cache_file_path = doc_settings:read("cache_file_path")
      if cache_file_path then
        os.remove(cache_file_path)
      end
    end
    do_purge = true
  end

  if do_purge then
    doc_settings.custom_cover_file = custom_cover_file -- cache
    doc_settings.custom_metadata_file = custom_metadata_file -- cache
    doc_settings:purge()
  end
end

-- custom section

function DocSettings:getCustomLocationCandidates(doc_path)
  local sidecar_file = self:findSidecarFile(doc_path)
  if sidecar_file then
    for _, cand in ipairs(getCandidates(doc_path)) do
      if cand.file == sidecar_file and cand.dir then
        return { cand.dir }
      end
    end
  end
  local candidates = {}
  for _, cand in ipairs(getCandidates(doc_path)) do
    if cand.dir then
      table.insert(candidates, cand.dir)
    end
  end
  return candidates
end

-- custom cover

local function findCustomCoverFileInDir(dir)
  local ok, iter, dir_obj = pcall(lfs.dir, dir)
  if ok then
    for f in iter, dir_obj do
      if util.splitFileNameSuffix(f) == "cover" then
        return dir .. "/" .. f
      end
    end
  end
end

--- Returns path to book custom cover file if it exists, or nil.
function DocSettings:findCustomCoverFile(doc_path)
  local candidates = doc_path and getCandidates(doc_path) or self.candidates
  for _, cand in ipairs(candidates) do
    if cand.dir and util.directoryExists(cand.dir) then
      local custom_cover_file = findCustomCoverFileInDir(cand.dir)
      if custom_cover_file then
        return custom_cover_file
      end
    end
  end
end

function DocSettings:getCustomCoverFile(reset_cache)
  if reset_cache then
    self.custom_cover_file = nil
  else
    if self.custom_cover_file == nil then -- fill empty cache
      self.custom_cover_file = self:findCustomCoverFile() or false
    end
    return self.custom_cover_file
  end
end

function DocSettings:flushCustomCover(doc_path, image_file)
  if util.isMonkeyTest() then
    logger.warn("Skipping custom cover flush in monkey test mode.")
    return
  end
  local sidecar_dirs = self:getCustomLocationCandidates(doc_path)
  local new_cover_filename = "/cover."
    .. util.getFileNameSuffix(image_file):lower()
  for _, sidecar_dir in ipairs(sidecar_dirs) do
    if util.isDirRW(sidecar_dir, true) then
      local new_cover_file = sidecar_dir .. new_cover_filename
      if ffiutil.copyFile(image_file, new_cover_file) == nil then
        return true
      end
    end
  end
end

-- custom metadata

--- Returns path to book custom metadata file if it exists, or nil.
function DocSettings:findCustomMetadataFile(doc_path)
  local candidates = doc_path and getCandidates(doc_path) or self.candidates
  for _, cand in ipairs(candidates) do
    if cand.dir then
      local custom_metadata_file = cand.dir .. "/" .. custom_metadata_filename
      if util.fileExists(custom_metadata_file) then
        return custom_metadata_file
      end
    end
  end
end

function DocSettings:getCustomMetadataFile(reset_cache)
  if reset_cache then
    self.custom_metadata_file = nil
  else
    if self.custom_metadata_file == nil then -- fill empty cache
      self.custom_metadata_file = self:findCustomMetadataFile() or false
    end
    return self.custom_metadata_file
  end
end

function DocSettings:flushCustomMetadata(doc_path)
  local sidecar_dirs = self:getCustomLocationCandidates(doc_path)
  local s_out = dump(self.data)
  for _, sidecar_dir in ipairs(sidecar_dirs) do
    if util.isDirRW(sidecar_dir, true) then
      local new_metadata_file = sidecar_dir .. "/" .. custom_metadata_filename
      if util.writeToFile(s_out, new_metadata_file, true) then
        return true
      end
    end
  end
end

-- "hash" section

-- Returns the list of tables { dir = ..., metadata = ..., custom_metadata = ..., cover = ... }.
-- Note: entries are grouped by content-hash directory (<partialMD5>.sdr). If multiple
-- documents share the same content hash (or have identical content under different extensions),
-- they resolve to the same sidecar directory and are reported as a single entry.
function DocSettings.findSidecarFilesInHashLocation()
  local by_dir = {}
  local dir_list = {}
  local callback = function(fullpath, name)
    local dir = fullpath:match("(.*)/[^/]*$")
    local entry = by_dir[dir]
    if not entry then
      entry = { dir = dir }
      by_dir[dir] = entry
      table.insert(dir_list, entry)
    end
    if name:match("^metadata%..+%.lua$") then
      entry.metadata = fullpath
    elseif name == custom_metadata_filename then
      entry.custom_metadata = fullpath
    elseif name:match("^cover%.") then
      entry.cover = fullpath
    end
  end
  util.findFiles(DOCSETTINGS_HASH_DIR, callback)
  local res = {}
  for _, entry in ipairs(dir_list) do
    if entry.metadata or entry.custom_metadata or entry.cover then
      table.insert(res, entry)
    end
  end
  return res
end

return DocSettings
