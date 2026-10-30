--[[--
@module ffi.archiver
]]

local ffi = require("ffi")
local libarchive = ffi.loadlib("archive", "13")
require("ffi/libarchive_h")
require("ffi/posix_h")

local function archive_error_string(archive)
  local err = libarchive.archive_error_string(archive)
  return err ~= nil and ffi.string(err) or nil
end

local ENTRY_MODE = {
  [libarchive.AE_IFREG] = "file",
  [libarchive.AE_IFLNK] = "link",
  [libarchive.AE_IFSOCK] = "socket",
  [libarchive.AE_IFCHR] = "char device",
  [libarchive.AE_IFBLK] = "block device",
  [libarchive.AE_IFDIR] = "directory",
  [libarchive.AE_IFIFO] = "named pipe",
}

local Reader = {}

function Reader:new()
  local o = {}
  setmetatable(o, self)
  self.__index = self
  o.archive_entry = ffi.gc(libarchive.archive_entry_new(), libarchive.archive_entry_free)
  o.entries = {}
  o.size = 0
  o.err = nil
  return o
end

function Reader:open(filepath)
  self.err = nil
  if not filepath then
    return
  end
  self.archive = ffi.gc(libarchive.archive_read_new(), libarchive.archive_free)
  libarchive.archive_read_support_format_all(self.archive)
  libarchive.archive_read_support_filter_all(self.archive)
  if libarchive.archive_read_open_filename(self.archive, filepath, 10240) ~= libarchive.ARCHIVE_OK then
    self.err = archive_error_string(self.archive)
    self.archive = nil
    return
  end
  self.filepath = filepath
  self.index = 0
  return true
end

function Reader:next()
  self.err = nil
  if self.archive == nil then
    return
  end
  -- We can't consume the data twice: tweak the index
  -- to trigger a reset in case of subsequent attempt.
  self.index = math.floor(self.index) + 0.1
  local err = libarchive.archive_read_next_header2(self.archive, self.archive_entry)
  if err ~= libarchive.ARCHIVE_OK then
    if err ~= libarchive.ARCHIVE_EOF then
      self.err = archive_error_string(self.archive)
    end
    return
  end
  local entry
  self.index = math.floor(self.index) + 1
  if self.index > self.size then
    entry = {
      path = ffi.string(libarchive.archive_entry_pathname(self.archive_entry)),
      mode = ENTRY_MODE[libarchive.archive_entry_filetype(self.archive_entry)] or "other",
      size = libarchive.archive_entry_size(self.archive_entry),
      index = self.index,
    }
    self.entries[self.index] = entry
    self.entries[entry.path] = entry
    self.size = self.size + 1
  else
    entry = self.entries[self.index]
  end
  return entry
end

function Reader:iterate(keep_pos)
  if self.index ~= 0 and not keep_pos then
    self:close(true)
    self:open(self.filepath)
  end
  return self.next, self
end

function Reader:seek(key)
  local entry = self.entries[key]
  if not entry then
    return
  end
  if entry.index == self.index then
    return entry
  end
  for __ in self:iterate(entry.index > self.index) do
    if entry.index == self.index then
      return entry
    end
  end
end

function Reader:extractToPath(key, dest_path)
  self.err = nil
  local entry = self:seek(key)
  if not entry then
    return false, "no such path"
  end
  if
    (entry.mode ~= "file" and entry.mode ~= "directory")
    or libarchive.archive_entry_hardlink(self.archive_entry) ~= nil
  then
    self.err = "refusing to extract link or special entry: " .. entry.path
    return false, self.err
  end
  local dest = ffi.gc(libarchive.archive_write_disk_new(), libarchive.archive_free)
  libarchive.archive_write_disk_set_options(dest, libarchive.ARCHIVE_EXTRACT_SECURE_NODOTDOT)
  if dest_path then
    libarchive.archive_entry_set_pathname(self.archive_entry, dest_path)
  end
  -- We can't consume the data twice: tweak the index
  -- to trigger a reset in case of subsequent attempt.
  self.index = self.index + 0.1
  local ok = libarchive.archive_read_extract2(self.archive, self.archive_entry, dest) == libarchive.ARCHIVE_OK
  if not ok then
    self.err = archive_error_string(self.archive)
  end
  libarchive.archive_write_close(dest)
  return ok
end

function Reader:close(keep_info)
  self.err = nil
  if self.archive ~= nil then
    libarchive.archive_read_close(self.archive)
    self.archive = nil
  end
  self.index = nil
  if not keep_info then
    self.filepath = nil
    self.entries = {}
    self.size = nil
  end
end

return {
  Reader = Reader,
}
