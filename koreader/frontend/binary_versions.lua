local bit = require("bit")
local ffi = require("ffi")
local gettext = require("gettext")
local lfs = require("libs/libkoreader-lfs")

require("ffi/freetype_h")
require("ffi/utf8proc_h")

ffi.cdef([[
const char *OpenSSL_version(int);
void zsys_version(int *, int *, int *);
void FT_Library_Version(FT_Library, FT_Int *, FT_Int *, FT_Int *);
int FT_Done_FreeType(FT_Library);
extern const char *fribidi_version_info;
const char *hb_version_string(void);
char *getLeptonicaVersion(void);
void lept_free(void *);
extern const char *LODEPNG_VERSION_STRING;
const char *png_get_libpng_ver(void *);
int SharpYuvGetVersion(void);
const char *sqlite3_libversion(void);
unsigned long http_parser_version(void);
extern const int unibreak_version;
int WebPGetDecoderVersion(void);
int WebPGetDemuxVersion(void);
const char *zlibVersion(void);
void zmq_version(int *, int *, int *);
const char *ZSTD_versionString(void);
]])

local BinaryVersions = {}

local function isElfFile(path)
  if lfs.attributes(path, "mode") ~= "file" then
    return false
  end
  local f = assert(io.open(path, "rb"))
  local magic = f:read(4)
  f:close()
  return magic == "\127ELF"
end

local function collectElfFiles(dir, recursive, out)
  for entry in lfs.dir(dir) do
    if entry ~= "." and entry ~= ".." then
      local path = dir == "." and entry or (dir .. "/" .. entry)
      if recursive and lfs.attributes(path, "mode") == "directory" then
        collectElfFiles(path, true, out)
      elseif isElfFile(path) then
        table.insert(out, path)
      end
    end
  end
end

local function readCommandFirstLine(cmd)
  local pipe = assert(io.popen(cmd, "r"))
  local result
  for line in pipe:lines() do
    local trimmed = line:match("^%s*(.-)%s*$")
    if trimmed ~= "" then
      result = trimmed
      break
    end
  end
  pipe:close()
  return result
end

local function scanFilePattern(path, pattern)
  local f = assert(io.open(path, "rb"))
  local tail = ""
  local matched
  while true do
    local chunk = f:read(65536)
    local buf = tail .. (chunk or "")
    local s, e = buf:find(pattern)
    if s and (not chunk or e < #buf) then
      matched = buf:sub(s, e)
      break
    end
    if not chunk then
      break
    end
    tail = buf:sub(-128)
  end
  f:close()
  return matched
end

local function scanMaxGlibcxx(path)
  local f = assert(io.open(path, "rb"))
  local tail = ""
  local max_n
  while true do
    local chunk = f:read(65536)
    if not chunk then
      break
    end
    local buf = tail .. chunk
    for num_str in buf:gmatch("GLIBCXX_3%.4%.(%d+)") do
      local n = tonumber(num_str)
      if not max_n or n > max_n then
        max_n = n
      end
    end
    tail = buf:sub(-32)
  end
  f:close()
  if max_n then
    return "GLIBCXX_3.4." .. max_n
  end
end

local resolvers = {
  { "^dropbear$", function()
    return readCommandFirstLine("./dropbear -V 2>&1")
  end },
  { "^fbdepth$", function()
    return readCommandFirstLine("./fbdepth -? 2>/dev/null")
  end },
  { "^fbink$", function()
    return readCommandFirstLine("./fbink -? 2>/dev/null")
  end },
  { "^lua$", function()
    return readCommandFirstLine("./lua -v")
  end },
  { "^luac$", function()
    return readCommandFirstLine("./luac -v")
  end },
  { "^luajit$", function()
    return readCommandFirstLine("./luajit -v")
  end },
  { "^rsync$", function()
    return readCommandFirstLine("./rsync --version")
  end },
  { "^sdcv$", function()
    return readCommandFirstLine("./sdcv --version")
  end },
  { "^tar$", function()
    return readCommandFirstLine("./tar --version")
  end },
  { "^wmctrl$", function(path)
    return scanFilePattern(path, "wmctrl %d+%.%d+")
  end },
  { "^lpeg%.so$", function()
    return require("lpeg").version
  end },
  { "^mcore%.so$", function()
    return require("mime")._VERSION
  end },
  { "^rapidjson%.so$", function()
    local rj = require("rapidjson")
    return rj._NAME .. " " .. rj._VERSION
  end },
  { "^score%.so$", function()
    return require("socket")._VERSION
  end },
  { "^ssl%.so$", function()
    return "LuaSec " .. require("ssl")._VERSION
  end },
  { "^libcrypto%.so", function(path)
    return ffi.string(ffi.load(path).OpenSSL_version(0))
  end },
  { "^libssl%.so", function(path)
    return ffi.string(ffi.load(path).OpenSSL_version(0))
  end },
  { "^libczmq%.so", function(path)
    local lib = ffi.load(path)
    local maj, min, pat = ffi.new("int[1]"), ffi.new("int[1]"), ffi.new("int[1]")
    lib.zsys_version(maj, min, pat)
    return string.format("%d.%d.%d", maj[0], min[0], pat[0])
  end },
  { "^libfreetype%.so", function(path)
    local lib = ffi.load(path)
    local ft = ffi.new("FT_Library[1]")
    assert(lib.FT_Init_FreeType(ft) == 0)
    local maj, min, pat = ffi.new("FT_Int[1]"), ffi.new("FT_Int[1]"), ffi.new("FT_Int[1]")
    lib.FT_Library_Version(ft[0], maj, min, pat)
    lib.FT_Done_FreeType(ft[0])
    return string.format("%d.%d.%d", maj[0], min[0], pat[0])
  end },
  { "^libfribidi%.so", function(path)
    return ffi.string(ffi.load(path).fribidi_version_info):match("^[^\n]+")
  end },
  { "^libharfbuzz%.so", function(path)
    return ffi.string(ffi.load(path).hb_version_string())
  end },
  { "^libjpeg%.so", function(path)
    return scanFilePattern(path, "libjpeg%-turbo version [%d%.]+")
  end },
  { "^libturbojpeg%.so", function(path)
    return scanFilePattern(path, "libjpeg%-turbo version [%d%.]+")
  end },
  { "^libkoreader%-djvu%.so$", function(path)
    return scanFilePattern(path, "DjVuLibre%-[%d%.]+")
  end },
  { "^libkoreader%-lfs%.so$", function()
    return require("libs/libkoreader-lfs")._VERSION
  end },
  { "^libleptonica%.so", function(path)
    local lib = ffi.load(path)
    local ptr = lib.getLeptonicaVersion()
    local ver = ffi.string(ptr)
    lib.lept_free(ptr)
    return ver
  end },
  { "^liblodepng%.so$", function(path)
    return ffi.string(ffi.load(path).LODEPNG_VERSION_STRING)
  end },
  { "^libpng16%.so", function(path)
    return ffi.string(ffi.load(path).png_get_libpng_ver(nil))
  end },
  { "^libsharpyuv%.so", function(path)
    local v = ffi.load(path).SharpYuvGetVersion()
    return string.format("%d.%d.%d", bit.rshift(v, 24), bit.band(bit.rshift(v, 16), 0xff), bit.band(v, 0xffff))
  end },
  { "^libsqlite3%.so", function(path)
    return ffi.string(ffi.load(path).sqlite3_libversion())
  end },
  { "^libstdc%+%+%.so", function(path)
    return scanMaxGlibcxx(path)
  end },
  { "^libtffi_wrap%.so$", function(path)
    local v = tonumber(ffi.load(path).http_parser_version())
    return string.format(
      "http_parser %d.%d.%d",
      bit.band(bit.rshift(v, 16), 0xff),
      bit.band(bit.rshift(v, 8), 0xff),
      bit.band(v, 0xff)
    )
  end },
  { "^libunibreak%.so", function(path)
    local v = ffi.load(path).unibreak_version
    return string.format("%d.%d", bit.rshift(v, 8), bit.band(v, 0xff))
  end },
  { "^libutf8proc%.so", function(path)
    return ffi.string(ffi.load(path).utf8proc_version())
  end },
  { "^libwebp%.so", function(path)
    local v = ffi.load(path).WebPGetDecoderVersion()
    return string.format("%d.%d.%d", bit.band(bit.rshift(v, 16), 0xff), bit.band(bit.rshift(v, 8), 0xff), bit.band(v, 0xff))
  end },
  { "^libwebpdemux%.so", function(path)
    local v = ffi.load(path).WebPGetDemuxVersion()
    return string.format("%d.%d.%d", bit.band(bit.rshift(v, 16), 0xff), bit.band(bit.rshift(v, 8), 0xff), bit.band(v, 0xff))
  end },
  { "^libwrap%-mupdf%.so$", function()
    return require("ffi/mupdf").version
  end },
  { "^libz%.so", function(path)
    return ffi.string(ffi.load(path).zlibVersion())
  end },
  { "^libzmq%.so", function(path)
    local lib = ffi.load(path)
    local maj, min, pat = ffi.new("int[1]"), ffi.new("int[1]"), ffi.new("int[1]")
    lib.zmq_version(maj, min, pat)
    return string.format("%d.%d.%d", maj[0], min[0], pat[0])
  end },
  { "^libzstd%.so", function(path)
    return ffi.string(ffi.load(path).ZSTD_versionString())
  end },
}

local function resolveVersion(path)
  local basename = path:match("[^/]+$")
  for _, entry in ipairs(resolvers) do
    if basename:match(entry[1]) then
      local ver = entry[2](path)
      if ver then
        return ver
      end
      break
    end
  end
  return gettext("Unknown")
end

function BinaryVersions:getKeyValuePairs()
  local kv_pairs = {}
  for _, group in ipairs({ { ".", false }, { "common", true }, { "libs", true } }) do
    local paths = {}
    collectElfFiles(group[1], group[2], paths)
    table.sort(paths)
    for _, path in ipairs(paths) do
      table.insert(kv_pairs, { path, resolveVersion(path) })
    end
  end
  return kv_pairs
end

return BinaryVersions
