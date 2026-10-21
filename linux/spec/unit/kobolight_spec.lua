-- luacheck: ignore 122 311
local KoboLight

describe("ffi/kobolight module", function()
  local open_c_idx
  local close_c_idx
  local orig_open_C
  local orig_close_C
  local close_fn

  local function get_upval(fn, name)
    local i = 1
    while true do
      local n, v = debug.getupvalue(fn, i)
      if not n then
        return nil
      end
      if n == name then
        return i, v
      end
      i = i + 1
    end
  end

  setup(function()
    require("commonrequire")
    KoboLight = require("ffi/kobolight")

    open_c_idx, orig_open_C = get_upval(KoboLight.open, "C")
    local _, mt = get_upval(KoboLight.open, "kobolight_mt")
    close_fn = mt.__index.close
    close_c_idx, orig_close_C = get_upval(close_fn, "C")
  end)

  after_each(function()
    if open_c_idx and orig_open_C then
      debug.setupvalue(KoboLight.open, open_c_idx, orig_open_C)
    end
    if close_c_idx and orig_close_C then
      debug.setupvalue(close_fn, close_c_idx, orig_close_C)
    end
  end)

  it("validates brightness bounds and dispatches ioctl", function()
    local ioctl_called = false
    local mock_C = setmetatable({
      open = function()
        return 5
      end,
      close = function()
        return 0
      end,
      ioctl = function(fd, req, arg)
        ioctl_called = true
        return 0
      end,
    }, {
      __index = orig_open_C,
    })

    debug.setupvalue(KoboLight.open, open_c_idx, mock_C)
    debug.setupvalue(close_fn, close_c_idx, mock_C)

    local light = KoboLight.open()

    assert.has.errors(function()
      light:setBrightness(-1)
    end)
    assert.has.errors(function()
      light:setBrightness(105)
    end)

    assert.has_no.errors(function()
      light:setBrightness(50)
    end)
    assert.is_true(ioctl_called)
    light:close()
  end)
end)
