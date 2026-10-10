describe("CalculatorConvertDialog widget", function()
  local CalculatorConvertDialog, CalculatorUnitsDialog, UIManager

  setup(function()
    require("commonrequire")
    require("document/canvascontext"):init(require("device"))
    UIManager = require("ui/uimanager")
    CalculatorUnitsDialog = require("plugins/calculator.koplugin/calculatorunitsdialog")
    CalculatorConvertDialog = require("plugins/calculator.koplugin/calculatorconvertdialog")
  end)

  local orig_show, orig_close, orig_setDirty
  local shown_widgets, closed_widgets, dirtied_calls

  before_each(function()
    shown_widgets = {}
    closed_widgets = {}
    dirtied_calls = {}

    orig_show = UIManager.show
    orig_close = UIManager.close
    orig_setDirty = UIManager.setDirty

    UIManager.show = function(_self, widget)
      table.insert(shown_widgets, widget)
    end
    UIManager.close = function(_self, widget)
      table.insert(closed_widgets, widget)
    end
    UIManager.setDirty = function(_self, widget, func)
      table.insert(dirtied_calls, { widget = widget, func = func })
    end
  end)

  after_each(function()
    UIManager.show = orig_show
    UIManager.close = orig_close
    UIManager.setDirty = orig_setDirty
  end)

  it("should build 2-column ButtonDialog in self[1] with 10 unit categories and close button", function()
    local inserted
    local dialog = CalculatorConvertDialog:new({
      insert_callback = function(val) inserted = val end,
    })

    assert.is_table(dialog)
    assert.is_table(dialog[1])
    local button_dialog = dialog[1]
    assert.is_table(button_dialog.buttons)

    -- 11 buttons arranged in 2-column rows -> 6 rows
    assert.are.equal(6, #button_dialog.buttons)

    local button_texts = {}
    for _, row in ipairs(button_dialog.buttons) do
      for _, btn in ipairs(row) do
        table.insert(button_texts, btn.text)
      end
    end

    assert.are.equal(11, #button_texts)
    assert.are.equal("Length", button_texts[1])
    assert.are.equal("Area", button_texts[2])
    assert.are.equal("Volume", button_texts[3])
    assert.are.equal("Speed", button_texts[4])
    assert.are.equal("Time", button_texts[5])
    assert.are.equal("Energy", button_texts[6])
    assert.are.equal("Power", button_texts[7])
    assert.are.equal("Mass", button_texts[8])
    assert.are.equal("Pressure", button_texts[9])
    assert.are.equal("Temperature", button_texts[10])
    assert.are.equal("✕", button_texts[11])
  end)

  it("should close dialog and show CalculatorUnitsDialog on category button click", function()
    local dialog = CalculatorConvertDialog:new({
      insert_callback = function() end,
    })

    -- Find Length button (Row 1, Column 1)
    local length_btn = dialog[1].buttons[1][1]
    assert.are.equal("Length", length_btn.text)
    length_btn.callback()

    -- Verify dialog was closed
    assert.are.equal(1, #closed_widgets)
    assert.are.equal(dialog, closed_widgets[1])

    -- Verify CalculatorUnitsDialog was instantiated and shown
    assert.are.equal(1, #shown_widgets)
    assert.are.equal(dialog.units_dialog, shown_widgets[1])
    assert.are.equal(dialog, dialog.units_dialog.parent)
    assert.is_table(dialog.units_dialog.units)
    assert.are.equal("Å", dialog.units_dialog.units[1][1])
  end)

  it("should close dialog on close button click", function()
    local dialog = CalculatorConvertDialog:new({
      insert_callback = function() end,
    })

    -- Close button is in Row 6, Column 1
    local close_btn = dialog[1].buttons[6][1]
    assert.are.equal("✕", close_btn.text)
    close_btn.callback()

    assert.are.equal(1, #closed_widgets)
    assert.are.equal(dialog, closed_widgets[1])
  end)

  it("should trigger UIManager:setDirty onShow and onExit", function()
    local dialog = CalculatorConvertDialog:new({
      insert_callback = function() end,
    })
    dialog.dimen = { x = 0, y = 0, w = 100, h = 100 }
    dialog[1][1] = { dimen = { x = 0, y = 0, w = 100, h = 100 } }

    dialog:onShow()
    assert.are.equal(1, #dirtied_calls)
    assert.are.equal(dialog, dirtied_calls[1].widget)

    dialog:onExit()
    assert.are.equal(2, #dirtied_calls)
    assert.is_nil(dirtied_calls[2].widget)
  end)
end)
