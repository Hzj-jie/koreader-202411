describe("Button widget", function()
  local Button, Blitbuffer
  setup(function()
    require("commonrequire")
    Button = require("ui/widget/button")
    Blitbuffer = require("ffi/blitbuffer")
  end)

  it(
    "should update label widget color when disabled without dimming after being disabled",
    function()
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
    end
  )

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

  it(
    "should calculate size via getSize and support geometry merge methods",
    function()
      local b = Button:new({
        text = "Geometry test",
        width = 100,
        height = 40,
      })

      local size = b:getSize()
      assert.is_not_nil(size)
      assert.are.equal(100, size.w)
      assert.is_true(size.h >= 40)

      b:mergeSize(120, 50)
      local new_size = b:getSize()
      assert.are.equal(120, new_size.w)
      assert.are.equal(50, new_size.h)

      b:mergePosition(10, 20)
      local pos_size = b:getSize()
      assert.are.equal(10, pos_size.x)
      assert.are.equal(20, pos_size.y)
    end
  )

  it("should support dirtyRegion", function()
    local b = Button:new({
      text = "Region test",
    })
    local region = b:dirtyRegion()
    assert.is_not_nil(region)
  end)
end)
