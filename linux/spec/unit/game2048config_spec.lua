describe("Game2048Config module", function()
  local Game2048Config, UIManager

  setup(function()
    require("commonrequire")
    Game2048Config = require("plugins/game2048.koplugin/modules/game2048config")
    UIManager = require("ui/uimanager")
  end)

  local orig_show, orig_close
  local shown_widgets, closed_widgets

  before_each(function()
    shown_widgets = {}
    closed_widgets = {}
    orig_show = UIManager.show
    orig_close = UIManager.close

    UIManager.show = function(_self, w)
      table.insert(shown_widgets, w)
    end
    UIManager.close = function(_self, w)
      table.insert(closed_widgets, w)
    end
  end)

  after_each(function()
    UIManager.show = orig_show
    UIManager.close = orig_close
  end)

  it("should handle Game2048Settings creation, reset, merge, and dump", function()
    local settings = Game2048Config.makeDefaultSettings()
    assert.is_table(settings)
    assert.are.equal("default", settings.profile)
    assert.are.equal(4, settings.size)
    assert.are.equal(0.1, settings.new_tile_delay)
    assert.are.equal("default", settings.theme)

    settings.size = 5
    settings.theme = "all_black"
    settings:reset()
    assert.are.equal(4, settings.size)
    assert.are.equal("default", settings.theme)

    settings:merge({ size = 3, theme = "gray", unknown = 123 })
    assert.are.equal(3, settings.size)
    assert.are.equal("gray", settings.theme)
    assert.is_nil(settings.unknown)

    local dumped = settings:dump()
    assert.is_table(dumped)
    assert.are.equal(3, dumped.size)
    assert.are.equal("gray", dumped.theme)
    assert.are.equal("default", dumped.profile)
  end)

  it("should initialize Game2048Config and build option panels", function()
    local config = Game2048Config:new()
    assert.is_table(config)
    assert.is_table(config.options)
    assert.are.equal("game2048", config.options.prefix)
    assert.are.equal(2, #config.options)
    assert.is_false(config._did_show_size_notification)
  end)

  it("should show config menu without error (fails due to production typo onShowConfigPanel)", function()
    local settings = Game2048Config.makeDefaultSettings()
    local config = Game2048Config:new({
      configurable = settings,
    })

    assert.has_no.errors(function()
      config:showConfigMenu()
    end)
  end)

  it("should handle onSetDimensions and onCloseCallback", function()
    local callback_called = false
    local settings = Game2048Config.makeDefaultSettings()
    local config = Game2048Config:new({
      configurable = settings,
      new_settings_callback = function()
        callback_called = true
      end,
    })

    local mock_dialog_inited = false
    config.config_dialog = {
      panel_index = 2,
      init = function()
        mock_dialog_inited = true
      end,
    }

    config:onSetDimensions()
    assert.is_true(mock_dialog_inited)

    config:onCloseCallback()
    assert.is_nil(config.config_dialog)
    assert.are.equal(2, config.last_panel_index)
    assert.is_true(callback_called)
  end)

  it("should handle onConfigChange for size, theme, and profile", function()
    local handled_events = {}
    local mock_ui = {
      handleEvent = function(_self, ev)
        table.insert(handled_events, ev)
      end,
    }
    local settings = Game2048Config.makeDefaultSettings()
    local config = Game2048Config:new({
      ui = mock_ui,
      configurable = settings,
    })

    -- Size change notifies user first time
    config:onConfigChange("size", 5)
    assert.are.equal(5, settings.size)
    assert.are.equal(1, #shown_widgets)
    assert.are.equal("Start a new game to change the size of the board", shown_widgets[1].text)

    -- Size change second time does not show notification again
    config:onConfigChange("size", 3)
    assert.are.equal(3, settings.size)
    assert.are.equal(1, #shown_widgets)

    -- Theme change triggers onThemeChange event
    config:onConfigChange("theme", "all_black")
    assert.are.equal("all_black", settings.theme)
    assert.are.equal(1, #handled_events)
    assert.are.equal("onThemeChange", handled_events[1].handler)
    assert.are.equal("all_black", handled_events[1].args[1])

    -- Profile change triggers onProfileChange event
    config:onConfigChange("profile", "player2")
    assert.are.equal("player2", settings.profile)
    assert.are.equal(2, #handled_events)
    assert.are.equal("onProfileChange", handled_events[2].handler)
    assert.are.equal("player2", handled_events[2].args[1])
  end)

  it("should show theme select dialog and allow selecting a theme", function()
    local settings = Game2048Config.makeDefaultSettings()
    local mock_ui = {
      handleEvent = function() end,
    }
    local config = Game2048Config:new({
      ui = mock_ui,
      configurable = settings,
    })

    config:onSelectTheme()
    assert.is_table(config._theme_select_dialog)
    assert.are.equal(1, #shown_widgets)
    local dialog = shown_widgets[1]
    assert.are.equal(config._theme_select_dialog, dialog)
    assert.is_table(dialog.buttons)
    assert.is_true(#dialog.buttons > 0)

    -- Select second theme (all_black)
    local second_btn = dialog.buttons[2][1]
    second_btn.callback()

    assert.are.equal("all_black", settings.theme)
    assert.are.equal(1, #closed_widgets)
    assert.is_nil(config._theme_select_dialog)
  end)
end)
