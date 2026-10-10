describe("ReaderConfig module", function()
  local ReaderConfig
  local Configurable
  local CreOptions
  local Device
  local Event
  local KoptOptions
  local UIManager

  setup(function()
    require("commonrequire")
    ReaderConfig = require("apps/reader/modules/readerconfig")
    Configurable = require("configurable")
    CreOptions = require("ui/data/creoptions")
    Device = require("device")
    Event = require("ui/event")
    KoptOptions = require("ui/data/koptoptions")
    UIManager = require("ui/uimanager")
  end)

  local function createMockUI()
    local touch_zones = {}
    local doc_settings_data = {}
    return {
      touch_zones = touch_zones,
      registerTouchZones = function(_self, zones)
        for _, z in ipairs(zones) do
          table.insert(touch_zones, z)
        end
      end,
      doc_settings = {
        save = function(_self, key, val)
          doc_settings_data[key] = val
        end,
        read = function(_self, key)
          return doc_settings_data[key]
        end,
        data = doc_settings_data,
      },
    }
  end

  describe("Initialization & Options Selection", function()
    it("should select CreOptions when document has no koptinterface", function()
      local mock_ui = createMockUI()
      local mock_doc = { koptinterface = nil }
      local rc = ReaderConfig:new({
        ui = mock_ui,
        document = mock_doc,
        configurable = Configurable:new(),
      })

      assert.are.equal(CreOptions, rc.options)
      assert.is_nil(rc.ges_events)
      assert.are.equal(1, rc.last_panel_index)
      assert.is_not_nil(rc.activation_menu)
    end)

    it("should select KoptOptions when document has koptinterface", function()
      local mock_ui = createMockUI()
      local mock_doc = { koptinterface = {} }
      local rc = ReaderConfig:new({
        ui = mock_ui,
        document = mock_doc,
        configurable = Configurable:new(),
      })

      assert.are.equal(KoptOptions, rc.options)
    end)
  end)

  describe("Key Events & Touch Listeners", function()
    it("should register key events when device has keys", function()
      local old_has_keys = Device.hasKeys
      Device.hasKeys = function()
        return true
      end

      local mock_ui = createMockUI()
      local rc = ReaderConfig:new({
        ui = mock_ui,
        document = { koptinterface = nil },
        configurable = Configurable:new(),
      })

      assert.is_table(rc.key_events.ShowConfigMenu)

      Device.hasKeys = old_has_keys
    end)

    it("should register touch zones when device is touch-capable", function()
      local old_is_touch = Device.isTouchDevice
      Device.isTouchDevice = function()
        return true
      end

      local mock_ui = createMockUI()
      local rc = ReaderConfig:new({
        ui = mock_ui,
        document = { koptinterface = nil },
        configurable = Configurable:new(),
      })

      assert.is_true(#mock_ui.touch_zones >= 6)
      local ids = {}
      for _, z in ipairs(mock_ui.touch_zones) do
        ids[z.id] = z
      end
      assert.is_not_nil(ids["readerconfigmenu_tap"])
      assert.is_not_nil(ids["readerconfigmenu_ext_tap"])
      assert.is_not_nil(ids["readerconfigmenu_swipe"])
      assert.is_not_nil(ids["readerconfigmenu_ext_swipe"])
      assert.is_not_nil(ids["readerconfigmenu_pan"])
      assert.is_not_nil(ids["readerconfigmenu_ext_pan"])

      Device.isTouchDevice = old_is_touch
    end)
  end)

  describe("Menu Activation & Gestures", function()
    it("should handle onTapShowConfigMenu based on activation_menu setting", function()
      local mock_ui = createMockUI()
      local rc = ReaderConfig:new({
        ui = mock_ui,
        document = { koptinterface = nil },
        configurable = Configurable:new(),
      })

      local shown = 0
      rc.onShowConfigMenu = function()
        shown = shown + 1
        return true
      end

      rc.activation_menu = "tap"
      assert.is_true(rc:onTapShowConfigMenu())
      assert.are.equal(1, shown)

      rc.activation_menu = "all"
      assert.is_true(rc:onTapShowConfigMenu())
      assert.are.equal(2, shown)

      rc.activation_menu = "swipe"
      assert.is_nil(rc:onTapShowConfigMenu())
      assert.are.equal(2, shown)
    end)

    it("should handle onSwipeShowConfigMenu based on direction and activation setting", function()
      local mock_ui = createMockUI()
      local rc = ReaderConfig:new({
        ui = mock_ui,
        document = { koptinterface = nil },
        configurable = Configurable:new(),
      })

      local shown = 0
      rc.onShowConfigMenu = function()
        shown = shown + 1
        return true
      end

      rc.activation_menu = "swipe"
      assert.is_true(rc:onSwipeShowConfigMenu({ direction = "north" }))
      assert.are.equal(1, shown)

      -- wrong direction
      assert.is_nil(rc:onSwipeShowConfigMenu({ direction = "south" }))
      assert.are.equal(1, shown)

      -- tap only mode
      rc.activation_menu = "tap"
      assert.is_nil(rc:onSwipeShowConfigMenu({ direction = "north" }))
      assert.are.equal(1, shown)
    end)
  end)

  describe("Dialog Lifecycle & Dimension Changes", function()
    it("should handle onSetDimensions by delegating to active dialog", function()
      local mock_ui = createMockUI()
      local rc = ReaderConfig:new({
        ui = mock_ui,
        document = { koptinterface = nil },
        configurable = Configurable:new(),
      })

      local inited = 0
      rc.config_dialog = {
        init = function()
          inited = inited + 1
        end,
      }

      rc:onSetDimensions()
      assert.are.equal(1, inited)

      rc.config_dialog = nil
      assert.has_no_errors(function()
        rc:onSetDimensions()
      end)
    end)

    it("should handle onCloseConfigMenu and _closeCallback cleanly", function()
      local mock_ui = createMockUI()
      local rc = ReaderConfig:new({
        ui = mock_ui,
        document = { koptinterface = nil },
        configurable = Configurable:new(),
      })

      local closed = 0
      local broadcasted = {}
      local old_broadcast = UIManager.broadcastEvent
      UIManager.broadcastEvent = function(_self, ev)
        table.insert(broadcasted, ev.handler or ev.name or ev[1])
      end

      rc.config_dialog = {
        panel_index = 3,
        closeDialog = function()
          closed = closed + 1
        end,
      }

      rc:onCloseConfigMenu()
      assert.are.equal(1, closed)

      rc:_closeCallback()
      assert.are.equal(3, rc.last_panel_index)
      assert.is_nil(rc.config_dialog)
      assert.is_true(broadcasted[#broadcasted] == "onRestoreHinting")

      UIManager.broadcastEvent = old_broadcast
    end)
  end)

  describe("Settings Persistence", function()
    it("should read and clamp panel index on onReadSettings", function()
      local mock_ui = createMockUI()
      local rc = ReaderConfig:new({
        ui = mock_ui,
        document = { koptinterface = nil },
        configurable = Configurable:new(),
      })

      local mock_config = {
        has = function(_self, _key)
          return false
        end,
        read = function(_self, key)
          if key == "config_panel_index" then
            return 999
          end
        end,
        readSetting = function() end,
      }

      rc:onReadSettings(mock_config)
      assert.are.equal(#rc.options, rc.last_panel_index)

      local mock_config_default = {
        has = function(_self, _key)
          return false
        end,
        read = function(_self, key)
          if key == "config_panel_index" then
            return nil
          end
        end,
        readSetting = function() end,
      }
      rc:onReadSettings(mock_config_default)
      assert.are.equal(1, rc.last_panel_index)
    end)

    it("should save panel index on onSaveSettings", function()
      local mock_ui = createMockUI()
      local rc = ReaderConfig:new({
        ui = mock_ui,
        document = { koptinterface = nil },
        configurable = Configurable:new(),
      })

      rc.last_panel_index = 2
      rc:onSaveSettings()
      assert.are.equal(2, mock_ui.doc_settings:read("config_panel_index"))
    end)
  end)
end)
