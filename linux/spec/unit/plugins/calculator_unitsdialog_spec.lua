describe("CalculatorUnitsDialog widget", function()
  local CalculatorUnitsDialog

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    CalculatorUnitsDialog =
      require("plugins/calculator.koplugin/calculatorunitsdialog")
  end)

  it("should initialize CalculatorUnitsDialog widget", function()
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
  end)

  it("should trigger onShow and onClose handlers without error", function()
    local dialog = CalculatorUnitsDialog:new({
      units = {
        { "m", 1, true },
        { "km", 1000 },
      },
    })
    dialog:onShow()
    dialog:onClose()
  end)
end)
