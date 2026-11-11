describe("Game2048 close lifecycle", function()
  local Device, Game2048, Key, UIManager
  local orig_has_keys

  setup(function()
    require("commonrequire")
    Device = require("device")
    Key = require("device/key")
    UIManager = require("ui/uimanager")
    Game2048 = require("plugins/game2048.koplugin/main")
  end)

  before_each(function()
    orig_has_keys = Device.hasKeys
    Device.hasKeys = function()
      return true
    end
  end)

  after_each(function()
    Device.hasKeys = orig_has_keys
    UIManager:quit()
  end)

  local function createPlugin()
    return Game2048:new({
      ui = {
        menu = {
          registerToMainMenu = function() end,
        },
      },
      path = "plugins/game2048.koplugin",
    })
  end

  it("closes once without recursion when pressing Back", function()
    local plugin = createPlugin()
    local save_calls = 0
    local orig_save = plugin.storage.saveState
    plugin.storage.saveState = function(storage_self, state)
      save_calls = save_calls + 1
      return orig_save(storage_self, state)
    end

    plugin:showGame()
    local screen = plugin.screen
    assert.is_table(screen)
    assert.is_true(UIManager:isWindowWidget(screen))

    local handled = screen:onKeyPress(Key:new("Back", {}))
    assert.is_true(handled)
    assert.is_false(UIManager:isWindowWidget(screen))
    assert.is_nil(plugin.screen)
    assert.are.equal(1, save_calls)
  end)

  it("closes once without recursion via TitleBar close button", function()
    local plugin = createPlugin()
    local save_calls = 0
    local orig_save = plugin.storage.saveState
    plugin.storage.saveState = function(storage_self, state)
      save_calls = save_calls + 1
      return orig_save(storage_self, state)
    end

    plugin:showGame()
    local screen = plugin.screen
    assert.is_true(UIManager:isWindowWidget(screen))

    screen._title_bar.close_callback()
    assert.is_false(UIManager:isWindowWidget(screen))
    assert.is_nil(plugin.screen)
    assert.are.equal(1, save_calls)
  end)

  it("closes once when closed directly via UIManager", function()
    local plugin = createPlugin()
    local save_calls = 0
    local orig_save = plugin.storage.saveState
    plugin.storage.saveState = function(storage_self, state)
      save_calls = save_calls + 1
      return orig_save(storage_self, state)
    end

    plugin:showGame()
    local screen = plugin.screen
    UIManager:close(screen)
    assert.is_false(UIManager:isWindowWidget(screen))
    assert.is_nil(plugin.screen)
    assert.are.equal(1, save_calls)
  end)

  it(
    "does not schedule setDirty before show on touch devices and still marks dirty after show",
    function()
      local logger = require("logger")
      local orig_warn = logger.warn
      local orig_has_dpad = Device.hasDPad
      local fixme_warnings = {}
      Device.hasDPad = function()
        return false
      end
      logger.warn = function(...)
        local msg = table.concat({ ... }, " ")
        if msg:find("FixMe", 1, true) then
          table.insert(fixme_warnings, msg)
        end
      end
      finally(function()
        logger.warn = orig_warn
        Device.hasDPad = orig_has_dpad
      end)

      local plugin = createPlugin()
      plugin:showGame()
      UIManager:forceRepaint()
      assert.are.same({}, fixme_warnings)

      local screen = plugin.screen
      screen:onThemeChange("all_black")
      assert.is_true(UIManager._dirty[screen._game_widget])
      assert.is_nil(UIManager._dirty[screen])
      UIManager:forceRepaint()

      screen._game_widget:setActive(false)
      assert.is_true(UIManager._dirty[screen._game_widget])
      assert.is_nil(UIManager._dirty[screen])
      UIManager:forceRepaint()
      assert.are.same({}, fixme_warnings)
    end
  )
end)
