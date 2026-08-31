describe("FrontLightWidget UI component", function()
  local Device, PowerD, FrontLightWidget, Geom, UIManager

  setup(function()
    require("commonrequire")
    package.unloadAll()
    local device = require("device")
    require("document/canvascontext"):init(device)

    Device = require("device")
    PowerD = require("device/generic/powerd")
    FrontLightWidget = require("ui/widget/frontlightwidget")
    Geom = require("ui/geometry")
    UIManager = require("ui/uimanager")
  end)

  local function setupDevice(has_nl, has_nl_mixer, has_nl_api, few_keys)
    Device.isKobo = function() return true end
    Device.model = "Kobo_dahlia"
    Device.hasFrontlight = function() return true end
    Device.hasNaturalLight = function() return has_nl or false end
    Device.hasNaturalLightMixer = function() return has_nl_mixer or false end
    Device.hasNaturalLightApi = function() return has_nl_api or false end
    Device.hasFewKeys = function() return few_keys or false end
    Device.isTouchDevice = function() return true end

    local current_intensity = 2
    local current_warmth = 5
    local powerd_mock = PowerD:new({
      fl_min = 0,
      fl_max = 10,
      fl_warmth_min = 0,
      fl_warmth_max = 10,
      is_fl_on = true,
      device = Device,
    })
    powerd_mock.frontlightIntensity = function() return current_intensity end
    powerd_mock.setIntensity = function(self, val) current_intensity = val end
    powerd_mock.toggleFrontlight = function(self)
      current_intensity = (current_intensity == 0) and 2 or 0
    end
    powerd_mock.updateResumeFrontlightState = function() end

    powerd_mock.frontlightWarmth = function() return current_warmth end
    powerd_mock.setWarmth = function(self, val) current_warmth = val end
    powerd_mock.toNativeWarmth = function(self, val) return val end
    powerd_mock.fromNativeWarmth = function(self, val) return val end

    Device.powerd = powerd_mock
    Device.getPowerDevice = function() return powerd_mock end
    return powerd_mock
  end

  before_each(function()
    setupDevice(false, false, false, false)
  end)

  it("should initialize frontlight properties correctly without natural light", function()
    local flw = FrontLightWidget:new({})
    assert.is_not_nil(flw)
    assert.is.same(0, flw.fl.min)
    assert.is.same(10, flw.fl.max)
    assert.is.same(2, flw.fl.cur)
    assert.is_nil(flw.nl)
    assert.is_not_nil(flw.fl_minus)
    assert.is_not_nil(flw.fl_plus)
  end)

  it("should initialize with natural light and configure button when no mixer or api", function()
    setupDevice(true, false, false, false)
    local flw = FrontLightWidget:new({})
    assert.is_not_nil(flw.nl)
    assert.is.same(0, flw.nl.min)
    assert.is.same(10, flw.nl.max)
    assert.is.same(5, flw.nl.cur)
    assert.is_not_nil(flw.nl_progress)
    assert.is_not_nil(flw.nl_minus)
    assert.is_not_nil(flw.nl_plus)

    -- Test configure button callback
    local shown_widget = nil
    flw.showWidget = function(self, w) shown_widget = w end
    local configure_btn = flw.layout[5][2]
    assert.is_not_nil(configure_btn)
    configure_btn.callback()
    assert.is_not_nil(shown_widget)
  end)

  it("should initialize with natural light when mixer or api is present", function()
    setupDevice(true, true, false, true) -- few_keys = true, mixer = true
    local flw = FrontLightWidget:new({})
    assert.is_not_nil(flw.nl)
  end)

  it("should handle all brightness button callbacks", function()
    local flw = FrontLightWidget:new({})
    local old_stack = UIManager._window_stack
    UIManager._window_stack = { { widget = flw } }

    -- fl_minus callback
    flw.fl.cur = 5
    flw.fl_minus.callback()
    assert.are_equal(4, flw.fl.cur)

    -- fl_plus callback
    flw.fl_plus.callback()
    assert.are_equal(5, flw.fl.cur)

    -- fl_min (sets to min + 1)
    local fl_min_btn = flw.layout[2][1]
    fl_min_btn.callback()
    assert.are_equal(1, flw.fl.cur)

    -- fl_max (sets to fl.max)
    local fl_max_btn = flw.layout[2][3]
    fl_max_btn.callback()
    assert.are_equal(10, flw.fl.cur)

    -- fl_toggle (sets to fl.min = 0, which toggles)
    local fl_toggle_btn = flw.layout[2][2]
    fl_toggle_btn.callback()
    assert.are_equal(0, flw.fl.cur)

    UIManager._window_stack = old_stack
  end)

  it("should handle warmth adjustments and callbacks", function()
    setupDevice(true, false, false, false)
    local flw = FrontLightWidget:new({})
    local old_stack = UIManager._window_stack
    UIManager._window_stack = { { widget = flw } }

    -- setWarmth same value does nothing
    flw:setWarmth(flw.nl.cur, true)

    -- nl_minus callback
    flw.nl.cur = 5
    flw.nl_minus.callback()
    assert.are_equal(4, flw.nl.cur)

    -- nl_plus callback
    flw.nl_plus.callback()
    assert.are_equal(5, flw.nl.cur)

    -- nl_min (sets to nl.min)
    local nl_min_btn = flw.layout[5][1]
    nl_min_btn.callback()
    assert.are_equal(0, flw.nl.cur)
    assert.is_false(flw.nl_minus.enabled)

    -- nl_max (sets to nl.max)
    local nl_max_btn = flw.layout[5][3]
    nl_max_btn.callback()
    assert.are_equal(10, flw.nl.cur)
    assert.is_false(flw.nl_plus.enabled)

    -- ButtonProgressWidget callback
    flw.nl_progress.callback(0.5)

    UIManager._window_stack = old_stack
  end)

  it("should handle setBrightness edge cases", function()
    local flw = FrontLightWidget:new({})
    local old_stack = UIManager._window_stack
    UIManager._window_stack = { { widget = flw } }

    flw.fl.cur = 5
    -- Same brightness returns early
    flw:setBrightness(5)
    assert.are_equal(5, flw.fl.cur)

    -- Disabling minus button at min
    flw:setBrightness(0)
    assert.are_equal(0, flw.fl.cur)
    assert.is_false(flw.fl_minus.enabled)

    -- Disabling plus button at max
    flw:setBrightness(10)
    assert.are_equal(10, flw.fl.cur)
    assert.is_false(flw.fl_plus.enabled)

    UIManager._window_stack = old_stack
  end)

  it("should handle widget lifecycle events onShow, onClose, onExit", function()
    local flw = FrontLightWidget:new({})
    local close_called = false
    local orig_close = UIManager.close
    UIManager.close = function(_, widget)
      if widget == flw then close_called = true end
    end

    assert.is_true(flw:onShow())
    flw:onClose()
    assert.is_true(flw:onExit())
    assert.is_true(close_called)

    UIManager.close = orig_close
  end)

  it("should handle tap and pan gestures", function()
    local flw = FrontLightWidget:new({})
    local old_stack = UIManager._window_stack
    UIManager._window_stack = { { widget = flw } }

    -- When dimensions are not yet set
    flw.fl_progress.dimen = nil
    flw.frame.dimen = nil
    assert.is_true(flw:onTapProgress(nil, { pos = Geom:new({ x = 50, y = 50 }), ges = "tap" }))

    -- Set mock dimensions
    flw.frame.dimen = Geom:new({ x = 10, y = 10, w = 400, h = 300 })
    flw.fl_progress.dimen = Geom:new({ x = 20, y = 50, w = 360, h = 40 })

    -- Tap inside progress bar
    flw.fl_progress.getPercentageFromPosition = function(_, pos)
      return 0.7
    end
    assert.is_true(flw:onTapProgress(nil, { pos = Geom:new({ x = 100, y = 60 }), ges = "tap" }))
    assert.are_equal(7, flw.fl.cur)

    -- Tap inside progress bar returning nil percentage
    flw.fl_progress.getPercentageFromPosition = function(_, pos)
      return nil
    end
    assert.is_true(flw:onTapProgress(nil, { pos = Geom:new({ x = 100, y = 60 }), ges = "tap" }))

    -- Tap outside window frame triggers onExit
    local exit_called = false
    flw.onExit = function() exit_called = true end
    assert.is_true(flw:onTapProgress(nil, { pos = Geom:new({ x = 500, y = 500 }), ges = "tap" }))
    assert.is_true(exit_called)

    -- Pan outside window frame does not trigger onExit
    exit_called = false
    assert.is_true(flw:onTapProgress(nil, { pos = Geom:new({ x = 500, y = 500 }), ges = "pan" }))
    assert.is_false(exit_called)

    -- Low pan rate throttling
    local orig_low_pan = G_named_settings.low_pan_rate
    G_named_settings.low_pan_rate = function() return true end
    flw.fl_progress.getPercentageFromPosition = function(_, pos) return 0.4 end
    flw.last_time = 0
    assert.is_true(flw:onTapProgress(nil, { pos = Geom:new({ x = 100, y = 60 }), ges = "pan" }))
    -- Pan again immediately within rate window
    assert.is_true(flw:onTapProgress(nil, { pos = Geom:new({ x = 100, y = 60 }), ges = "pan" }))
    G_named_settings.low_pan_rate = orig_low_pan

    UIManager._window_stack = old_stack
  end)
end)
