describe("HtmlBoxWidget module", function()
    local HtmlBoxWidget, Blitbuffer
    setup(function()
        require("commonrequire")
        HtmlBoxWidget = require("ui/widget/htmlboxwidget")
        Blitbuffer = require("ffi/blitbuffer")
    end)

    it("should set and clear highlight rects on drag/pan and release", function()
        -- Mock document and page
        local mock_page = {
            getPageText = function()
                return {
                    {
                        { word = "Hello", x0 = 0, y0 = 0, x1 = 50, y1 = 20 },
                        { word = "World", x0 = 60, y0 = 0, x1 = 110, y1 = 20 }
                    }
                }
            end,
            draw_new = function(self, dc, w, h)
                return Blitbuffer.new(w, h)
            end,
            close = function() end,
        }

        local mock_document = {
            layoutDocument = function() end,
            getPages = function() return 1 end,
            setColorRendering = function() end,
            openPage = function() return mock_page end,
        }

        local widget = HtmlBoxWidget:new({
            document = mock_document,
            width = 200,
            height = 100,
        })

        assert.is_nil(widget.highlight_rects)

        -- 1. Start hold/selection
        widget:onHoldStartText(nil, { pos = { x = 10, y = 10 } })
        assert.is_nil(widget.highlight_rects)

        -- 2. Pan/Drag to select text
        widget:onHoldPanText(nil, { pos = { x = 80, y = 10 } })
        assert.is_not_nil(widget.highlight_rects)
        assert.are.equal(2, #widget.highlight_rects)
        assert.are.equal(0, widget.highlight_rects[1].x0)
        assert.are.equal(60, widget.highlight_rects[2].x0)

        -- 3. Release hold/selection
        local called = false
        widget:onHoldReleaseText(function(text, duration)
            assert.are.equal("Hello World", text)
            called = true
        end, { pos = { x = 80, y = 10 } })

        assert.is_true(called)
        assert.is_nil(widget.highlight_rects)
    end)
end)
