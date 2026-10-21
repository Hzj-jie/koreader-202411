-- luacheck: ignore 122
local BB
local ffi
local FramebufferPocketbook

describe("ffi/framebuffer_pocketbook module", function()
  local orig_ffi_load
  local dummy_buf

  setup(function()
    require("commonrequire")
    BB = require("ffi/blitbuffer")
    ffi = require("ffi")

    orig_ffi_load = ffi.load
    ffi.load = function(name)
      if name == "inkview" then
        return {
          OpenScreen = function() end,
          GetCurrentTask = function()
            return 1
          end,
          GetTaskFramebuffer = function()
            return {
              scanline = 2048,
              width = 1000,
              height = 1000,
              depth = 16,
              addr = dummy_buf,
            }
          end,
          adjustAreaDefault = function() end,
          PartialUpdate = function() end,
          PartialUpdateHQ = function() end,
          FullUpdate = function() end,
          FullUpdateHQ = function() end,
          DynamicUpdate = function() end,
        }
      end
      return orig_ffi_load(name)
    end

    dummy_buf = ffi.new("uint8_t[?]", 2048 * 1000)
    package.loaded["ffi/framebuffer_pocketbook"] = nil
    FramebufferPocketbook = require("ffi/framebuffer_pocketbook")
  end)

  teardown(function()
    ffi.load = orig_ffi_load
  end)

  it("handles nightmode query", function()
    local mock_fb = FramebufferPocketbook:extend({})
    assert.is_false(mock_fb:reverseNightmode())
  end)

  it("invokes device.hasColorScreen without self receiver", function()
    local called = false
    local mock_device = {
      hasColorScreen = function(...)
        assert.are.equal(0, select("#", ...))
        called = true
        return true
      end,
    }

    local mock_fb = FramebufferPocketbook:extend({
      device = mock_device,
      debug = function() end,
      bb = BB.new(100, 100, BB.TYPE_BBRGB32),
      _finfo = { line_length = 400 },
      _vinfo = { width = 100, height = 100 },
      data = dummy_buf,
    })

    assert.has_no.errors(function()
      mock_fb:refreshPartialImp(0, 0, 10, 10, true)
    end)
    assert.is_true(called)
  end)

  it("initializes blitbuffer pixel_stride based on screen width", function()
    local mock_device = {
      hasColorScreen = function()
        return false
      end,
    }

    local mock_fb = FramebufferPocketbook:extend({
      device = mock_device,
      getRawSize = function()
        return { w = 1000, h = 1000 }
      end,
      debug = function() end,
    })

    mock_fb:init()

    assert.are.equal(1000, mock_fb.bb.pixel_stride)
  end)
end)
