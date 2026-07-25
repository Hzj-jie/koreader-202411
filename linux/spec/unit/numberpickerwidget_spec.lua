local NumberPickerWidget

describe("NumberPickerWidget module", function()
  setup(function()
    require("commonrequire")
    NumberPickerWidget = require("ui/widget/numberpickerwidget")
  end)

  it("should change value within min/max with wrapping", function()
    local val = NumberPickerWidget:changeValue(0, 1, 23, 0, true)
    assert.is_equal(val, 1)

    -- Wrapping around min -> max
    val = NumberPickerWidget:changeValue(0, -1, 23, 0, true)
    assert.is_equal(val, 23)

    -- Wrapping around max -> min
    val = NumberPickerWidget:changeValue(23, 1, 23, 0, true)
    assert.is_equal(val, 0)
  end)

  it("should change value within min/max without wrapping", function()
    -- Clamped at min
    local val = NumberPickerWidget:changeValue(0, -1, 23, 0, false)
    assert.is_equal(val, 0)

    -- Clamped at max
    val = NumberPickerWidget:changeValue(23, 1, 23, 0, false)
    assert.is_equal(val, 23)
  end)

  it("should calculate correct number of days in month", function()
    -- February in leap year
    local days = NumberPickerWidget:getDaysInMonth(2, 2024)
    assert.is_equal(days, 29)

    -- February in non-leap year
    days = NumberPickerWidget:getDaysInMonth(2, 2023)
    assert.is_equal(days, 28)

    -- April
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
end)
