-- luacheck: ignore 122 311
local KoboLight

describe("ffi/kobolight module", function()
  local orig_open_C
  local orig_close_C
  local close_fn

  setup(function()
    require("commonrequire")
    KoboLight = require("ffi/kobolight")

    local _, open_c = debug.getupvalue(KoboLight.open, 1)
    orig_open_C = open_c

    local _, mt = debug.getupvalue(KoboLight.open, 4)
    close_fn = mt.__index.close
    local _, close_c = debug.getupvalue(close_fn, 1)
    orig_close_C = close_c
  end)

  after_each(function()
    debug.setupvalue(KoboLight.open, 1, orig_open_C)
    debug.setupvalue(close_fn, 1, orig_close_C)
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

    debug.setupvalue(KoboLight.open, 1, mock_C)
    debug.setupvalue(close_fn, 1, mock_C)

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

  it("detaches GC finalizer on manual close to prevent C.close(-1)", function()
    local closed_fds = {}
    local mock_C = setmetatable({
      open = function()
        return 42
      end,
      close = function(fd)
        table.insert(closed_fds, fd)
        return 0
      end,
      ioctl = function()
        return 0
      end,
    }, {
      __index = orig_open_C,
    })

    debug.setupvalue(KoboLight.open, 1, mock_C)
    debug.setupvalue(close_fn, 1, mock_C)

    local light = KoboLight.open()
    assert.are.equal(42, light.light_fd.ld)

    light:close()
    assert.are.equal(1, #closed_fds)
    assert.are.equal(42, closed_fds[1])

    -- When light:close() is called, it sets light_fd.ld = -1 without detaching
    -- ffi.gc finalizer. When garbage collection runs, the finalizer callback
    -- invokes C.close(-1).
    light = nil
    collectgarbage("collect")
    collectgarbage("collect")

    local saw_negative_close = false
    for _, fd in ipairs(closed_fds) do
      if fd == -1 then
        saw_negative_close = true
        break
      end
    end
    assert.is_false(saw_negative_close)
  end)
end)
