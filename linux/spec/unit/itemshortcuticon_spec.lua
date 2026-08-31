describe("ItemShortCutIcon", function()
  local ItemShortCutIcon
  local Geom
  local Blitbuffer

  setup(function()
    require("commonrequire")
    ItemShortCutIcon = require("ui/widget/itemshortcuticon")
    Geom = require("ui/geometry")
    Blitbuffer = require("ffi/blitbuffer")
  end)

  it("should initialize single letter shortcut icon", function()
    local icon = ItemShortCutIcon:new({
      key = "A",
      dimen = Geom:new({ w = 30, h = 30 }),
    })

    assert.truthy(icon[1])
    assert.are.equal(Blitbuffer.COLOR_WHITE, icon[1].background)
  end)

  it("should initialize multi-letter shortcut icon with grey_square style", function()
    local icon = ItemShortCutIcon:new({
      key = "Del",
      style = "grey_square",
      dimen = Geom:new({ w = 40, h = 30 }),
    })

    assert.truthy(icon[1])
    assert.are.equal(Blitbuffer.COLOR_LIGHT_GRAY, icon[1].background)
  end)

  it("should return early when key is nil", function()
    local icon = ItemShortCutIcon:new({})
    assert.is_nil(icon[1])
  end)
end)
