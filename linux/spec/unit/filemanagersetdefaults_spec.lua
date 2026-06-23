describe("filemanagersetdefaults", function()
  local SetDefaults
  local mock_ffiutil
  local mock_device
  local mock_confirm_box
  local mock_info_message
  local mock_input_dialog
  local mock_multi_input_dialog
  local mock_menu
  local mock_util

  setup(function()
    require("commonrequire")
  end)

  before_each(function()
    _G.G_defaults = {
      ro_data = {
        BOOL_KEY = true,
        NUM_KEY = 42,
        STR_KEY = "hello",
        TBL_KEY = { a = 1, b = "two" },
      },
      rw_data = {},
      getDataTables = function(self)
        return self.ro_data, self.rw_data
      end,
      save = spy.new(function(self, k, v)
        self.rw_data[k] = v
      end),
      flush = spy.new(function(self) end),
    }

    mock_ffiutil = {
      orderedPairs = function(t)
        local keys = {}
        for k in pairs(t) do
          table.insert(keys, k)
        end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        local i = 0
        return function()
          i = i + 1
          if keys[i] then
            return keys[i], t[keys[i]]
          end
        end
      end
    }
    package.loaded["ffi/util"] = mock_ffiutil

    mock_device = {
      screen = {
        getSize = function() return { w = 800, h = 600 } end,
        getWidth = function() return 800 end,
        getHeight = function() return 600 end,
        scaleBySize = function(self, val) return val end,
      },
      canRestart = function() return true end,
    }
    package.loaded["device"] = mock_device

    package.loaded["ui/size"] = {
      margin = {
        fullscreen_popout = 10,
      }
    }

    local mock_center_container = {
      extend = function(self, subclass)
        subclass = subclass or {}
        setmetatable(subclass, { __index = self })
        subclass.new = function(cls, ...)
          local inst = setmetatable({}, { __index = cls })
          if inst.init then inst:init(...) end
          return inst
        end
        return subclass
      end,
      showWidget = function(self, widget, ...)
        require("ui/uimanager"):show(widget, ...)
      end,
    }
    package.loaded["ui/widget/container/centercontainer"] = mock_center_container

    mock_menu = {
      new = spy.new(function(self, args)
        local obj = {
          is_menu = true,
          width = args.width,
          height = args.height,
          item_table = args.item_table,
          title = args.title,
          switchItemTable = spy.new(function() end),
        }
        return obj
      end)
    }
    package.loaded["ui/widget/menu"] = mock_menu

    mock_confirm_box = {
      new = spy.new(function(self, args)
        return {
          is_confirm_box = true,
          text = args.text,
          ok_text = args.ok_text,
          ok_callback = args.ok_callback,
          cancel_text = args.cancel_text,
          cancel_callback = args.cancel_callback,
          dismissable = args.dismissable,
        }
      end)
    }
    package.loaded["ui/widget/confirmbox"] = mock_confirm_box

    mock_info_message = {
      new = spy.new(function(self, args)
        return {
          is_info_message = true,
          text = args.text,
        }
      end)
    }
    package.loaded["ui/widget/infomessage"] = mock_info_message

    mock_input_dialog = {
      new = spy.new(function(self, args)
        local obj
        obj = {
          is_input_dialog = true,
          title = args.title,
          input = args.input,
          buttons = args.buttons,
          input_type = args.input_type,
          width = args.width,
          getInputValue = function() return obj.mock_input_value or args.input end,
        }
        return obj
      end)
    }
    package.loaded["ui/widget/inputdialog"] = mock_input_dialog

    mock_multi_input_dialog = {
      new = spy.new(function(self, args)
        local obj
        obj = {
          is_multi_input_dialog = true,
          title = args.title,
          fields = args.fields,
          buttons = args.buttons,
          width = args.width,
          getFields = function() return obj.mock_fields or {} end,
        }
        return obj
      end)
    }
    package.loaded["ui/widget/multiinputdialog"] = mock_multi_input_dialog

    local last_shown_widget
    local last_closed_widget
    package.loaded["ui/uimanager"] = {
      broadcastEvent = spy.new(function() end),
      show = spy.new(function(self, widget)
        last_shown_widget = widget
      end),
      close = spy.new(function(self, widget)
        last_closed_widget = widget
      end),
      restartKOReader = spy.new(function() end),
      quit = spy.new(function() end),
      getLastShownWidget = function() return last_shown_widget end,
      getLastClosedWidget = function() return last_closed_widget end,
    }

    package.loaded["gettext"] = function(text)
      return text
    end

    package.loaded["logger"] = {
      warn = spy.new(function() end),
      info = spy.new(function() end),
      dbg = spy.new(function() end),
    }

    mock_util = {
      tableEquals = function(t1, t2)
        if type(t1) ~= type(t2) then return false end
        if type(t1) ~= "table" then return t1 == t2 end
        for k, v in pairs(t1) do
          if not mock_util.tableEquals(v, t2[k]) then return false end
        end
        for k, v in pairs(t2) do
          if not mock_util.tableEquals(v, t1[k]) then return false end
        end
        return true
      end
    }
    package.loaded["util"] = mock_util

    package.loaded["apps/filemanager/filemanagersetdefaults"] = nil
    SetDefaults = require("apps/filemanager/filemanagersetdefaults")
  end)

  after_each(function()
    package.loaded["apps/filemanager/filemanagersetdefaults"] = nil
    package.loaded["ffi/util"] = nil
    package.loaded["device"] = nil
    package.loaded["ui/size"] = nil
    package.loaded["ui/widget/container/centercontainer"] = nil
    package.loaded["ui/widget/menu"] = nil
    package.loaded["ui/widget/confirmbox"] = nil
    package.loaded["ui/widget/infomessage"] = nil
    package.loaded["ui/widget/inputdialog"] = nil
    package.loaded["ui/widget/multiinputdialog"] = nil
    package.loaded["ui/uimanager"] = nil
    package.loaded["gettext"] = nil
    package.loaded["logger"] = nil
    package.loaded["util"] = nil
    _G.G_defaults = nil
  end)

  describe("ConfirmEdit", function()
    it("should show confirm box on first edit, then show SetDefaultsWidget", function()
      local UIManager = require("ui/uimanager")
      UIManager.show:clear()

      SetDefaults.EditConfirmed = nil -- Reset state

      SetDefaults:ConfirmEdit()

      assert.spy(UIManager.show).was.called(1)
      local confirmbox = UIManager.getLastShownWidget()
      assert.is_true(confirmbox.is_confirm_box)
      assert.truthy(confirmbox.text:find("Are you sure you want to continue?"))

      -- Trigger OK
      UIManager.show:clear()
      confirmbox.ok_callback()

      assert.is_true(SetDefaults.EditConfirmed)
      assert.spy(UIManager.show).was.called(1)
      local widget = UIManager.getLastShownWidget()
      assert.truthy(widget.defaults_menu) -- Widget initialized and created menu

      -- Second time should show directly
      UIManager.show:clear()
      SetDefaults:ConfirmEdit()
      assert.spy(UIManager.show).was.called(1)
      local widget2 = UIManager.getLastShownWidget()
      assert.truthy(widget2.defaults_menu)
    end)
  end)

  describe("SetDefaultsWidget", function()
    local widget

    before_each(function()
      -- Bypass ConfirmEdit and create widget directly for other tests
      local UIManager = require("ui/uimanager")
      SetDefaults.EditConfirmed = true
      SetDefaults:ConfirmEdit()
      widget = UIManager.getLastShownWidget()
    end)

    it("should initialize with correct state and menu entries", function()
      assert.truthy(widget.state)
      assert.truthy(widget.menu_entries)
      assert.truthy(widget.defaults_menu)

      -- Check state loaded from G_defaults (sorted keys: BOOL_KEY, NETWORK_PROXY, NUM_KEY, STARDICT_DATA_DIR, STR_KEY, TBL_KEY)
      -- Wait, we have nil_defaults: NETWORK_PROXY, STARDICT_DATA_DIR
      assert.are.equal(true, widget.state.BOOL_KEY.value)
      assert.is_nil(widget.state.NETWORK_PROXY.value)
      assert.are.equal(42, widget.state.NUM_KEY.value)
      assert.is_nil(widget.state.STARDICT_DATA_DIR.value)
      assert.are.equal("hello", widget.state.STR_KEY.value)
      assert.are.same({ a = 1, b = "two" }, widget.state.TBL_KEY.value)

      -- Check menu entries count (6 entries)
      assert.are.equal(6, #widget.menu_entries)

      -- Check gen_menu_entry formatting
      assert.are.equal("BOOL_KEY = true", widget.menu_entries[widget.state.BOOL_KEY.idx].text)
      assert.are.equal("NUM_KEY = 42", widget.menu_entries[widget.state.NUM_KEY.idx].text)
      assert.are.equal("STR_KEY = \"hello\"", widget.menu_entries[widget.state.STR_KEY.idx].text)
      assert.are.equal("TBL_KEY = {...}", widget.menu_entries[widget.state.TBL_KEY.idx].text)
      assert.are.equal("NETWORK_PROXY = nil", widget.menu_entries[widget.state.NETWORK_PROXY.idx].text)
    end)

    it("should handle unknown keys in rw_defaults with a warning", function()
      local logger = require("logger")
      logger.warn:clear()

      _G.G_defaults.rw_data = {
        UNKNOWN_KEY = "custom_val",
      }

      -- Re-create widget to trigger init with new rw_data
      local UIManager = require("ui/uimanager")
      SetDefaults:ConfirmEdit()
      local new_widget = UIManager.getLastShownWidget()

      assert.spy(logger.warn).was.called(1)
      assert.is_nil(new_widget.state.UNKNOWN_KEY)
    end)

    it("should handle known custom keys correctly", function()
      _G.G_defaults.rw_data = {
        NUM_KEY = 100,
      }

      local UIManager = require("ui/uimanager")
      SetDefaults:ConfirmEdit()
      local new_widget = UIManager.getLastShownWidget()

      assert.are.equal(100, new_widget.state.NUM_KEY.value)
      assert.is_true(new_widget.state.NUM_KEY.custom)
      -- Menu entry for customized key should be bold (depending on implementation, bold = custom is set during init)
      assert.is_true(new_widget.menu_entries[new_widget.state.NUM_KEY.idx].bold)
    end)

    describe("Editing boolean values", function()
      it("should show InputDialog and update value to true/false/default", function()
        local UIManager = require("ui/uimanager")
        local idx = widget.state.BOOL_KEY.idx
        local entry = widget.menu_entries[idx]

        -- Trigger callback (editBoolean)
        UIManager.show:clear()
        entry.callback()

        assert.spy(UIManager.show).was.called(1)
        local dialog = UIManager.getLastShownWidget()
        assert.is_true(dialog.is_input_dialog)
        assert.are.equal("BOOL_KEY", dialog.title)
        assert.are.equal("true", dialog.input)

        -- Buttons: Cancel, Default, true, false
        -- Let's check buttons structure
        -- dialog.buttons = { { cancel_button, default_button, true_button, false_button } }
        local buttons = dialog.buttons[1]
        assert.are.equal("Cancel", buttons[1].text)
        assert.are.equal("Default", buttons[2].text)
        assert.are.equal("true", buttons[3].text)
        assert.are.equal("false", buttons[4].text)

        -- Default button should be disabled initially because value is default
        assert.is_false(buttons[2].enabled)

        -- Click "false"
        UIManager.close:clear()
        widget.defaults_menu.switchItemTable:clear()
        buttons[4].callback()

        assert.spy(UIManager.close).was.called(1)
        assert.are.equal(dialog, UIManager.getLastClosedWidget())
        assert.are.equal(false, widget.state.BOOL_KEY.value)
        assert.is_true(widget.state.BOOL_KEY.dirty)
        assert.is_true(widget.settings_changed)
        assert.are.equal("BOOL_KEY = false", widget.menu_entries[idx].text)
        assert.is_true(widget.menu_entries[idx].bold)
        assert.spy(widget.defaults_menu.switchItemTable).was.called(1)

        -- Edit again to test "Default" button
        UIManager.show:clear()
        entry.callback()
        dialog = UIManager.getLastShownWidget()
        buttons = dialog.buttons[1]

        -- Default button should now be enabled
        assert.is_true(buttons[2].enabled)

        -- Click "Default"
        UIManager.close:clear()
        buttons[2].callback()
        assert.spy(UIManager.close).was.called(1)
        assert.are.equal(true, widget.state.BOOL_KEY.value)
        assert.is_false(widget.menu_entries[idx].bold)
      end)
    end)

    describe("Editing table values", function()
      it("should show MultiInputDialog and update table value", function()
        local UIManager = require("ui/uimanager")
        local idx = widget.state.TBL_KEY.idx
        local entry = widget.menu_entries[idx]

        UIManager.show:clear()
        entry.callback()

        assert.spy(UIManager.show).was.called(1)
        local dialog = UIManager.getLastShownWidget()
        assert.is_true(dialog.is_multi_input_dialog)
        assert.are.equal("TBL_KEY", dialog.title)

        -- Fields should be populated (sorted keys: a, b)
        assert.are.equal(2, #dialog.fields)
        assert.are.equal("a = 1", dialog.fields[1].text)
        assert.are.equal("b = two", dialog.fields[2].text)

        local buttons = dialog.buttons[1]
        assert.are.equal("Cancel", buttons[1].text)
        assert.are.equal("Default", buttons[2].text)
        assert.are.equal("OK", buttons[3].text)

        -- Default should be disabled
        assert.is_false(buttons[2].enabled)

        -- Mock new values from fields
        dialog.getFields = function()
          return { "a=2", "b=three" }
        end

        -- Click "OK"
        UIManager.close:clear()
        widget.defaults_menu.switchItemTable:clear()
        buttons[3].callback()

        assert.spy(UIManager.close).was.called(1)
        assert.are.same({ a = 2, b = "three" }, widget.state.TBL_KEY.value)
        assert.is_true(widget.state.TBL_KEY.dirty)
        assert.is_true(widget.menu_entries[idx].bold)
        assert.spy(widget.defaults_menu.switchItemTable).was.called(1)
      end)
    end)

    describe("Editing other values (string/number)", function()
      it("should show InputDialog and update string value", function()
        local UIManager = require("ui/uimanager")
        local idx = widget.state.STR_KEY.idx
        local entry = widget.menu_entries[idx]

        UIManager.show:clear()
        entry.callback()

        assert.spy(UIManager.show).was.called(1)
        local dialog = UIManager.getLastShownWidget()
        assert.is_true(dialog.is_input_dialog)

        local buttons = dialog.buttons[1]
        assert.are.equal("OK", buttons[3].text)

        -- Mock new input value
        dialog.mock_input_value = "world"

        -- Click OK
        UIManager.close:clear()
        buttons[3].callback()

        assert.spy(UIManager.close).was.called(1)
        assert.are.equal("world", widget.state.STR_KEY.value)
        assert.is_true(widget.state.STR_KEY.dirty)
        assert.are.equal("STR_KEY = \"world\"", widget.menu_entries[idx].text)
        assert.is_true(widget.menu_entries[idx].bold)
      end)

      it("should handle nil values correctly", function()
        local UIManager = require("ui/uimanager")
        local idx = widget.state.NETWORK_PROXY.idx
        local entry = widget.menu_entries[idx]

        UIManager.show:clear()
        entry.callback()

        local dialog = UIManager.getLastShownWidget()
        local buttons = dialog.buttons[1]

        -- Change to a string
        dialog.mock_input_value = "http://proxy"
        buttons[3].callback()

        assert.are.equal("http://proxy", widget.state.NETWORK_PROXY.value)
        assert.is_true(widget.menu_entries[idx].bold)

        -- Change back to "nil" string, which should be parsed as nil
        UIManager.show:clear()
        entry.callback()
        dialog = UIManager.getLastShownWidget()
        buttons = dialog.buttons[1]
        dialog.mock_input_value = "nil"
        buttons[3].callback()

        assert.is_nil(widget.state.NETWORK_PROXY.value)
        assert.is_false(widget.menu_entries[idx].bold) -- back to default
      end)
    end)

    describe("saveSettings", function()
      it("should save dirty settings to G_defaults and flush", function()
        local UIManager = require("ui/uimanager")
        UIManager.show:clear()

        -- Make some changes
        widget.state.BOOL_KEY.value = false
        widget.state.BOOL_KEY.dirty = true
        widget.state.NUM_KEY.value = 100
        widget.state.NUM_KEY.dirty = true

        _G.G_defaults.save:clear()
        _G.G_defaults.flush:clear()

        widget:saveSettings()

        assert.spy(_G.G_defaults.save).was.called(2)
        -- We can check calls, but since order of pairs is not strictly guaranteed to be what we expect if we didn't use orderedPairs in saveSettings (it uses pairs)
        -- Actually saveSettings uses `pairs(self.state)` which is standard pairs, so order is not guaranteed.
        -- We can check if it was called with expected args.
        local args1 = _G.G_defaults.save.calls[1].vals
        local args2 = _G.G_defaults.save.calls[2].vals
        local saved = {}
        saved[args1[2]] = args1[3]
        saved[args2[2]] = args2[3]

        assert.are.equal(false, saved.BOOL_KEY)
        assert.are.equal(100, saved.NUM_KEY)

        assert.spy(_G.G_defaults.flush).was.called(1)
        assert.spy(UIManager.show).was.called(1)
        local msg = UIManager.getLastShownWidget()
        assert.is_true(msg.is_info_message)
        assert.are.equal("Default settings saved.", msg.text)
      end)
    end)

    describe("saveBeforeExit", function()
      it("should do nothing if settings not changed", function()
        local UIManager = require("ui/uimanager")
        UIManager.show:clear()

        widget.settings_changed = false
        widget:saveBeforeExit()

        assert.spy(UIManager.show).was.not_called()
      end)

      it("should show ConfirmBox if settings changed", function()
        local UIManager = require("ui/uimanager")
        UIManager.show:clear()

        widget.settings_changed = true
        widget:saveBeforeExit()

        assert.spy(UIManager.show).was.called(1)
        local confirmbox = UIManager.getLastShownWidget()
        assert.is_true(confirmbox.is_confirm_box)
        assert.are.equal("Save and restart", confirmbox.ok_text) -- since Device:canRestart() is true

        -- Click OK
        UIManager.show:clear()
        UIManager.restartKOReader:clear()
        spy.on(widget, "saveSettings")

        confirmbox.ok_callback()

        assert.spy(widget.saveSettings).was.called(1)
        assert.spy(UIManager.restartKOReader).was.called(1)
      end)

      it("should show ConfirmBox with Save and quit if Device cannot restart", function()
        local UIManager = require("ui/uimanager")
        UIManager.show:clear()

        mock_device.canRestart = function() return false end
        widget.settings_changed = true
        widget:saveBeforeExit()

        local confirmbox = UIManager.getLastShownWidget()
        assert.are.equal("Save and quit", confirmbox.ok_text)

        -- Click OK
        UIManager.quit:clear()
        confirmbox.ok_callback()
        assert.spy(UIManager.quit).was.called(1)
      end)

      it("should discard changes on Cancel", function()
        local UIManager = require("ui/uimanager")
        UIManager.show:clear()

        local logger = require("logger")
        logger.info:clear()

        widget.settings_changed = true
        widget:saveBeforeExit()

        local confirmbox = UIManager.getLastShownWidget()

        confirmbox.cancel_callback()
        assert.spy(logger.info).was.called_with("discard defaults")
      end)
    end)

    describe("defaults_menu close_callback", function()
      it("should trigger saveBeforeExit and close widget", function()
        local UIManager = require("ui/uimanager")
        UIManager.close:clear()
        spy.on(widget, "saveBeforeExit")

        widget.defaults_menu.close_callback()

        assert.spy(widget.saveBeforeExit).was.called(1)
        assert.spy(UIManager.close).was.called(1)
        assert.are.equal(widget, UIManager.getLastClosedWidget())
      end)
    end)
  end)
end)
