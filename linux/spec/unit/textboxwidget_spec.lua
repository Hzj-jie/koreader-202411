describe("TextBoxWidget widget", function()
  require("commonrequire")
  local TextBoxWidget = require("ui/widget/textboxwidget")
  local Font = require("ui/font")

  setup(function()
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))
  end)

  teardown(function()
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))
  end)

  it("should wrap text correctly and detect holds", function()
    local tw = TextBoxWidget:new({
      dimen = { x = 0, y = 0 },
      face = Font:getFace("cfont", 25),
      text = "Foo welcomes Bar into the fun.",
    })
    tw:onHoldStartText(nil, { pos = { x = 50, y = 10 } })
    tw:onHoldReleaseText(function(w)
      assert.is.same(w, "welcomes Bar into")
    end, { pos = { x = 240, y = 10 } })

    -- Test multiline wrapping
    tw = TextBoxWidget:new({
      dimen = { x = 0, y = 0 },
      face = Font:getFace("cfont", 25),
      text = "Foo welcomes Bar into\nthe fun.",
    })
    tw:onHoldStartText(nil, { pos = { x = 240, y = 10 } })
    tw:onHoldReleaseText(function(w)
      assert.is.same(w, "Bar.\nFoo welcomes Bar into")
    end, { pos = { x = 240, y = 100 } })
  end)

  it(
    "should handle nil face gracefully by falling back to default face",
    function()
      local tw
      assert.has_no.errors(function()
        tw = TextBoxWidget:new({
          dimen = { x = 0, y = 0 },
          text = "Hello World",
        })
      end)
      assert.is_not_nil(tw.face)
      assert.are.equal(tw.face.realname, Font.fontmap.cfont)
    end
  )

  it(
    "should set and clear selection indexes on drag/pan and release",
    function()
      local tw = TextBoxWidget:new({
        dimen = { x = 0, y = 0 },
        face = Font:getFace("cfont", 25),
        text = "Foo welcomes Bar into the fun.",
      })

      assert.is_nil(tw.sel_start_idx)
      assert.is_nil(tw.sel_end_idx)

      -- 1. Start selection
      tw:onHoldStartText(nil, { pos = { x = 50, y = 10 } })
      assert.is_nil(tw.sel_start_idx)
      assert.is_nil(tw.sel_end_idx)

      -- 2. Drag/Pan to select more text
      tw:onHoldPanText(nil, { pos = { x = 240, y = 10 } })
      assert.is_not_nil(tw.sel_start_idx)
      assert.is_not_nil(tw.sel_end_idx)
      -- Verify that start is before end
      assert.is_true(tw.sel_start_idx < tw.sel_end_idx)

      -- 3. Release selection
      tw:onHoldReleaseText(function(w)
        assert.is.same(w, "welcomes Bar into")
      end, { pos = { x = 240, y = 10 } })

      -- Selection indexes must be cleared after release
      assert.is_nil(tw.sel_start_idx)
      assert.is_nil(tw.sel_end_idx)
    end
  )
end)
