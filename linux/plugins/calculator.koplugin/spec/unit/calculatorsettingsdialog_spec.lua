describe("CalculatorSettingsDialog unit tests", function()
  local CalculatorSettingsDialog
  local UIManager
  local Parser
  local Widget
  local Geom

  setup(function()
    require("commonrequire")
    local device = require("device")
    require("document/canvascontext"):init(device)

    CalculatorSettingsDialog =
      require("plugins/calculator.koplugin/calculatorsettingsdialog")
    UIManager = require("ui/uimanager")
    Parser = require("plugins/calculator.koplugin/formulaparser/formulaparser")
    Widget = require("ui/widget/widget")
    Geom = require("ui/geometry")
  end)

  local function createMockParent()
    local mock_input_dialog = Widget:new({ dimen = Geom:new({ w = 100, h = 100 }) })
    UIManager:show(mock_input_dialog)
    return {
      angle_mode = "degree",
      angle_modes = {
        { "radiant", "Radiant" },
        { "degree", "Degree" },
        { "gon", "Gon" },
      },
      number_format = "auto",
      number_formats = {
        { "scientific", "Scientific" },
        { "engineer", "Engineer" },
        { "auto", "Auto" },
        { "programmer", "Programmer" },
        { "native", "Native" },
      },
      use_init_file = "yes",
      significant_places = 5,
      status_line = "",
      getStatusLine = spy.new(function()
        return "mock_status"
      end),
      onCalculatorStart = spy.new(function() end),
      input_dialog = mock_input_dialog,
    }
  end

  it("should initialize dialog with correct settings options", function()
    local parent = createMockParent()
    local dialog = CalculatorSettingsDialog:new({ parent = parent })

    assert.is_not_nil(dialog)
    assert.is_not_nil(dialog.title_widget)
    assert.is_not_nil(dialog.radio_button_table_angle)
    assert.is_not_nil(dialog.radio_button_table_format)
    assert.is_not_nil(dialog.radio_button_table_init)
    assert.is_not_nil(dialog.radio_button_table_significant)

    -- Check initial selections match parent properties
    assert.are.equal(
      "degree",
      dialog.radio_button_table_angle.checked_button.provider
    )
    assert.are.equal(
      "auto",
      dialog.radio_button_table_format.checked_button.provider
    )
    assert.are.equal(
      "yes",
      dialog.radio_button_table_init.checked_button.provider
    )
    assert.are.equal(
      5,
      dialog.radio_button_table_significant.checked_button.provider
    )
  end)

  it("should handle close/cancel button without changing settings", function()
    local parent = createMockParent()
    local dialog = CalculatorSettingsDialog:new({ parent = parent })
    UIManager:show(dialog)

    local close_spy = spy.on(UIManager, "close")
    -- Cancel button is the first button in buttons table (index 1)
    local cancel_button_cb = dialog.button_table.buttons[1][1].callback
    cancel_button_cb()

    assert.spy(close_spy).was.called()
    assert.spy(parent.onCalculatorStart).was_not.called()
    assert.are.equal("degree", parent.angle_mode)
    assert.are.equal("auto", parent.number_format)
    assert.are.equal("yes", parent.use_init_file)
    assert.are.equal(5, parent.significant_places)
    close_spy:revert()
  end)

  it("should save updated settings when OK button is pressed", function()
    local parent = createMockParent()
    local dialog = CalculatorSettingsDialog:new({ parent = parent })
    UIManager:show(dialog)

    -- Change angle_mode to "gon"
    dialog.radio_button_table_angle.checked_button = { provider = "gon" }
    -- Change number_format to "scientific"
    dialog.radio_button_table_format.checked_button =
      { provider = "scientific" }
    -- Change significant_places to 8
    dialog.radio_button_table_significant.checked_button = { provider = 8 }
    -- Change use_init_file to "no"
    dialog.radio_button_table_init.checked_button = { provider = "no" }

    local close_spy = spy.on(UIManager, "close")
    local eval_spy = spy.on(Parser, "eval")

    local ok_button_cb = dialog.button_table.buttons[1][2].callback
    ok_button_cb()

    -- Verify parent updated values
    assert.are.equal("gon", parent.angle_mode)
    assert.are.equal("scientific", parent.number_format)
    assert.are.equal(8, parent.significant_places)
    assert.are.equal("no", parent.use_init_file)

    -- Verify Parser:eval was called for setgon()
    assert.spy(eval_spy).was.called()

    -- Verify G_reader_settings saved values
    assert.are.equal("gon", G_reader_settings:read("calculator_angle_mode"))
    assert.are.equal(
      "scientific",
      G_reader_settings:read("calculator_number_format")
    )
    assert.are.equal(
      8,
      G_reader_settings:read("calculator_significant_places")
    )
    assert.are.equal("no", G_reader_settings:read("calculator_use_init_file"))

    -- Verify status line refreshed and calculator restarted
    assert.spy(parent.getStatusLine).was.called()
    assert.spy(parent.onCalculatorStart).was.called()
    assert.spy(close_spy).was.called()

    close_spy:revert()
    eval_spy:revert()
  end)

  it(
    "should handle radiant and degree angle mode changes in OK callback",
    function()
      local parent = createMockParent()
      local dialog = CalculatorSettingsDialog:new({ parent = parent })
      UIManager:show(dialog)

      -- Test degree -> radiant
      dialog.radio_button_table_angle.checked_button = { provider = "radiant" }
      local eval_spy = spy.on(Parser, "eval")
      local close_spy = spy.on(UIManager, "close")
      local ok_button_cb = dialog.button_table.buttons[1][2].callback
      ok_button_cb()

      assert.are.equal("radiant", parent.angle_mode)
      assert.spy(eval_spy).was.called()

      -- Test radiant -> degree
      dialog = CalculatorSettingsDialog:new({ parent = parent })
      UIManager:show(dialog)
      dialog.radio_button_table_angle.checked_button = { provider = "degree" }
      ok_button_cb = dialog.button_table.buttons[1][2].callback
      ok_button_cb()

      assert.are.equal("degree", parent.angle_mode)
      assert.spy(eval_spy).was.called()

      eval_spy:revert()
      close_spy:revert()
    end
  )

  it("should trigger onShow and onClose UI dirty calls", function()
    local parent = createMockParent()
    local dialog = CalculatorSettingsDialog:new({ parent = parent })

    local set_dirty_spy = spy.on(UIManager, "setDirty")
    dialog:onShow()
    assert.spy(set_dirty_spy).was.called()

    dialog:onClose()
    assert.spy(set_dirty_spy).was.called()

    set_dirty_spy:revert()
  end)

  it("should choose folder path in choosePathFile", function()
    local parent = createMockParent()
    local dialog = CalculatorSettingsDialog:new({ parent = parent })
    UIManager:show(dialog)
    dialog.test_key = "/tmp/test_dir"

    local show_spy = spy.on(UIManager, "show")
    local mock_menu = { updateItems = spy.new(function() end) }
    local migrate_spy = spy.new(function() end)

    dialog:choosePathFile(mock_menu, "test_key", true, false, migrate_spy)

    assert.spy(show_spy).was.called()
    -- Find PathChooser in UIManager:show calls
    local path_chooser
    for _, call in ipairs(show_spy.calls) do
      if call.refs[2] and call.refs[2].onConfirm then
        path_chooser = call.refs[2]
        break
      end
    end

    assert.is_not_nil(path_chooser)
    assert.is_not_nil(path_chooser.onConfirm)

    -- Trigger onConfirm callback with a directory path without trailing slash
    path_chooser.onConfirm("/tmp/new_dir")

    assert.are.equal("/tmp/new_dir/", dialog.test_key)
    assert.are.equal("/tmp/new_dir/", G_reader_settings:read("test_key"))
    assert.spy(migrate_spy).was.called()
    assert.spy(mock_menu.updateItems).was.called()

    show_spy:revert()
    UIManager:close(dialog)
  end)

  it("should choose file path in choosePathFile when mode is file", function()
    local parent = createMockParent()
    local dialog = CalculatorSettingsDialog:new({ parent = parent })
    UIManager:show(dialog)
    dialog.test_key = "/tmp/old_file.calc"

    local lfs = require("libs/libkoreader-lfs")
    local attr_stub = stub(lfs, "attributes", function(path, mode_name)
      if mode_name == "mode" then
        return "file"
      end
    end)

    local show_spy = spy.on(UIManager, "show")
    local mock_menu = { updateItems = spy.new(function() end) }

    dialog:choosePathFile(mock_menu, "test_key", false, false, nil)

    local path_chooser
    for _, call in ipairs(show_spy.calls) do
      if call.refs[2] and call.refs[2].onConfirm then
        path_chooser = call.refs[2]
        break
      end
    end

    assert.is_not_nil(path_chooser)
    assert.is_not_nil(path_chooser.onConfirm)
    path_chooser.onConfirm("/tmp/selected_file.calc")

    assert.are.equal("/tmp/selected_file.calc", dialog.test_key)
    assert.are.equal(
      "/tmp/selected_file.calc",
      G_reader_settings:read("test_key")
    )
    assert.spy(mock_menu.updateItems).was.called()

    show_spy:revert()
    attr_stub:revert()
    UIManager:close(dialog)
  end)

  it(
    "should prompt for new file when choosing path directory with new_file enabled",
    function()
      local parent = createMockParent()
      local dialog = CalculatorSettingsDialog:new({ parent = parent })
      UIManager:show(dialog)
      dialog.test_key = "/tmp/old_file.calc"

      local lfs = require("libs/libkoreader-lfs")
      local attr_stub = stub(lfs, "attributes", function(path, mode_name)
        if mode_name == "mode" then
          return "directory"
        end
      end)

      local show_spy = spy.on(UIManager, "show")
      local close_spy = spy.on(UIManager, "close")
      local mock_menu = { updateItems = spy.new(function() end) }
      local migrate_spy = spy.new(function() end)

      dialog:choosePathFile(mock_menu, "test_key", false, true, migrate_spy)

      local path_chooser
      for _, call in ipairs(show_spy.calls) do
        if call.refs[2] and call.refs[2].onConfirm then
          path_chooser = call.refs[2]
          break
        end
      end

      assert.is_not_nil(path_chooser)
      assert.is_not_nil(path_chooser.onConfirm)
      path_chooser.onConfirm("/tmp/chosen_dir")

      -- Find InputDialog in UIManager:show calls
      local input_dialog
      for _, call in ipairs(show_spy.calls) do
        if call.refs[2] and call.refs[2].getInputText then
          input_dialog = call.refs[2]
          break
        end
      end

      assert.is_not_nil(input_dialog)

      -- Mock getInputText
      input_dialog.getInputText = function()
        return "/tmp/chosen_dir/new_file.calc"
      end

      -- Cancel button callback
      local cancel_cb = input_dialog.buttons[1][1].callback
      cancel_cb()
      assert.spy(close_spy).was.called()

      -- Save button callback
      local save_cb = input_dialog.buttons[1][2].callback
      save_cb()

      assert.are.equal("/tmp/chosen_dir/new_file.calc", dialog.test_key)
      assert.are.equal(
        "/tmp/chosen_dir/new_file.calc",
        G_reader_settings:read("test_key")
      )
      assert.spy(migrate_spy).was.called()
      assert.spy(mock_menu.updateItems).was.called()

      show_spy:revert()
      close_spy:revert()
      attr_stub:revert()
      UIManager:close(dialog)
    end
  )
end)
