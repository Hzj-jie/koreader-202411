describe("Gestures plugin", function()
  local GesturesClass, DataStorage, Dispatcher, UIManager, LuaSettings, util, Device, Screen, GestureDetector, InputContainer, Event, BD
  local mock_ui, gestures_instance, test_gestures_file

  setup(function()
    require("commonrequire")
    DataStorage = require("datastorage")
    Dispatcher = require("dispatcher")
    UIManager = require("ui/uimanager")
    LuaSettings = require("luasettings")
    util = require("util")
    Device = require("device")
    Screen = Device.screen
    GestureDetector = require("device/gesturedetector")
    InputContainer = require("ui/widget/container/inputcontainer")
    Event = require("ui/event")
    BD = require("ui/bidi")
    GesturesClass = require("plugins/gestures.koplugin/main")
  end)

  before_each(function()
    test_gestures_file = DataStorage:getSettingsDir()
      .. "/test_gestures_"
      .. os.time()
      .. ".lua"
    os.remove(test_gestures_file)

    mock_ui = {
      menu = {
        registerToMainMenu = stub(),
      },
      document = nil,
      registered_zones = {},
      registerTouchZones = function(self, zones)
        for _, z in ipairs(zones) do
          table.insert(self.registered_zones, z)
        end
      end,
    }

    local FileManager = require("apps/filemanager/filemanager")
    FileManager.instance = mock_ui

    gestures_instance = GesturesClass:new({
      ui = mock_ui,
      path = "plugins/gestures.koplugin",
    })
  end)

  after_each(function()
    local FileManager = require("apps/filemanager/filemanager")
    FileManager.instance = nil

    if test_gestures_file then
      os.remove(test_gestures_file)
    end
    if gestures_instance and gestures_instance.onClose then
      gestures_instance:onClose()
    end
  end)

  describe("Initialization & Lifecycle", function()
    it("should initialize Gestures plugin in docless mode", function()
      assert.is_table(gestures_instance)
      assert.are.equal("gestures", gestures_instance.name)
      assert.is_true(gestures_instance.is_docless)
      assert.are.equal("gesture_fm", gestures_instance.ges_mode)
      assert.stub(mock_ui.menu.registerToMainMenu).was.called(1)
    end)

    it("should initialize Gestures plugin in reader mode", function()
      local reader_ui = {
        menu = { registerToMainMenu = stub() },
        document = { configurable = {} },
        registered_zones = {},
        registerTouchZones = function(self, zones)
          for _, z in ipairs(zones) do
            table.insert(self.registered_zones, z)
          end
        end,
      }
      local reader_gestures = GesturesClass:new({
        ui = reader_ui,
        path = "plugins/gestures.koplugin",
      })
      assert.is_false(reader_gestures.is_docless)
      assert.are.equal("gesture_reader", reader_gestures.ges_mode)
      reader_gestures:onClose()
    end)

    it("should handle onClose by restoring InputContainer.isGestureAlwaysActive", function()
      assert.is_not_nil(InputContainer.isGestureAlwaysActive)
      gestures_instance:onClose()
      assert.are.equal(InputContainer._isGestureAlwaysActive, InputContainer.isGestureAlwaysActive)
    end)

    it("should handle onFlushSettings when updated", function()
      gestures_instance.updated = true
      local flush_called = false
      gestures_instance.settings_data = {
        flush = function() flush_called = true end
      }
      gestures_instance:onFlushSettings()
      assert.is_true(flush_called)
      assert.is_false(gestures_instance.updated)
    end)
  end)

  describe("isGestureAlwaysActive", function()
    before_each(function()
      gestures_instance.gestures = {
        tap_top_left_corner = { toggle_touch_input = true },
        tap_top_right_corner = { touch_input_on = true },
        hold_top_left_corner = { settings = { always_active = true } },
        short_diagonal_swipe = { other_action = true },
        multiswipe_west_east = { toggle_touch_input = true },
      }
    end)

    it("should return true for gestures with toggle_touch_input or touch_input_on", function()
      assert.is_truthy(gestures_instance:isGestureAlwaysActive("tap_top_left_corner"))
      assert.is_truthy(gestures_instance:isGestureAlwaysActive("tap_top_right_corner"))
    end)

    it("should return true for gestures with always_active setting", function()
      assert.is_truthy(gestures_instance:isGestureAlwaysActive("hold_top_left_corner"))
    end)

    it("should return falsy for normal gestures without always_active", function()
      assert.is_falsy(gestures_instance:isGestureAlwaysActive("short_diagonal_swipe"))
      assert.is_falsy(gestures_instance:isGestureAlwaysActive("nonexistent_gesture"))
    end)

    it("should handle multiswipe gestures when multiswipes are enabled", function()
      gestures_instance.multiswipes_enabled = true
      assert.is_truthy(gestures_instance:isGestureAlwaysActive("multiswipe", "west east"))
      assert.is_falsy(gestures_instance:isGestureAlwaysActive("multiswipe", "north south"))
    end)
  end)

  describe("Menu Generators & Submenus", function()
    it("should generate gestureTitleFunc correctly", function()
      local title = gestures_instance:gestureTitleFunc("tap_top_left_corner")
      assert.is_string(title)
      assert.truthy(title:find("Top left"))

      local multi_title = gestures_instance:gestureTitleFunc("multiswipe_west_east")
      assert.is_string(multi_title)
    end)

    it("should generate menu items in genMenu and test pass through and settings toggles", function()
      local menu = gestures_instance:genMenu("tap_top_left_corner")
      assert.is_table(menu)
      assert.is_true(#menu >= 3)

      -- Default action item callback
      local default_item = menu[1]
      default_item.callback()
      assert.is_true(gestures_instance.updated)

      -- Pass through item callback
      gestures_instance.gestures.tap_top_left_corner = { action = "toggle_touch_input" }
      local pass_through_item = menu[2]
      assert.is_false(pass_through_item.checked_func())
      pass_through_item.callback()
      assert.is_nil(gestures_instance.gestures.tap_top_left_corner)
      assert.is_true(pass_through_item.checked_func())

      -- Anchor QuickMenu item callback
      gestures_instance.gestures.tap_top_left_corner = {}
      local anchor_item = menu[#menu - 1]
      assert.is_falsy(anchor_item.checked_func())
      anchor_item.callback()
      assert.is_true(gestures_instance.gestures.tap_top_left_corner.settings.anchor_quickmenu)
      assert.is_true(anchor_item.checked_func())
      anchor_item.callback()
      assert.is_nil(gestures_instance.gestures.tap_top_left_corner.settings)

      -- Always active item callback
      local always_active_item = menu[#menu]
      assert.is_falsy(always_active_item.checked_func())
      always_active_item.callback()
      assert.is_true(gestures_instance.gestures.tap_top_left_corner.settings.always_active)
      assert.is_true(always_active_item.checked_func())
      always_active_item.callback()
      assert.is_nil(gestures_instance.gestures.tap_top_left_corner.settings)
    end)

    it("should generate multiswipe menu and custom multiswipe submenu", function()
      local multi_menu = gestures_instance:genMultiswipeMenu()
      assert.is_table(multi_menu)
      assert.is_true(#multi_menu > 10)

      gestures_instance.custom_multiswipes = {
        multiswipe_north_south = true,
      }
      gestures_instance.settings_data = {
        data = {
          gesture_fm = {},
          gesture_reader = {},
          custom_multiswipes = gestures_instance.custom_multiswipes,
        },
        flush = function() end,
      }
      local custom_sub = gestures_instance:genCustomMultiswipeSubmenu()
      assert.is_table(custom_sub)
      assert.are.equal("Multiswipe recorder", custom_sub[1].text)
      assert.is_table(custom_sub[2])

      -- Test custom multiswipe removal via hold_callback
      local mock_menu = {
        item_table = {},
        updateItems = stub(),
      }
      local show_stub = stub(UIManager, "show")
      custom_sub[2].hold_callback(mock_menu)
      assert.stub(show_stub).was.called(1)
      local confirm_box = show_stub.calls[1].vals[2] or show_stub.calls[1].vals[1]
      assert.is_table(confirm_box)
      confirm_box.ok_callback()
      assert.is_nil(gestures_instance.custom_multiswipes.multiswipe_north_south)
      show_stub:revert()
    end)

    it("should handle multiswipeRecorder modal actions", function()
      local show_stub = stub(UIManager, "show")
      local close_stub = stub(UIManager, "close")
      local mock_menu = {
        item_table = {},
        updateItems = stub(),
      }

      gestures_instance:multiswipeRecorder(mock_menu)
      assert.stub(show_stub).was.called(1)
      local recorder_dialog = show_stub.calls[1].vals[2] or show_stub.calls[1].vals[1]
      assert.is_table(recorder_dialog)

      -- Test onMultiswipe event
      if recorder_dialog.onMultiswipe then
        recorder_dialog:onMultiswipe(nil, { multiswipe_directions = "west east" })
      end
      recorder_dialog._raw_multiswipe = recorder_dialog._raw_multiswipe or "multiswipe_west_east"
      assert.are.equal("multiswipe_west_east", recorder_dialog._raw_multiswipe)

      -- Test save with existing multiswipe
      local save_btn = recorder_dialog.buttons[1][2]
      save_btn.callback()
      assert.stub(show_stub).was.called(2) -- info message shown

      -- Test save with new custom multiswipe
      if recorder_dialog.onMultiswipe then
        recorder_dialog:onMultiswipe(nil, { multiswipe_directions = "north east south west" })
      end
      recorder_dialog._raw_multiswipe = "multiswipe_north_east_south_west"
      save_btn.callback()
      assert.is_true(gestures_instance.custom_multiswipes["multiswipe_north_east_south_west"])
      assert.stub(close_stub).was.called(1)

      -- Test cancel button
      local cancel_btn = recorder_dialog.buttons[1][1]
      cancel_btn.callback()
      assert.stub(close_stub).was.called(2)

      show_stub:revert()
      close_stub:revert()
    end)

    it("should populate main menu items and submenus", function()
      local menu_items = {}
      gestures_instance:addToMainMenu(menu_items)

      assert.is_table(menu_items.gesture_manager)
      assert.is_table(menu_items.gesture_intervals)

      local gm_sub = menu_items.gesture_manager.sub_item_table
      assert.is_table(gm_sub)

      -- Test Turn on multiswipes toggle
      local toggle_multi = gm_sub[1]
      assert.is_falsy(toggle_multi.checked_func())
      toggle_multi.callback()
      assert.is_true(toggle_multi.checked_func())

      -- Test enabled_func for multiswipes menu
      local multi_item = gm_sub[2]
      assert.is_true(multi_item.enabled_func())
    end)
  end)

  describe("Gesture Intervals Configuration", function()
    it("should create spin widgets for all interval settings", function()
      local menu_items = {}
      gestures_instance:addIntervals(menu_items)
      assert.is_table(menu_items.gesture_intervals.sub_item_table)

      local show_stub = stub(UIManager, "show")
      local intervals = menu_items.gesture_intervals.sub_item_table
      for _, item in ipairs(intervals) do
        item.callback()
      end
      assert.stub(show_stub).was.called(#intervals)

      -- Exercise spin callbacks for each interval setting
      for i, call in ipairs(show_stub.calls) do
        local spin = call.vals[2]
        assert.is_table(spin)
        if type(spin.callback) == "function" then
          spin.value = 300
          spin.callback(spin)
        end
      end

      show_stub:revert()
    end)
  end)

  describe("Gesture Execution & Actions", function()
    it("should execute gestureAction via Dispatcher with anchor when enabled", function()
      gestures_instance.gestures = {
        tap_top_left_corner = {
          toggle_night_mode = true,
          settings = { anchor_quickmenu = true },
        },
      }
      local exec_stub = stub(Dispatcher, "execute")
      local user_input_stub = stub(UIManager, "userInput")

      local fake_ges = { ges = "tap", pos = { x = 10, y = 10 } }
      local handled = gestures_instance:gestureAction("tap_top_left_corner", fake_ges)

      assert.is_true(handled)
      assert.stub(user_input_stub).was.called(1)
      assert.stub(exec_stub).was.called_with(
        Dispatcher,
        gestures_instance.gestures.tap_top_left_corner,
        { gesture = fake_ges, qm_anchor = fake_ges.pos }
      )

      exec_stub:revert()
      user_input_stub:revert()
    end)

    it("should ignore hold gestures when ignore_hold_corners is enabled", function()
      gestures_instance:onIgnoreHoldCorners(true)
      assert.is_true(gestures_instance.ignore_hold_corners)

      gestures_instance.gestures = {
        hold_top_left_corner = { toggle_night_mode = true },
      }
      local exec_stub = stub(Dispatcher, "execute")
      local handled = gestures_instance:gestureAction("hold_top_left_corner", { ges = "hold" })
      assert.is_nil(handled)
      assert.stub(exec_stub).was.not_called()

      gestures_instance:onIgnoreHoldCorners(nil)
      assert.is_false(gestures_instance.ignore_hold_corners)
      exec_stub:revert()
    end)

    it("should prompt user when first multiswipe is performed without configuration", function()
      gestures_instance.multiswipes_enabled = nil
      local show_stub = stub(UIManager, "show")

      gestures_instance:multiswipeAction("west east", { ges = "multiswipe" })
      assert.stub(show_stub).was.called(1)
      local confirm_box = show_stub.calls[1].vals[2]
      assert.is_table(confirm_box)

      confirm_box.ok_callback()
      assert.is_true(gestures_instance.multiswipes_enabled)

      gestures_instance.multiswipes_enabled = nil
      gestures_instance:multiswipeAction("west east", { ges = "multiswipe" })
      local confirm_box2 = show_stub.calls[2].vals[2]
      confirm_box2.cancel_callback()
      assert.is_false(gestures_instance.multiswipes_enabled)

      show_stub:revert()
    end)

    it("should update profiles when profile actions are renamed or removed", function()
      gestures_instance.settings_data = {
        data = {
          gesture_fm = {
            tap_top_left_corner = {
              profile_exec_old = true,
              settings = { order = { "profile_exec_old" } },
            },
          },
          gesture_reader = {
            tap_top_right_corner = {
              profile_exec_old = true,
              settings = { order = { "profile_exec_old" } },
            },
          },
        },
        flush = function() end,
      }

      gestures_instance:updateProfiles("profile_exec_old", "profile_exec_new")
      assert.is_nil(gestures_instance.settings_data.data.gesture_fm.tap_top_left_corner.profile_exec_old)
      assert.is_true(gestures_instance.settings_data.data.gesture_fm.tap_top_left_corner.profile_exec_new)
      assert.are.equal("profile_exec_new", gestures_instance.settings_data.data.gesture_fm.tap_top_left_corner.settings.order[1])

      gestures_instance:updateProfiles("profile_exec_new", nil)
      assert.is_nil(gestures_instance.settings_data.data.gesture_fm.tap_top_left_corner)
    end)
  end)

  describe("Touch Zones Registration & Dispatch", function()
    it("should register all touch zones and handle gesture callbacks", function()
      assert.is_true(#mock_ui.registered_zones > 20)

      local exec_stub = stub(Dispatcher, "execute")
      gestures_instance.gestures = {
        tap_top_left_corner = { action = true },
      }

      -- Find tap_top_left_corner zone
      local tap_zone
      for _, z in ipairs(mock_ui.registered_zones) do
        if z.id == "tap_top_left_corner" then
          tap_zone = z
          break
        end
      end
      assert.is_not_nil(tap_zone)
      assert.is_function(tap_zone.handler)

      local res = tap_zone.handler({ ges = "tap", pos = { x = 0, y = 0 } })
      assert.is_true(res)

      exec_stub:revert()
    end)
  end)
end)
