describe("Sudoku close lifecycle", function()
  local Device, Key, Sudoku, UIManager, gettext
  local orig_has_keys

  setup(function()
    require("commonrequire")
    Device = require("device")
    Key = require("device/key")
    UIManager = require("ui/uimanager")
    gettext = require("gettext")
    Sudoku = require("plugins/sudoku.koplugin/main")
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
    return Sudoku:new({
      ui = {
        menu = {
          registerToMainMenu = function() end,
        },
      },
      path = "plugins/sudoku.koplugin",
    })
  end

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

  it("closes UIManager window and saves state once when pressing Back", function()
    local plugin = createPlugin()
    local save_calls = 0
    local closed_calls = 0
    local orig_save = plugin.saveState
    local orig_closed = plugin.onScreenClosed
    plugin.saveState = function(self)
      save_calls = save_calls + 1
      return orig_save(self)
    end
    plugin.onScreenClosed = function(self)
      closed_calls = closed_calls + 1
      return orig_closed(self)
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
    assert.are.equal(1, closed_calls)
  end)

  it("closes UIManager window and saves state once via Close button", function()
    local plugin = createPlugin()
    local save_calls = 0
    local closed_calls = 0
    local orig_save = plugin.saveState
    local orig_closed = plugin.onScreenClosed
    plugin.saveState = function(self)
      save_calls = save_calls + 1
      return orig_save(self)
    end
    plugin.onScreenClosed = function(self)
      closed_calls = closed_calls + 1
      return orig_closed(self)
    end

    plugin:showGame()
    local screen = plugin.screen
    assert.is_true(UIManager:isWindowWidget(screen))

    local close_button = findButtonByText(screen, gettext("Close"))
    assert.is_table(close_button)
    close_button.callback()

    assert.is_false(UIManager:isWindowWidget(screen))
    assert.is_nil(plugin.screen)
    assert.are.equal(1, save_calls)
    assert.are.equal(1, closed_calls)
  end)

  it("closes once when closed directly via UIManager", function()
    local plugin = createPlugin()
    local save_calls = 0
    local closed_calls = 0
    local orig_save = plugin.saveState
    local orig_closed = plugin.onScreenClosed
    plugin.saveState = function(self)
      save_calls = save_calls + 1
      return orig_save(self)
    end
    plugin.onScreenClosed = function(self)
      closed_calls = closed_calls + 1
      return orig_closed(self)
    end

    plugin:showGame()
    local screen = plugin.screen
    UIManager:close(screen)

    assert.is_false(UIManager:isWindowWidget(screen))
    assert.is_nil(plugin.screen)
    assert.are.equal(1, save_calls)
    assert.are.equal(1, closed_calls)
  end)
end)
