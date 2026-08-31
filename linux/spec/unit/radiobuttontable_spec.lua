describe("RadioButtonTable", function()
  local RadioButtonTable
  local Device

  setup(function()
    require("commonrequire")
    RadioButtonTable = require("ui/widget/radiobuttontable")
    Device = require("device")
  end)

  it("should initialize with default buttons and select first button", function()
    local selected_entry = nil
    local table_widget = RadioButtonTable:new({
      width = 300,
      radio_buttons = {
        {
          { text = "Option A", provider = "a" },
          { text = "Option B", provider = "b" },
        },
      },
      button_select_callback = function(entry)
        selected_entry = entry
      end,
    })

    assert.truthy(table_widget.checked_button)
    assert.are.equal("Option A", table_widget.checked_button.text)

    -- Click second button
    local btn2 = table_widget.radio_buttons_layout[1][2]
    btn2.callback()

    assert.are.equal(btn2, table_widget.checked_button)
    assert.truthy(selected_entry)
    assert.are.equal("b", selected_entry.provider)

    -- Clicking already checked button does nothing
    btn2.callback()
    assert.are.equal(btn2, table_widget.checked_button)
  end)

  it("should support zero_sep = true", function()
    local table_widget = RadioButtonTable:new({
      width = 300,
      zero_sep = true,
      radio_buttons = {
        {
          { text = "One", checked = true },
          { text = "Two" },
        },
      },
    })

    assert.truthy(table_widget.container)
    assert.are.equal("One", table_widget.checked_button.text)
  end)

  it("should support multiple rows of radio buttons", function()
    local table_widget = RadioButtonTable:new({
      width = 400,
      radio_buttons = {
        { { text = "Row 1, Col 1" }, { text = "Row 1, Col 2" } },
        { { text = "Row 2, Col 1" }, { text = "Row 2, Col 2" } },
      },
    })

    assert.are.equal(2, #table_widget.radio_buttons_layout)
    assert.are.equal(2, #table_widget.radio_buttons_layout[1])
    assert.are.equal(2, #table_widget.radio_buttons_layout[2])
  end)

  it("should add horizontal separators", function()
    local table_widget = RadioButtonTable:new({
      width = 300,
      radio_buttons = {
        { { text = "Only Option" } },
      },
    })

    local initial_count = #table_widget.container
    table_widget:addHorizontalSep(true, true, true, true)
    assert.is_true(#table_widget.container > initial_count)
  end)
end)
