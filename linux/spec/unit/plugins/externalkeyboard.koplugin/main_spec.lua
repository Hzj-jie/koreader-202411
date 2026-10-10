describe("ExternalKeyboard plugin main module", function()
  local Device, UIManager, lfs, util

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))
    Device = require("device")
    UIManager = require("ui/uimanager")
    lfs = require("libs/libkoreader-lfs")
    util = require("util")

    _G.G_reader_settings = {
      data = {},
      read = function(self, key)
        return self.data[key]
      end,
      readTableRef = function(self, key, default)
        return self.data[key] or default or {}
      end,
      readSetting = function(self, key, default)
        if self.data[key] ~= nil then
          return self.data[key]
        end
        return default
      end,
      has = function(self, key)
        return self.data[key] ~= nil
      end,
      nilOrTrue = function(self, key)
        if self.data[key] == nil then
          return true
        end
        return not not self.data[key]
      end,
      isTrue = function(self, key)
        return not not self.data[key]
      end,
      flipNilOrFalse = function(self, key)
        self.data[key] = not self.data[key]
      end,
      save = function(self, key, val)
        self.data[key] = val
      end,
      saveSetting = function(self, key, val)
        self.data[key] = val
      end,
      flush = function() end,
    }
  end)

  describe("Disabled Guard Paths", function()
    it(
      "should return disabled table when debugfs or role paths are missing",
      function()
        package.loaded["plugins/externalkeyboard.koplugin/main"] = nil
        local ExternalKeyboard =
          require("plugins/externalkeyboard.koplugin/main")
        assert.is_table(ExternalKeyboard)
        assert.is_true(ExternalKeyboard.disabled)
      end
    )
  end)

  describe("Real ExternalKeyboard Class", function()
    local ExternalKeyboard
    local orig_lfs_attr, orig_io_open

    setup(function()
      orig_lfs_attr = lfs.attributes
      orig_io_open = io.open

      lfs.attributes = function(path, request_name)
        if path == "/sys/kernel/debug" then
          if request_name == "mode" or request_name == nil then
            return "directory"
          end
        elseif path == "/sys/kernel/debug/ci_hdrc.0/role" then
          if request_name == "mode" or request_name == nil then
            return "file"
          end
        elseif path == "/sys/devices/platform/soc/usbc0/otg_role" then
          if request_name == "mode" or request_name == nil then
            return "file"
          end
        end
        return orig_lfs_attr(path, request_name)
      end

      io.open = function(path, mode)
        if path == "/proc/mounts" then
          return {
            lines = function()
              local yielded = false
              return function()
                if not yielded then
                  yielded = true
                  return "none /sys/kernel/debug debugfs rw,relatime 0 0"
                end
                return nil
              end
            end,
            close = function() end,
          }
        end
        return orig_io_open(path, mode)
      end

      package.loaded["plugins/externalkeyboard.koplugin/main"] = nil
      ExternalKeyboard = require("plugins/externalkeyboard.koplugin/main")
    end)

    teardown(function()
      lfs.attributes = orig_lfs_attr
      io.open = orig_io_open
      package.loaded["plugins/externalkeyboard.koplugin/main"] = nil
    end)

    before_each(function()
      G_reader_settings.data = {}
    end)

    it("should load real ExternalKeyboard widget container class", function()
      assert.is_table(ExternalKeyboard)
      assert.is_nil(ExternalKeyboard.disabled)
      assert.are.equal("external_keyboard", ExternalKeyboard.name)
    end)

    it("should handle chipideaGetOTGRole and chipideaSetOTGRole", function()
      local keyboard = ExternalKeyboard:new({
        ui = { menu = { registerToMainMenu = function() end } },
      })

      local role_written
      local current_file_content = "gadget"
      local old_open = io.open
      io.open = function(path, mode)
        if path == "/sys/kernel/debug/ci_hdrc.0/role" then
          if mode == "re" then
            return {
              read = function()
                return current_file_content
              end,
              close = function() end,
            }
          elseif mode == "we" then
            return {
              write = function(self, val)
                role_written = val
              end,
              close = function() end,
            }
          end
        end
        return old_open(path, mode)
      end

      assert.are.equal("device", keyboard:chipideaGetOTGRole())
      current_file_content = "host"
      assert.are.equal("host", keyboard:chipideaGetOTGRole())

      keyboard:chipideaSetOTGRole("host")
      assert.are.equal("host", role_written)
      keyboard:chipideaSetOTGRole("device")
      assert.are.equal("gadget", role_written)

      io.open = old_open
    end)

    it("should handle sunxiGetOTGRole and sunxiSetOTGRole", function()
      local keyboard = ExternalKeyboard:new({
        ui = { menu = { registerToMainMenu = function() end } },
      })

      local role_written
      local current_file_content = "usb_device"
      local old_open = io.open
      io.open = function(path, mode)
        if path == "/sys/devices/platform/soc/usbc0/otg_role" then
          if mode == "re" then
            return {
              read = function()
                return current_file_content
              end,
              close = function() end,
            }
          elseif mode == "we" then
            return {
              write = function(self, val)
                role_written = val
              end,
              close = function() end,
            }
          end
        end
        return old_open(path, mode)
      end

      assert.are.equal("device", keyboard:sunxiGetOTGRole())
      current_file_content = "usb_host"
      assert.are.equal("host", keyboard:sunxiGetOTGRole())

      keyboard:sunxiSetOTGRole("host")
      assert.are.equal("usb_host", role_written)
      keyboard:sunxiSetOTGRole("device")
      assert.are.equal("usb_device", role_written)

      io.open = old_open
    end)

    it(
      "should initialize roles and handle external_keyboard_otg_mode_on_start",
      function()
        local registered = false
        local keyboard = ExternalKeyboard:new({
          ui = {
            menu = {
              registerToMainMenu = function()
                registered = true
              end,
            },
          },
        })

        local role_val = "device"
        local function mock_get()
          return role_val
        end
        local function mock_set(self, r)
          role_val = r
        end
        keyboard.chipideaGetOTGRole = mock_get
        keyboard.chipideaSetOTGRole = mock_set
        keyboard.sunxiGetOTGRole = mock_get
        keyboard.sunxiSetOTGRole = mock_set
        keyboard.findAndSetupKeyboards = function() end

        G_reader_settings.data["external_keyboard_otg_mode_on_start"] = true
        keyboard:init()
        assert.is_true(registered)
        assert.are.equal("host", role_val)
      end
    )

    it("should populate main menu items and callbacks", function()
      local keyboard = ExternalKeyboard:new({
        ui = { menu = { registerToMainMenu = function() end } },
      })
      local current_role = "device"
      keyboard.getOTGRole = function()
        return current_role
      end
      keyboard.setOTGRole = function(self, r)
        current_role = r
      end

      local menu_items = {}
      keyboard:addToMainMenu(menu_items)
      assert.is_table(menu_items.external_keyboard)
      local sub = menu_items.external_keyboard.sub_item_table
      assert.are.equal(3, #sub)

      -- 1. Enable OTG mode toggle
      assert.is_false(sub[1].checked_func())
      sub[1].callback()
      assert.are.equal("host", current_role)
      assert.is_true(sub[1].checked_func())

      -- 2. Always enable OTG mode
      assert.is_false(sub[2].checked_func())
      sub[2].callback()
      assert.is_true(sub[2].checked_func())

      -- 3. Help callback
      local shown_info
      local old_show = UIManager.show
      UIManager.show = function(self, msg)
        shown_info = msg
      end
      sub[3].callback()
      assert.is_not_nil(shown_info)
      UIManager.show = old_show
    end)

    it("should reset USB_ROLE_HOST to USB_ROLE_DEVICE on onExit", function()
      local keyboard = ExternalKeyboard:new({
        ui = { menu = { registerToMainMenu = function() end } },
      })
      local current_role = "host"
      keyboard.getOTGRole = function()
        return current_role
      end
      keyboard.setOTGRole = function(self, r)
        current_role = r
      end

      keyboard:onExit()
      assert.are.equal("device", current_role)
    end)

    it(
      "should manage setupKeyboard and restore device caps in _onEvdevInputRemove",
      function()
        local keyboard = ExternalKeyboard:new({
          ui = { menu = { registerToMainMenu = function() end } },
        })

        -- Save initial Device properties
        local orig_hasKeyboard = Device.hasKeyboard
        local orig_hasKeys = Device.hasKeys
        local orig_hasFewKeys = Device.hasFewKeys
        local orig_hasDPad = Device.hasDPad
        local orig_event_map = Device.input.event_map

        -- Mock Device.input fdopen and close
        local old_fdopen = Device.input.fdopen
        local old_close = Device.input.close
        local closed_paths = {}
        Device.input.fdopen = function(self, fd, path, name)
          return { fd = fd, path = path, name = name }
        end
        Device.input.close = function(self, path)
          closed_paths[path] = true
        end

        local old_show = UIManager.show
        UIManager.show = function() end

        ExternalKeyboard.connected_keyboards = 0
        ExternalKeyboard.keyboard_fds = {}
        ExternalKeyboard.original_device_values = nil

        -- Connect a keyboard
        local kb_data = {
          event_fd = 12,
          event_path = "/dev/input/event3",
          name = "USB Keyboard",
          has_dpad = true,
        }
        keyboard:setupKeyboard(kb_data)

        assert.are.equal(1, ExternalKeyboard.connected_keyboards)
        assert.is_not_nil(ExternalKeyboard.keyboard_fds["/dev/input/event3"])
        assert.is_not_nil(ExternalKeyboard.original_device_values)
        assert.are.equal(util.yes, Device.hasKeyboard)
        assert.are.equal(util.yes, Device.hasKeys)
        assert.are.equal(util.no, Device.hasFewKeys)
        assert.are.equal(util.yes, Device.hasDPad)

        -- Disconnect non-existent keyboard is no-op
        keyboard:_onEvdevInputRemove("/dev/input/event99")
        assert.are.equal(1, ExternalKeyboard.connected_keyboards)

        -- Disconnect real keyboard
        local old_lfs_attr = lfs.attributes
        lfs.attributes = function(path, req)
          if path == "/dev/input/event3" then
            return nil
          end
          return old_lfs_attr(path, req)
        end

        keyboard:_onEvdevInputRemove("/dev/input/event3")
        assert.are.equal(0, ExternalKeyboard.connected_keyboards)
        assert.is_true(closed_paths["/dev/input/event3"])
        assert.is_nil(ExternalKeyboard.original_device_values)
        assert.are.equal(orig_hasKeyboard, Device.hasKeyboard)
        assert.are.equal(orig_hasKeys, Device.hasKeys)

        -- Clean up
        lfs.attributes = old_lfs_attr
        Device.input.fdopen = old_fdopen
        Device.input.close = old_close
        UIManager.show = old_show
        Device.hasKeyboard = orig_hasKeyboard
        Device.hasKeys = orig_hasKeys
        Device.hasFewKeys = orig_hasFewKeys
        Device.hasDPad = orig_hasDPad
        Device.input.event_map = orig_event_map
      end
    )
  end)
end)
