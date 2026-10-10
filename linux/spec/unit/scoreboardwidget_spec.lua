describe("ScoreBoardWidget widget", function()
  local ScoreBoardWidget, Blitbuffer, UIManager

  setup(function()
    require("commonrequire")
    Blitbuffer = require("ffi/blitbuffer")
    UIManager = require("ui/uimanager")
    ScoreBoardWidget =
      require("plugins/game2048.koplugin/ui/widget/scoreboardwidget")
  end)

  local orig_setDirty
  local dirty_calls

  before_each(function()
    dirty_calls = {}
    orig_setDirty = UIManager.setDirty
    UIManager.setDirty = function(_, target, mode, dimen)
      table.insert(dirty_calls, { target = target, mode = mode, dimen = dimen })
    end
  end)

  after_each(function()
    UIManager.setDirty = orig_setDirty
  end)

  describe("Initialization & layout", function()
    it("should initialize ScoreBoardWidget with title and value", function()
      local widget = ScoreBoardWidget:new({
        name = "SCORE",
        value = "128",
      })
      assert.is_table(widget)
      assert.are.equal("SCORE", widget.name)
      assert.are.equal("128", widget.value)
      assert.is_nil(widget.dimen)

      local size = widget:getSize()
      assert.is_table(size)
      assert.is_true(size.w > 0)
      assert.is_true(size.h > 0)
    end)
  end)

  describe("paintTo and setValue lifecycle", function()
    it("should initialize dimen on paintTo and render to blitbuffer", function()
      local widget = ScoreBoardWidget:new({
        name = "BEST",
        value = "2048",
      })
      local size = widget:getSize()
      local bb = Blitbuffer.new(size.w + 20, size.h + 20)

      assert.is_nil(widget.dimen)
      widget:paintTo(bb, 10, 10)

      assert.is_not_nil(widget.dimen)
      assert.are.equal(10, widget.dimen.x)
      assert.are.equal(10, widget.dimen.y)
      assert.are.equal(size.w, widget.dimen.w)
      assert.are.equal(size.h, widget.dimen.h)
    end)

    it("should update value and schedule redraw only after dimen is populated", function()
      local widget = ScoreBoardWidget:new({
        name = "SCORE",
        value = "100",
      })

      -- Before paintTo, dimen is nil, so setValue does not call setDirty
      widget:setValue("200")
      assert.are.equal("200", widget._value_label.text)
      assert.are.equal(0, #dirty_calls)

      -- Populate dimen via paintTo
      local size = widget:getSize()
      local bb = Blitbuffer.new(size.w, size.h)
      widget:paintTo(bb, 0, 0)
      assert.is_not_nil(widget.dimen)

      -- After paintTo, setValue triggers setDirty with dimen
      widget:setValue("256")
      assert.are.equal("256", widget._value_label.text)
      assert.are.equal(1, #dirty_calls)
      assert.are.equal(widget, dirty_calls[1].target)
      assert.are.equal("fast", dirty_calls[1].mode)
      assert.are.equal(widget.dimen, dirty_calls[1].dimen)
    end)
  end)
end)
