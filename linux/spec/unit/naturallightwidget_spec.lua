describe("NaturalLightWidget UI component", function()
  local Device, PowerD, NaturalLightWidget, UIManager

  setup(function()
    require("commonrequire")
    package.unloadAll()
    local device = require("device")
    require("document/canvascontext"):init(device)

    Device = require("device")
    PowerD = require("device/generic/powerd")
    NaturalLightWidget = require("ui/widget/naturallightwidget")
    UIManager = require("ui/uimanager")
  end)

  local powerd_mock
  local brightness_called

  before_each(function()
    Device.isKobo = function()
      return true
    end
    Device.model = "Kobo_dahlia"
    Device.hasFrontlight = function()
      return true
    end
    Device.hasNaturalLight = function()
      return true
    end

    brightness_called = 0
    powerd_mock = PowerD:new({
      fl_min = 1,
      fl_max = 5,
      fl_intensity = 2,
      is_fl_on = true,
      device = Device,
    })
    powerd_mock.fl = {
      white_gain = 10,
      white_offset = 20,
      red_gain = 30,
      red_offset = 40,
      green_gain = 50,
      green_offset = 60,
      exponent = 70,
      setNaturalBrightness = function()
        brightness_called = brightness_called + 1
      end,
    }
    powerd_mock.frontlightWarmth = function()
      return 2
    end

    Device.powerd = powerd_mock
    Device.getPowerDevice = function()
      return powerd_mock
    end

    _G.G_reader_settings = _G.G_reader_settings or {}
    _G.G_reader_settings.save = function() end
  end)

  it("should initialize with correct default properties and structure", function()
    local nlw = NaturalLightWidget:new({})
    assert.is_not_nil(nlw)
    assert.is_true(nlw.modal)
    assert.is_not_nil(nlw.white_gain)
    assert.is_not_nil(nlw.white_offset)
    assert.is_not_nil(nlw.red_gain)
    assert.is_not_nil(nlw.red_offset)
    assert.is_not_nil(nlw.green_gain)
    assert.is_not_nil(nlw.green_offset)
    assert.is_not_nil(nlw.exponent)
    assert.is_not_nil(nlw.nl_frame)
    assert.is_not_nil(nlw[1])
  end)

  it("should handle onShow and capture current values in old_values", function()
    local nlw = NaturalLightWidget:new({})
    local dirty_widget, dirty_type, dirty_dimen
    local old_setDirty = UIManager.setDirty
    UIManager.setDirty = function(self, widget, callback_or_mode)
      dirty_widget = widget
      if type(callback_or_mode) == "function" then
        dirty_type, dirty_dimen = callback_or_mode()
      else
        dirty_type = callback_or_mode
      end
    end

    local res = nlw:onShow()
    assert.is_true(res)
    assert.are.equal(nlw, dirty_widget)
    assert.are.equal("ui", dirty_type)
    assert.are.equal(nlw.nl_frame.dimen, dirty_dimen)
    assert.is_not_nil(nlw.old_values)
    assert.are.equal(10, nlw.old_values.white_gain)
    assert.are.equal(20, nlw.old_values.white_offset)
    assert.are.equal(30, nlw.old_values.red_gain)
    assert.are.equal(40, nlw.old_values.red_offset)
    assert.are.equal(50, nlw.old_values.green_gain)
    assert.are.equal(60, nlw.old_values.green_offset)
    assert.are.equal(70, nlw.old_values.exponent)

    UIManager.setDirty = old_setDirty
  end)

  it("should handle applyValues and setNaturalBrightness", function()
    local nlw = NaturalLightWidget:new({})
    brightness_called = 0
    nlw.white_gain[2]:setText("15")
    nlw.white_offset[2]:setText("25")
    nlw.red_gain[2]:setText("35")
    nlw.red_offset[2]:setText("45")
    nlw.green_gain[2]:setText("55")
    nlw.green_offset[2]:setText("65")
    nlw.exponent[2]:setText("0.5")

    nlw:applyValues()

    assert.are.equal(15, powerd_mock.fl.white_gain)
    assert.are.equal(25, powerd_mock.fl.white_offset)
    assert.are.equal(35, powerd_mock.fl.red_gain)
    assert.are.equal(45, powerd_mock.fl.red_offset)
    assert.are.equal(55, powerd_mock.fl.green_gain)
    assert.are.equal(65, powerd_mock.fl.green_offset)
    assert.are.equal(0.5, powerd_mock.fl.exponent)
    assert.are.equal(1, brightness_called)
  end)

  it("should handle adaptableNumber button interactions and input_text getText fallback", function()
    local nlw = NaturalLightWidget:new({})
    local group = nlw.white_gain
    local btn_minus = group[1]
    local input = group[2]
    local btn_plus = group[3]

    -- Test getText with valid and invalid text
    input:setText("10")
    assert.are.equal(10, input:getText())
    input.text = "invalid_number"
    assert.are.equal(10, input:getText()) -- fallbacks to initial (which was 10)

    -- Test btn_plus callback (+step = +1)
    input:setText("10")
    btn_plus.callback()
    assert.are.equal(11, input:getText())
    assert.are.equal(11, powerd_mock.fl.white_gain)

    -- Test btn_plus hold_callback (+step/10 = +0.1)
    btn_plus.hold_callback()
    assert.are.equal(11.1, input:getText())
    assert.are.equal(11.1, powerd_mock.fl.white_gain)

    -- Test btn_minus callback (-step = -1)
    btn_minus.callback()
    assert.are.equal(10.1, input:getText())
    assert.are.equal(10.1, powerd_mock.fl.white_gain)

    -- Test btn_minus hold_callback (-step/10 = -0.1)
    btn_minus.hold_callback()
    assert.are.equal(10, input:getText())
    assert.are.equal(10, powerd_mock.fl.white_gain)

    -- Test enter_callback
    input:setText("22")
    input.enter_callback()
    assert.are.equal(22, powerd_mock.fl.white_gain)
  end)

  it("should handle Restore Defaults button callback", function()
    local nlw = NaturalLightWidget:new({})
    -- Find restore defaults button in fl_container
    local vertical_group = nlw.fl_container[1]
    local button_group = vertical_group[#vertical_group]
    local button_defaults = button_group[1]
    assert.are.equal("Restore Defaults", button_defaults.text)

    button_defaults.callback()
    assert.are.equal(25, powerd_mock.fl.white_gain)
    assert.are.equal(-25, powerd_mock.fl.white_offset)
    assert.are.equal(24, powerd_mock.fl.red_gain)
    assert.are.equal(0, powerd_mock.fl.red_offset)
    assert.are.equal(24, powerd_mock.fl.green_gain)
    assert.are.equal(-65, powerd_mock.fl.green_offset)
    assert.are.equal(0.25, powerd_mock.fl.exponent)
  end)

  it("should handle Cancel button callback", function()
    local nlw = NaturalLightWidget:new({})
    nlw:onShow()

    -- Change some values
    nlw.white_gain[2]:setText("99")
    nlw:applyValues()
    assert.are.equal(99, powerd_mock.fl.white_gain)

    local closed_widget = nil
    local old_close = UIManager.close
    UIManager.close = function(self, widget)
      closed_widget = widget
    end

    local vertical_group = nlw.fl_container[1]
    local button_group = vertical_group[#vertical_group]
    local button_cancel = button_group[3]
    assert.are.equal("Cancel", button_cancel.text)

    button_cancel.callback()
    assert.are.equal(10, powerd_mock.fl.white_gain) -- Restored to old value
    assert.are.equal(nlw, closed_widget)

    UIManager.close = old_close
  end)

  it("should handle Save button callback", function()
    local nlw = NaturalLightWidget:new({})
    local saved_section, saved_val
    _G.G_reader_settings.save = function(self, section, val)
      saved_section = section
      saved_val = val
    end

    local closed_widget = nil
    local old_close = UIManager.close
    UIManager.close = function(self, widget)
      closed_widget = widget
    end

    local vertical_group = nlw.fl_container[1]
    local button_group = vertical_group[#vertical_group]
    local button_ok = button_group[4]
    assert.are.equal("Save", button_ok.text)

    button_ok.callback()
    assert.are.equal("natural_light_config", saved_section)
    assert.is_not_nil(saved_val)
    assert.are.equal(10, saved_val.white_gain)
    assert.are.equal(nlw, closed_widget)

    UIManager.close = old_close
  end)

  it("should handle TitleBar close callback", function()
    local nlw = NaturalLightWidget:new({})
    nlw:onShow()

    local closed_widget = nil
    local old_close = UIManager.close
    UIManager.close = function(self, widget)
      closed_widget = widget
    end

    local title_bar = nlw.nl_frame[1][1]
    title_bar.close_callback()
    assert.are.equal(nlw, closed_widget)

    UIManager.close = old_close
  end)

  it("should handle keyboard and focus switching methods", function()
    local nlw = NaturalLightWidget:new({})
    local input = nlw.white_gain[2]

    local kb_shown = false
    local kb_closed = false
    input.showKeyboard = function() kb_shown = true end
    input.closeKeyboard = function() kb_closed = true end

    -- showKeyboard & closeKeyboard when _current_input is nil
    nlw._current_input = nil
    assert.has_no.errors(function()
      nlw:showKeyboard()
      nlw:closeKeyboard()
    end)

    -- onSwitchFocus
    nlw:onSwitchFocus(input)
    assert.are.equal(input, nlw._current_input)
    assert.is_true(kb_shown)

    -- showKeyboard when _current_input is set
    kb_shown = false
    nlw:showKeyboard()
    assert.is_true(kb_shown)

    -- closeKeyboard when _current_input is set
    kb_closed = false
    nlw:closeKeyboard()
    assert.is_true(kb_closed)
  end)

  it("should handle onClose dirty marking and cleanup", function()
    local nlw = NaturalLightWidget:new({})
    local dirty_widget, dirty_type, dirty_dimen
    local old_setDirty = UIManager.setDirty
    UIManager.setDirty = function(self, widget, callback_or_mode)
      dirty_widget = widget
      if type(callback_or_mode) == "function" then
        dirty_type, dirty_dimen = callback_or_mode()
      else
        dirty_type = callback_or_mode
      end
    end

    nlw:onClose()
    assert.is_nil(dirty_widget)
    assert.are.equal("flashui", dirty_type)
    assert.are.equal(nlw.nl_frame.dimen, dirty_dimen)

    UIManager.setDirty = old_setDirty
  end)

  it("should handle onExit", function()
    local nlw = NaturalLightWidget:new({})
    local closed_widget = nil
    local old_close = UIManager.close
    UIManager.close = function(self, widget)
      closed_widget = widget
    end

    local res = nlw:onExit()
    assert.is_true(res)
    assert.are.equal(nlw, closed_widget)

    UIManager.close = old_close
  end)

  it("should return dimensions via getSize", function()
    local nlw = NaturalLightWidget:new({})
    local size = nlw:getSize()
    assert.is_not_nil(size)
  end)
end)
