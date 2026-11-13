local DataStorage = require("datastorage")
local dump = require("dump")
local ffiutil = require("ffi/util")
local gettext = require("gettext")
local lfs = require("libs/libkoreader-lfs")
local util = require("util")

local history_file = ffiutil.joinPath(DataStorage:getDataDir(), "history.lua")
local sdr_list_file =
  ffiutil.joinPath(DataStorage:getDataDir(), "sdr_list.lua")

local ignore_patterns = {
  "^batterystat%.log$",
  "^crash%.log$",
  "^crash%.prev%.log$",
  "^koreader%.crash%..*%.log$",
  "^quickstart%-.*%.html$",
}

local SdrList = {
  files = {},
  last_read_time = 0,
  seeded = false,
}

local function normalizePath(file)
  return ffiutil.realpath(file) or file
end

local function scanMetadataFiles(root, extractor, out_files, sdr_list)
  local p = io.popen(util.shell_escape({ "find", root, "-name", "metadata.*.lua" }))
  if not p then
    return false
  end
  for line in p:lines() do
    local doc_path, replaced = extractor(line)
    if replaced > 0 and doc_path ~= "" and not sdr_list:ignorePath(doc_path) then
      if util.fileExists(doc_path) then
        out_files[normalizePath(doc_path)] = true
      end
    end
  end
  p:close()
  return true
end

function SdrList:ignoreFile(file)
  local filename = ffiutil.basename(file)
  if not require("ui/widget/filechooser"):show_file(filename) then
    return true
  end
  for _, pattern in ipairs(ignore_patterns) do
    if filename:match(pattern) then
      return true
    end
  end
  return false
end

function SdrList:ignorePath(file)
  local FileChooser = require("ui/widget/filechooser")
  local dir = ffiutil.dirname(normalizePath(file))
  local raw_home = G_named_settings.home_dir()
  local stop_dir
  if raw_home and raw_home ~= "" then
    local norm_home = normalizePath(raw_home):gsub("/+$", "")
    local clean_home = raw_home:gsub("/+$", "")
    if norm_home ~= "" and util.stringStartsWith(dir, norm_home .. "/") then
      stop_dir = norm_home
    elseif
      clean_home ~= ""
      and util.stringStartsWith(dir, clean_home .. "/")
    then
      stop_dir = clean_home
    end
  end
  if stop_dir then
    while dir ~= stop_dir and dir ~= "." and dir ~= "/" do
      if not FileChooser:show_dir(ffiutil.basename(dir)) then
        return true
      end
      dir = ffiutil.dirname(dir)
    end
  elseif
    dir ~= "."
    and dir ~= "/"
    and not FileChooser:show_dir(ffiutil.basename(dir))
  then
    return true
  end
  return self:ignoreFile(file)
end

function SdrList:_flush()
  local content = {}
  for file in pairs(self.files) do
    table.insert(content, file)
  end
  table.sort(content)
  if util.writeToFile(dump(content), sdr_list_file, true) then
    local attr = lfs.attributes(sdr_list_file)
    if attr then
      self.last_read_time = attr.modification
    end
    return true
  end
  require("ui/widget/notification"):notify(
    gettext("Failed to save reading status collection index.")
  )
  return false
end

function SdrList:_seedFromReadHistory()
  local DocSettings = require("docsettings")
  local hist_entries
  local loaded_history = package.loaded["readhistory"]
  if loaded_history then
    hist_entries = loaded_history.hist
  elseif util.fileExists(history_file) then
    local ok, data = pcall(dofile, history_file)
    if ok and type(data) == "table" then
      hist_entries = data
    end
  end
  self.files = {}
  if hist_entries then
    for _, v in ipairs(hist_entries) do
      local file = v.file and normalizePath(v.file)
      if
        file
        and file ~= ""
        and not self:ignorePath(file)
        and DocSettings:hasSidecarFile(file)
      then
        self.files[file] = true
      end
    end
  end
  self.seeded = true
  return self:_flush()
end

function SdrList:reload(force_read)
  local attr = lfs.attributes(sdr_list_file)
  if not attr then
    if not self.seeded then
      return self:_seedFromReadHistory()
    end
    return false
  end
  if not force_read and attr.modification <= self.last_read_time then
    return false
  end
  local ok, stored = pcall(dofile, sdr_list_file)
  if ok and type(stored) == "table" then
    self.files = {}
    for _, path in ipairs(stored) do
      if type(path) == "string" and path ~= "" then
        self.files[path] = true
      end
    end
    self.seeded = true
    self.last_read_time = attr.modification
    return true
  end
  require("ui/widget/notification"):notify(
    gettext("Failed to load reading status collection index.")
  )
  return false
end

function SdrList:getFiles()
  self:reload()
  local files = {}
  for file in pairs(self.files) do
    table.insert(files, file)
  end
  table.sort(files)
  return files
end

function SdrList:addItem(file)
  assert(
    type(file) == "string" and file ~= "",
    "SdrList: file must not be nil or empty"
  )
  self:reload()
  file = normalizePath(file)
  if self.files[file] or self:ignorePath(file) then
    return false
  end
  self.files[file] = true
  return self:_flush()
end

function SdrList:removeItem(file)
  assert(
    type(file) == "string" and file ~= "",
    "SdrList: file must not be nil or empty"
  )
  self:reload()
  file = normalizePath(file)
  if not self.files[file] then
    return false
  end
  self.files[file] = nil
  return self:_flush()
end

function SdrList:updateItem(old_file, new_file, copy)
  assert(
    type(old_file) == "string" and old_file ~= "",
    "SdrList: old_file must not be nil or empty"
  )
  assert(
    type(new_file) == "string" and new_file ~= "",
    "SdrList: new_file must not be nil or empty"
  )
  self:reload()
  old_file = normalizePath(old_file)
  new_file = normalizePath(new_file)
  local changed = false
  if not copy and old_file ~= new_file and self.files[old_file] then
    self.files[old_file] = nil
    changed = true
  end
  if not self.files[new_file] and not self:ignorePath(new_file) then
    self.files[new_file] = true
    changed = true
  end
  if changed then
    return self:_flush()
  end
  return false
end

function SdrList:updateItemsByPath(old_path, new_path, copy)
  self:reload()
  local old_prefix = normalizePath(old_path):gsub("/+$", "") .. "/"
  local new_prefix = normalizePath(new_path):gsub("/+$", "") .. "/"
  local prefix_len = #old_prefix
  local to_remove = {}
  local to_add = {}
  local DocSettings = copy and require("docsettings")
  for file in pairs(self.files) do
    if file:sub(1, prefix_len) == old_prefix then
      if not copy then
        table.insert(to_remove, file)
      end
      local updated = normalizePath(new_prefix .. file:sub(prefix_len + 1))
      if
        not self.files[updated]
        and not self:ignorePath(updated)
        and (not copy or DocSettings:hasSidecarFile(updated))
      then
        table.insert(to_add, updated)
      end
    end
  end
  if #to_remove == 0 and #to_add == 0 then
    return false
  end
  for _, file in ipairs(to_remove) do
    self.files[file] = nil
  end
  for _, file in ipairs(to_add) do
    self.files[file] = true
  end
  return self:_flush()
end

function SdrList:removeItemsByPath(path)
  self:reload()
  local prefix = normalizePath(path):gsub("/+$", "") .. "/"
  local prefix_len = #prefix
  local to_remove = {}
  for file in pairs(self.files) do
    if file:sub(1, prefix_len) == prefix then
      table.insert(to_remove, file)
    end
  end
  if #to_remove == 0 then
    return false
  end
  for _, file in ipairs(to_remove) do
    self.files[file] = nil
  end
  return self:_flush()
end

function SdrList:rebuildFromDisk()
  self:reload()
  local DocSettings = require("docsettings")
  local new_files = {}
  if
    not scanMetadataFiles(
      G_named_settings.home_dir(),
      function(line)
        return line:gsub("%.sdr/metadata(%.[^/%.]+)%.lua$", "%1")
      end,
      new_files,
      self
    )
  then
    require("ui/widget/notification"):notify(
      gettext("Failed to scan metadata files for reading status collections.")
    )
    return false
  end
  local docsettings_dir = DataStorage:getDocSettingsDir():gsub("/+$", "")
  if util.directoryExists(docsettings_dir) then
    local prefix_len = #docsettings_dir
    if
      not scanMetadataFiles(
        docsettings_dir,
        function(line)
          if
            line:sub(1, prefix_len) == docsettings_dir
            and line:sub(prefix_len + 1, prefix_len + 1) == "/"
          then
            return line:sub(prefix_len + 1):gsub(
              "%.sdr/metadata(%.[^/%.]+)%.lua$",
              "%1"
            )
          end
          return line, 0
        end,
        new_files,
        self
      )
    then
      require("ui/widget/notification"):notify(
        gettext("Failed to scan metadata files for reading status collections.")
      )
      return false
    end
  end
  -- Preserve valid hash-located entries that cannot be reversed from disk hashes.
  for file in pairs(self.files) do
    if
      not new_files[file]
      and not self:ignorePath(file)
      and util.fileExists(file)
      and DocSettings:hasSidecarFile(file)
    then
      new_files[file] = true
    end
  end
  self.files = new_files
  self.seeded = true
  return self:_flush()
end

return SdrList
