-- luacheck: ignore 122
local ffi
local input

describe("ffi/input_pocketbook module", function()
  local orig_ffi_load
  local is_task_active_val = 0
  local waitForEventRaw

  setup(function()
    require("commonrequire")
    ffi = require("ffi")

    orig_ffi_load = ffi.load
    ffi.load = function(name)
      if name == "inkview" or name == "librt.so" or name == "rt" then
        return setmetatable({}, {
          __index = function(t, k)
            if k == "IsTaskActive" then
              return function()
                return is_task_active_val
              end
            end
            return function()
              return 0
            end
          end,
        })
      end
      return orig_ffi_load(name)
    end

    package.loaded["ffi/input_pocketbook"] = nil
    input = require("ffi/input_pocketbook")
    local i = 1
    while true do
      local name, val = debug.getupvalue(input.waitForEvent, i)
      if not name then
        break
      end
      if name == "waitForEventRaw" then
        waitForEventRaw = val
        break
      end
      i = i + 1
    end
  end)

  teardown(function()
    ffi.load = orig_ffi_load
  end)

  it("exposes closeAll cleanup method", function()
    assert.is_function(input.closeAll)
  end)

  it("returns focus transition synthetic events", function()
    is_task_active_val = 1 -- Transition from initial is_active=false to active=true

    local ok, ev = waitForEventRaw(1000)
    assert.is_true(ok)
    assert.is_table(ev)
    assert.are.equal(ffi.C.EV_MSC, ev.type)
    assert.are.equal(ffi.C.EVT_SHOW, ev.code)
  end)
end)
