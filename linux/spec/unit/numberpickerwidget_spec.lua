local NumberPickerWidget

describe("NumberPickerWidget module", function()
  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    NumberPickerWidget = require("ui/widget/numberpickerwidget")
  end)

  it("should change value within min/max with wrapping", function()
    local val = NumberPickerWidget:changeValue(0, 1, 23, 0, true)
    assert.is_equal(val, 1)

    val = NumberPickerWidget:changeValue(0, -1, 23, 0, true)
    assert.is_equal(val, 23)

    val = NumberPickerWidget:changeValue(23, 1, 23, 0, true)
    assert.is_equal(val, 0)
  end)

  it("should change value within min/max without wrapping", function()
    local val = NumberPickerWidget:changeValue(0, -1, 23, 0, false)
    assert.is_equal(val, 0)

    val = NumberPickerWidget:changeValue(23, 1, 23, 0, false)
    assert.is_equal(val, 23)
  end)

  it("should calculate correct number of days in month", function()
    local days = NumberPickerWidget:getDaysInMonth(2, 2024)
    assert.is_equal(days, 29)

    days = NumberPickerWidget:getDaysInMonth(2, 2023)
    assert.is_equal(days, 28)

    days = NumberPickerWidget:getDaysInMonth(4, 2024)
    assert.is_equal(days, 30)
  end)

  it("should instantiate widget and return value", function()
    local picker = NumberPickerWidget:new({
      value = 10,
      value_min = 0,
      value_max = 20,
    })
    assert.is_equal(picker:getValue(), 10)

    picker.value = 15
    picker:update()
    assert.is_equal(picker:getValue(), 15)
  end)

  it("should handle table value indexing", function()
    local val_table = { "Small", "Medium", "Large" }
    local picker = NumberPickerWidget:new({
      value_table = val_table,
      value_index = 1,
    })

    assert.is_table(picker)
    assert.are.equal("Small", picker:getValue())

    if type(picker.changeTableIndex) == "function" then
      local idx = picker:changeTableIndex(1, 1, #val_table, 1, true)
      assert.are.equal(2, idx)
    end
  end)

  it("should trigger picker_updated_callback on update", function()
    local updated_val = nil
    local picker = NumberPickerWidget:new({
      value = 5,
      value_min = 0,
      value_max = 10,
      picker_updated_callback = function(val)
        updated_val = val
      end,
    })

    picker.value = 8
    picker:update()
    assert.are.equal(8, updated_val)
  end)

  it("should calculate century leap year rules correctly", function()
    -- 2000 is divisible by 400 -> leap year
    assert.are.equal(29, NumberPickerWidget:getDaysInMonth(2, 2000))
    -- 1900 is divisible by 100 but not 400 -> not a leap year
    assert.are.equal(28, NumberPickerWidget:getDaysInMonth(2, 1900))
    -- 2024 is divisible by 4 and not 100 -> leap year
    assert.are.equal(29, NumberPickerWidget:getDaysInMonth(2, 2024))
    -- 2023 is not divisible by 4 -> not a leap year
    assert.are.equal(28, NumberPickerWidget:getDaysInMonth(2, 2023))
  end)

  it(
    "should handle up and down button clicks and holds with date limits",
    function()
      local month_picker = {
        getValue = function()
          return 2
        end,
      }
      local year_picker = {
        getValue = function()
          return 2024
        end,
      }

      local picker = NumberPickerWidget:new({
        value = 1,
        value_min = 1,
        value_max = 31,
        value_step = 1,
        value_hold_step = 5,
        date_month = month_picker,
        date_year = year_picker,
        wrap = true,
      })

      -- button_up is layout[1][1], button_down is layout[2][1]
      local btn_up = picker.layout[1][1]
      local btn_down = picker.layout[3][1] -- button_down is index 3 when text_value is at index 2

      btn_up.callback()
      assert.are.equal(2, picker:getValue())

      btn_up.hold_callback()
      assert.are.equal(7, picker:getValue())

      btn_down.callback()
      assert.are.equal(6, picker:getValue())

      btn_down.hold_callback()
      assert.are.equal(1, picker:getValue())

      -- Wrap down from 1 should go to 29 (Feb 2024 has 29 days)
      btn_down.callback()
      assert.are.equal(29, picker:getValue())
    end
  )

  it(
    "should handle direct input dialog interactions and math expressions",
    function()
      local UIManager = require("ui/uimanager")
      local shown_widget
      local closed_dialog
      local orig_show = UIManager.show
      local orig_close = UIManager.close
      UIManager.show = function(self, w)
        shown_widget = w
      end
      UIManager.close = function(self, w)
        closed_dialog = w
      end

      local picker = NumberPickerWidget:new({
        value = 10,
        value_min = 0,
        value_max = 100,
      })
      picker.showWidget = function(self, w)
        shown_widget = w
      end

      -- Trigger input dialog via text_value button callback
      assert.is_function(picker.text_value.callback)
      picker.text_value.callback()
      assert.is_not_nil(shown_widget)

      local input_dlg = shown_widget
      local cancel_btn = input_dlg.buttons[1][1]
      local ok_btn = input_dlg.buttons[1][2]

      -- Cancel button
      cancel_btn.callback()
      assert.are.equal(input_dlg, closed_dialog)

      -- Valid numeric input
      input_dlg.getInputText = function()
        return "42"
      end
      ok_btn.callback()
      assert.are.equal(42, picker:getValue())

      -- Math expression input (=15 * 3)
      input_dlg.getInputText = function()
        return "=15 * 3"
      end
      ok_btn.callback()
      assert.are.equal(45, picker:getValue())

      -- Math expression with math.floor
      input_dlg.getInputText = function()
        return "=math.floor(19.8)"
      end
      ok_btn.callback()
      assert.are.equal(19, picker:getValue())

      -- Unsafe expression rejection
      input_dlg.getInputText = function()
        return "=os.exit()"
      end
      ok_btn.callback()
      assert.are.equal(19, picker:getValue()) -- value unchanged

      -- Below minimum input
      input_dlg.getInputText = function()
        return "-10"
      end
      ok_btn.callback()
      assert.are.equal(19, picker:getValue()) -- value unchanged

      -- Above maximum input
      input_dlg.getInputText = function()
        return "200"
      end
      ok_btn.callback()
      assert.are.equal(19, picker:getValue()) -- value unchanged

      -- Invalid non-number input
      input_dlg.getInputText = function()
        return "abc"
      end
      ok_btn.callback()
      assert.are.equal(19, picker:getValue()) -- value unchanged

      -- Verbose debug colon prefix bypass checks
      G_reader_settings:makeTrue("debug_verbose")
      input_dlg.getInputText = function()
        return ":150"
      end
      ok_btn.callback()
      assert.are.equal(150, picker:getValue())
      G_reader_settings:makeFalse("debug_verbose")

      UIManager.show = orig_show
      UIManager.close = orig_close
    end
  )
end)
