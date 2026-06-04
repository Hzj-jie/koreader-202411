describe("Button widget", function()
    local Button, Font, Blitbuffer
    setup(function()
        require("commonrequire")
        Button = require("ui/widget/button")
        Font = require("ui/font")
        Blitbuffer = require("ffi/blitbuffer")
    end)

    it("should update label widget color when disabled without dimming after being disabled", function()
        local b = Button:new({
            text = "Very long text that will force TextBoxWidget",
            width = 50,
            height = 30,
            avoid_text_truncation = true,
        })

        -- Verify it is indeed a TextBoxWidget (has update method)
        assert.is_not_nil(b.label_widget.update)

        -- Start enabled (color should be black)
        assert.are.equal(b.label_widget.fgcolor, Blitbuffer.COLOR_BLACK)

        -- Disable it (should become gray)
        b:disable()
        assert.are.equal(b.label_widget.fgcolor, Blitbuffer.COLOR_DARK_GRAY)

        -- Spy on update
        local spy_update = spy.on(b.label_widget, "update")

        -- Disable without dimming (should become black again)
        b:disableWithoutDimming()
        assert.are.equal(b.label_widget.fgcolor, Blitbuffer.COLOR_BLACK)

        assert.spy(spy_update).was_called()
    end)

    it("should allow changing from text to icon and vice versa", function()
        local b = Button:new({
            text = "Click me",
        })

        assert.is_equal("Click me", b.text)
        assert.is_nil(b.icon)
        assert.is_equal("Click me", b.label_widget.text)

        -- Change to icon
        b:setIcon("home")
        assert.is_nil(b.text)
        assert.is_equal("home", b.icon)
        assert.is_equal("home", b.label_widget.icon)

        -- Change back to text
        b:setText("Back to text")
        assert.is_equal("Back to text", b.text)
        assert.is_nil(b.icon)
        assert.is_equal("Back to text", b.label_widget.text)
    end)
end)
