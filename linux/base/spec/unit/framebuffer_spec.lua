describe("Framebuffer unit tests", function()
    local fb

    setup(function()
        fb = require("ffi/framebuffer_dummy"):new{
            dummy = true,
            device = {
                device_dpi = 167,
                canHWInvert = function() return false end,
            }
        }
    end)

    it("should store logical night_mode state in setNightmode", function()
        assert.is_false(fb.night_mode)
        fb:setNightmode(true)
        assert.is_true(fb.night_mode)
        fb:setNightmode(false)
        assert.is_false(fb.night_mode)
    end)

    it("should set & update DPI", function()
        assert.are.equals(160, fb:getDPI())

        fb:setDPI(120)
        assert.are.equals(120, fb:getDPI())

        fb:setDPI(60)
        assert.are.equals(60, fb:getDPI())
    end)

    it("should scale by DPI", function()
        fb:setDPI(167)
        assert.are.equals(31, fb:scaleBySize(30))

        fb:setDPI(167 * 3)
        assert.are.equals(62, fb:scaleBySize(30))
    end)
end)
