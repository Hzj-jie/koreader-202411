describe("FocusManager module", function()
  local FocusManager
  local layout, big_layout
  local Key
  local Input
  local Up = function(self)
    self:onFocusMove({ 0, -1 })
  end
  local Down = function(self)
    self:onFocusMove({ 0, 1 })
  end
  local Left = function(self)
    self:onFocusMove({ -1, 0 })
  end
  local Right = function(self)
    self:onFocusMove({ 1, 0 })
  end
  local Next = function(self)
    self:onFocusNext()
  end
  local Previous = function(self)
    self:onFocusPrevious()
  end
  local HalfMoveUp = function(self)
    self:onFocusHalfMove({ "up" })
  end
  local HalfMoveDown = function(self)
    self:onFocusHalfMove({ "down" })
  end
  local HalfMoveLeft = function(self)
    self:onFocusHalfMove({ "left" })
  end
  local HalfMoveRight = function(self)
    self:onFocusHalfMove({ "right" })
  end
  local MoveTo = function(self, x, y)
    self:moveFocusTo(x, y)
  end
  setup(function()
    require("commonrequire")
    FocusManager = require("ui/widget/focusmanager")
    Key = require("device/key")
    Input = require("device/input")
    local Widget = require("ui/widget/textwidget")
    local w = Widget:new({})
    layout = {
      { w, w, w },
      { nil, w, nil },
      { nil, w, nil },
    }
    big_layout = {
      { w, w, w, w, w },
      { w, w, w, w, w },
      { w, w, w, w, w },
      { w, w, w, w, w },
      { w, w, w, w, w },
    }
  end)
  it("should go right", function()
    local focusmanager = FocusManager:new({})
    focusmanager.layout = layout
    focusmanager.selected = { y = 1, x = 1 }
    Right(focusmanager)
    assert.are.same({ y = 1, x = 2 }, focusmanager.selected)
  end)
  it("should go left", function()
    local focusmanager = FocusManager:new({})
    focusmanager.layout = layout
    focusmanager.selected = { y = 1, x = 2 }
    Left(focusmanager)
    assert.are.same({ y = 1, x = 1 }, focusmanager.selected)
  end)
  it("should go up", function()
    local focusmanager = FocusManager:new({})
    focusmanager.layout = layout
    focusmanager.selected = { y = 2, x = 2 }
    Up(focusmanager)
    assert.are.same({ y = 1, x = 2 }, focusmanager.selected)
  end)
  it("should go down", function()
    local focusmanager = FocusManager:new({})
    focusmanager.layout = layout
    focusmanager.selected = { y = 2, x = 2 }
    Down(focusmanager)
    assert.are.same({ y = 3, x = 2 }, focusmanager.selected)
  end)
  it("should vertical wrapAround up", function()
    local focusmanager = FocusManager:new({})
    focusmanager.layout = layout
    focusmanager.selected = { y = 1, x = 1 }
    Up(focusmanager)
    assert.are.same({ y = 3, x = 2 }, focusmanager.selected)
  end)
  it("should vertical wrapAround down", function()
    local focusmanager = FocusManager:new({})
    focusmanager.layout = layout
    focusmanager.selected = { y = 3, x = 2 }
    Down(focusmanager)
    assert.are.same({ y = 1, x = 2 }, focusmanager.selected)
  end)
  it("should do vertical step to the right", function()
    local focusmanager = FocusManager:new({})
    focusmanager.layout = layout
    focusmanager.selected = { y = 1, x = 1 }
    Down(focusmanager)
    assert.are.same({ y = 2, x = 2 }, focusmanager.selected)
  end)
  it("should do vertical step to the left", function()
    local focusmanager = FocusManager:new({})
    focusmanager.layout = layout
    focusmanager.selected = { y = 1, x = 3 }
    Down(focusmanager)
    assert.are.same({ y = 2, x = 2 }, focusmanager.selected)
  end)
  it("should respect left limit", function()
    local focusmanager = FocusManager:new({})
    focusmanager.layout = layout
    focusmanager.selected = { y = 2, x = 2 }
    Left(focusmanager)
    assert.are.same({ y = 2, x = 2 }, focusmanager.selected)
  end)
  it("should respect right limit", function()
    local focusmanager = FocusManager:new({})
    focusmanager.layout = layout
    focusmanager.selected = { y = 2, x = 2 }
    Right(focusmanager)
    assert.are.same({ y = 2, x = 2 }, focusmanager.selected)
  end)
  it("should move next right", function()
    local focusmanager = FocusManager:new({})
    focusmanager.layout = layout
    focusmanager.selected = { y = 1, x = 2 }
    Next(focusmanager)
    assert.are.same({ y = 1, x = 3 }, focusmanager.selected)
  end)
  it("should move next row at end of row", function()
    local focusmanager = FocusManager:new({})
    focusmanager.layout = layout
    focusmanager.selected = { y = 1, x = 3 }
    Next(focusmanager)
    assert.are.same({ y = 2, x = 2 }, focusmanager.selected)
  end)
  it("should move to first item of next row on Next at end of row", function()
    local w = layout[1][1]
    local focusmanager = FocusManager:new({})
    focusmanager.layout = {
      { w, w, w },
      { w, w },
    }
    focusmanager.selected = { y = 1, x = 3 }
    Next(focusmanager)
    assert.are.same({ y = 2, x = 1 }, focusmanager.selected)
  end)
  it("should move next left", function()
    local focusmanager = FocusManager:new({})
    focusmanager.layout = layout
    focusmanager.selected = { y = 1, x = 2 }
    Previous(focusmanager)
    assert.are.same({ y = 1, x = 1 }, focusmanager.selected)
  end)
  it("should move previous at start of row", function()
    local focusmanager = FocusManager:new({})
    focusmanager.layout = layout
    focusmanager.selected = { y = 3, x = 2 }
    Previous(focusmanager)
    assert.are.same({ y = 2, x = 2 }, focusmanager.selected)
  end)
  it(
    "should move to last item of previous row on Previous at start of row",
    function()
      local w = layout[1][1]
      local focusmanager = FocusManager:new({})
      focusmanager.layout = {
        { w, w },
        { w, w, w },
      }
      focusmanager.selected = { y = 2, x = 1 }
      Previous(focusmanager)
      assert.are.same({ y = 1, x = 2 }, focusmanager.selected)
    end
  )
  it("should move half rows or columns", function()
    local focusmanager = FocusManager:new({})
    focusmanager.layout = big_layout
    focusmanager.selected = { x = 1, y = 1 }
    HalfMoveRight(focusmanager)
    assert.are.same({ y = 1, x = 3 }, focusmanager.selected)
    HalfMoveDown(focusmanager)
    assert.are.same({ y = 3, x = 3 }, focusmanager.selected)
    HalfMoveLeft(focusmanager)
    assert.are.same({ y = 3, x = 1 }, focusmanager.selected)
    HalfMoveUp(focusmanager)
    assert.are.same({ y = 1, x = 1 }, focusmanager.selected)
  end)
  it("should move to specified position", function()
    local focusmanager = FocusManager:new({})
    focusmanager.layout = big_layout
    focusmanager.selected = { x = 1, y = 1 }
    MoveTo(focusmanager, 3, 4)
    assert.are.same({ y = 4, x = 3 }, focusmanager.selected)
  end)
  it("should set layout to nil", function()
    local focusmanager = FocusManager:new({})
    focusmanager.layout = layout
    focusmanager:disableFocusManagement()
    assert.is_nil(focusmanager.layout)
  end)
  it("should merge into rows", function()
    local w = layout[1][1]
    local fm1 = FocusManager:new({})
    fm1.layout = {
      { w, w, w },
    }
    local fm2 = FocusManager:new({})
    fm2.layout = {
      { w, w },
    }
    fm1:mergeLayoutInVertical(fm2)
    local expected = {
      { w, w, w },
      { w, w },
    }
    assert.are.same(expected, fm1.layout)
  end)
  it("should merge into rows at specified position", function()
    local w = layout[1][1]
    local fm1 = FocusManager:new({})
    fm1.layout = {
      { w, w, w },
      { w, w, w },
    }
    local fm2 = FocusManager:new({})
    fm2.layout = {
      { w, w },
    }
    fm1:mergeLayoutInVertical(fm2, 2)
    local expected = {
      { w, w, w },
      { w, w },
      { w, w, w },
    }
    assert.are.same(expected, fm1.layout)
  end)
  it("should merge into columns", function()
    local w = layout[1][1]
    local fm1 = FocusManager:new({})
    fm1.layout = {
      { w },
      { w },
    }
    local fm2 = FocusManager:new({})
    fm2.layout = {
      { w, w },
      { w },
    }
    fm1:mergeLayoutInHorizontal(fm2, 2)
    local expected = {
      { w, w, w },
      { w, w },
    }
    assert.are.same(expected, fm1.layout)
  end)
  it("alternative key", function()
    local focusmanager = FocusManager:new({})
    focusmanager.extra_key_events = {
      Hold = { { "Sym", "AA" }, event = "Hold" },
      HalfFocusUp = {
        { "Alt", "Up" },
        event = "FocusHalfMove",
        args = { "up" },
      },
    }
    local m = Input.modifiers
    m.Sym = true
    assert.is_true(focusmanager:isAlternativeKey(Key:new("AA", m)))
    m.Sym = false
    m.Alt = true
    assert.is_true(focusmanager:isAlternativeKey(Key:new("Up", m)))
    m.Alt = false
    assert.is_false(focusmanager:isAlternativeKey(Key:new("AA", m)))
    assert.is_false(focusmanager:isAlternativeKey(Key:new("Up", m)))
  end)

  it(
    "should not loop infinitely when navigating layout with only inactive items",
    function()
      local TextWidget = require("ui/widget/textwidget")
      local wi = TextWidget:new({ is_inactive = true })

      local focusmanager = FocusManager:new({})
      focusmanager.layout = {
        { wi, wi },
      }
      focusmanager.selected = { y = 1, x = 1 }

      local calls = 0
      local original_wrapAroundX = focusmanager._wrapAroundX
      focusmanager._wrapAroundX = function(self, dx)
        calls = calls + 1
        if calls > 5 then
          error("Infinite loop detected in _wrapAroundX!")
        end
        return original_wrapAroundX(self, dx)
      end

      assert.has_no.errors(function()
        Right(focusmanager)
      end)
    end
  )
  it("should not focus inactive widget even if it is different", function()
    local TextWidget = require("ui/widget/textwidget")
    local wi1 = TextWidget:new({ is_inactive = true, name = "wi1" })
    local wi2 = TextWidget:new({ is_inactive = true, name = "wi2" })
    local w3 = TextWidget:new({ name = "w3" })

    local focusmanager = FocusManager:new({})
    focusmanager.layout = {
      { wi1, wi2, w3 },
    }
    focusmanager.selected = { y = 1, x = 1 }

    Right(focusmanager)
    assert.are.same({ y = 1, x = 3 }, focusmanager.selected)
  end)

  it("should send tap and hold gesture events on onPress and onHold", function()
    local Geom = require("ui/geometry")
    local UIManager = require("ui/uimanager")
    local TextWidget = require("ui/widget/textwidget")
    local w = TextWidget:new({ text = "Focused", dimen = Geom:new({ x = 10, y = 20, w = 100, h = 40 }) })

    local focusmanager = FocusManager:new({})
    focusmanager.layout = { { w } }
    focusmanager.selected = { y = 1, x = 1 }

    local user_input_event = nil
    local old_userInput = UIManager.userInput
    UIManager.userInput = function(self, ev)
      user_input_event = ev
    end

    -- onPress sends "tap"
    assert.is_true(focusmanager:onPress())
    assert.is_not_nil(user_input_event)
    assert.are.equal("tap", user_input_event.args.ges)
    assert.are.equal(60, user_input_event.args.pos.x)
    assert.are.equal(40, user_input_event.args.pos.y)

    -- onHold sends "hold"
    assert.is_true(focusmanager:onHold())
    assert.are.equal("hold", user_input_event.args.ges)

    -- layout nil returns false
    focusmanager.layout = nil
    assert.is_false(focusmanager:onPress())
    assert.is_false(focusmanager:onHold())

    UIManager.userInput = old_userInput
  end)

  it("should handle refocusWidget with RENDER_NOW, RENDER_IN_NEXT_TICK, and parent delegation", function()
    local UIManager = require("ui/uimanager")
    local TextWidget = require("ui/widget/textwidget")
    local w = TextWidget:new({ text = "Item" })

    local focusmanager = FocusManager:new({})
    focusmanager.layout = { { w } }
    focusmanager.selected = { y = 1, x = 1 }

    local moved_x, moved_y
    focusmanager.moveFocusTo = function(self, x, y, flags)
      moved_x = x
      moved_y = y
    end

    -- RENDER_NOW
    focusmanager:refocusWidget(FocusManager.RENDER_NOW)
    assert.are.equal(1, moved_x)
    assert.are.equal(1, moved_y)

    -- RENDER_IN_NEXT_TICK
    local next_tick_cb = nil
    local old_nextTick = UIManager.nextTick
    UIManager.nextTick = function(self, cb)
      next_tick_cb = cb
    end
    moved_x, moved_y = nil, nil
    focusmanager:refocusWidget(FocusManager.RENDER_IN_NEXT_TICK)
    assert.is_function(next_tick_cb)
    next_tick_cb()
    assert.are.equal(1, moved_x)
    assert.are.equal(1, moved_y)

    -- Parent delegation
    local parent_refocused = false
    local parent_mock = {
      refocusWidget = function()
        parent_refocused = true
      end,
    }
    focusmanager._parent = parent_mock
    focusmanager:refocusWidget(FocusManager.RENDER_NOW)
    assert.is_true(parent_refocused)
    assert.is_nil(focusmanager._parent)

    UIManager.nextTick = old_nextTick
  end)

  it("should handle onPhysicalKeyboardConnected and onPhysicalKeyboardDisconnected", function()
    local focusmanager = FocusManager:new({})
    assert.has_no.errors(function()
      focusmanager:onPhysicalKeyboardConnected()
      focusmanager:onPhysicalKeyboardDisconnected()
    end)
  end)
end)
