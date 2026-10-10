describe("AutoDim widget tests", function()
  local Device, PowerD, MockTime, class, AutoDim, UIManager, PluginShare, TrapWidget

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    MockTime = require("mock_time")
    MockTime:install()

    PluginShare = require("pluginshare")
    TrapWidget = require("ui/widget/trapwidget")

    PowerD = require("device/generic/powerd"):new({
      frontlight = 10,
    })
    PowerD.frontlightIntensityHW = function()
      return 10
    end
    PowerD.setIntensityHW = function(self, intensity)
      self.frontlight = intensity
    end
    PowerD.resetT1Timeout = function() end
  end)

  teardown(function()
    MockTime:uninstall()
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))
  end)

  before_each(function()
    Device = require("device")
    stub(Device, "isKindle")
    Device.isKindle.returns(false)
    stub(Device, "hasEinkScreen")
    Device.hasEinkScreen.returns(false)

    Device.powerd = PowerD:new({
      device = Device,
    })
    Device.input.waitEvent = function() end

    G_reader_settings:save("autodim_starttime_minutes", 5)

    UIManager = require("ui/uimanager")
    UIManager:setRunForeverMode()

    UIManager:handleInput()
    UIManager:updateLastUserActionTime()
    UIManager:quit()

    requireBackgroundRunner()
    class = dofile("plugins/autodim.koplugin/main.lua")
    local mock_ui = {
      menu = {
        registerToMainMenu = function() end,
      },
    }
    AutoDim = class:new({ ui = mock_ui })
    notifyBackgroundJobsUpdated()

    MockTime:increase(2)
    UIManager:handleInput()
  end)

  after_each(function()
    if AutoDim and AutoDim.trap_widget then
      UIManager:close(AutoDim.trap_widget)
      AutoDim.trap_widget = nil
    end
    PluginShare.DeviceIdling = false
    AutoDim:onClose()
    MockTime:increase(2)
    UIManager:handleInput()
    AutoDim = nil
    stopBackgroundRunner()
    Device.isKindle:revert()
    Device.hasEinkScreen:revert()
    G_reader_settings:delete("autodim_starttime_minutes")
  end)

  it(
    "should not dim when idle time is less than configuration threshold",
    function()
      Device:getPowerDevice():setIntensity(10)

      MockTime:increase(240)
      UIManager:handleInput()

      assert.are.equal(10, Device:getPowerDevice():frontlightIntensity())
      assert.is_nil(AutoDim.trap_widget)
    end
  )

  it("should start dimming when idle time exceeds threshold", function()
    Device:getPowerDevice():setIntensity(10)

    MockTime:increase(301)
    UIManager:handleInput()

    assert.is_not_nil(AutoDim.trap_widget)

    for i = 1, 9 do
      MockTime:increase(0.15)
      UIManager:handleInput()
    end

    assert.are.equal(1, Device:getPowerDevice():frontlightIntensity())
  end)

  it("should restore frontlight level on resume", function()
    Device:getPowerDevice():setIntensity(10)

    MockTime:increase(301)
    UIManager:handleInput()

    for i = 1, 9 do
      MockTime:increase(0.15)
      UIManager:handleInput()
    end
    assert.are.equal(1, Device:getPowerDevice():frontlightIntensity())
    assert.is_not_nil(AutoDim.trap_widget)

    AutoDim:onResume()

    MockTime:increase(1)
    UIManager:handleInput()

    assert.are.equal(10, Device:getPowerDevice():frontlightIntensity())
    assert.is_nil(AutoDim.trap_widget)
  end)

  it("should handle frontlight turned off manually during dimming", function()
    Device:getPowerDevice():setIntensity(10)

    MockTime:increase(301)
    UIManager:handleInput()
    assert.is_not_nil(AutoDim.trap_widget)

    AutoDim:onFrontlightTurnedOff()

    assert.is_nil(AutoDim.trap_widget)
    assert.is_nil(AutoDim.origin_fl)
  end)

  describe("Main menu and spin dialog configuration", function()
    it("should register menu item with text and checked functions", function()
      local menu_items = {}
      AutoDim:addToMainMenu(menu_items)
      assert.is_table(menu_items.autodim)
      local item = menu_items.autodim

      AutoDim.autodim_starttime_m = 5
      assert.is_true(item.checked_func())
      assert.is_true(item.text_func():find("5") ~= nil)

      AutoDim.autodim_starttime_m = -1
      assert.is_false(item.checked_func())
      assert.is_true(item.text_func():find("disabled") ~= nil)
    end)

    it(
      "should open SpinWidget and update timeout or disable via callbacks",
      function()
        local menu_items = {}
        AutoDim:addToMainMenu(menu_items)
        local item = menu_items.autodim

        local shown_dialog = nil
        local orig_show = UIManager.show
        UIManager.show = function(_, w)
          shown_dialog = w
        end

        local menu_updated = false
        local mock_menu = {
          updateItems = function()
            menu_updated = true
          end,
        }

        item.callback(mock_menu)
        assert.is_table(shown_dialog)
        assert.are.equal("Automatic dimmer idle time", shown_dialog.title_text)

        -- SpinWidget save callback
        shown_dialog.callback({ value = 3.5 })
        assert.are.equal(3.5, AutoDim.autodim_starttime_m)
        assert.is_true(menu_updated)

        -- SpinWidget extra_callback (disable)
        menu_updated = false
        shown_dialog.extra_callback()
        assert.are.equal(-1, AutoDim.autodim_starttime_m)
        assert.is_true(menu_updated)

        UIManager.show = orig_show
      end
    )
  end)

  describe("TrapWidget dismiss callback", function()
    it("should clear idling and restore frontlight upon dismissal", function()
      Device:getPowerDevice():setIntensity(2)
      AutoDim.origin_fl = 10
      PluginShare.DeviceIdling = true
      local dismissed = false
      AutoDim.trap_widget = TrapWidget:new({
        name = "AutoDim",
        dismiss_callback = function()
          AutoDim:_clearIdling()
          AutoDim:_restoreFrontlight()
          AutoDim.trap_widget = nil
          dismissed = true
        end,
      })

      AutoDim.trap_widget.dismiss_callback()
      assert.is_true(dismissed)
      assert.is_nil(AutoDim.trap_widget)
      assert.is_false(PluginShare.DeviceIdling)
      assert.are.equal(10, Device:getPowerDevice():frontlightIntensity())
    end)
  end)

  describe("Executable guards", function()
    it(
      "should return early from _executable when frontlight is already off or diff <= 0",
      function()
        -- Frontlight off
        stub(Device:getPowerDevice(), "isFrontlightOff")
        Device:getPowerDevice().isFrontlightOff.returns(true)
        AutoDim:_executable()
        assert.is_nil(AutoDim.trap_widget)
        Device:getPowerDevice().isFrontlightOff:revert()

        -- Frontlight intensity <= AUTODIM_END_FL (1)
        Device:getPowerDevice():setIntensity(1)
        AutoDim:_executable()
        assert.is_nil(AutoDim.trap_widget)
        assert.is_nil(AutoDim.origin_fl)
      end
    )

    it("should return early from _executable when already dimmed", function()
      AutoDim.trap_widget = TrapWidget:new({ name = "AutoDim" })
      AutoDim:_executable()
      assert.are.equal("AutoDim", AutoDim.trap_widget.name)
      AutoDim.trap_widget = nil
    end)
  end)

  describe("Ramp task and dismissal bugs", function()
    it(
      "should dismiss trap_widget and restore frontlight when _shouldNotDim triggers in _rampTask",
      function()
        Device:getPowerDevice():setIntensity(10)
        AutoDim.origin_fl = 10
        AutoDim.trap_widget = TrapWidget:new({ name = "AutoDim" })
        PluginShare.DeviceIdling = true

        -- Trigger user action so _shouldNotDim returns true
        UIManager:updateLastUserActionTime()
        assert.is_true(AutoDim:_shouldNotDim())

        AutoDim:_rampTask(9, 0.1)

        -- Exposes production bug: bare return in _rampTask leaks trap_widget & frontlight
        assert.is_nil(AutoDim.trap_widget)
        assert.is_false(PluginShare.DeviceIdling)
      end
    )

    it(
      "should clean up trap_widget and restore frontlight on onClose while dimmed",
      function()
        Device:getPowerDevice():setIntensity(3)
        AutoDim.origin_fl = 10
        AutoDim.trap_widget = TrapWidget:new({ name = "AutoDim" })
        PluginShare.DeviceIdling = true

        AutoDim:onClose()

        -- Exposes production bug: onClose leaves trap_widget, DeviceIdling, and dimmed level
        assert.is_nil(AutoDim.trap_widget)
        assert.is_false(PluginShare.DeviceIdling)
        assert.are.equal(10, Device:getPowerDevice():frontlightIntensity())
      end
    )
  end)
end)
