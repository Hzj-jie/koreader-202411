describe("InputText widget module", function()
  local InputText
  local equals
  setup(function()
    require("commonrequire")
    InputText = require("ui/widget/inputtext"):new({})

    equals = require("util").tableEquals
  end)

  describe("addChars()", function()
    it("should add regular text", function()
      InputText:initTextBox("")
      InputText:addChars("a")
      assert.is_true(equals({ "a" }, InputText.charlist))
      InputText:addChars("aa")
      assert.is_true(equals({ "a", "a", "a" }, InputText.charlist))
    end)

    it("should add unicode text", function()
      InputText:initTextBox("")
      InputText:addChars("Л")
      assert.is_true(equals({ "Л" }, InputText.charlist))
      InputText:addChars("Луа")
      assert.is_true(equals({ "Л", "Л", "у", "а" }, InputText.charlist))
    end)

    it("should assert when added_charlist contains nil", function()
      local util = require("util")
      local old_split = util.splitToChars
      local mock_called = false
      -- Mock splitToChars to inject a nil
      util.splitToChars = function(s)
        if s == "inject_nil" then
          mock_called = true
          return { "a", nil, "b", "c" }
        else
          return old_split(s)
        end
      end

      InputText:initTextBox("")
      InputText.readonly = false
      assert.has_error(function()
        InputText:addChars("inject_nil")
      end)
      assert.is_true(mock_called)

      util.splitToChars = old_split
    end)
  end)

  describe("_setChar()", function()
    it("should write character at index", function()
      InputText.charlist = { "a" }
      InputText.charpos = 1
      InputText:_setChar(2, "b")
      assert.is_true(equals({ "a", "b" }, InputText.charlist))
    end)

    it("should pad gaps with spaces when writing past the end", function()
      InputText.charlist = { "a" }
      InputText.charpos = 1
      InputText:_setChar(5, "e")
      assert.is_true(equals({ "a", " ", " ", " ", "e" }, InputText.charlist))
    end)
  end)

  describe("initTextBox()", function()
    it("should reduce text_widget width by scrollbar required width", function()
      local input = require("ui/widget/inputtext"):new({
        width = 200,
      })
      input:initTextBox("")

      local expected_width = 200 - input.text_widget.reserved_width
      assert.are.equal(expected_width, input.text_widget.text_widget.width)
    end)
  end)

  describe("Text manipulation & deletion", function()
    it("should set and get text correctly", function()
      local input = require("ui/widget/inputtext"):new({
        text = "initial",
      })
      assert.are.equal("initial", input:getText())
      input:setText("updated")
      assert.are.equal("updated", input:getText())
    end)

    it("should handle delChar when text is not empty", function()
      local input = require("ui/widget/inputtext"):new({
        text = "abc",
      })
      input:delChar()
      assert.are.equal("ab", input:getText())
      input:delChar()
      assert.are.equal("a", input:getText())
      input:delChar()
      assert.are.equal("", input:getText())
      input:delChar()
      assert.are.equal("", input:getText())
    end)

    it("should handle delNextChar", function()
      local input = require("ui/widget/inputtext"):new({
        text = "abc",
      })
      input.charpos = 1
      input:delNextChar()
      assert.are.equal("bc", input:getText())
      input.charpos = 3
      input:delNextChar()
      assert.are.equal("bc", input:getText())
    end)

    it("should handle delWord and delToStartOfLine and delAll", function()
      local input = require("ui/widget/inputtext"):new({
        text = "hello world foo",
      })
      input:delWord()
      assert.are.equal("hello world", input:getText())

      input:setText("line one\nline two")
      input:goToEnd()
      input:delToStartOfLine()
      assert.are.equal("line one\n", input:getText())
      input:delToStartOfLine()
      assert.are.equal("line one", input:getText())

      input:delAll()
      assert.are.equal("", input:getText())
      input:delAll()
      assert.are.equal("", input:getText())
    end)
  end)

  describe("Cursor navigation and positioning", function()
    local input
    before_each(function()
      input = require("ui/widget/inputtext"):new({
        text = "hello world\nsecond line",
      })
    end)

    it(
      "should move cursor left, right, home, end, start/end of line",
      function()
        input:goToEnd()
        assert.is_number(input.charpos)

        input:leftChar()
        assert.is_number(input.charpos)

        input:rightChar()
        assert.is_number(input.charpos)

        input:goToHome()
        assert.is_number(input.charpos)

        input:goToStartOfLine()
        assert.is_number(input.charpos)

        input:goToEndOfLine()
        assert.is_number(input.charpos)

        input:moveCursorToCharPos(5)
        assert.are.equal(5, input.charpos)
      end
    )

    it("should navigate lines up and down", function()
      input:goToHome()
      input:downLine()
      assert.is_number(input.charpos)

      input:upLine()
      assert.is_number(input.charpos)

      local empty_input = require("ui/widget/inputtext"):new({ text = "" })
      empty_input:downLine()
      assert.are.equal(1, empty_input.charpos)
    end)

    it("should calculate line numbers and string positions", function()
      local curr, last = input:getLineNums()
      assert.are.equal(2, curr)
      assert.are.equal(2, last)

      local char_pos_1 = input:getLineCharPos(1)
      local char_pos_2 = input:getLineCharPos(2)
      assert.are.equal(1, char_pos_1)
      assert.are.equal(13, char_pos_2)

      local c_rel = input:getChar(-1)
      local c_abs = input:getChar(1, true)
      assert.are.equal("h", c_abs)
      assert.is_not_nil(c_rel)

      local s1, e1 = input:getStringPos(true)
      assert.is_number(s1)
      assert.is_number(e1)
    end)

    it("should handle scroll methods", function()
      input:scrollDown()
      input:scrollUp()
      input:scrollToTop()
      input:scrollToBottom()
      assert.is_number(input.charpos)
    end)
  end)

  describe("Initialization options & editability", function()
    it("should handle number input type conversion", function()
      local input = require("ui/widget/inputtext"):new({
        input_type = "number",
        text = 123,
        hint = 456,
      })
      assert.are.equal("123", input:getText())
      assert.are.equal("456", input.hint)
    end)

    it("should handle readonly state", function()
      local input = require("ui/widget/inputtext"):new({
        readonly = true,
        text = "readonly text",
      })
      assert.is_true(input.readonly)
      assert.is_nil(input.keyboard)
      local dimen = input:getKeyboardDimen()
      assert.are.equal(0, dimen.w)
      assert.are.equal(0, dimen.h)

      input:addChars("extra")
      assert.are.equal("readonly text", input:getText())

      input:delChar()
      assert.are.equal("readonly text", input:getText())

      input:delNextChar()
      assert.are.equal("readonly text", input:getText())

      input:delWord()
      assert.are.equal("readonly text", input:getText())

      input:delToStartOfLine()
      assert.are.equal("readonly text", input:getText())

      input:delAll()
      assert.are.equal("readonly text", input:getText())
    end)

    it("should report text edited state and invoke edit_callback", function()
      local edited_val
      local input = require("ui/widget/inputtext"):new({
        text = "start",
        edit_callback = function(is_edited)
          edited_val = is_edited
        end,
      })
      assert.is_false(input:isTextEdited())
      input:addChars(" more")
      assert.is_true(input:isTextEdited())
      assert.is_true(edited_val)

      input:setText("reset")
      assert.is_false(input:isTextEdited())
    end)

    it("should handle password text type and toggle", function()
      local Device = require("device")
      local orig_is_touch = Device.isTouchDevice
      Device.isTouchDevice = function()
        return true
      end

      local ok, err = pcall(function()
        local input = require("ui/widget/inputtext"):new({
          text_type = "password",
          text = "secret123",
          width = 200,
          parent = {
            onSwitchFocus = function() end,
          },
        })
        assert.is_true(input.is_password_type)
        assert.is_not_nil(input._check_button)
        assert.is_not_nil(input._password_toggle)

        input._check_button.checked = true
        input._check_button.callback()
        assert.are.equal("text", input.text_type)
        assert.are.equal("secret123", input:getText())

        input._check_button.checked = false
        input._check_button.callback()
        assert.are.equal("password", input.text_type)
      end)
      Device.isTouchDevice = orig_is_touch
      if not ok then
        error(err)
      end
    end)

    it("should query text and line heights", function()
      local input = require("ui/widget/inputtext"):new({
        text = "some text",
      })
      assert.is_number(input:getTextHeight())
      assert.is_number(input:getLineHeight())
    end)
  end)

  describe("Focus and keyboard visibility", function()
    it("should manage focus and unfocus", function()
      local input = require("ui/widget/inputtext"):new({
        text = "hello",
      })
      input:unfocus()
      assert.is_false(input.focused)
      input:focus()
      assert.is_true(input.focused)
    end)

    it("should handle showKeyboard, closeKeyboard and onClose", function()
      local input = require("ui/widget/inputtext"):new({
        text = "hello",
      })
      input:showKeyboard()
      assert.is_true(input.focused)
      input:closeKeyboard()
      assert.is_false(input.focused)
      input:onClose()
    end)
  end)

  describe("Keypress and text input handling", function()
    local function make_key(key_name, mods)
      mods = mods or {}
      local mod_count = #mods
      local key = {
        key = key_name,
        hasMultipleModifiers = function()
          return mod_count > 1
        end,
        hasModifiers = function()
          return mod_count > 0
        end,
        hasSingleModifier = function()
          return mod_count == 1
        end,
        numOfModifiers = function()
          return mod_count
        end,
      }
      if key_name then
        key[key_name] = true
      end
      for _, m in ipairs(mods) do
        key[m] = true
      end
      return key
    end

    it(
      "should handle control keys: Backspace, Del, Left, Right, Up, Down, Home, End, Press, Enter, Tab, Back",
      function()
        local input = require("ui/widget/inputtext"):new({
          text = "hello world",
        })

        assert.is_true(input:onKeyPress(make_key("Backspace")))
        assert.are.equal("hello worl", input:getText())

        input.charpos = 1
        assert.is_true(input:onKeyPress(make_key("Del")))
        assert.are.equal("ello worl", input:getText())

        assert.is_true(input:onKeyPress(make_key("Right")))
        assert.is_true(input:onKeyPress(make_key("Left")))
        assert.is_true(input:onKeyPress(make_key("Up")))
        assert.is_true(input:onKeyPress(make_key("Down")))
        assert.is_true(input:onKeyPress(make_key("Home")))
        assert.is_true(input:onKeyPress(make_key("End")))

        local pressed = false
        input.press_callback = function()
          pressed = true
        end
        assert.is_true(input:onKeyPress(make_key("Press")))
        assert.is_true(pressed)

        input.press_callback = nil
        assert.is_true(input:onKeyPress(make_key("Enter")))
        assert.is_true(input:getText():find("\n") ~= nil)

        assert.is_true(input:onKeyPress(make_key("Tab")))
        assert.is_true(input:getText():find("    ") ~= nil)

        assert.is_true(input:onKeyPress(make_key("Back")))
        assert.is_false(input.focused)
      end
    )

    it("should handle Ctrl+U and Ctrl+H", function()
      local input = require("ui/widget/inputtext"):new({
        text = "hello world",
      })
      assert.is_true(input:onKeyPress(make_key("H", { "Ctrl" })))
      assert.are.equal("hello worl", input:getText())

      assert.is_true(input:onKeyPress(make_key("U", { "Ctrl" })))
      assert.are.equal("", input:getText())
    end)

    it("should ignore keypress when multiple modifiers or unfocused", function()
      local input = require("ui/widget/inputtext"):new({
        text = "hello",
      })
      assert.is_false(input:onKeyPress(make_key("A", { "Ctrl", "Alt" })))

      input:unfocus()
      assert.is_false(input:onKeyPress(make_key("Backspace")))
    end)

    it("should handle onTextInput", function()
      local input = require("ui/widget/inputtext"):new({
        text = "hello",
      })
      assert.is_true(input:onTextInput(" world"))
      assert.are.equal("hello world", input:getText())

      input:unfocus()
      assert.is_false(input:onTextInput(" ignored"))
      assert.are.equal("hello world", input:getText())
    end)
  end)

  describe("Gesture handling & clipboard operations", function()
    local Device = require("device")
    local UIManager = require("ui/uimanager")

    it("should handle onTapTextBox", function()
      local input = require("ui/widget/inputtext"):new({
        text = "hello world",
        parent = {},
      })
      local handled = input:onTapTextBox(nil, {
        pos = { x = 50, y = 50 },
      })
      assert.is_true(handled)
      assert.is_true(input.focused)
    end)

    it("should handle onSwipeTextBox", function()
      local input = require("ui/widget/inputtext"):new({
        text = "hello world",
      })
      local refreshed = false
      input.refresh_callback = function()
        refreshed = true
      end
      local handled = input:onSwipeTextBox(nil, {
        direction = "northeast",
      })
      assert.is_false(handled)
      assert.is_true(refreshed)
    end)

    it("should handle onHoldTextBox and clipboard actions", function()
      local orig_has_cb = Device.hasClipboard
      local orig_get_cb = Device.input.getClipboardText
      local orig_set_cb = Device.input.setClipboardText

      local clipboard_store = "clip_text"
      Device.hasClipboard = function()
        return true
      end
      Device.input.getClipboardText = function()
        return clipboard_store
      end
      Device.input.setClipboardText = function(txt)
        clipboard_store = txt
      end

      local shown_dialog
      local input = require("ui/widget/inputtext"):new({
        text = "hello world",
        parent = {},
      })
      input.showWidget = function(self, w)
        shown_dialog = w
      end

      local handled = input:onHoldTextBox(nil, {})
      assert.is_true(handled)
      assert.is_not_nil(shown_dialog)

      -- Exercise buttons in clipboard_dialog
      local buttons = shown_dialog.buttons_table
      -- Row 1: Copy all, Copy line, Copy word
      local copy_all_btn = buttons[1][1]
      copy_all_btn.callback()
      assert.are.equal("hello world", clipboard_store)

      local copy_line_btn = buttons[1][2]
      copy_line_btn.callback()
      assert.are.equal("hello world", clipboard_store)

      local copy_word_btn = buttons[1][3]
      copy_word_btn.callback()
      assert.are.equal("world", clipboard_store)

      -- Row 2: Delete all, Select, Paste
      local select_btn = buttons[2][2]
      select_btn.callback()
      assert.is_true(input.do_select)

      -- Hold again in select mode (start of selection)
      input.charpos = 1
      input:onHoldTextBox(nil, {})
      assert.are.equal(1, input.selection_start_pos)

      -- Move cursor and hold again (end of selection)
      input.charpos = 6
      input:onHoldTextBox(nil, {})
      assert.are.equal("hello", clipboard_store)
      assert.is_false(input.do_select)

      -- Paste button
      clipboard_store = " 123"
      input:onHoldTextBox(nil, {})
      local paste_btn = shown_dialog.buttons_table[2][3]
      paste_btn.callback()
      assert.is_true(input:getText():find("123") ~= nil)

      -- Delete all button
      input:onHoldTextBox(nil, {})
      local del_all_btn = shown_dialog.buttons_table[2][1]
      del_all_btn.callback()
      assert.are.equal("", input:getText())

      assert.is_true(input:onHoldReleaseTextBox(nil, {}))
      assert.is_false(input:onHoldReleaseTextBox(nil, {}))

      Device.hasClipboard = orig_has_cb
      Device.input.getClipboardText = orig_get_cb
      Device.input.setClipboardText = orig_set_cb
    end)

    it("should handle onSwipeTextBox and test strike_callback", function()
      local struck = false
      local refreshed = false
      local input = require("ui/widget/inputtext"):new({
        text = "line1\nline2\nline3\nline4\nline5",
        strike_callback = function()
          struck = true
        end,
        refresh_callback = function()
          refreshed = true
        end,
      })

      input:resyncPos()
      assert.is_true(struck)

      local ges = {
        direction = "northeast",
        distance = 30,
        pos = { x = 50, y = 50 },
      }
      assert.is_false(input:onSwipeTextBox(nil, ges))
      assert.is_true(refreshed)
    end)
  end)
end)
