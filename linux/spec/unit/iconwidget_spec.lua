describe("IconWidget", function()
  local IconWidget

  setup(function()
    require("commonrequire")
    IconWidget = require("ui/widget/iconwidget")
  end)

  it("should initialize with found icon", function()
    local icon = IconWidget:new({
      icon = "appbar.menu",
    })

    assert.truthy(icon.file)
    assert.is_true(icon.is_icon)
  end)

  it("should fallback to icon-not-found for missing icon", function()
    local icon = IconWidget:new({
      icon = "nonexistent_custom_icon_xyz",
    })

    assert.truthy(icon.file)
    assert.truthy(icon.file:find("icon-not-found"))
  end)

  it("should pass through existing image or file attribute", function()
    local icon_img = IconWidget:new({
      file = "/tmp/test.png",
    })
    assert.are.equal("/tmp/test.png", icon_img.file)
  end)
end)
