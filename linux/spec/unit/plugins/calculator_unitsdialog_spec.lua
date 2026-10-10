describe("CalculatorUnitsDialog widget", function()
  local CalculatorUnitsDialog
  local CanvasContext
  local Device
  local UIManager

  setup(function()
    require("commonrequire")
    CanvasContext = require("document/canvascontext")
    Device = require("device")
    CanvasContext:init(Device)
    UIManager = require("ui/uimanager")

    CalculatorUnitsDialog =
      require("plugins/calculator.koplugin/calculatorunitsdialog")
  end)

  local function createMockInputWidget(initial_text)
    local w = {
      text = initial_text or "",
      charpos = #(initial_text or ""),
    }
    function w:goToEndOfLine()
      self.charpos = #self.text
    end
    function w:goToStartOfLine()
      self.charpos = 0
    end
    function w:addChars(chars)
      local before = self.text:sub(1, self.charpos)
      local after = self.text:sub(self.charpos + 1)
      self.text = before .. chars .. after
      self.charpos = self.charpos + #chars
    end
    return w
  end

  local function createMockCalc(initial_text)
    local input_widget = createMockInputWidget(initial_text)
    local calc = {
      history = "",
      calculated_input = nil,
      goto_end_called = false,
      input_dialog = {
        _input_widget = input_widget,
        getInputText = function()
          return input_widget.text
        end,
        setInputText = function(_self, text)
          input_widget.text = text
        end,
      },
    }
    function calc:calculate(expr)
      self.calculated_input = expr
      self.history = "eval(" .. expr .. ")"
    end
    function calc:gotoEnd()
      self.goto_end_called = true
    end
    return calc
  end

  describe("Widget Initialization & Layout", function()
    it("should initialize CalculatorUnitsDialog widget and child radio button tables", function()
      local dialog = CalculatorUnitsDialog:new({
        units = {
          { "cm", 0.01, true },
          { "inch", 0.0254 },
        },
      })
      assert.is_table(dialog)
      assert.is_table(dialog.radio_button_table_units_from)
      assert.is_table(dialog.radio_button_table_units_too)
      assert.is_table(dialog.button_table)
      assert.is_table(dialog.dialog_frame)
      assert.is_table(dialog.movable)
      assert.is_table(dialog[1])
    end)

    it("should trigger onShow and onClose handlers updating UIManager dirty state", function()
      local dialog = CalculatorUnitsDialog:new({
        units = {
          { "m", 1, true },
          { "km", 1000 },
        },
      })
      dialog.dialog_frame.dimen = { x = 0, y = 0, w = 200, h = 300 }
      dialog[1][1].dimen = { x = 0, y = 0, w = 200, h = 300 }

      local set_dirty_calls = 0
      local old_set_dirty = UIManager.setDirty
      UIManager.setDirty = function(_self, _target, func)
        set_dirty_calls = set_dirty_calls + 1
        local mode, dimen = func()
        assert.are.equal("ui", mode)
        assert.is_table(dimen)
      end

      dialog:onShow()
      assert.are.equal(1, set_dirty_calls)

      dialog:onClose()
      assert.are.equal(2, set_dirty_calls)

      UIManager.setDirty = old_set_dirty
    end)
  end)

  describe("Buttons & Unit Conversion Callbacks", function()
    it("should close dialog when cancel button (✕) is tapped", function()
      local calc = createMockCalc("")
      local parent = { parent = calc }
      local dialog = CalculatorUnitsDialog:new({
        parent = parent,
        units = {
          { "cm", 0.01, true },
          { "inch", 0.0254 },
        },
      })
      parent.units_dialog = dialog

      local closed_widget
      local old_close = UIManager.close
      UIManager.close = function(_self, widget)
        closed_widget = widget
      end

      -- Close button is first button in button_table
      local close_btn = dialog.button_table.buttons[1][1]
      assert.are.equal("✕", close_btn.text)
      close_btn.callback()
      assert.are.equal(dialog, closed_widget)

      UIManager.close = old_close
    end)

    it("should insert ans and apply numeric conversion when input line is empty", function()
      local calc = createMockCalc("")
      local parent = { parent = calc }
      local dialog = CalculatorUnitsDialog:new({
        parent = parent,
        units = {
          { "cm", 0.01, true },
          { "inch", 0.0254 },
        },
      })
      parent.units_dialog = dialog

      -- Set checked buttons (cm -> inch)
      dialog.radio_button_table_units_from.checked_button = {
        text = "cm",
        provider = 0.01,
      }
      dialog.radio_button_table_units_too.checked_button = {
        text = "inch",
        provider = 0.0254,
      }

      local old_close = UIManager.close
      UIManager.close = function() end

      -- OK button is second button in button_table
      local ok_btn = dialog.button_table.buttons[1][2]
      assert.are.equal("✓", ok_btn.text)
      ok_btn.callback()

      assert.is_truthy(calc.calculated_input:find("%(ans%)%*%(0%.01/0%.0254%)"))
      assert.is_truthy(calc.calculated_input:find("// cm %-> inch"))
      assert.is_true(calc.goto_end_called)
      assert.are.equal("eval(" .. calc.calculated_input .. ")", calc.input_dialog:getInputText())

      UIManager.close = old_close
    end)

    it("should wrap existing input and apply numeric conversion", function()
      local calc = createMockCalc("100 + 50")
      local parent = { parent = calc }
      local dialog = CalculatorUnitsDialog:new({
        parent = parent,
        units = {
          { "m", 1, true },
          { "km", 1000 },
        },
      })
      parent.units_dialog = dialog

      dialog.radio_button_table_units_from.checked_button = {
        text = "m",
        provider = 1,
      }
      dialog.radio_button_table_units_too.checked_button = {
        text = "km",
        provider = 1000,
      }

      local old_close = UIManager.close
      UIManager.close = function() end

      local ok_btn = dialog.button_table.buttons[1][2]
      ok_btn.callback()

      assert.is_truthy(calc.calculated_input:find("%(100 %+ 50%)%*%(1/1000%)"))
      assert.is_truthy(calc.calculated_input:find("// m %-> km"))
      assert.is_true(calc.goto_end_called)

      UIManager.close = old_close
    end)

    it("should handle formula string conversions (non-numeric providers)", function()
      local calc = createMockCalc("25")
      local parent = { parent = calc }
      local dialog = CalculatorUnitsDialog:new({
        parent = parent,
        units = {
          { "celsius", "c2k", true },
          { "kelvin", "k2c" },
        },
      })
      parent.units_dialog = dialog

      dialog.radio_button_table_units_from.checked_button = {
        text = "celsius",
        provider = "c2k",
      }
      dialog.radio_button_table_units_too.checked_button = {
        text = "kelvin",
        provider = "k2c",
      }

      local old_close = UIManager.close
      UIManager.close = function() end

      local ok_btn = dialog.button_table.buttons[1][2]
      ok_btn.callback()

      assert.is_truthy(calc.calculated_input:find("c2k"))
      assert.is_truthy(calc.calculated_input:find("// celsius %-> kelvin"))
      assert.is_true(calc.goto_end_called)

      UIManager.close = old_close
    end)
  end)
end)
