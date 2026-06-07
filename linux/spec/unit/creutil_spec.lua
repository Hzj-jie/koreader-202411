local CreUtil
local Device

describe("creutil", function()
    setup(function()
        require("commonrequire")
        CreUtil = require("creutil")
        Device = require("device")
    end)

    describe("font_size", function()
        it("scales font size correctly for 160 DPI (no scaling)", function()
            Device.screen.getDPI = function() return 160 end
            assert.is.same(16, CreUtil.font_size(16))
            assert.is.same(12, CreUtil.font_size(12))
        end)

        it("scales font size correctly for 320 DPI (2x scaling)", function()
            Device.screen.getDPI = function() return 320 end
            assert.is.same(32, CreUtil.font_size(16))
            assert.is.same(24, CreUtil.font_size(12))
        end)

        it("scales font size correctly for 80 DPI (0.5x scaling)", function()
            Device.screen.getDPI = function() return 80 end
            assert.is.same(8, CreUtil.font_size(16))
            assert.is.same(6, CreUtil.font_size(12))
        end)

        it("scales font size correctly for 240 DPI (1.5x scaling)", function()
            Device.screen.getDPI = function() return 240 end
            assert.is.same(24, CreUtil.font_size(16))
            assert.is.same(18, CreUtil.font_size(12))
        end)
    end)
end)
