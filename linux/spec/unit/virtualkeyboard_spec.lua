describe("VirtualKeyboard component", function()
  local Device, VirtualKeyboard, UIManager
  local settings_store

  setup(function()
    require("commonrequire")
    package.unloadAll()
    local device = require("device")
    require("document/canvascontext"):init(device)

    Device = require("device")
    VirtualKeyboard = require("ui/widget/virtualkeyboard")
    UIManager = require("ui/uimanager")
  end)

  before_each(function()
    UIManager._window_stack = {}
    settings_store = {
      keyboard_layouts = { "en", "es" },
      keyboard_layout = "en",
    }
    _G.G_reader_settings = {
      read = function(self, key)
        return settings_store[key]
      end,
      save = function(self, key, val)
        settings_store[key] = val
      end,
      nilOrTrue = function(self, key)
        return settings_store[key] ~= false
      end,
      isTrue = function(self, key)
        return settings_store[key] == true
      end,
      isFalse = function(self, key)
        return settings_store[key] == false
      end,
      readTableRef = function(self, key)
        return settings_store[key] or { "en" }
      end,
    }
    Device.performHapticFeedback = function() end
  end)

  after_each(function()
    UIManager._window_stack = {}
  end)

  local function createMockInputbox()
    local actions = {
      added_chars = {},
      del_char_called = 0,
      del_word_called = {},
      del_to_start_called = 0,
      left_char_called = 0,
      right_char_called = 0,
      go_to_start_called = 0,
      go_to_end_called = 0,
      up_line_called = 0,
      down_line_called = 0,
      scroll_up_called = 0,
      scroll_down_called = 0,
      keyboard_closed_called = 0,
      keyboard_height_changed_called = 0,
    }

    local mock_parent = {
      onKeyboardClosed = function()
        actions.keyboard_closed_called = actions.keyboard_closed_called + 1
      end,
      onKeyboardHeightChanged = function()
        actions.keyboard_height_changed_called = actions.keyboard_height_changed_called
          + 1
      end,
    }

    local mock_inputbox = {
      parent = mock_parent,
      addChars = function(_, char)
        table.insert(actions.added_chars, char)
      end,
      delChar = function()
        actions.del_char_called = actions.del_char_called + 1
      end,
      delWord = function(_, left_to_cursor)
        table.insert(actions.del_word_called, left_to_cursor)
      end,
      delToStartOfLine = function()
        actions.del_to_start_called = actions.del_to_start_called + 1
      end,
      leftChar = function()
        actions.left_char_called = actions.left_char_called + 1
      end,
      rightChar = function()
        actions.right_char_called = actions.right_char_called + 1
      end,
      goToStartOfLine = function()
        actions.go_to_start_called = actions.go_to_start_called + 1
      end,
      goToEndOfLine = function()
        actions.go_to_end_called = actions.go_to_end_called + 1
      end,
      upLine = function()
        actions.up_line_called = actions.up_line_called + 1
      end,
      downLine = function()
        actions.down_line_called = actions.down_line_called + 1
      end,
      scrollUp = function()
        actions.scroll_up_called = actions.scroll_up_called + 1
      end,
      scrollDown = function()
        actions.scroll_down_called = actions.scroll_down_called + 1
      end,
      scheduleRepaint = function() end,
    }

    return mock_inputbox, actions
  end

  local function findKey(vk, target_label)
    for _, row in ipairs(vk.layout) do
      for _, key_widget in ipairs(row) do
        if
          key_widget.label == target_label or key_widget.key == target_label
        then
          return key_widget
        end
      end
    end
    return nil
  end

  it(
    "should instantiate and forward character inputs to target inputbox",
    function()
      local mock_inputbox, actions = createMockInputbox()

      local vk = VirtualKeyboard:new({
        inputbox = mock_inputbox,
        width = 600,
        height = 300,
      })

      assert.is_not_nil(vk)
      assert.is_true(vk:isAlwaysOnTop())

      -- Test direct delegation methods
      vk:addChar("x")
      assert.is.same({ "x" }, actions.added_chars)

      vk:delChar()
      assert.is_equal(1, actions.del_char_called)

      vk:delWord(true)
      assert.is.same({ true }, actions.del_word_called)

      vk:delToStartOfLine()
      assert.is_equal(1, actions.del_to_start_called)

      vk:leftChar()
      assert.is_equal(1, actions.left_char_called)

      vk:rightChar()
      assert.is_equal(1, actions.right_char_called)

      vk:goToStartOfLine()
      assert.is_equal(1, actions.go_to_start_called)

      vk:goToEndOfLine()
      assert.is_equal(1, actions.go_to_end_called)

      vk:upLine()
      assert.is_equal(1, actions.up_line_called)

      vk:downLine()
      assert.is_equal(1, actions.down_line_called)

      vk:scrollUp()
      assert.is_equal(1, actions.scroll_up_called)

      vk:scrollDown()
      assert.is_equal(1, actions.scroll_down_called)
    end
  )

  it("should trigger inputbox actions when virtual keys are tapped", function()
    local mock_inputbox, actions = createMockInputbox()

    local vk = VirtualKeyboard:new({
      inputbox = mock_inputbox,
      width = 600,
      height = 300,
    })
    vk:showKeyboard()

    local key_a = findKey(vk, "a")
    assert.is_not_nil(key_a)

    key_a:onTapSelect(true)
    assert.is.same({ "a" }, actions.added_chars)
    vk:hideKeyboard()
  end)

  it("should handle focus and unfocus on virtual keys", function()
    local mock_inputbox = createMockInputbox()
    local vk = VirtualKeyboard:new({
      inputbox = mock_inputbox,
      width = 600,
      height = 300,
    })

    local key_a = findKey(vk, "a")
    assert.is_not_nil(key_a)

    key_a:onFocus()
    assert.is_equal(key_a.focused_bordersize, key_a[1].inner_bordersize)

    key_a:onUnfocus()
    assert.is_equal(0, key_a[1].inner_bordersize)
  end)

  it("should handle layer and mode switching", function()
    local mock_inputbox = createMockInputbox()
    local vk = VirtualKeyboard:new({
      inputbox = mock_inputbox,
      width = 600,
      height = 300,
    })

    assert.is_false(vk.shiftmode)
    assert.is_false(vk.symbolmode)
    assert.is_false(vk.umlautmode)

    -- Toggle shift
    vk:setLayer("Shift")
    assert.is_true(vk.shiftmode)

    vk:setLayer("Shift")
    assert.is_false(vk.shiftmode)

    -- Toggle symbol
    vk:setLayer("Sym")
    assert.is_true(vk.symbolmode)

    vk:setLayer("ABC")
    assert.is_false(vk.symbolmode)

    -- Toggle umlaut
    vk:setLayer("Äéß")
    assert.is_true(vk.umlautmode)

    vk:setLayer("Äéß")
    assert.is_false(vk.umlautmode)
  end)

  it(
    "should handle single shift and caps lock via shift key tap/hold",
    function()
      local mock_inputbox, actions = createMockInputbox()
      local vk = VirtualKeyboard:new({
        inputbox = mock_inputbox,
        width = 600,
        height = 300,
      })
      vk:showKeyboard()

      local shift_key = findKey(vk, "")
      assert.is_not_nil(shift_key)

      -- Tap shift key -> enables shiftmode with release_shift = true
      shift_key:onTapSelect(true)
      assert.is_true(vk.shiftmode)
      assert.is_true(vk.release_shift)

      -- Typing a character in shiftmode should switch shift off after character input
      local key_A = findKey(vk, "A")
      assert.is_not_nil(key_A)
      key_A:onTapSelect(true)
      assert.is.same({ "A" }, actions.added_chars)
      assert.is_false(vk.shiftmode)

      -- Hold shift key -> enables shiftmode with release_shift = false (Caps Lock)
      shift_key:onHoldSelect()
      assert.is_true(vk.shiftmode)
      assert.is_false(vk.release_shift)

      key_A = findKey(vk, "A")
      assert.is_not_nil(key_A)
      key_A:onTapSelect(true)
      assert.is.same({ "A", "A" }, actions.added_chars)
      assert.is_true(vk.shiftmode)

      vk:hideKeyboard()
    end
  )

  it("should handle backspace key tap, hold, and swipe actions", function()
    local mock_inputbox, actions = createMockInputbox()
    local vk = VirtualKeyboard:new({
      inputbox = mock_inputbox,
      width = 600,
      height = 300,
    })
    vk:showKeyboard()

    local backspace_key = findKey(vk, "")
    assert.is_not_nil(backspace_key)

    -- Tap backspace
    backspace_key:onTapSelect(true)
    assert.is_equal(1, actions.del_char_called)

    -- Hold backspace
    backspace_key:onHoldSelect()
    assert.is_equal(1, actions.del_to_start_called)

    -- Swipe west backspace
    backspace_key:onSwipeKey(nil, { direction = "west" })
    assert.is.same({ true }, actions.del_word_called)

    -- Swipe north backspace
    backspace_key:onSwipeKey(nil, { direction = "north" })
    assert.is.same({ true, nil }, actions.del_word_called)

    vk:hideKeyboard()
  end)

  it("should handle navigation arrow key tap and hold actions", function()
    local mock_inputbox, actions = createMockInputbox()
    local vk = VirtualKeyboard:new({
      inputbox = mock_inputbox,
      width = 600,
      height = 300,
    })
    vk:showKeyboard()

    local left_key = findKey(vk, "←")
    local right_key = findKey(vk, "→")

    assert.is_not_nil(left_key)
    assert.is_not_nil(right_key)

    left_key:onTapSelect(true)
    assert.is_equal(1, actions.left_char_called)

    left_key:onHoldSelect()
    assert.is_equal(1, actions.go_to_start_called)

    right_key:onTapSelect(true)
    assert.is_equal(1, actions.right_char_called)

    right_key:onHoldSelect()
    assert.is_equal(1, actions.go_to_end_called)

    -- Switch to symbol mode to access ↑ and ↓ keys
    vk:setLayer("Sym")
    local up_key = findKey(vk, "↑")
    local down_key = findKey(vk, "↓")

    assert.is_not_nil(up_key)
    assert.is_not_nil(down_key)

    up_key:onTapSelect(true)
    assert.is_equal(1, actions.up_line_called)

    up_key:onHoldSelect()
    assert.is_equal(1, actions.scroll_up_called)

    down_key:onTapSelect(true)
    assert.is_equal(1, actions.down_line_called)

    down_key:onHoldSelect()
    assert.is_equal(1, actions.scroll_down_called)

    vk:hideKeyboard()
  end)

  it("should fall back to tap when swipes are disabled", function()
    local mock_inputbox, actions = createMockInputbox()
    settings_store["keyboard_swipes_enabled"] = false

    local vk = VirtualKeyboard:new({
      inputbox = mock_inputbox,
      width = 600,
      height = 300,
    })
    vk:showKeyboard()

    local key_a = findKey(vk, "a")
    assert.is_not_nil(key_a)

    key_a:onSwipeKey(nil, { direction = "north" })
    assert.is.same({ "a" }, actions.added_chars)

    vk:hideKeyboard()
  end)

  it("should handle layout retrieval and switching", function()
    local mock_inputbox = createMockInputbox()
    settings_store["keyboard_remember_layout"] = false
    settings_store["keyboard_layout_default"] = "es"

    local vk = VirtualKeyboard:new({
      inputbox = mock_inputbox,
      width = 600,
      height = 300,
    })

    assert.is_equal("es", vk:getKeyboardLayout())

    vk:setKeyboardLayout("en")
    assert.is_equal("en", settings_store["keyboard_layout"])
  end)

  it("should manage visibility and exit events", function()
    local mock_inputbox, actions = createMockInputbox()
    local vk = VirtualKeyboard:new({
      inputbox = mock_inputbox,
      width = 600,
      height = 300,
    })

    vk:showKeyboard(true)
    assert.is_true(vk:isVisible())
    assert.is_true(vk.ignore_first_hold_release)

    vk:hideKeyboard()
    assert.is_false(vk:isVisible())

    vk:showKeyboard()
    assert.is_true(vk:isVisible())

    actions.keyboard_closed_called = 0
    assert.is_true(vk:onKeyboardBack())
    assert.is_false(vk:isVisible())
    assert.is_equal(1, actions.keyboard_closed_called)

    local size = vk:visibleSize()
    assert.is_not_nil(size)
    assert.is_number(size.w)
    assert.is_number(size.h)
  end)

  it("should not trigger assertion under normal conditions", function()
    local mock_inputbox = createMockInputbox()
    local vk = VirtualKeyboard:new({
      inputbox = mock_inputbox,
      width = 600,
      height = 300,
    })

    assert.has_no.errors(function()
      vk:setVisibility(true)
    end)

    assert.has_no.errors(function()
      vk:setVisibility(false)
    end)
  end)

  it("should trigger assertion when showing multiple instances", function()
    local mock_inputbox = createMockInputbox()
    local vk1 = VirtualKeyboard:new({
      inputbox = mock_inputbox,
      width = 600,
      height = 300,
    })
    local vk2 = VirtualKeyboard:new({
      inputbox = mock_inputbox,
      width = 600,
      height = 300,
    })

    vk1:setVisibility(true)

    assert.has.errors(function()
      vk2:setVisibility(true)
    end, "Multiple VirtualKeyboard instances detected!")

    -- Cleanup
    vk1:setVisibility(false)
    UIManager:close(vk2)
  end)
end)
