describe("FrameContainer", function()
    local FrameContainer
    setup(function()
        require("commonrequire")
        FrameContainer = require("ui/widget/container/framecontainer")
    end)

    it("should preserve border size on multiple focus calls", function()
        local dummy_widget = {
            getSize = function() return { w = 10, h = 10 } end,
            paintTo = function() end,
        }
        local fc = FrameContainer:new{
            dummy_widget,
            focusable = true,
            bordersize = 2,
            focus_border_size = 5,
        }

        assert.is_equal(2, fc.bordersize)

        fc:onFocus()
        assert.is_equal(5, fc.bordersize)

        -- Call onFocus again, should not overwrite original border size
        fc:onFocus()
        assert.is_equal(5, fc.bordersize)

        fc:onUnfocus()
        assert.is_equal(2, fc.bordersize) -- Should restore to original!
    end)
end)
