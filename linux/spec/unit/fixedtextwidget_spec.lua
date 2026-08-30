describe("FixedTextWidget module", function()
  local FixedTextWidget, Font

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    FixedTextWidget = require("ui/widget/fixedtextwidget")
    Font = require("ui/font")
  end)

  it("should initialize FixedTextWidget and update size correctly", function()
    local widget = FixedTextWidget:new({
      text = "Sample Text",
      face = Font:getFace("infofont", 14),
    })

    assert.is_table(widget)
    local size = widget:getSize()
    assert.is_table(size)
    assert.is_number(size.w)
    assert.is_number(size.h)
  end)

  it("should handle empty text gracefully", function()
    local widget = FixedTextWidget:new({
      text = "",
      face = Font:getFace("infofont", 14),
    })

    local size = widget:getSize()
    assert.is_table(size)
    assert.are.equal(0, size.w)
    assert.are.equal(0, size.h)
  end)
end)
