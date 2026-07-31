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
end)
