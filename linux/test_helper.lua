-- Load the original loadlib helper first
require("ffi/loadlib")

local ffi = require("ffi")

pcall(function()
    ffi.cdef[[
        int getpid(void);
    ]]
end)

-- Intercept require globally to ensure determinism across different host workstations
-- and avoid relying on physical hardware state (such as system fonts, battery charging state, etc.).
local orig_require = _G.require
_G.require = function(name)
    if name == "libs/libkoreader-nnsvg" then
        local ok, res = pcall(orig_require, name)
        if ok then
            return res
        else
            io.stderr:write("WARNING: Failed to load libs/libkoreader-nnsvg, using mock!\n")
            return {
                new = function(filename)
                    return {
                        getSize = function() return 100, 100 end,
                        drawTo = function() end,
                        free = function() end,
                    }
                end
            }
        end
    end
    if name == "luasettings" then
        local luasettings = orig_require(name)
        local orig_open = luasettings.open
        luasettings.open = function(self, ...)
            local settings = orig_open(self, ...)
            local orig_read = settings.read
            local orig_nilOrTrue = settings.nilOrTrue
            local orig_isTrue = settings.isTrue
            local orig_isFalse = settings.isFalse
            local orig_nilOrFalse = settings.nilOrFalse
            local orig_isTrueOr = settings.isTrueOr

            settings.read = function(self, key)
                if key == "use_xtext" then return false end
                return orig_read(self, key)
            end
            settings.nilOrTrue = function(self, key)
                if key == "use_xtext" then return false end
                return orig_nilOrTrue(self, key)
            end
            settings.isTrue = function(self, key)
                if key == "use_xtext" then return false end
                return orig_isTrue(self, key)
            end
            settings.isFalse = function(self, key)
                if key == "use_xtext" then return true end
                return orig_isFalse(self, key)
            end
            settings.nilOrFalse = function(self, key)
                if key == "use_xtext" then return true end
                return orig_nilOrFalse(self, key)
            end
            settings.isTrueOr = function(self, key, default)
                if key == "use_xtext" then return false end
                return orig_isTrueOr(self, key, default)
            end
            return settings
        end
        return luasettings
    end
    local res = orig_require(name)
    if name == "ffi/SDL2_0" then
        if type(res) == "table" and res.getPowerInfo and not res._orig_getPowerInfo then
            res._orig_getPowerInfo = res.getPowerInfo
            res.getPowerInfo = function()
                -- Return deterministic power state: has battery, not charging, not plugged, 0% capacity
                return true, false, false, 0
            end
        end
    elseif name == "device/sdl/device" then
        if type(res) == "table" then
            res.hasSystemFonts = function() return false end
        end
    end
    return res
end

local ffi = require("ffi")
pcall(ffi.cdef, [[
  struct tm {
    int tm_sec;
    int tm_min;
    int tm_hour;
    int tm_mday;
    int tm_mon;
    int tm_year;
    int tm_wday;
    int tm_yday;
    int tm_isdst;
    long int tm_gmtoff;
    const char *tm_zone;
  };
  struct tm *localtime(const long *timep);
  struct tm *gmtime(const long *timep);
  size_t strftime(char *s, size_t max, const char *format, const struct tm *tm);
  int getpid(void);
]])

-- Override os.tmpname to generate temporary files inside the isolated worker/sandbox temp folder
-- instead of writing directly into system /tmp (which ignores TMPDIR in glibc).
local orig_tmpname = os.tmpname
local tmp_seq = 0
os.tmpname = function()
    local tmp_dir = os.getenv("TMPDIR") or os.getenv("XDG_CONFIG_HOME")
    if not tmp_dir or tmp_dir == "" then
        return orig_tmpname()
    end
    tmp_seq = tmp_seq + 1
    local pid = ffi.C.getpid()
    local fn = string.format("%s/lua_tmp_%d_%d", tmp_dir, pid, tmp_seq)
    local f = io.open(fn, "w")
    if f then
        f:close()
    end
    return fn
end

local orig_os_date = os.date
os.date = function(format, seconds)
  if type(format) == "string" and (format:match("%%%-") or format:match("%%_")) then
    seconds = seconds or os.time()
    local t = ffi.new("long[1]", seconds)
    local tm
    local is_utc = false
    if format:sub(1, 1) == "!" then
      is_utc = true
      format = format:sub(2)
    end
    if is_utc then
      tm = ffi.C.gmtime(t)
    else
      tm = ffi.C.localtime(t)
    end
    if tm == nil then
      return nil
    end
    local buf = ffi.new("char[1024]")
    local ret = ffi.C.strftime(buf, 1024, format, tm)
    if ret == 0 then
      return ""
    end
    return ffi.string(buf)
  else
    return orig_os_date(format, seconds)
  end
end

local orig_tonumber = _G.tonumber
_G.tonumber = function(x, ...)
  if type(x) == "userdata" then
    local s = tostring(x)
    local num_str = s:match("^(%-?%d+)[UL]*%s*%z*$")
    if num_str then
      return orig_tonumber(num_str, ...)
    end
  end
  return orig_tonumber(x, ...)
end

local max_jobs = 4
local nproc_p = io.popen("nproc 2>/dev/null")
if nproc_p then
    local cores = tonumber(nproc_p:read("*l"))
    nproc_p:close()
    if cores and cores > 0 then
        max_jobs = cores
    end
end

return {
    max_jobs = max_jobs,
}
