describe("TextWidget", function()
  local TextWidget
  local Font
  local Blitbuffer
  local Device

  setup(function()
    require("commonrequire")
    TextWidget = require("ui/widget/textwidget")
    Font = require("ui/font")
    Blitbuffer = require("ffi/blitbuffer")
    Device = require("device")
  end)

  it("should calculate font size to fit height", function()
    local font_size = TextWidget:getFontSizeToFitHeight("infofont", 30, 2)
    assert.is_number(font_size)
    assert.is_true(font_size > 0)
    assert.is_true(font_size < 30)
  end)

  it("should initialize with text and compute size without xtext", function()
    local face = Font:getFace("infofont", 14)
    local tw = TextWidget:new({
      text = "Hello KOReader",
      face = face,
      use_xtext = false,
    })

    local size = tw:getSize()
    assert.truthy(size)
    assert.is_true(size.w > 0)
    assert.is_true(size.h > 0)
    assert.are.equal(size.w, tw:getWidth())
    assert.is_false(tw:isTruncated())
    assert.is_true(tw:getBaseline() > 0)
  end)

  it("should handle numeric text and empty text", function()
    local face = Font:getFace("infofont", 14)
    local tw_num = TextWidget:new({
      text = 12345,
      face = face,
      use_xtext = false,
    })
    assert.is_true(tw_num:getWidth() > 0)

    local tw_empty = TextWidget:new({
      text = "",
      face = face,
      use_xtext = false,
    })
    assert.are.equal(0, tw_empty:getWidth())

    local tw_nil = TextWidget:new({
      text = nil,
      face = face,
      use_xtext = false,
    })
    assert.are.equal(0, tw_nil:getWidth())
  end)

  it("should handle forced_height and forced_baseline", function()
    local face = Font:getFace("infofont", 14)
    local tw = TextWidget:new({
      text = "Custom",
      face = face,
      forced_height = 50,
      forced_baseline = 25,
      use_xtext = false,
    })

    local size = tw:getSize()
    assert.are.equal(50, size.h)
  end)

  it("should truncate right with and without ellipsis without xtext", function()
    local face = Font:getFace("infofont", 14)
    local long_text = "This is a very long string that should exceed the small maximum width"
    local tw = TextWidget:new({
      text = long_text,
      face = face,
      max_width = 60,
      truncate_with_ellipsis = true,
      use_xtext = false,
    })

    assert.is_true(tw:isTruncated())
    assert.is_true(tw:getWidth() <= 60)
    local fitted, with_ell = tw:getFittedText()
    assert.truthy(fitted)
    assert.is_true(with_ell)

    local tw_no_ell = TextWidget:new({
      text = long_text,
      face = face,
      max_width = 60,
      truncate_with_ellipsis = false,
      use_xtext = false,
    })
    assert.is_true(tw_no_ell:isTruncated())
    assert.is_true(tw_no_ell:getWidth() <= 60)
    local fitted_no_ell, with_ell2 = tw_no_ell:getFittedText()
    assert.truthy(fitted_no_ell)
    assert.is_false(with_ell2)
  end)

  it("should truncate left with and without ellipsis without xtext", function()
    local face = Font:getFace("infofont", 14)
    local long_text = "This is a very long string that should exceed the small maximum width"
    local tw_left = TextWidget:new({
      text = long_text,
      face = face,
      max_width = 60,
      truncate_left = true,
      truncate_with_ellipsis = true,
      use_xtext = false,
    })

    assert.is_true(tw_left:isTruncated())
    assert.is_true(tw_left:getWidth() <= 60)
    local fitted_left, with_ell = tw_left:getFittedText()
    assert.truthy(fitted_left)
    assert.is_true(with_ell)

    local tw_left_no_ell = TextWidget:new({
      text = long_text,
      face = face,
      max_width = 60,
      truncate_left = true,
      truncate_with_ellipsis = false,
      use_xtext = false,
    })
    assert.is_true(tw_left_no_ell:isTruncated())
    assert.is_true(tw_left_no_ell:getWidth() <= 60)
  end)

  it("should measure and truncate using xtext when use_xtext is true", function()
    local face = Font:getFace("infofont", 14)
    local tw_xtext = TextWidget:new({
      text = "Testing XText rendering and measuring",
      face = face,
      use_xtext = true,
    })

    assert.is_true(tw_xtext:getWidth() > 0)
    local fitted, with_ell = tw_xtext:getFittedText()
    assert.are.equal("Testing XText rendering and measuring", fitted)
    assert.is_nil(with_ell)

    local tw_xtext_trunc = TextWidget:new({
      text = "Very long text to truncate with xtext line breaking",
      face = face,
      max_width = 50,
      truncate_with_ellipsis = true,
      use_xtext = true,
    })
    assert.is_true(tw_xtext_trunc:isTruncated())
    local fitted_t, with_ell_t = tw_xtext_trunc:getFittedText()
    assert.truthy(fitted_t)

    local tw_xtext_left = TextWidget:new({
      text = "Very long text to truncate on left with xtext",
      face = face,
      max_width = 50,
      truncate_left = true,
      truncate_with_ellipsis = true,
      use_xtext = true,
    })
    assert.is_true(tw_xtext_left:isTruncated())
  end)

  it("should update when setText and setMaxWidth are called", function()
    local face = Font:getFace("infofont", 14)
    local tw = TextWidget:new({
      text = "Original",
      face = face,
      use_xtext = false,
    })
    local w1 = tw:getWidth()

    tw:setText("Original") -- no-op
    assert.are.equal(w1, tw:getWidth())

    tw:setText("Much Longer Text That Has Larger Width")
    local w2 = tw:getWidth()
    assert.is_true(w2 > w1)

    tw:setMaxWidth(30)
    local w3 = tw:getWidth()
    assert.is_true(w3 <= 30)

    tw:setMaxWidth(30) -- no-op
    assert.are.equal(w3, tw:getWidth())
  end)

  it("should paint to blitbuffer without xtext", function()
    local face = Font:getFace("infofont", 14)
    local tw = TextWidget:new({
      text = "Paint test",
      face = face,
      use_xtext = false,
    })

    local bb = Blitbuffer.new(200, 50)
    tw:paintTo(bb, 0, 0)
    bb:free()
  end)

  it("should paint to blitbuffer with xtext", function()
    local face = Font:getFace("infofont", 14)
    local tw = TextWidget:new({
      text = "Paint XText",
      face = face,
      use_xtext = true,
      max_width = 80,
    })

    local bb = Blitbuffer.new(200, 50)
    tw:paintTo(bb, 0, 0)
    bb:free()
  end)

  it("should free and onClose cleanly", function()
    local face = Font:getFace("infofont", 14)
    local tw = TextWidget:new({
      text = "Free test",
      face = face,
      use_xtext = true,
    })
    tw:getSize()
    assert.truthy(tw._xtext)

    tw:onClose()
    assert.is_nil(tw._xtext)
    assert.is_false(tw._updated)
  end)
end)
