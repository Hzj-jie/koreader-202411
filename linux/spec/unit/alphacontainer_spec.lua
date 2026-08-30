describe("AlphaContainer widget", function()
  local AlphaContainer, Blitbuffer, Geom, Widget

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    AlphaContainer = require("ui/widget/container/alphacontainer")
    Blitbuffer = require("ffi/blitbuffer")
    Geom = require("ui/geometry")
    Widget = require("ui/widget/widget")
  end)

  it("should initialize alpha container", function()
    local inner_widget =
      Widget:new({ dimen = Geom:new({ x = 0, y = 0, w = 50, h = 50 }) })
    local container = AlphaContainer:new({
      [1] = inner_widget,
      alpha = 0.5,
    })

    assert.is_table(container)
    assert.are.equal(0.5, container.alpha)
  end)

  it(
    "should paint to target blitbuffer and reuse/free private blitbuffer on close",
    function()
      local child = Widget:new({
        dimen = Geom:new({ x = 0, y = 0, w = 100, h = 100 }),
        paintTo = function(self, target_bb, x, y) end,
      })

      local container = AlphaContainer:new({
        [1] = child,
        alpha = 0.8,
      })

      local target_bb = Blitbuffer.new(200, 200)
      container:paintTo(target_bb, 10, 10)

      assert.is_not_nil(container.private_bb)
      assert.are.equal(100, container.private_bb:getWidth())
      assert.are.equal(100, container.private_bb:getHeight())

      -- Close container and free private blitbuffer
      container:onClose()
      assert.is_nil(container.private_bb)

      target_bb:free()
    end
  )
end)
