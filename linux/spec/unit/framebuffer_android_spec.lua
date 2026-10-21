-- luacheck: ignore 122
local FramebufferAndroid

describe("ffi/framebuffer_android module", function()
  setup(function()
    require("commonrequire")
    package.preload["android"] = function()
      return {
        isEink = function()
          return true, "standard"
        end,
        isEinkFull = function()
          return true
        end,
        getEinkPlatform = function()
          return "standard"
        end,
        getEinkConstants = function()
          return 1, 2, 3, 4, 5, 10, 20, 30
        end,
        einkUpdate = function(...) end,
        screen = { width = 600, height = 800 },
        getScreenWidth = function()
          return 600
        end,
        getScreenHeight = function()
          return 800
        end,
      }
    end
    package.loaded["ffi/framebuffer_android"] = nil
    FramebufferAndroid = require("ffi/framebuffer_android")
  end)

  teardown(function()
    package.preload["android"] = nil
    package.loaded["android"] = nil
    package.loaded["ffi/framebuffer_android"] = nil
  end)

  it(
    "passes (0, 0) origin coordinates to _updatePartial in _updateFull",
    function()
      local captured = {}
      local mock_fb = FramebufferAndroid:extend({
        viewport = { x = 50, y = 100, w = 500, h = 700 },
        getWidth = function(self)
          return self.viewport.w
        end,
        getHeight = function(self)
          return self.viewport.h
        end,
        _updatePartial = function(_, mode, delay, x, y, w, h)
          captured.x = x
          captured.y = y
          captured.w = w
          captured.h = h
        end,
      })

      mock_fb:_updateFull()

      assert.are.equal(0, captured.x)
      assert.are.equal(0, captured.y)
      assert.are.equal(500, captured.w)
      assert.are.equal(700, captured.h)
    end
  )

  it("passes (0, 0) origin coordinates when no viewport is active", function()
    local captured = {}
    local mock_fb = FramebufferAndroid:extend({
      viewport = nil,
      getWidth = function()
        return 600
      end,
      getHeight = function()
        return 800
      end,
      _updatePartial = function(_, mode, delay, x, y, w, h)
        captured.x = x
        captured.y = y
        captured.w = w
        captured.h = h
      end,
    })

    mock_fb:_updateFull()

    assert.are.equal(0, captured.x)
    assert.are.equal(0, captured.y)
    assert.are.equal(600, captured.w)
    assert.are.equal(800, captured.h)
  end)
end)
