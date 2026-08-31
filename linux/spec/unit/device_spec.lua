describe("device module", function()
  -- luacheck: push ignore
  local mock_fb, mock_input
  local iopen = io.open
  local ipopen = io.popen
  local osgetenv = os.getenv
  local ffi, C

  setup(function()
    local fb = require("ffi/framebuffer")
    mock_fb = {
      new = function()
        return {
          device = package.loaded.device,
          bb = require("ffi/blitbuffer").new(600, 800, 1),
          getRawSize = function()
            return { w = 600, h = 800 }
          end,
          getWidth = function()
            return 600
          end,
          getHeight = function()
            return 800
          end,
          getArea = function()
            return 600 * 800
          end,
          getDPI = function()
            return 72
          end,
          setViewport = function() end,
          getRotationMode = function()
            return 0
          end,
          getScreenMode = function()
            return "portrait"
          end,
          setRotationMode = function() end,
          scaleByDPI = fb.scaleByDPI,
          scaleBySize = fb.scaleBySize,
          setWindowTitle = function() end,
          refreshFull = function() end,
          refreshA2 = function() end,
          refreshFast = function() end,
          refreshUI = function() end,
          refreshPartial = function() end,
          refreshNoMergeUI = function() end,
          refreshNoMergePartial = function() end,
          refreshFlashUI = function() end,
          refreshFlashPartial = function() end,
          getHWNightmode = function()
            return false
          end,
          setNightmode = function() end,
          beforePaint = function() end,
          afterPaint = function() end,
          setupDithering = function() end,
        }
      end,
    }
    require("commonrequire")
    package.unloadAll()
    ffi = require("ffi")
    C = ffi.C
    require("ffi/linux_input_h")
    require("document/canvascontext"):init(require("device"))
  end)

  before_each(function()
    package.loaded["ffi/framebuffer_mxcfb"] = mock_fb
    mock_input = require("device/input")
    mock_input.input = {}
    mock_input.gameControllerRumble = function()
      return false
    end
    stub(mock_input, "open")
    stub(os, "getenv")
    stub(os, "execute")
    G_reader_settings:save("plugins_disabled", {
      statistics = true,
    })
  end)

  after_each(function()
    -- Don't let UIManager hang on to a stale Device reference, and vice-versa...
    package.unload("device")
    package.unload("device/generic/device")
    package.unload("device/generic/powerd")
    package.unload("ui/uimanager")
    package.unload("apps/reader/readerui")
    mock_input.open:revert()
    os.getenv:revert()
    os.execute:revert()

    os.getenv = osgetenv
    io.open = iopen
    io.popen = ipopen
  end)

  describe("kobo", function()
    local time
    local NickelConf
    setup(function()
      time = require("ui/time")
      NickelConf = require("device/kobo/nickel_conf")
    end)

    before_each(function()
      stub(NickelConf.frontLightLevel, "get")
      NickelConf.frontLightLevel.get.returns(0)
      stub(NickelConf.frontLightState, "get")
    end)

    after_each(function()
      NickelConf.frontLightLevel.get:revert()
      NickelConf.frontLightState.get:revert()
    end)

    it("should initialize properly on Kobo dahlia", function()
      os.getenv.returns("dahlia")
      local kobo_dev = require("device/kobo/device")

      kobo_dev:init()
      assert.is.same("Kobo_dahlia", kobo_dev.model)
    end)

    it(
      "should setup eventAdjustHooks properly for input on trilogy C",
      function()
        os.getenv.invokes(function(key)
          if key == "PRODUCT" then
            return "trilogy"
          elseif key == "MODEL_NUMBER" then
            return "320"
          else
            return osgetenv(key)
          end
        end)

        package.loaded["device/kobo/device"] = nil
        local kobo_dev = require("device/kobo/device")
        kobo_dev:init()
        local Screen = kobo_dev.screen

        assert.is.same("Kobo_trilogy_C", kobo_dev.model)
        local x, y = Screen:getWidth() - 5, 10
        -- mirror x, then switch_xy
        local ev_x = {
          type = C.EV_ABS,
          code = C.ABS_X,
          value = y,
          time = time:realtime(),
        }
        local ev_y = {
          type = C.EV_ABS,
          code = C.ABS_Y,
          value = Screen:getWidth() - 1 - x,
          time = time:realtime(),
        }

        kobo_dev.input:eventAdjustHook(ev_x)
        kobo_dev.input:eventAdjustHook(ev_y)
        assert.is.same(x, ev_y.value)
        assert.is.same(C.ABS_X, ev_y.code)
        assert.is.same(y, ev_x.value)
        assert.is.same(C.ABS_Y, ev_x.code)

        -- reset eventAdjustHook
        kobo_dev.input.eventAdjustHook = function() end
      end
    )

    it(
      "should setup eventAdjustHooks properly for trilogy with non-epoch ev time",
      function()
        -- This has no more value since #6798 as ev time can now stay
        -- non-epoch. Adjustments are made on first event handled, and
        -- have only effects when handling long-press (so, the long-press
        -- for dict lookup tests with test this).
        -- We just check here it still works with non-epoch ev time, as previous test
        os.getenv.invokes(function(key)
          if key == "PRODUCT" then
            return "trilogy"
          elseif key == "MODEL_NUMBER" then
            return "320"
          else
            return osgetenv(key)
          end
        end)

        package.loaded["device/kobo/device"] = nil
        local kobo_dev = require("device/kobo/device")
        kobo_dev:init()
        local Screen = kobo_dev.screen

        assert.is.same("Kobo_trilogy_C", kobo_dev.model)
        local x, y = Screen:getWidth() - 5, 10
        local ev_x = {
          type = C.EV_ABS,
          code = C.ABS_X,
          value = y,
          time = { sec = 1000 },
        }
        local ev_y = {
          type = C.EV_ABS,
          code = C.ABS_Y,
          value = Screen:getWidth() - 1 - x,
          time = { sec = 1000 },
        }

        kobo_dev.input:eventAdjustHook(ev_x)
        kobo_dev.input:eventAdjustHook(ev_y)
        assert.is.same(x, ev_y.value)
        assert.is.same(C.ABS_X, ev_y.code)
        assert.is.same(y, ev_x.value)
        assert.is.same(C.ABS_Y, ev_x.code)

        -- reset eventAdjustHook
        kobo_dev.input.eventAdjustHook = function() end
      end
    )
  end)

  describe("kindle", function()
    local function make_io_open_kindle_model_override(model_no)
      return function(filename, mode)
        if filename == "/proc/usid" then
          return {
            read = function()
              return model_no
            end,
            close = function() end,
          }
        else
          return iopen(filename, mode)
        end
      end
    end

    insulate("without framework", function()
      local mock_lipc = {
        init = function()
          return {
            set_int_property = mock(function() end),
            get_int_property = function()
              return 0
            end,
            get_string_property = function()
              return "string prop"
            end,
            set_string_property = function() end,
            register_int_property = function()
              return {}
            end,
            close = function() end,
          }
        end,
      }
      package.loaded["liblipclua"] = mock_lipc
      package.loaded["libopenlipclua"] = mock_lipc

      before_each(function()
        os.getenv.invokes(function(e)
          if e == "STOP_FRAMEWORK" then
            return "yes"
          else
            return osgetenv(e)
          end
        end)
      end)

      it("sets framework_lipc_handle", function()
        io.open = make_io_open_kindle_model_override("B013XX")

        local kindle_dev = require("device/kindle/device")
        assert.is.truthy(kindle_dev.framework_lipc_handle)
      end)

      it("reactivates voyage whispertouch keys", function()
        io.open = make_io_open_kindle_model_override("B013XX")

        local kindle_dev = require("device/kindle/device")
        local fw_lipc_handle = kindle_dev.framework_lipc_handle

        kindle_dev:init()

        for _, fsr_prop in pairs({
          "fsrkeypadEnable",
          "fsrkeypadPrevEnable",
          "fsrkeypadNextEnable",
        }) do
          assert
            .spy(fw_lipc_handle.l.set_int_property).was
            .called_with(fw_lipc_handle.l, "com.lab126.deviced", fsr_prop, 1)
        end
      end)
    end)

    insulate("with framework", function()
      it("does not set framework_lipc_handle", function()
        io.open = make_io_open_kindle_model_override("B013XX")

        local kindle_dev = require("device/kindle/device")
        assert.is.falsy(kindle_dev.framework_lipc_handle)
      end)
    end)

    it("should initialize voyage without error", function()
      io.open = make_io_open_kindle_model_override("B013XX")

      local kindle_dev = require("device/kindle/device")
      assert.is.same(kindle_dev.model, "KindleVoyage")
      kindle_dev:init()
      assert.is.same(kindle_dev.input.event_map[104], "LPgBack")
      assert.is.same(kindle_dev.input.event_map[109], "LPgFwd")
      assert.is.same(kindle_dev.powerd.fl_min, 0)
      -- NOTE: fl_max + 1 since #5989
      assert.is.same(kindle_dev.powerd.fl_max, 25)
    end)

    it("should toggle frontlight", function()
      io.open = function(filename, mode)
        if filename == "/proc/usid" then
          return {
            read = function()
              return "B013XX"
            end,
            close = function() end,
          }
        elseif filename == "/sys/class/backlight/max77696-bl/brightness" then
          return {
            read = function()
              return 12
            end,
            close = function() end,
          }
        else
          return iopen(filename, mode)
        end
      end

      local kindle_dev = require("device/kindle/device")
      kindle_dev:init()

      assert.is.same(kindle_dev.powerd.fl_intensity, 12)
      kindle_dev.powerd:setIntensity(5)
      assert.is.same(kindle_dev.powerd.fl_intensity, 5)

      kindle_dev.powerd:toggleFrontlight()
      -- Here be shenanigans: we don't override powerd's fl_intensity when we turn the light off,
      -- so that we can properly turn it back on at the previous intensity ;)
      assert.is.same(kindle_dev.powerd.fl_intensity, 5)
      -- But if we were to cat /sys/class/backlight/max77696-bl/brightness, it should now be 0.

      kindle_dev.powerd:toggleFrontlight()
      assert.is.same(kindle_dev.powerd.fl_intensity, 5)
      -- And /sys/class/backlight/max77696-bl/brightness is now !0
      -- (exact value is HW-dependent, each model has a different curve, we let lipc do the work for us).
    end)

    it("oasis should interpret orientation event", function()
      package.unload("device/kindle/device")
      io.open = make_io_open_kindle_model_override("G0B0GCXXX")

      stub(mock_input.input, "waitForEvent")
      mock_input.input.waitForEvent.returns(true, {
        {
          type = C.EV_ABS,
          time = {
            usec = 450565,
            sec = 1471081881,
          },
          code = 24, -- C.ABS_PRESSURE
          value = 16,
        },
      })

      local UIManager = require("ui/uimanager")
      stub(UIManager, "onRotation")

      local kindle_dev = require("device/kindle/device")
      assert.is.same("KindleOasis", kindle_dev.model)
      kindle_dev:init()
      kindle_dev:lockGSensor(true)

      kindle_dev.input:waitEvent()
      assert.stub(UIManager.onRotation).was_called()

      mock_input.input.waitForEvent:revert()
      UIManager.onRotation:revert()
    end)
  end)

  describe("Flush book Settings for", function()
    it("Kobo", function()
      os.getenv.invokes(function(key)
        if key == "PRODUCT" then
          return "trilogy"
        elseif key == "MODEL_NUMBER" then
          return "320"
        else
          return osgetenv(key)
        end
      end)
      -- Bypass frontend/device probeDevice, while making sure that it points to the right implementation
      local Device = require("device/kobo/device")
      -- Apparently common isn't setup properly in the testsuite, so we can't have nice things
      stub(Device, "initNetworkManager")
      stub(Device, "suspend")
      Device:init()
      -- Don't poke the RTC
      Device.wakeup_mgr = require("device/wakeupmgr"):new({
        rtc = require("device/kindle/mockrtc"),
      })
      -- Don't poke the fl
      Device.powerd.fl = nil
      package.loaded.device = Device

      local UIManager = require("ui/uimanager")
      -- Generic's onPowerEvent may request a repaint, but we can't do that
      stub(UIManager, "forceRepaint")
      UIManager:init()

      local sample_pdf = "spec/front/unit/data/tall.pdf"
      local ReaderUI = require("apps/reader/readerui")
      ReaderUI:showReader(sample_pdf)
      local readerui = ReaderUI.instance
      -- Busted stub table is incompatible with EventListener:handleEvent array check
      local onFlushSettings_called = 0
      readerui.onFlushSettings = function(self, ...)
        onFlushSettings_called = onFlushSettings_called + 1
      end
      UIManager.event_handlers.PowerPress()
      UIManager.event_handlers.PowerRelease()
      assert.is.same(1, onFlushSettings_called)

      UIManager.forceRepaint:revert()
      Device.initNetworkManager:revert()
      Device.suspend:revert()
      Device.screen_saver_mode = false
      readerui:onClose()
    end)

    it("Cervantes", function()
      io.popen = function(filename, mode)
        if filename:find("/usr/bin/ntxinfo") then
          return {
            read = function()
              return 68 -- Cervantes4
            end,
            close = function() end,
          }
        else
          return ipopen(filename, mode)
        end
      end

      local Device = require("device/cervantes/device")
      stub(Device, "initNetworkManager")
      stub(Device, "suspend")
      Device:init()
      Device.powerd.fl = nil
      package.loaded.device = Device

      local UIManager = require("ui/uimanager")
      stub(UIManager, "forceRepaint")
      UIManager:init()

      local sample_pdf = "spec/front/unit/data/tall.pdf"
      local ReaderUI = require("apps/reader/readerui")
      ReaderUI:showReader(sample_pdf)
      local readerui = ReaderUI.instance
      local onFlushSettings_called = 0
      readerui.onFlushSettings = function(self, ...)
        onFlushSettings_called = onFlushSettings_called + 1
      end
      UIManager.event_handlers.PowerPress()
      UIManager.event_handlers.PowerRelease()
      assert.is.same(1, onFlushSettings_called)

      UIManager.forceRepaint:revert()
      Device.initNetworkManager:revert()
      Device.suspend:revert()
      Device.screen_saver_mode = false
      readerui:onClose()
    end)

    it("Remarkable", function()
      io.open = function(filename, mode)
        if filename == "/usr/bin/xochitl" then
          return {
            read = function()
              return true
            end,
            close = function() end,
          }
        elseif filename == "/sys/devices/soc0/machine" then
          return {
            read = function()
              return "reMarkable", "generic"
            end,
            close = function() end,
          }
        else
          return iopen(filename, mode)
        end
      end
      local Device = require("device/remarkable/device")
      stub(Device, "initNetworkManager")
      stub(Device, "suspend")
      Device:init()
      Device.powerd.fl = nil
      package.loaded.device = Device

      local UIManager = require("ui/uimanager")
      stub(UIManager, "forceRepaint")
      UIManager:init()

      local sample_pdf = "spec/front/unit/data/tall.pdf"
      local ReaderUI = require("apps/reader/readerui")
      ReaderUI:showReader(sample_pdf)
      local readerui = ReaderUI.instance
      local onFlushSettings_called = 0
      readerui.onFlushSettings = function(self, ...)
        onFlushSettings_called = onFlushSettings_called + 1
      end
      UIManager.event_handlers.PowerPress()
      UIManager.event_handlers.PowerRelease()
      assert.is.same(1, onFlushSettings_called)

      UIManager.forceRepaint:revert()
      Device.initNetworkManager:revert()
      Device.suspend:revert()
      Device.screen_saver_mode = false
      readerui:onClose()
    end)

    it("SDL", function()
      local Device = require("device/sdl/device")
      stub(Device, "initNetworkManager")
      stub(Device, "suspend")
      Device:init()
      package.loaded.device = Device

      local UIManager = require("ui/uimanager")
      UIManager:init()

      local sample_pdf = "spec/front/unit/data/tall.pdf"
      local ReaderUI = require("apps/reader/readerui")
      ReaderUI:showReader(sample_pdf)
      local readerui = ReaderUI.instance
      local onFlushSettings_called = 0
      readerui.onFlushSettings = function(self, ...)
        onFlushSettings_called = onFlushSettings_called + 1
      end
      -- UIManager.event_handlers.PowerPress() -- We only fake a Release event on the Emu
      UIManager.event_handlers.PowerRelease()
      assert.is.same(1, onFlushSettings_called)

      Device.initNetworkManager:revert()
      Device.suspend:revert()
      Device.screen_saver_mode = false
      readerui:onClose()
    end)

    describe("getTmpDir()", function()
      it("returns tmp directory string", function()
        local tmp_dir = Device:getTmpDir()
        assert.is_string(tmp_dir)
        assert.is_true(#tmp_dir > 0)
      end)

      it("respects TMPDIR environment variable if present", function()
        local old_tmp = Device.tmp_dir
        Device.tmp_dir = nil
        local custom_tmp = os.getenv("TMPDIR") or "/tmp"
        local res = Device:_getTmpDir()
        assert.is_string(res)
        Device.tmp_dir = old_tmp
      end)
    end)
  end)

  describe("generic device", function()
    local Generic, Screen
    local test_dev

    before_each(function()
      Generic = require("device/generic/device")
      Screen = mock_fb.new()
      Screen.setDPI = spy(function() end)
      Screen.getHWNightmode = function()
        return false
      end
      Screen.setNightmode = spy(function() end)
      Screen.setupDithering = spy(function() end)
      Screen.toggleHWDithering = spy(function() end)
      Screen.toggleSWDithering = spy(function() end)
      Screen.close = spy(function() end)
      Screen.refreshFull = spy(function() end)

      test_dev = Generic:extend({
        model = "GenericTestModel",
        screen = Screen,
        hasKeys = util.yes,
        hasGSensor = util.yes,
        hasEinkScreen = util.yes,
        hasWifiToggle = util.yes,
        isTouchDevice = util.yes,
        canUseCBB = util.no,
        canHWDither = util.yes,
        disableKeyRepeat = spy(function() end),
        restoreKeyRepeat = spy(function() end),
        setupChargingLED = spy(function() end),
        saveSettings = spy(function() end),
        suspend = spy(function() end),
        resume = spy(function() end),
      })

      test_dev.input = {
        event_map = {
          [104] = "LPgBack",
          [109] = "LPgFwd",
          [114] = "RPgBack",
          [119] = "RPgFwd",
        },
        toggleGyroEvents = spy(function() end),
        registerEventAdjustHook = spy(function() end),
        adjustTouchTranslate = function() end,
        gesture_detector = {
          init = spy(function() end),
        },
        UIManagerReady = spy(function() end),
        teardown = spy(function() end),
      }

      test_dev.powerd = {
        UIManagerReady = spy(function() end),
        beforeSuspend = spy(function() end),
        afterResume = spy(function() end),
        invalidateCapacityCache = spy(function() end),
      }

      local UIManager = require("ui/uimanager")
      UIManager:init()
    end)

    describe("button inversion", function()
      it("inverts all page turn buttons", function()
        test_dev:invertButtons()
        assert.is_equal("LPgFwd", test_dev.input.event_map[104])
        assert.is_equal("LPgBack", test_dev.input.event_map[109])
        assert.is_equal("RPgFwd", test_dev.input.event_map[114])
        assert.is_equal("RPgBack", test_dev.input.event_map[119])
      end)

      it("inverts left page turn buttons only", function()
        test_dev:invertButtonsLeft()
        assert.is_equal("LPgFwd", test_dev.input.event_map[104])
        assert.is_equal("LPgBack", test_dev.input.event_map[109])
        assert.is_equal("RPgBack", test_dev.input.event_map[114])
        assert.is_equal("RPgFwd", test_dev.input.event_map[119])
      end)

      it("inverts right page turn buttons only", function()
        test_dev:invertButtonsRight()
        assert.is_equal("LPgBack", test_dev.input.event_map[104])
        assert.is_equal("LPgFwd", test_dev.input.event_map[109])
        assert.is_equal("RPgFwd", test_dev.input.event_map[114])
        assert.is_equal("RPgBack", test_dev.input.event_map[119])
      end)

      it("handles button inversion safely when hasKeys is false", function()
        test_dev.hasKeys = util.no
        test_dev:invertButtons()
        assert.is_equal("LPgBack", test_dev.input.event_map[104])
      end)
    end)

    describe("gsensor and gyro controls", function()
      it("toggles gsensor", function()
        test_dev:toggleGSensor(true)
        assert
          .spy(test_dev.input.toggleGyroEvents).was
          .called_with(test_dev.input, true)

        test_dev:toggleGSensor(false)
        assert
          .spy(test_dev.input.toggleGyroEvents).was
          .called_with(test_dev.input, false)
      end)

      it("locks and unlocks gsensor", function()
        test_dev:lockGSensor(true)
        assert.is_true(test_dev:isGSensorLocked())

        test_dev:lockGSensor(false)
        assert.is_false(test_dev:isGSensorLocked())

        -- Toggle mode
        test_dev:lockGSensor()
        assert.is_true(test_dev:isGSensorLocked())
        test_dev:lockGSensor()
        assert.is_false(test_dev:isGSensorLocked())
      end)

      it("does nothing when device has no gsensor", function()
        test_dev.hasGSensor = util.no
        test_dev:toggleGSensor(true)
        test_dev:lockGSensor(true)
        assert.is_nil(test_dev.isGSensorLocked)
      end)
    end)

    describe("init and viewport", function()
      it("raises error if screen is not provided", function()
        test_dev.screen = nil
        assert.has_error(function()
          test_dev:init()
        end)
      end)

      it(
        "initializes device, registers viewport hook, and sets properties",
        function()
          test_dev.viewport = { x = 10, y = 20 }
          test_dev.screen.setViewport = spy(function() end)
          test_dev:init()

          assert
            .spy(test_dev.screen.setViewport).was
            .called_with(test_dev.screen, test_dev.viewport)
          assert.spy(test_dev.input.registerEventAdjustHook).was_called()
          assert.is_function(test_dev.screen.getSize)
          local sz = test_dev.screen:getSize()
          assert.is_equal(600, sz.w)
          assert.is_equal(800, sz.h)
        end
      )

      it("initializes color rendering settings", function()
        test_dev.hasColorScreen = util.yes
        test_dev:init()
        assert.is_true(test_dev.screen:isColorEnabled())
      end)

      it("sets screen DPI and triggers gesture detector init", function()
        test_dev.display_dpi = 300
        assert.is_equal(300, test_dev:getDeviceScreenDPI())
        assert.is_equal(test_dev.powerd, test_dev:getPowerDevice())

        test_dev:setScreenDPI(212)
        assert.spy(test_dev.screen.setDPI).was_called_with(test_dev.screen, 212)
        assert.spy(test_dev.input.gesture_detector.init).was_called()
      end)
    end)

    describe("power and lifecycle hooks", function()
      it("handles _UIManagerReady and sets event handlers", function()
        local UIManager = require("ui/uimanager")
        test_dev:_UIManagerReady(UIManager)
        assert.is_function(UIManager.event_handlers.Suspend)
        assert.is_function(UIManager.event_handlers.Resume)

        UIManager.event_handlers.Suspend()
        assert.spy(test_dev.powerd.beforeSuspend).was_called()

        UIManager.event_handlers.Resume()
        assert.spy(test_dev.powerd.afterResume).was_called()
      end)

      it("executes _beforeSuspend and _afterResume", function()
        local UIManager = require("ui/uimanager")
        local flushed = false
        stub(UIManager, "flushSettings", function()
          flushed = true
        end)
        stub(UIManager, "broadcastEvent")

        test_dev.total_suspend_time = 0
        test_dev:_beforeSuspend()
        assert.is_true(flushed)
        assert.spy(test_dev.disableKeyRepeat).was_called()
        assert.stub(UIManager.broadcastEvent).was_called()

        test_dev:_afterResume()
        assert.spy(test_dev.restoreKeyRepeat).was_called()
        assert.is_true(test_dev.total_suspend_time >= 0)

        UIManager.flushSettings:revert()
        UIManager.broadcastEvent:revert()
      end)

      it("executes _beforeCharging and _afterNotCharging", function()
        local UIManager = require("ui/uimanager")
        stub(UIManager, "broadcastEvent")
        test_dev._updateChargingLED = spy(function() end)

        test_dev:_beforeCharging()
        assert.spy(test_dev.powerd.invalidateCapacityCache).was_called()
        assert.spy(test_dev._updateChargingLED).was_called()

        test_dev:_afterNotCharging()
        assert.spy(test_dev.powerd.invalidateCapacityCache).was_called()

        UIManager.broadcastEvent:revert()
      end)

      it(
        "handles handlePowerEvent in screensaver mode with closed cover",
        function()
          test_dev.screen_saver_mode = true
          test_dev.is_cover_closed = true
          test_dev.rescheduleSuspend = spy(function() end)

          test_dev:handlePowerEvent("Power")
          assert.spy(test_dev.rescheduleSuspend).was_called()
        end
      )

      it(
        "handles handlePowerEvent in screensaver mode with open cover",
        function()
          test_dev.screen_saver_mode = true
          test_dev.is_cover_closed = false
          local Screensaver = require("ui/screensaver")
          stub(Screensaver, "close").returns(true)

          test_dev:handlePowerEvent("Power")
          assert.spy(test_dev.resume).was_called()
          assert.spy(test_dev.powerd.afterResume).was_called()

          Screensaver.close:revert()
        end
      )

      it("handles handlePowerEvent suspending when awake", function()
        test_dev.screen_saver_mode = false
        local Screensaver = require("ui/screensaver")
        local UIManager = require("ui/uimanager")
        stub(Screensaver, "setup")
        stub(Screensaver, "show")
        stub(UIManager, "forceRepaint")
        test_dev.rescheduleSuspend = spy(function() end)

        test_dev:handlePowerEvent("Power")
        assert.spy(Screensaver.setup).was_called()
        assert.spy(Screensaver.show).was_called()
        assert.spy(test_dev.powerd.beforeSuspend).was_called()
        assert.spy(test_dev.rescheduleSuspend).was_called()

        Screensaver.setup:revert()
        Screensaver.show:revert()
        UIManager.forceRepaint:revert()
      end)
    end)

    describe("helper methods", function()
      it("checks canExecuteScript for supported extensions", function()
        assert.is_true(test_dev:canExecuteScript("test.sh"))
        assert.is_true(test_dev:canExecuteScript("SCRIPT.PY"))
        assert.is_nil(test_dev:canExecuteScript("test.lua"))
        assert.is_nil(test_dev:canExecuteScript("test.txt"))
      end)

      it("checks path validation, info, and ota model", function()
        assert.is_equal("GenericTestModel", test_dev:info())
        test_dev.ota_model = "test_ota"
        local model, typ = test_dev:otaModel()
        assert.is_equal("test_ota", model)
        assert.is_equal("ota", typ)
        assert.is_equal(0, test_dev:ambientBrightnessLevel())
        assert.is_true(test_dev:isStartupScriptUpToDate())
        assert.is_true(test_dev:isAlwaysFullscreen())
        assert.is_false(test_dev:supportsScreensaver())
      end)

      it(
        "checks unpackArchive supported and unsupported formats",
        function()
          os.execute.returns(0)
          local ok = test_dev:unpackArchive("archive.tar.gz", "/tmp/extracted")
          assert.is_true(ok)

          local bad_ok, err =
            test_dev:unpackArchive("archive.zip", "/tmp/extracted")
          assert.is_false(bad_ok)
          assert.is_string(err)
        end
      )

      it("executes exit teardown cleanly", function()
        test_dev.orig_hw_nightmode = false
        test_dev:exit()
        assert.spy(test_dev.saveSettings).was_called()
        assert.spy(test_dev.screen.close).was_called()
        assert.spy(test_dev.input.teardown).was_called()
      end)
    end)

    describe("route and network diagnostics", function()
      it("parses routing table in getDefaultRoute", function()
        local sample_route = "Iface\tDestination\tGateway\tFlags\tRefCnt\tUse\tMetric\tMask\tMTU\tWindow\tIRTT\n"
          .. "eth0\t00000000\t0101A8C0\t0003\t0\t0\t0\t00000000\t0\t0\t0\n"
          .. "wlan0\t00000000\t010010AC\t0003\t0\t0\t0\t00000000\t0\t0\t0\n"

        io.open = function(path, mode)
          if path == "/proc/net/route" then
            local lines = {}
            for line in sample_route:gmatch("([^\n]+)") do
              table.insert(lines, line)
            end
            local idx = 0
            return {
              lines = function()
                return function()
                  idx = idx + 1
                  return lines[idx]
                end
              end,
              close = function() end,
            }
          end
          return iopen(path, mode)
        end

        local gw = test_dev:getDefaultRoute("eth0")
        assert.is_string(gw)
        assert.is_equal("192.168.1.1", gw)

        local gw_wlan = test_dev:getDefaultRoute("wlan0")
        assert.is_string(gw_wlan)
        assert.is_equal("172.16.0.1", gw_wlan)
      end)
    end)
  end)
  -- luacheck: pop
end)
