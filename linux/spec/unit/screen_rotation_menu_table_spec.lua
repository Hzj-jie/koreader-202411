describe("ScreenRotationMenuTable", function()
  local ScreenRotationMenuTable
  local Device, UIManager, FileManager, Screen
  local orig_hasGSensor, orig_getRotationMode, orig_filemanager_instance

  setup(function()
    require("commonrequire")
    ScreenRotationMenuTable = require("ui/elements/screen_rotation_menu_table")
    Device = require("device")
    UIManager = require("ui/uimanager")
    FileManager = require("apps/filemanager/filemanager")
    Screen = Device.screen
    orig_hasGSensor = Device.hasGSensor
    orig_getRotationMode = Screen.getRotationMode
    orig_filemanager_instance = FileManager.instance
  end)

  teardown(function()
    Device.hasGSensor = orig_hasGSensor
    Screen.getRotationMode = orig_getRotationMode
    FileManager.instance = orig_filemanager_instance
  end)

  before_each(function()
    G_reader_settings:delete("fm_rotation_mode")
    G_reader_settings:delete("input_ignore_gsensor")
    G_reader_settings:delete("input_lock_gsensor")
    G_reader_settings:delete("lock_rotation")
    G_reader_settings:delete("imageviewer_rotation_portrait_invert")
    G_reader_settings:delete("imageviewer_rotation_landscape_invert")
    G_reader_settings:delete("imageviewer_rotate_auto_for_best_fit")
  end)

  it("should have title text and sub_item_table_func", function()
    assert.is_table(ScreenRotationMenuTable)
    assert.are.equal("Rotation", ScreenRotationMenuTable.text)
    assert.is_function(ScreenRotationMenuTable.sub_item_table_func)
  end)

  describe("when Device has GSensor", function()
    before_each(function()
      Device.hasGSensor = function()
        return true
      end
      FileManager.instance = nil
    end)

    it("includes accelerometer options in sub_item_table", function()
      local items = ScreenRotationMenuTable.sub_item_table_func()
      assert.are.equal("Ignore accelerometer rotation events", items[1].text)
      assert.is_not_nil(items[1].help_text)
      assert.are.equal(
        "Lock auto rotation to current orientation",
        items[2].text
      )
      assert.is_not_nil(items[2].help_text)
    end)

    it("correctly handles 'Ignore accelerometer rotation events'", function()
      local items = ScreenRotationMenuTable.sub_item_table_func()
      local item = items[1]

      assert.is_false(item.checked_func())
      G_reader_settings:save("input_ignore_gsensor", true)
      assert.is_true(item.checked_func())

      local spy_broadcast = spy.on(UIManager, "broadcastEvent")
      item.callback()
      assert.spy(spy_broadcast).was_called(1)
      local event_arg = spy_broadcast.calls[1].vals[2]
      assert.are.equal("onToggleGSensor", event_arg.handler)
      UIManager.broadcastEvent:revert()
    end)

    it(
      "correctly handles 'Lock auto rotation to current orientation'",
      function()
        local items = ScreenRotationMenuTable.sub_item_table_func()
        local item = items[2]

        assert.is_true(item.enabled_func())
        G_reader_settings:save("input_ignore_gsensor", true)
        assert.is_false(item.enabled_func())

        assert.is_false(item.checked_func())
        G_reader_settings:save("input_lock_gsensor", true)
        assert.is_true(item.checked_func())

        local spy_broadcast = spy.on(UIManager, "broadcastEvent")
        item.callback()
        assert.spy(spy_broadcast).was_called(1)
        local event_arg = spy_broadcast.calls[1].vals[2]
        assert.are.equal("onLockGSensor", event_arg.handler)
        UIManager.broadcastEvent:revert()
      end
    )
  end)

  describe("when Device has no GSensor", function()
    before_each(function()
      Device.hasGSensor = function()
        return false
      end
      FileManager.instance = nil
    end)

    it("does not include accelerometer options", function()
      local items = ScreenRotationMenuTable.sub_item_table_func()
      assert.are.equal("Keep current rotation across views", items[1].text)
    end)
  end)

  describe("Keep current rotation across views item", function()
    it("toggles lock_rotation setting when callback is executed", function()
      Device.hasGSensor = function()
        return false
      end
      FileManager.instance = nil
      local items = ScreenRotationMenuTable.sub_item_table_func()
      local item = items[1]

      assert.are.equal("Keep current rotation across views", item.text)
      assert.is_true(item.separator)
      assert.is_false(item.checked_func())

      item.callback()
      assert.is_true(G_reader_settings:isTrue("lock_rotation"))
      assert.is_true(item.checked_func())

      item.callback()
      assert.is_false(G_reader_settings:isTrue("lock_rotation"))
      assert.is_false(item.checked_func())
    end)
  end)

  describe(
    "Rotation mode options when FileManager.instance is present",
    function()
      before_each(function()
        Device.hasGSensor = function()
          return false
        end
        FileManager.instance = {}
      end)

      it("generates items for rotation modes", function()
        local optionsutil = require("ui/data/optionsutil")
        local items = ScreenRotationMenuTable.sub_item_table_func()

        local num_modes = #optionsutil.rotation_modes
        local mode_item_1 = items[2]
        assert.is_table(mode_item_1)
        assert.is_true(mode_item_1.radio)
        assert.is_function(mode_item_1.text_func)
        assert.is_function(mode_item_1.checked_func)
        assert.is_function(mode_item_1.callback)
        assert.is_function(mode_item_1.hold_callback)

        local last_mode_item = items[1 + num_modes]
        assert.is_true(last_mode_item.separator)
      end)

      it("formats text_func correctly with and without star", function()
        local items = ScreenRotationMenuTable.sub_item_table_func()
        local mode_item_1 = items[2]
        local mode = require("ui/data/optionsutil").rotation_modes[1]

        G_reader_settings:delete("fm_rotation_mode")
        assert.is_nil(string.find(mode_item_1.text_func(), "★"))

        G_reader_settings:save("fm_rotation_mode", mode)
        assert.is_not_nil(string.find(mode_item_1.text_func(), "★"))
      end)

      it("checked_func checks current rotation mode from Screen", function()
        local items = ScreenRotationMenuTable.sub_item_table_func()
        local mode_item_1 = items[2]
        local mode = require("ui/data/optionsutil").rotation_modes[1]

        Screen.getRotationMode = function()
          return mode
        end
        assert.is_true(mode_item_1.checked_func())

        Screen.getRotationMode = function()
          return mode + 1
        end
        assert.is_false(mode_item_1.checked_func())
      end)

      it("callback broadcasts SetRotationMode event and closes menu", function()
        local items = ScreenRotationMenuTable.sub_item_table_func()
        local mode_item_1 = items[2]
        local mode = require("ui/data/optionsutil").rotation_modes[1]

        local mock_menu = {
          close_called = false,
          closeMenu = function(self)
            self.close_called = true
          end,
        }

        local spy_broadcast = spy.on(UIManager, "broadcastEvent")
        mode_item_1.callback(mock_menu)

        assert.spy(spy_broadcast).was_called(1)
        local event_arg = spy_broadcast.calls[1].vals[2]
        assert.are.equal("onSetRotationMode", event_arg.handler)
        assert.are.equal(mode, event_arg.args[1])
        assert.is_true(mock_menu.close_called)

        UIManager.broadcastEvent:revert()
      end)

      it("hold_callback saves fm_rotation_mode and updates menu", function()
        local items = ScreenRotationMenuTable.sub_item_table_func()
        local mode_item_1 = items[2]
        local mode = require("ui/data/optionsutil").rotation_modes[1]

        local mock_menu = {
          update_called = false,
          updateItems = function(self)
            self.update_called = true
          end,
        }

        mode_item_1.hold_callback(mock_menu)
        assert.are.equal(mode, G_reader_settings:read("fm_rotation_mode"))
        assert.is_true(mock_menu.update_called)
      end)
    end
  )

  describe("Image viewer rotation sub-items", function()
    before_each(function()
      Device.hasGSensor = function()
        return false
      end
      FileManager.instance = nil
    end)

    it("includes image viewer rotation sub-table and options", function()
      local items = ScreenRotationMenuTable.sub_item_table_func()
      local img_item = items[#items]
      assert.are.equal("Image viewer rotation", img_item.text)
      assert.is_table(img_item.sub_item_table)
      assert.are.equal(3, #img_item.sub_item_table)

      local sub1 = img_item.sub_item_table[1]
      local sub2 = img_item.sub_item_table[2]
      local sub3 = img_item.sub_item_table[3]

      assert.are.equal("Invert default rotation in portrait mode", sub1.text)
      assert.are.equal("Invert default rotation in landscape mode", sub2.text)
      assert.is_true(sub2.separator)
      assert.are.equal("Auto-rotate for best fit", sub3.text)
      assert.is_not_nil(sub3.help_text)
    end)

    it("toggles imageviewer_rotation_portrait_invert", function()
      local items = ScreenRotationMenuTable.sub_item_table_func()
      local sub1 = items[#items].sub_item_table[1]

      assert.is_false(sub1.checked_func())
      sub1.callback()
      assert.is_true(
        G_reader_settings:isTrue("imageviewer_rotation_portrait_invert")
      )
      assert.is_true(sub1.checked_func())
    end)

    it("toggles imageviewer_rotation_landscape_invert", function()
      local items = ScreenRotationMenuTable.sub_item_table_func()
      local sub2 = items[#items].sub_item_table[2]

      assert.is_false(sub2.checked_func())
      sub2.callback()
      assert.is_true(
        G_reader_settings:isTrue("imageviewer_rotation_landscape_invert")
      )
      assert.is_true(sub2.checked_func())
    end)

    it("toggles imageviewer_rotate_auto_for_best_fit", function()
      local items = ScreenRotationMenuTable.sub_item_table_func()
      local sub3 = items[#items].sub_item_table[3]

      assert.is_false(sub3.checked_func())
      sub3.callback()
      assert.is_true(
        G_reader_settings:isTrue("imageviewer_rotate_auto_for_best_fit")
      )
      assert.is_true(sub3.checked_func())
    end)
  end)
end)
