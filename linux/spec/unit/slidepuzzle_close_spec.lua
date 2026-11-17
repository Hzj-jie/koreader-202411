describe("SlidePuzzle close lifecycle", function()
  local DataStorage, Device, I18n, Key, SlidePuzzle, UIManager
  local orig_has_keys, active_screen

  setup(function()
    require("commonrequire")
    DataStorage = require("datastorage")
    Device = require("device")
    Key = require("device/key")
    UIManager = require("ui/uimanager")
    I18n = require("plugins/slidepuzzle.koplugin/slidepuzzle_i18n")
    SlidePuzzle = require("plugins/slidepuzzle.koplugin/main")
  end)

  before_each(function()
    orig_has_keys = Device.hasKeys
    Device.hasKeys = function()
      return true
    end
    active_screen = nil
  end)

  after_each(function()
    if active_screen then
      active_screen:stopTicker()
      UIManager:closeIfShown(active_screen)
      active_screen = nil
    end
    Device.hasKeys = orig_has_keys
    UIManager:quit()
    I18n.setActive("default")
    local settings_path = DataStorage:getSettingsDir() .. "/slidepuzzle.lua"
    os.remove(settings_path)
    os.remove(settings_path .. ".old")
  end)

  local function findButtonByText(widget, target_text)
    if type(widget) ~= "table" then
      return nil
    end
    if widget.text == target_text and type(widget.callback) == "function" then
      return widget
    end
    for _, child in ipairs(widget) do
      local found = findButtonByText(child, target_text)
      if found then
        return found
      end
    end
    return nil
  end

  local function assertClosedOnce(trigger_close)
    local plugin = SlidePuzzle:new({
      ui = {
        menu = {
          registerToMainMenu = function() end,
        },
      },
      path = "plugins/slidepuzzle.koplugin",
    })
    local save_calls = 0
    local closed_calls = 0
    local orig_save = plugin.saveCurrentState
    local orig_closed = plugin.onScreenClosed
    plugin.saveCurrentState = function(self, game)
      save_calls = save_calls + 1
      return orig_save(self, game)
    end
    plugin.onScreenClosed = function(self)
      closed_calls = closed_calls + 1
      return orig_closed(self)
    end

    plugin:showGame()
    local screen = plugin.screen
    active_screen = screen
    assert.is_table(screen)
    assert.is_true(UIManager:isWindowWidget(screen))
    assert.is_true(screen.tick_scheduled)

    trigger_close(screen)

    assert.is_false(UIManager:isWindowWidget(screen))
    assert.is_false(screen.tick_scheduled)
    for _, task in ipairs(UIManager._task_queue) do
      assert.are_not.equal(screen.tick_handler, task.action)
    end
    assert.is_nil(plugin.screen)
    assert.are.equal(1, save_calls)
    assert.are.equal(1, closed_calls)
  end

  it(
    "closes UIManager window and saves state once when pressing Back",
    function()
      assertClosedOnce(function(screen)
        local handled = screen:onKeyPress(Key:new("Back", {}))
        assert.is_true(handled)
      end)
    end
  )

  it("closes UIManager window and saves state once via Close button", function()
    assertClosedOnce(function(screen)
      local close_button = findButtonByText(screen, I18n.t("Close"))
      assert.is_table(close_button)
      close_button.callback()
    end)
  end)

  it("closes once when closed directly via UIManager", function()
    assertClosedOnce(function(screen)
      UIManager:close(screen)
    end)
  end)
end)
