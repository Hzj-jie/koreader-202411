describe("ExternalKeyboard main plugin module", function()
  local ExternalKeyboard, lfs

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    lfs = require("libs/libkoreader-lfs")

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

  it("should expose plugin structure and default properties", function()
    assert.is_table(ExternalKeyboard)
    assert.are.equal("external_keyboard", ExternalKeyboard.name)
  end)

  it("should get OTG roles for chipidea and sunxi drivers", function()
    local inst = ExternalKeyboard:new({
      ui = { menu = { registerToMainMenu = function() end } },
    })

    local old_open = io.open
    io.open = function(path, mode)
      if path:find("ci_hdrc") then
        return {
          read = function()
            return "host"
          end,
          close = function() end,
        }
      elseif path:find("usbc0") then
        return {
          read = function()
            return "usb_device"
          end,
          close = function() end,
        }
      end
      return old_open(path, mode)
    end

    assert.are.equal("host", inst:chipideaGetOTGRole())
    assert.are.equal("device", inst:sunxiGetOTGRole())

    io.open = old_open
  end)

  it("should add OTG configuration items to main menu", function()
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
  end)
end)
