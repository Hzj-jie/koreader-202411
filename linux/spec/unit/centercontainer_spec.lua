describe("CenterContainer", function()
    local CenterContainer
    setup(function()
        require("commonrequire")
        CenterContainer = require("ui/widget/container/centercontainer")
    end)

    it("should center dynamically when container size changes", function()
        local dummy_widget = {
            getSize = function(self) return self.dimen end,
            paintTo = function(self, bb, x, y)
                self.painted_x = x
                self.painted_y = y
            end,
            dimen = { w = 20, h = 20 }
        }
        local cc = CenterContainer:new{
            dummy_widget,
            ignore_if_over = "height",
            dimen = { w = 40, h = 10 } -- Container height (10) < content height (20)
        }

        -- Frame 1: Container is smaller than content, should ignore height centering (align top)
        cc:paintTo(nil, 0, 0)
        assert.is_equal(0, dummy_widget.painted_y) -- should be at y=0 (top aligned)

        -- Frame 2: Container becomes larger than content, should center height
        cc.dimen = { w = 40, h = 40 } -- Container height (40) > content height (20)
        cc:paintTo(nil, 0, 0)
        -- Expected y: (40 - 20) / 2 = 10
        -- If bug is present, cc.ignore remains "height", so it will still be at 0.
        assert.is_equal(10, dummy_widget.painted_y)
    end)
end)
