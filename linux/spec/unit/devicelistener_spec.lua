describe("devicelistener", function()
  local DeviceListener
  local mock_device
  local mock_screen
  local mock_uimanager
  local mock_reader_settings
  local mock_named_settings
  local mock_powerd
  local mock_notification
  local mock_mass_storage

  before_each(function()
    mock_screen = {
      setNightmode = spy.new(function() end),
      getHeight = function() return 600 end,
      getWidth = function() return 800 end,
      getRotationMode = function() return 0 end,
    }

    mock_powerd = {
      fl_max = 100,
      fl_warmth_max = 10,
      frontlightIntensity = spy.new(function() return 50 end),
      frontlightWarmth = spy.new(function() return 5 end),
      turnOffFrontlight = spy.new(function() end),
      setIntensity = spy.new(function() end),
      updateResumeFrontlightState = spy.new(function() end),
      fromNativeWarmth = spy.new(function(self, w) return w * 10 end),
      toNativeWarmth = spy.new(function(self, w) return math.floor(w / 10) end),
      setWarmth = spy.new(function() end),
      isFrontlightOn = spy.new(function() return true end),
      toggleFrontlight = spy.new(function(self, cb) if cb then cb() end return true end),
    }

    mock_device = {
      screen = mock_screen,
      hasFrontlight = spy.new(function() return true end),
      hasNaturalLight = spy.new(function() return true end),
      hasGSensor = spy.new(function() return true end),
      isAlwaysFullscreen = spy.new(function() return false end),
      getPowerDevice = function() return mock_powerd end,
      toggleGSensor = spy.new(function() end),
      lockGSensor = spy.new(function() end),
      toggleFullscreen = spy.new(function() end),
      invertButtons = spy.new(function() end),
      invertButtonsLeft = spy.new(function() end),
      invertButtonsRight = spy.new(function() end),
      showLightDialog = spy.new(function() end),
      exit = spy.new(function() end),
      toggleKeyRepeat = spy.new(function() end),
    }
    package.loaded["device"] = mock_device

    local reader_settings_data = {
      night_mode = false,
      input_ignore_gsensor = false,
      input_lock_gsensor = false,
      input_invert_page_turn_keys = false,
    }
    mock_reader_settings = {
      save = spy.new(function(self, key, val) reader_settings_data[key] = val end),
      read = spy.new(function(self, key) return reader_settings_data[key] end),
      isTrue = spy.new(function(self, key) return reader_settings_data[key] == true end),
      nilOrFalse = spy.new(function(self, key)
        return reader_settings_data[key] == nil or reader_settings_data[key] == false
      end),
      flipNilOrFalse = spy.new(function(self, key)
        if reader_settings_data[key] == nil or reader_settings_data[key] == false then
          reader_settings_data[key] = true
        else
          reader_settings_data[key] = nil
        end
      end),
      makeTrue = spy.new(function(self, key) reader_settings_data[key] = true end),
      makeFalse = spy.new(function(self, key) reader_settings_data[key] = false end),
      delete = spy.new(function(self, key) reader_settings_data[key] = nil end),
      has = spy.new(function(self, key) return reader_settings_data[key] ~= nil end),
    }
    _G.G_reader_settings = mock_reader_settings

    mock_named_settings = {
      set = {
        full_refresh_count = spy.new(function() end),
      },
      home_dir = function() return "/home" end,
    }
    _G.G_named_settings = mock_named_settings

    mock_uimanager = {
      toggleNightMode = spy.new(function() end),
      broadcastEvent = spy.new(function() end),
      updateRefreshRate = spy.new(function() end),
      restartKOReader = spy.new(function() end),
      suspend = spy.new(function() end),
      askForReboot = spy.new(function() end),
      askForPowerOff = spy.new(function() end),
      scheduleRefresh = spy.new(function() end),
      setIgnoreTouchInput = spy.new(function() end),
      scheduleIn = spy.new(function(self, _delay, cb) if cb then cb() end end),
    }
    package.loaded["ui/uimanager"] = mock_uimanager

    mock_notification = {
      notify = spy.new(function() end),
      notify_source = "test",
    }
    package.loaded["ui/widget/notification"] = mock_notification

    package.loaded["ui/event"] = {
      new = function(self, name, arg) return { name = name, arg = arg } end,
    }

    package.loaded["gettext"] = function(text) return text end
    package.loaded["ffi/util"] = {
      template = function(tmpl, ...)
        local args = { ... }
        return (tmpl:gsub("%%(%d+)", function(n) return tostring(args[tonumber(n)]) end))
      end
    }

    package.loaded["device/wakeupmgr"] = {
      new = function() return {} end
    }

    mock_mass_storage = {
      start = spy.new(function() end),
    }
    package.loaded["ui/elements/mass_storage"] = mock_mass_storage

    package.loaded["device/devicelistener"] = nil
    DeviceListener = require("device/devicelistener")
  end)

  after_each(function()
    package.loaded["device"] = nil
    package.loaded["ui/uimanager"] = nil
    package.loaded["ui/widget/notification"] = nil
    package.loaded["ui/elements/mass_storage"] = nil
    package.loaded["ui/event"] = nil
    package.loaded["gettext"] = nil
    package.loaded["ffi/util"] = nil
    package.loaded["device/devicelistener"] = nil
    _G.G_reader_settings = nil
    _G.G_named_settings = nil
  end)

  describe("onToggleNightMode", function()
    it("should save setting and toggle night mode in screen and UIManager", function()
      local listener = DeviceListener:new{ ui = {} }
      listener:onToggleNightMode(true)

      assert.spy(G_reader_settings.save).was.called_with(G_reader_settings, "night_mode", true, false)
      assert.spy(mock_screen.setNightmode).was.called_with(mock_screen, true)
      assert.spy(mock_uimanager.toggleNightMode).was.called(1)
    end)

    it("should reset document call cache if provider is crengine", function()
      local mock_document = {
        provider = "crengine",
        resetCallCache = spy.new(function() end),
      }
      local listener = DeviceListener:new{
        ui = {
          document = mock_document
        }
      }
      listener:onToggleNightMode(true)

      assert.spy(mock_document.resetCallCache).was.called(1)
    end)

    it("should NOT reset document call cache if provider is not crengine", function()
      local mock_document = {
        provider = "mupdf",
        resetCallCache = spy.new(function() end),
      }
      local listener = DeviceListener:new{
        ui = {
          document = mock_document
        }
      }
      listener:onToggleNightMode(true)

      assert.spy(mock_document.resetCallCache).was_not.called()
    end)
  end)

  describe("changeFlIntensity", function()
    it("should return false if device has no frontlight", function()
      mock_device.hasFrontlight = spy.new(function() return false end)
      local listener = DeviceListener:new{}
      assert.is_false(listener:changeFlIntensity(5, 1))
    end)

    it("should change frontlight intensity by absolute value", function()
      local listener = DeviceListener:new{}
      stub(listener, "onSetFlIntensity")

      listener:changeFlIntensity(5, 1)
      assert.stub(listener.onSetFlIntensity).was.called_with(listener, 55)

      listener:changeFlIntensity(5, -1)
      assert.stub(listener.onSetFlIntensity).was.called_with(listener, 45)
    end)
  end)

  describe("onSetFlIntensity", function()
    it("should return true and do nothing if new intensity is same as current", function()
      local listener = DeviceListener:new{}
      assert.is_true(listener:onSetFlIntensity(50))
      assert.spy(mock_powerd.turnOffFrontlight).was_not.called()
      assert.spy(mock_powerd.setIntensity).was_not.called()
      assert.spy(mock_notification.notify).was_not.called()
    end)

    it("should turn off frontlight if new intensity <= 0", function()
      local listener = DeviceListener:new{}
      assert.is_true(listener:onSetFlIntensity(0))
      assert.spy(mock_powerd.turnOffFrontlight).was.called(1)
      assert.spy(mock_powerd.updateResumeFrontlightState).was.called(1)
      assert.spy(mock_notification.notify).was.called_with(mock_notification, "Frontlight disabled.")
    end)

    it("should set intensity if new intensity > 0", function()
      local listener = DeviceListener:new{}
      assert.is_true(listener:onSetFlIntensity(75))
      assert.spy(mock_powerd.setIntensity).was.called_with(mock_powerd, 75)
      assert.spy(mock_powerd.updateResumeFrontlightState).was.called(1)
      assert.spy(mock_notification.notify).was.called_with(mock_notification, "Frontlight intensity set to 50.")
    end)
  end)

  describe("changeFlWarmth", function()
    it("should return false if device has no natural light", function()
      mock_device.hasNaturalLight = spy.new(function() return false end)
      local listener = DeviceListener:new{}
      assert.is_false(listener:changeFlWarmth(1, 1))
    end)

    it("should change warmth and call onSetFlWarmth with mapped native value", function()
      local listener = DeviceListener:new{}
      stub(listener, "onSetFlWarmth")

      listener:changeFlWarmth(1, 1)
      assert.stub(listener.onSetFlWarmth).was.called_with(listener, 10)

      listener:changeFlWarmth(1, -1)
      assert.stub(listener.onSetFlWarmth).was.called_with(listener, -10)
    end)
  end)

  describe("onSetFlWarmth", function()
    it("should return false if device has no natural light", function()
      mock_device.hasNaturalLight = spy.new(function() return false end)
      local listener = DeviceListener:new{}
      assert.is_false(listener:onSetFlWarmth(50))
    end)

    it("should clamp warmth and notify", function()
      local listener = DeviceListener:new{}
      assert.is_true(listener:onSetFlWarmth(120))
      assert.spy(mock_powerd.setWarmth).was.called_with(mock_powerd, 100)
      assert.spy(mock_notification.notify).was.called_with(mock_notification, "Warmth set to 0.")

      mock_powerd.setWarmth:clear()
      assert.is_true(listener:onSetFlWarmth(-10))
      assert.spy(mock_powerd.setWarmth).was.called_with(mock_powerd, 0)
    end)
  end)

  describe("onToggleFrontlight", function()
    it("should toggle frontlight and notify when on", function()
      mock_powerd.isFrontlightOn = spy.new(function() return true end)
      local listener = DeviceListener:new{}

      listener:onToggleFrontlight()
      assert.spy(mock_powerd.toggleFrontlight).was.called(1)
      assert.spy(mock_notification.notify).was.called_with(mock_notification, "Frontlight disabled.", "test")
      assert.spy(mock_powerd.updateResumeFrontlightState).was.called(1)
    end)

    it("should toggle frontlight and notify when off", function()
      mock_powerd.isFrontlightOn = spy.new(function() return false end)
      local listener = DeviceListener:new{}

      listener:onToggleFrontlight()
      assert.spy(mock_powerd.toggleFrontlight).was.called(1)
      assert.spy(mock_notification.notify).was.called_with(mock_notification, "Frontlight enabled.", "test")
      assert.spy(mock_powerd.updateResumeFrontlightState).was.called(1)
    end)

    it("should notify unchanged if powerd toggle returns false", function()
      mock_powerd.toggleFrontlight = spy.new(function() return false end)
      local listener = DeviceListener:new{}

      listener:onToggleFrontlight()
      assert.spy(mock_notification.notify).was.called_with(mock_notification, "Frontlight unchanged.", "test")
    end)
  end)

  describe("onShowFlDialog", function()
    it("should call Device:showLightDialog", function()
      local listener = DeviceListener:new{}
      listener:onShowFlDialog()
      assert.spy(mock_device.showLightDialog).was.called(1)
    end)
  end)

  describe("GSensor toggles", function()
    it("onToggleGSensor should flip setting and toggle sensor (currently off)", function()
      G_reader_settings:makeTrue("input_ignore_gsensor")
      local listener = DeviceListener:new{}
      assert.is_true(listener:onToggleGSensor())

      assert.is_false(G_reader_settings:isTrue("input_ignore_gsensor"))
      assert.spy(mock_device.toggleGSensor).was.called_with(mock_device, true)
      assert.spy(mock_notification.notify).was.called_with(mock_notification, "Accelerometer rotation events on.")
    end)

    it("onToggleGSensor should flip setting and toggle sensor (currently on)", function()
      G_reader_settings:makeFalse("input_ignore_gsensor")
      local listener = DeviceListener:new{}
      assert.is_true(listener:onToggleGSensor())

      assert.is_true(G_reader_settings:isTrue("input_ignore_gsensor"))
      assert.spy(mock_device.toggleGSensor).was.called_with(mock_device, false)
      assert.spy(mock_notification.notify).was.called_with(mock_notification, "Accelerometer rotation events off.")
    end)

    it("onTempGSensorOn should do nothing if sensor is already on", function()
      G_reader_settings:makeFalse("input_ignore_gsensor")
      local listener = DeviceListener:new{}
      assert.is_true(listener:onTempGSensorOn())

      assert.spy(mock_device.toggleGSensor).was_not.called()
      assert.spy(mock_notification.notify).was.called_with(mock_notification, "Accelerometer rotation events already on.")
    end)

    it("onTempGSensorOn should temporarily turn sensor on if it was off", function()
      G_reader_settings:makeTrue("input_ignore_gsensor")
      local listener = DeviceListener:new{}

      local scheduled_cb
      mock_uimanager.scheduleIn = spy.new(function(_, _delay, cb)
        scheduled_cb = cb
      end)

      assert.is_true(listener:onTempGSensorOn())

      assert.spy(mock_device.toggleGSensor).was.called_with(mock_device, true)
      assert.spy(mock_notification.notify).was.called_with(mock_notification, "Accelerometer rotation events on for 5 seconds.")

      assert.is_not_nil(scheduled_cb)
      mock_device.toggleGSensor:clear()
      scheduled_cb()
      assert.spy(mock_device.toggleGSensor).was.called_with(mock_device, false)
    end)

    it("onLockGSensor should flip lock setting and call Device:lockGSensor", function()
      G_reader_settings:makeFalse("input_lock_gsensor")
      local listener = DeviceListener:new{}
      assert.is_true(listener:onLockGSensor())

      assert.is_true(G_reader_settings:isTrue("input_lock_gsensor"))
      assert.spy(mock_device.lockGSensor).was.called_with(mock_device, true)
      assert.spy(mock_notification.notify).was.called_with(mock_notification, "Orientation locked.")

      mock_device.lockGSensor:clear()
      mock_notification.notify:clear()

      assert.is_true(listener:onLockGSensor())
      assert.is_nil(G_reader_settings:read("input_lock_gsensor"))
      assert.spy(mock_device.lockGSensor).was.called_with(mock_device, false)
      assert.spy(mock_notification.notify).was.called_with(mock_notification, "Orientation unlocked.")
    end)
  end)

  describe("Screen Rotation Controls", function()
    it("onIterateRotation should rotate CW (step 1) when ccw is false", function()
      mock_screen.getRotationMode = function() return 0 end
      local listener = DeviceListener:new{}
      assert.is_true(listener:onIterateRotation(false))

      assert.spy(mock_uimanager.broadcastEvent).was.called_with(mock_uimanager, { name = "SetRotationMode", arg = 1 })
    end)

    it("onIterateRotation should rotate CCW (step -1) when ccw is true", function()
      mock_screen.getRotationMode = function() return 0 end
      local listener = DeviceListener:new{}
      assert.is_true(listener:onIterateRotation(true))

      assert.spy(mock_uimanager.broadcastEvent).was.called_with(mock_uimanager, { name = "SetRotationMode", arg = 3 })
    end)

    it("onInvertRotation should rotate by 180 degrees (+2)", function()
      mock_screen.getRotationMode = function() return 1 end
      local listener = DeviceListener:new{}
      assert.is_true(listener:onInvertRotation())

      assert.spy(mock_uimanager.broadcastEvent).was.called_with(mock_uimanager, { name = "SetRotationMode", arg = 3 })
    end)

    it("onSwapRotation should swap portrait (0) to landscape (1)", function()
      mock_screen.getRotationMode = function() return 0 end
      local listener = DeviceListener:new{}
      assert.is_true(listener:onSwapRotation())

      assert.spy(mock_uimanager.broadcastEvent).was.called_with(mock_uimanager, { name = "SetRotationMode", arg = 1 })
    end)

    it("onSwapRotation should swap landscape (3) to portrait (2)", function()
      mock_screen.getRotationMode = function() return 3 end
      local listener = DeviceListener:new{}
      assert.is_true(listener:onSwapRotation())

      assert.spy(mock_uimanager.broadcastEvent).was.called_with(mock_uimanager, { name = "SetRotationMode", arg = 2 })
    end)
  end)

  describe("Button Mapping, Refresh, and Utilities", function()
    it("onSetRefreshRate should set full_refresh_count and call updateRefreshRate", function()
      local listener = DeviceListener:new{}
      listener:onSetRefreshRate(5)

      assert.spy(mock_named_settings.set.full_refresh_count).was.called_with(5)
      assert.spy(mock_uimanager.updateRefreshRate).was.called(1)
    end)

    describe("onSwapPageTurnButtons", function()
      it("side = left: should disable global inversion and flip left-side page-turn buttons inversion", function()
        G_reader_settings:makeTrue("input_invert_page_turn_keys")
        G_reader_settings:makeFalse("input_invert_left_page_turn_keys")
        local listener = DeviceListener:new{}

        assert.is_true(listener:onSwapPageTurnButtons("left"))

        assert.is_false(G_reader_settings:isTrue("input_invert_page_turn_keys"))
        assert.spy(mock_device.invertButtons).was.called(1)
        assert.is_true(G_reader_settings:isTrue("input_invert_left_page_turn_keys"))
        assert.spy(mock_device.invertButtonsLeft).was.called(1)
        assert.spy(mock_notification.notify).was.called_with(mock_notification, "Left-side page-turn buttons inverted.")
      end)

      it("side = right: should disable global inversion and flip right-side page-turn buttons inversion", function()
        G_reader_settings:makeTrue("input_invert_page_turn_keys")
        G_reader_settings:makeFalse("input_invert_right_page_turn_keys")
        local listener = DeviceListener:new{}

        assert.is_true(listener:onSwapPageTurnButtons("right"))

        assert.is_false(G_reader_settings:isTrue("input_invert_page_turn_keys"))
        assert.spy(mock_device.invertButtons).was.called(1)
        assert.is_true(G_reader_settings:isTrue("input_invert_right_page_turn_keys"))
        assert.spy(mock_device.invertButtonsRight).was.called(1)
        assert.spy(mock_notification.notify).was.called_with(mock_notification, "Right-side page-turn buttons inverted.")
      end)

      it("side = nil: if both left and right are inverted, should clear them all and notify no longer inverted", function()
        G_reader_settings:makeTrue("input_invert_left_page_turn_keys")
        G_reader_settings:makeTrue("input_invert_right_page_turn_keys")
        G_reader_settings:makeTrue("input_invert_page_turn_keys")
        local listener = DeviceListener:new{}

        assert.is_true(listener:onSwapPageTurnButtons())

        assert.is_false(G_reader_settings:isTrue("input_invert_left_page_turn_keys"))
        assert.is_false(G_reader_settings:isTrue("input_invert_right_page_turn_keys"))
        assert.is_false(G_reader_settings:isTrue("input_invert_page_turn_keys"))
        assert.spy(mock_device.invertButtons).was.called(1)
        assert.spy(mock_notification.notify).was.called_with(mock_notification, "Page-turn buttons no longer inverted.")
      end)

      it("side = nil: if only left was inverted, should clear left and toggle global inversion", function()
        G_reader_settings:makeTrue("input_invert_left_page_turn_keys")
        G_reader_settings:makeFalse("input_invert_right_page_turn_keys")
        G_reader_settings:makeFalse("input_invert_page_turn_keys")
        local listener = DeviceListener:new{}

        assert.is_true(listener:onSwapPageTurnButtons())

        assert.is_false(G_reader_settings:isTrue("input_invert_left_page_turn_keys"))
        assert.spy(mock_device.invertButtonsLeft).was.called(1)
        assert.is_true(G_reader_settings:isTrue("input_invert_page_turn_keys"))
        assert.spy(mock_device.invertButtons).was.called(1)
        assert.spy(mock_notification.notify).was.called_with(mock_notification, "Page-turn buttons inverted.")
      end)
    end)

    describe("onToggleKeyRepeat", function()
      it("toggle = true: should make input_no_key_repeat false and call toggleKeyRepeat(true)", function()
        G_reader_settings:makeTrue("input_no_key_repeat")
        local listener = DeviceListener:new{}

        listener:onToggleKeyRepeat(true)

        assert.is_false(G_reader_settings:isTrue("input_no_key_repeat"))
        assert.spy(mock_device.toggleKeyRepeat).was.called_with(mock_device, true)
      end)

      it("toggle = false: should make input_no_key_repeat true and call toggleKeyRepeat(false)", function()
        G_reader_settings:makeFalse("input_no_key_repeat")
        local listener = DeviceListener:new{}

        listener:onToggleKeyRepeat(false)

        assert.is_true(G_reader_settings:isTrue("input_no_key_repeat"))
        assert.spy(mock_device.toggleKeyRepeat).was.called_with(mock_device, false)
      end)

      it("toggle = nil: should flip input_no_key_repeat and call toggleKeyRepeat", function()
        G_reader_settings:makeFalse("input_no_key_repeat")
        local listener = DeviceListener:new{}

        listener:onToggleKeyRepeat()

        assert.is_true(G_reader_settings:isTrue("input_no_key_repeat"))
        assert.spy(mock_device.toggleKeyRepeat).was.called_with(mock_device, false)
      end)
    end)

    it("onRequestUSBMS should call start on MassStorage", function()
      local listener = DeviceListener:new{}
      listener:onRequestUSBMS()

      assert.spy(mock_mass_storage.start).was.called_with(mock_mass_storage, false)
    end)

    describe("UIManager and exit/restart callbacks", function()
      local mock_menu
      local listener

      before_each(function()
        mock_menu = {
          exitOrRestart = spy.new(function(self, cb) if cb then cb() end end),
        }
        listener = DeviceListener:new{
          ui = {
            menu = mock_menu,
            view = true,
          }
        }
      end)

      it("onExitKOReader should delegate to ui.menu:exitOrRestart with callback", function()
        local cb = spy.new(function() end)
        listener:onExitKOReader(cb)

        assert.spy(mock_menu.exitOrRestart).was.called(1)
        assert.spy(cb).was.called(1)
      end)

      it("onRestart should restart KOReader via callback to exitOrRestart", function()
        listener:onRestart()

        assert.spy(mock_menu.exitOrRestart).was.called(1)
        assert.spy(mock_uimanager.restartKOReader).was.called(1)
      end)

      it("onRequestSuspend should suspend UIManager", function()
        listener:onRequestSuspend()
        assert.spy(mock_uimanager.suspend).was.called(1)
      end)

      it("onRequestReboot should reboot UIManager", function()
        listener:onRequestReboot()
        assert.spy(mock_uimanager.askForReboot).was.called(1)
      end)

      it("onRequestPowerOff should power off UIManager", function()
        listener:onRequestPowerOff()
        assert.spy(mock_uimanager.askForPowerOff).was.called(1)
      end)

      it("onFullRefresh should broadcast UpdateFooter and schedule refresh", function()
        listener:onFullRefresh()

        assert.spy(mock_uimanager.broadcastEvent).was.called_with(mock_uimanager, "UpdateFooter")
        assert.spy(mock_uimanager.scheduleRefresh).was.called_with(mock_uimanager, "full")
      end)

      it("onResume should restore Gestures handling in InputContainer by setting setIgnoreTouchInput to false", function()
        listener:onResume()
        assert.spy(mock_uimanager.setIgnoreTouchInput).was.called_with(mock_uimanager, false)
      end)
    end)
  end)
end)
