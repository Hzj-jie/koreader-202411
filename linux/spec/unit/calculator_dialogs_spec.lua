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
      -- 1 inch = 0.0254 meters
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
end)
