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

