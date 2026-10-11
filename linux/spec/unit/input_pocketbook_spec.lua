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

  it("returns focus transition synthetic events as a list of events", function()
    is_task_active_val = 1 -- Transition from initial is_active=false to active=true

    local ok, ev_list = waitForEventRaw(1000)
    assert.is_true(ok)
    assert.is_table(ev_list)

    -- In production lines 391-397:
    --   return true, {
    --     type = C.EV_MSC,
    --     code = active and C.EVT_SHOW or C.EVT_HIDE,
    --     value = 0,
    --     time = updateTimestamp(),
    --   }
    -- It returns a single event dictionary instead of an event list {{ ... }}.
    -- Callers iterating with ipairs(ev_list) iterate 0 elements and drop the focus event.
    assert.are.equal(1, #ev_list)
    assert.is_not_nil(ev_list[1])
    assert.are.equal(ffi.C.EV_MSC, ev_list[1].type)
    assert.are.equal(ffi.C.EVT_SHOW, ev_list[1].code)
  end)
end)
