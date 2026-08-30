describe("ExternalKeyboard main plugin module", function()
  local ExternalKeyboard, lfs, Device, UIManager, ffi, orig_loadlib

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    lfs = require("libs/libkoreader-lfs")
    Device = require("device")
    UIManager = require("ui/uimanager")
    ffi = require("ffi")

    orig_loadlib = ffi.loadlib
    ffi.loadlib = function(lib, ver)
      if lib == "fbink_input" then
        return {
          fbink_input_scan = function(type, a, b, dev_count)
            return nil
          end,
          fbink_input_check = function(path, type, a, b)
            return nil
          end,
        }
      end
      return orig_loadlib(lib, ver)
    end

    local old_open = io.open
    io.open = function(path, mode)
      if path == "/proc/mounts" then
        return {
          lines = function()
            local done = false
            return function()
              if not done then
                done = true
                return "debugfs /sys/kernel/debug debugfs rw 0 0"
              end
            end
          end,
          close = function() end,
        }
      end
      return old_open(path, mode)
    end

    local old_attr = lfs.attributes
    lfs.attributes = function(path, request)
      if path:find("/sys/kernel/debug") then
        return "directory"
      elseif path:find("ci_hdrc") or path:find("usbc0") then
        return "file"
      end
      return old_attr(path, request)
    end

    ExternalKeyboard = require("plugins/externalkeyboard.koplugin/main")
    lfs.attributes = old_attr
    io.open = old_open
  end)

  teardown(function()
    if orig_loadlib then
      ffi.loadlib = orig_loadlib
    end
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))
  end)

  it("should expose plugin structure and default properties", function()
    assert.is_table(ExternalKeyboard)
    assert.are.equal("external_keyboard", ExternalKeyboard.name)
  end)

  it("should get and set OTG roles for chipidea and sunxi drivers", function()
    local inst = ExternalKeyboard:new({
      ui = { menu = { registerToMainMenu = function() end } },
    })

    local written_files = {}
    local old_open = io.open
    io.open = function(path, mode)
      if path:find("ci_hdrc") then
        if mode:find("w") then
          return {
            write = function(self_f, data) written_files[path] = data end,
            close = function() end,
          }
        else
          return {
            read = function() return "host" end,
            close = function() end,
          }
        end
      elseif path:find("usbc0") then
        if mode:find("w") then
          return {
            write = function(self_f, data) written_files[path] = data end,
            close = function() end,
          }
        else
          return {
            read = function() return "usb_device" end,
            close = function() end,
          }
        end
      end
      return old_open(path, mode)
    end

    assert.are.equal("host", inst:chipideaGetOTGRole())
    assert.are.equal("device", inst:sunxiGetOTGRole())

    inst:chipideaSetOTGRole("device")
    assert.are.equal("gadget", written_files["/sys/kernel/debug/ci_hdrc.0/role"])

    inst:sunxiSetOTGRole("host")
    assert.are.equal("usb_host", written_files["/sys/devices/platform/soc/usbc0/otg_role"])

    io.open = old_open
  end)

  it("should add OTG configuration items to main menu and show help", function()
    local mock_ui = {
      menu = {
        registerToMainMenu = function() end,
      },
    }

    local inst = ExternalKeyboard:new({ ui = mock_ui })
    inst.getOTGRole = function()
      return "device"
    end
    inst.setOTGRole = function() end

    local menu_items = {}
    inst:addToMainMenu(menu_items)
    assert.is_table(menu_items.external_keyboard)
    assert.is_table(menu_items.external_keyboard.sub_item_table)
    assert.are.equal(3, #menu_items.external_keyboard.sub_item_table)

    local sub_items = menu_items.external_keyboard.sub_item_table
    assert.is_boolean(sub_items[1].checked_func())
    sub_items[1].callback()
    sub_items[2].callback()
    sub_items[3].callback()

    inst:showHelp()
  end)

  it("should handle onExit and revert OTG host role", function()
    local inst = ExternalKeyboard:new({
      ui = { menu = { registerToMainMenu = function() end } },
    })

    local set_role
    inst.getOTGRole = function() return "host" end
    inst.setOTGRole = function(self_i, r) set_role = r end

    inst:onExit()
    assert.are.equal("device", set_role)
  end)

  it("should setup, connect, and disconnect external keyboards", function()
    local inst = ExternalKeyboard:new({
      ui = { menu = { registerToMainMenu = function() end } },
    })

    -- Mock Device.input
    local closed_paths = {}
    Device.input = {
      fdopen = function(self_in, fd, path, name)
        return 99
      end,
      close = function(self_in, path)
        closed_paths[path] = true
      end,
      event_map = {},
    }

    local kb_data = {
      event_fd = 5,
      event_path = "/dev/input/event10",
      name = "USB Test Keyboard",
      has_dpad = true,
    }

    -- Setup keyboard
    inst:setupKeyboard(kb_data)

    assert.are.equal(1, ExternalKeyboard.connected_keyboards)
    assert.are.equal(99, ExternalKeyboard.keyboard_fds["/dev/input/event10"])
    assert.is_true(Device.hasKeyboard())
    assert.is_true(Device.hasKeys())
    assert.is_true(Device.hasDPad())

    -- Evdev hotplug remove
    local old_attr = lfs.attributes
    lfs.attributes = function(path, request)
      if path == "/dev/input/event10" then
        return nil -- disconnected
      end
      return old_attr(path, request)
    end

    inst:_onEvdevInputRemove("/dev/input/event10")

    assert.are.equal(0, ExternalKeyboard.connected_keyboards)
    assert.is_nil(ExternalKeyboard.keyboard_fds["/dev/input/event10"])
    assert.is_true(closed_paths["/dev/input/event10"])

    lfs.attributes = old_attr
  end)

  it("should schedule hotplug insert and remove callbacks", function()
    local inst = ExternalKeyboard:new({
      ui = { menu = { registerToMainMenu = function() end } },
    })

    local scheduled = {}
    local orig_schedule = UIManager.scheduleIn
    UIManager.scheduleIn = function(self_uim, delay, func, target, arg)
      table.insert(scheduled, { delay = delay, func = func, target = target, arg = arg })
    end

    inst:onEvdevInputInsert("/dev/input/event12")
    inst:onEvdevInputRemove("/dev/input/event12")

    assert.are.equal(2, #scheduled)
    assert.are.equal("/dev/input/event12", scheduled[1].arg)
    assert.are.equal("/dev/input/event12", scheduled[2].arg)

    UIManager.scheduleIn = orig_schedule
  end)
end)
