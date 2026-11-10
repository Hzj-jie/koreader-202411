describe("Checkers new game lifecycle", function()
  local Checkers, LuaSettings, SettingsWidget, UIManager
  local tmp_settings_path
  local instances = {}
  local dialogs = {}

  local function count_on_window_stack(widget)
    local count = 0
    for _, entry in ipairs(UIManager._window_stack) do
      if entry.widget == widget then
        count = count + 1
      end
    end
    return count
  end

  local function create_checkers()
    tmp_settings_path = os.tmpname()
    os.remove(tmp_settings_path)
    local instance = Checkers:new({
      ui = {
        menu = { registerToMainMenu = function() end },
      },
    })
    instance.settings = LuaSettings:open(tmp_settings_path)
    table.insert(instances, instance)
    return instance
  end

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    Checkers = require("plugins/checkers.koplugin/main")
    LuaSettings = require("luasettings")
    SettingsWidget = require("plugins/checkers.koplugin/settingswidget")
    UIManager = require("ui/uimanager")
  end)

  after_each(function()
    for i = #dialogs, 1, -1 do
      UIManager:closeIfShown(dialogs[i])
      dialogs[i] = nil
    end
    for i = #instances, 1, -1 do
      UIManager:closeIfShown(instances[i])
      instances[i] = nil
    end
    for i = #UIManager._task_queue, 1, -1 do
      UIManager:unschedule(UIManager._task_queue[i].action)
    end
    if tmp_settings_path then
      os.remove(tmp_settings_path)
      os.remove(tmp_settings_path .. ".old")
      tmp_settings_path = nil
    end
  end)

  it(
    "restarts without error or duplicate stack entry via in-game settings applyAndClose",
    function()
      local instance = create_checkers()
      instance:startGame()
      assert.is_true(UIManager:isWindowWidget(instance))
      assert.are.equal(1, count_on_window_stack(instance))

      local created_settings
      local orig_new = SettingsWidget.new
      SettingsWidget.new = function(cls, opts)
        local w = orig_new(cls, opts)
        created_settings = w
        return w
      end
      finally(function()
        SettingsWidget.new = orig_new
        if created_settings and created_settings.dialog then
          table.insert(dialogs, created_settings.dialog)
        end
      end)

      instance.status_bar.left_icon_tap_callback()
      assert.is_table(created_settings)
      assert.is_table(created_settings.dialog)
      assert.is_true(UIManager:isWindowWidget(created_settings.dialog))

      local prev_game = instance.game
      created_settings.changes.ai_depth = 3
      created_settings:applyAndClose()

      assert.is_false(UIManager:isWindowWidget(created_settings.dialog))
      assert.is_true(UIManager:isWindowWidget(instance))
      assert.are.equal(1, count_on_window_stack(instance))
      assert.are_not.equal(prev_game, instance.game)
      assert.are.equal(3, instance.ai_depth)
    end
  )

  it(
    "restarts cleanly via onCheckersStart when Checkers is already shown",
    function()
      local instance = create_checkers()
      instance:startGame()
      assert.is_true(UIManager:isWindowWidget(instance))
      assert.are.equal(1, count_on_window_stack(instance))

      local prev_game = instance.game
      assert.is_true(instance:onCheckersStart())
      assert.is_true(UIManager:isWindowWidget(instance))
      assert.are.equal(1, count_on_window_stack(instance))
      assert.are_not.equal(prev_game, instance.game)
    end
  )
end)
