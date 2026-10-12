describe("CanvasContext", function()
  local CanvasContext, Mupdf

  setup(function()
    require("commonrequire")
    CanvasContext = require("document/canvascontext")
    Mupdf = require("ffi/mupdf")
  end)

  local function createMockDevice(is_bgr)
    return {
      screen = {
        getWidth = function()
          return 600
        end,
        getHeight = function()
          return 800
        end,
        getDPI = function()
          return 300
        end,
        getSize = function()
          return {}
        end,
        scaleBySize = function(_, n)
          return n
        end,
        isColorEnabled = function()
          return false
        end,
        fb_bpp = 32,
      },
      isAndroid = function()
        return false
      end,
      isDesktop = function()
        return true
      end,
      isEmulator = function()
        return false
      end,
      isKindle = function()
        return false
      end,
      isPocketBook = function()
        return false
      end,
      hasSystemFonts = function()
        return true
      end,
      hasBGRFrameBuffer = function()
        return is_bgr
      end,
      hasEinkScreen = function()
        return false
      end,
      canHWDither = function()
        return false
      end,
    }
  end

  it("should initialize BGR framebuffer support", function()
    local bgr_device = createMockDevice(true)
    CanvasContext:init(bgr_device)
    assert.is_true(CanvasContext.is_bgr)
    assert.is_true(Mupdf.bgr)

    -- Re-init with default Device so other tests have clean global state
    CanvasContext:init(require("device"))
  end)
end)
