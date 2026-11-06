local CreUtil
local Device

describe("creutil", function()
  setup(function()
    require("commonrequire")
    CreUtil = require("creutil")
    Device = require("device")
  end)

  it("defines CRE_HEADER_DEFAULT_SIZE constant as 20", function()
    assert.are.equal(20, CreUtil.CRE_HEADER_DEFAULT_SIZE)
  end)

  describe("font_size", function()
    it("scales font size via Device.screen:scaleBySize", function()
      local orig_scale = Device.screen.scaleBySize
      local called_arg = nil
      Device.screen.scaleBySize = function(self_s, px)
        called_arg = px
        return px * 2
      end
      finally(function()
        Device.screen.scaleBySize = orig_scale
      end)

      assert.are.equal(32, CreUtil.font_size(16))
      assert.are.equal(16, called_arg)

      assert.are.equal(24, CreUtil.font_size(12))
      assert.are.equal(12, called_arg)
    end)

    it("falls back to CRE_HEADER_DEFAULT_SIZE when value is omitted or nil", function()
      local orig_scale = Device.screen.scaleBySize
      local called_arg = nil
      Device.screen.scaleBySize = function(self_s, px)
        called_arg = px
        return px + 5
      end
      finally(function()
        Device.screen.scaleBySize = orig_scale
      end)

      assert.are.equal(25, CreUtil.font_size(nil))
      assert.are.equal(20, called_arg)

      assert.are.equal(25, CreUtil.font_size())
      assert.are.equal(20, called_arg)
    end)

    it("scales using screen dimensions rather than raw DPI", function()
      -- On a 1072x1448 screen with 300 DPI:
      -- size_scale = min(1072, 1448) / 600 = 1072 / 600 ~ 1.78667
      -- Without DPI override, scaleBySize(20) = ceil(20 * 1.78667) = 36
      -- Raw DPI formula (20 * 300 / 160) = 37.5
      local orig_screen = Device.screen
      local fake_screen = {
        getWidth = function() return 1072 end,
        getHeight = function() return 1448 end,
        dpi_override = false,
        getDPI = function() return 300 end,
        scaleBySize = function(self_s, px)
          local size_scale = math.min(self_s:getWidth(), self_s:getHeight()) / 600
          local dpi_scale = size_scale
          return math.ceil(px * (size_scale + dpi_scale) / 2)
        end,
      }
      Device.screen = fake_screen
      finally(function()
        Device.screen = orig_screen
      end)

      assert.are.equal(36, CreUtil.font_size(20))
      assert.are.equal(36, CreUtil.font_size())
    end)
  end)
end)
