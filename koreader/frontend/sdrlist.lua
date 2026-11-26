local DataStorage = require("datastorage")
local dump = require("dump")
local ffiutil = require("ffi/util")
local gettext = require("gettext")
local lfs = require("libs/libkoreader-lfs")
local util = require("util")

local sdr_list_file =
  ffiutil.joinPath(DataStorage:getDataDir(), "sdr_list.lua")

local SdrList = {
  files = {},
  last_read_time = 0,
  seeded = false,
}

local function normalizePath(file)
  return ffiutil.realpath(file) or file
end

local function scanMetadataFiles(root, extractor, out_files)
  util.findFiles(root, function(path)
    local doc_path, replaced = extractor(path)
    if replaced > 0 and doc_path ~= "" and util.fileExists(doc_path) then
      doc_path = normalizePath(doc_path)
      if not require("readhistory"):ignoreItem(doc_path) then
        out_files[doc_path] = true
      end
    end
  end)
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
  local ReadHistory = require("readhistory")
  self.files = {}
  for _, v in ipairs(ReadHistory.hist) do
    local file = v.file and normalizePath(v.file)
    if
      file
      and file ~= ""
      and not ReadHistory:ignoreItem(file)
      and require("docsettings"):hasSidecarFile(file)
    then
      self.files[file] = true
    end
  end
  self.seeded = true
  return self:_flush()
end

function SdrList:reload()
  local attr = lfs.attributes(sdr_list_file)
  if not attr then
    if not self.seeded then
      return self:_seedFromReadHistory()
    end
    return false
  end
  if attr.modification <= self.last_read_time then
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
  if self.files[file] or require("readhistory"):ignoreItem(file) then
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
  if
    not self.files[new_file]
    and not require("readhistory"):ignoreItem(new_file)
    and require("docsettings"):hasSidecarFile(new_file)
  then
    self.files[new_file] = true
    changed = true
  end
  if changed then
    return self:_flush()
  end
  return false
end

function SdrList:updateItemsByPath(old_path, new_path, copy)
  assert(
    type(old_path) == "string" and old_path ~= "",
    "SdrList: old_path must not be nil or empty"
  )
  assert(
    type(new_path) == "string" and new_path ~= "",
    "SdrList: new_path must not be nil or empty"
  )
  self:reload()
  local old_prefix = normalizePath(old_path):gsub("/+$", "") .. "/"
  local new_prefix = normalizePath(new_path):gsub("/+$", "") .. "/"
  local prefix_len = #old_prefix
  local to_remove = {}
  local to_add = {}
  for file in pairs(self.files) do
    if file:sub(1, prefix_len) == old_prefix then
      if not copy then
        table.insert(to_remove, file)
      end
      local updated = normalizePath(new_prefix .. file:sub(prefix_len + 1))
      if
        not self.files[updated]
        and not require("readhistory"):ignoreItem(updated)
        and require("docsettings"):hasSidecarFile(updated)
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
  assert(
    type(path) == "string" and path ~= "",
    "SdrList: path must not be nil or empty"
  )
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
  local new_files = {}
  scanMetadataFiles(
    G_named_settings.home_dir():gsub("(.+)/+$", "%1"),
    function(path)
      return path:gsub("%.sdr/metadata(%.[^/%.]+)%.lua$", "%1")
    end,
    new_files
  )
  local docsettings_dir = DataStorage:getDocSettingsDir():gsub("/+$", "")
  scanMetadataFiles(docsettings_dir, function(path)
    return path
      :sub(#docsettings_dir + 1)
      :gsub("%.sdr/metadata(%.[^/%.]+)%.lua$", "%1")
  end, new_files)
  -- Preserve valid hash-located entries that cannot be reversed from disk hashes.
  for file in pairs(self.files) do
    if
      not new_files[file]
      and not require("readhistory"):ignoreItem(file)
      and util.fileExists(file)
      and require("docsettings"):hasSidecarFile(file)
    then
      new_files[file] = true
    end
  end
  self.files = new_files
  self.seeded = true
  return self:_flush()
end

return SdrList
