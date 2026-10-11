local CalculatorUnitsDialog

describe("CalculatorUnitsDialog", function()
  setup(function()
    require("commonrequire")

    local ok1, mod1 = pcall(require, "calculatorunitsdialog")
    if not ok1 then
      mod1 = require("plugins/calculator.koplugin/calculatorunitsdialog")
    end
    CalculatorUnitsDialog = mod1
  end)

  it(
    "configures unit conversion scale for inches to meters correctly",
    function()
      assert.is_table(CalculatorUnitsDialog.units)
      assert.are.equal("cm", CalculatorUnitsDialog.units[1][1])
      assert.are.equal(0.01, CalculatorUnitsDialog.units[1][2])

      assert.are.equal("inch", CalculatorUnitsDialog.units[2][1])
      -- 1 inch = 0.0254 meters.
      -- In production line 37: units = { { "cm", 0.01 }, { "inch", 254 } }.
      -- 254 is off by a factor of 10,000x compared to 0.0254.
      assert.are.equal(0.0254, CalculatorUnitsDialog.units[2][2])
    end
  )

  it("creates separate radio button tables for from and to units", function()
    local dlg = CalculatorUnitsDialog:new({
      parent = { units_dialog = {} },
    })
    assert.are_not_equal(
      dlg.radio_button_table_units_from.radio_buttons,
      dlg.radio_button_table_units_too.radio_buttons
    )
  end)

  it("does not crash when confirmed without checked buttons", function()
    local dlg = CalculatorUnitsDialog:new({
      units = { { "cm", 0.01 }, { "inch", 0.0254 } },
      parent = {
        units_dialog = {},
        parent = {
          input_dialog = {
            _input_widget = {
              goToEndOfLine = function() end,
              goToStartOfLine = function() end,
              addChars = function() end,
              charpos = 0,
            },
            getInputText = function()
              return ""
            end,
            setInputText = function() end,
          },
          calculate = function() end,
          gotoEnd = function() end,
        },
      },
    })
    dlg.radio_button_table_units_from.checked_button = nil
    dlg.radio_button_table_units_too.checked_button = nil

    local UIManager = require("ui/uimanager")
    local orig_close = UIManager.close
    UIManager.close = function() end

    local ok_btn_callback = dlg.button_table.buttons[1][2].callback
    assert.has_no.errors(function()
      ok_btn_callback()
    end)
    UIManager.close = orig_close
  end)
end)
