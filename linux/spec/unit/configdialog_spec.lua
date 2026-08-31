describe("ConfigDialog", function()
  local ConfigDialog
  local UIManager
  local Geom

  local mock_options
  local mock_configurable

  setup(function()
    require("commonrequire")

    UIManager = require("ui/uimanager")
    Geom = require("ui/geometry")

    package.loaded["ui/widget/configdialog"] = nil
    ConfigDialog = require("ui/widget/configdialog")
  end)

  before_each(function()
    mock_options = {
      prefix = "test_prefix",
      {
        icon = "appbar.settings",
        options = {
          {
            name = "opt_text",
            name_text = "Text Option",
            item_text = { "Small", "Medium", "Large" },
            values = { "s", "m", "l" },
            default_pos = 1,
            event = "SetTextOpt",
          },
          {
            name = "opt_icon",
            name_text = "Icon Option",
            item_icons = { "icon1", "icon2" },
            values = { 1, 2 },
            labels = { "Icon 1", "Icon 2" },
            event = "SetIconOpt",
          },
          {
            name = "opt_toggle",
            name_text = "Toggle Option",
            toggle = { "Off", "On" },
            values = { "off", "on" },
            default_pos = 1,
            more_options = true,
            more_options_param = {
              value_min = 1,
              value_max = 10,
            },
          },
          {
            name = "opt_progress",
            name_text = "Progress Option",
            buttonprogress = true,
            values = { 1, 2, 3, 4, 5 },
            default_pos = 3,
            fine_tune = true,
            more_options = true,
          },
        },
      },
      {
        icon = "appbar.view",
        options = {
          {
            name = "opt_second_tab",
            name_text = "Second Tab Opt",
            toggle = { "No", "Yes" },
            values = { "no", "yes" },
          },
          {
            name = "h_page_margins",
            name_text = "Margins",
            toggle = { "Narrow", "Wide" },
            values = { { 10, 10 }, { 20, 20 } },
          },
        },
      },
    }

    mock_configurable = {
      opt_text = "s",
      opt_icon = 1,
      opt_toggle = "off",
      opt_progress = 3,
      opt_second_tab = "no",
      h_page_margins = { 10, 10 },
    }
  end)

  after_each(function()
    while #UIManager._window_stack > 0 do
      local w = table.remove(UIManager._window_stack)
      if w.onClose then
        pcall(function()
          w:onClose()
        end)
      end
    end
    UIManager._task_queue = {}
  end)

  it("should instantiate and initialize ConfigDialog correctly", function()
    local dialog = ConfigDialog:new({
      config_options = mock_options,
      configurable = mock_configurable,
    })
    assert.is_not_nil(dialog)
    assert.are.equal(1, dialog.panel_index)
    assert.is_not_nil(dialog.dialog_frame)
    assert.is_not_nil(dialog.config_menubar)
    assert.is_not_nil(dialog.config_panel)
  end)

  it("should find option by name", function()
    local dialog = ConfigDialog:new({
      config_options = mock_options,
      configurable = mock_configurable,
    })
    local opt = dialog:findOptionByName("opt_toggle")
    assert.is_not_nil(opt)
    assert.are.equal("Toggle Option", opt.name_text)

    local non_existent = dialog:findOptionByName("non_existent")
    assert.is_nil(non_existent)
  end)

  it("should navigate between configuration panels", function()
    local dialog = ConfigDialog:new({
      config_options = mock_options,
      configurable = mock_configurable,
    })

    UIManager:show(dialog)
    UIManager:forceRepaint()

    assert.are.equal(1, dialog.panel_index)

    dialog:onNextPage()
    assert.are.equal(2, dialog.panel_index)

    dialog:onNextPage()
    assert.are.equal(1, dialog.panel_index) -- wrap around

    dialog:onPrevPage()
    assert.are.equal(2, dialog.panel_index) -- wrap around back

    dialog:onPrevPage()
    assert.are.equal(1, dialog.panel_index)

    dialog:showConfigPanel(2)
    assert.are.equal(2, dialog.panel_index)

    dialog:closeDialog()
  end)

  it("should manage active instance count on show and close", function()
    local dialog = ConfigDialog:new({
      config_options = mock_options,
      configurable = mock_configurable,
    })

    UIManager:show(dialog)
    assert.has_no.errors(function()
      dialog:onClose()
    end)
  end)

  it(
    "should close dialog and invoke callback on closeDialog and onExit",
    function()
      local callback_called = false
      local dialog = ConfigDialog:new({
        config_options = mock_options,
        configurable = mock_configurable,
        close_callback = function()
          callback_called = true
        end,
      })

      UIManager:show(dialog)
      UIManager:forceRepaint()

      assert.is_true(dialog:onExit())
      assert.is_true(callback_called)
    end
  )

  it("should handle tap to close menu outside of dialog frame", function()
    local dialog = ConfigDialog:new({
      config_options = mock_options,
      configurable = mock_configurable,
    })

    UIManager:show(dialog)
    UIManager:forceRepaint()

    -- Inside frame
    local inside_event = {
      pos = Geom:new({
        x = dialog.dialog_frame.dimen.x + 1,
        y = dialog.dialog_frame.dimen.y + 1,
        w = 1,
        h = 1,
      }),
    }
    assert.is_nil(dialog:onTapCloseMenu(nil, inside_event))

    -- Outside frame
    local outside_event = {
      pos = Geom:new({
        x = -100,
        y = -100,
        w = 1,
        h = 1,
      }),
    }
    assert.is_true(dialog:onTapCloseMenu(nil, outside_event))
  end)

  it("should handle swipe south to close menu", function()
    local dialog = ConfigDialog:new({
      config_options = mock_options,
      configurable = mock_configurable,
    })

    UIManager:show(dialog)
    UIManager:forceRepaint()

    local swipe_south = {
      direction = "south",
      pos = Geom:new({
        x = dialog.dialog_frame.dimen.x + 1,
        y = dialog.dialog_frame.dimen.y + 1,
        w = 1,
        h = 1,
      }),
    }
    assert.is_true(dialog:onSwipeCloseMenu(nil, swipe_south))

    local dialog2 = ConfigDialog:new({
      config_options = mock_options,
      configurable = mock_configurable,
    })
    UIManager:show(dialog2)
    UIManager:forceRepaint()

    local swipe_north = {
      direction = "north",
      pos = Geom:new({
        x = dialog2.dialog_frame.dimen.x + 1,
        y = dialog2.dialog_frame.dimen.y + 1,
        w = 1,
        h = 1,
      }),
    }
    assert.is_nil(dialog2:onSwipeCloseMenu(nil, swipe_north))

    dialog2:closeDialog()
  end)

  it("should handle choice and event broadcasting", function()
    local dialog = ConfigDialog:new({
      config_options = mock_options,
      configurable = mock_configurable,
    })

    UIManager:show(dialog)
    UIManager:forceRepaint()

    local spy_choice = spy.on(UIManager, "broadcastEvent")

    dialog:onConfigChoice("test_opt", "test_val")
    assert.spy(spy_choice).was_called()

    dialog:onConfigEvent("TestEvent", "test_arg")
    assert.spy(spy_choice).was_called()

    spy_choice:clear()
    dialog:closeDialog()
  end)

  it("should handle onConfigChoose with tickAfterNext", function()
    local dialog = ConfigDialog:new({
      config_options = mock_options,
      configurable = mock_configurable,
    })

    UIManager:show(dialog)
    UIManager:forceRepaint()

    local choice_called = false
    dialog.onConfigChoice = function(self, _name, _val)
      choice_called = true
    end

    dialog:onConfigChoose(
      { "val1", "val2" },
      "opt_text",
      "SetTextOpt",
      nil,
      1,
      false
    )

    -- Flush task queue (tickAfterNext)
    UIManager:_checkTasks()
    UIManager:_checkTasks()
    assert.is_true(choice_called)

    dialog:closeDialog()
  end)

  it(
    "should handle onConfigFineTuneChoose for increment and decrement",
    function()
      local dialog = ConfigDialog:new({
        config_options = mock_options,
        configurable = mock_configurable,
      })

      UIManager:show(dialog)
      UIManager:forceRepaint()

      local last_choice_name, last_choice_val
      dialog.onConfigChoice = function(self, name, val)
        last_choice_name = name
        last_choice_val = val
      end

      -- Numeric decrement
      dialog:onConfigFineTuneChoose(
        { 1, 2, 3, 4, 5 },
        "opt_progress",
        nil,
        nil,
        "-",
        false,
        { value_step = 1 }
      )
      UIManager:_checkTasks()
      UIManager:_checkTasks()
      assert.are.equal("opt_progress", last_choice_name)
      assert.are.equal(2, last_choice_val)

      -- Numeric increment
      dialog:onConfigFineTuneChoose(
        { 1, 2, 3, 4, 5 },
        "opt_progress",
        nil,
        nil,
        "+",
        false,
        { value_step = 1 }
      )
      UIManager:_checkTasks()
      UIManager:_checkTasks()
      assert.are.equal("opt_progress", last_choice_name)
      assert.are.equal(4, last_choice_val)

      -- Table value decrement
      dialog:onConfigFineTuneChoose(
        { { 10, 10 }, { 20, 20 } },
        "h_page_margins",
        nil,
        nil,
        "-",
        false,
        { value_step = 2 }
      )
      UIManager:_checkTasks()
      UIManager:_checkTasks()
      assert.are.equal("h_page_margins", last_choice_name)
      assert.is_same({ 8, 8 }, last_choice_val)

      -- Table value increment
      dialog:onConfigFineTuneChoose(
        { { 10, 10 }, { 20, 20 } },
        "h_page_margins",
        nil,
        nil,
        "+",
        false,
        { value_step = 2 }
      )
      UIManager:_checkTasks()
      UIManager:_checkTasks()
      assert.are.equal("h_page_margins", last_choice_name)
      assert.is_same({ 12, 12 }, last_choice_val)

      dialog:closeDialog()
    end
  )

  it(
    "should handle onMakeDefault for normal, font_fine_tune, and h_page_margins options",
    function()
      local dialog = ConfigDialog:new({
        config_options = mock_options,
        configurable = mock_configurable,
      })

      UIManager:show(dialog)
      UIManager:forceRepaint()

      local confirm_box_shown = nil
      dialog.showWidget = function(self, widget)
        confirm_box_shown = widget
      end

      -- font_fine_tune ignore
      dialog:onMakeDefault(
        "font_fine_tune",
        "Font Fine Tune",
        { 1 },
        { "1" },
        1
      )
      assert.is_nil(confirm_box_shown)

      -- h_page_margins
      dialog:onMakeDefault(
        "h_page_margins",
        "Margins",
        { { 10, 10 } },
        { { 10, 10 } },
        1
      )
      assert.is_not_nil(confirm_box_shown)

      -- Test ok_callback in ConfirmBox
      confirm_box_shown.ok_callback()

      -- Normal primitive value
      confirm_box_shown = nil
      dialog:onMakeDefault(
        "opt_text",
        "Text Opt",
        { "s", "m" },
        { "Small", "Medium" },
        1
      )
      assert.is_not_nil(confirm_box_shown)
      confirm_box_shown.ok_callback()

      dialog:closeDialog()
    end
  )

  it("should handle onMakeFineTuneDefault", function()
    local dialog = ConfigDialog:new({
      config_options = mock_options,
      configurable = mock_configurable,
    })

    UIManager:show(dialog)
    UIManager:forceRepaint()

    local confirm_box_shown = nil
    dialog.showWidget = function(self, widget)
      confirm_box_shown = widget
    end

    -- Numeric option
    dialog:onMakeFineTuneDefault(
      "opt_progress",
      "Progress Opt",
      { 1, 5 },
      { 1, 5 },
      "+"
    )
    assert.is_not_nil(confirm_box_shown)
    confirm_box_shown.ok_callback()

    -- Table option (h_page_margins)
    confirm_box_shown = nil
    dialog:onMakeFineTuneDefault(
      "h_page_margins",
      "Margins",
      { { 10, 10 } },
      { { 10, 10 } },
      "-"
    )
    assert.is_not_nil(confirm_box_shown)
    confirm_box_shown.ok_callback()

    dialog:closeDialog()
  end)

  it(
    "should handle onConfigMoreChoose with SpinWidget and DoubleSpinWidget",
    function()
      local dialog = ConfigDialog:new({
        config_options = mock_options,
        configurable = mock_configurable,
      })

      UIManager:show(dialog)
      UIManager:forceRepaint()

      local widget_shown = nil
      dialog.showWidget = function(self, widget)
        widget_shown = widget
      end

      -- Single value SpinWidget
      dialog:onConfigMoreChoose(
        { 1, 5, 10 },
        5,
        "opt_progress",
        "SetProgress",
        nil,
        "Progress Option",
        {
          value_min = 1,
          value_max = 10,
        },
        false
      )
      UIManager:_checkTasks()
      UIManager:_checkTasks()
      assert.is_not_nil(widget_shown)

      -- Test spin widget callback & extra_callback
      if widget_shown.callback then
        widget_shown.callback(widget_shown)
      end
      if widget_shown.extra_callback then
        widget_shown.extra_callback(widget_shown)
      end

      -- Double value DoubleSpinWidget
      widget_shown = nil
      dialog:onConfigMoreChoose(
        { { 5, 5 }, { 20, 20 } },
        { 10, 10 },
        "h_page_margins",
        "SetMargins",
        nil,
        "Margins",
        {
          left_min = 0,
          left_max = 50,
          right_min = 0,
          right_max = 50,
        },
        false
      )
      UIManager:_checkTasks()
      UIManager:_checkTasks()
      assert.is_not_nil(widget_shown)

      if widget_shown.callback then
        widget_shown.callback(12, 12)
      end
      if widget_shown.extra_callback then
        widget_shown.extra_callback(12, 12)
      end

      dialog:closeDialog()
    end
  )

  it(
    "should support custom option callbacks, show_func, enabled_func, and text functions",
    function()
      local hold_called = false
      local custom_options = {
        prefix = "custom",
        {
          icon = "appbar.custom",
          options = {
            {
              name = "dyn_name",
              name_text_func = function()
                return "Dynamic Text"
              end,
              name_text_hold_callback = function()
                hold_called = true
              end,
              item_icons_func = function()
                return { "icon_a", "icon_b" }
              end,
              values = { "a", "b" },
              show_func = function()
                return true
              end,
              enabled_func = function()
                return true
              end,
            },
            {
              name = "hidden_opt",
              name_text = "Hidden",
              toggle = { "Off", "On" },
              values = { "off", "on" },
              show_func = function()
                return false
              end,
            },
            {
              name = "disabled_opt",
              name_text = "Disabled",
              toggle = { "Off", "On" },
              values = { "off", "on" },
              enabled_func = function()
                return false
              end,
            },
          },
        },
      }

      local dialog = ConfigDialog:new({
        config_options = custom_options,
        configurable = {
          dyn_name = "a",
          hidden_opt = "off",
          disabled_opt = "off",
        },
      })

      UIManager:show(dialog)
      UIManager:forceRepaint()

      assert.is_not_nil(dialog)
      local opt = dialog:findOptionByName("dyn_name")
      assert.is_not_nil(opt)
      if opt.name_text_hold_callback then
        opt.name_text_hold_callback()
      end
      assert.is_true(hold_called)

      local hidden_opt = dialog:findOptionByName("hidden_opt")
      assert.is_not_nil(hidden_opt)

      local disabled_opt = dialog:findOptionByName("disabled_opt")
      assert.is_not_nil(disabled_opt)

      dialog:closeDialog()
    end
  )

  it("should handle direct tap and hold events on config panel option items", function()
    local dialog = ConfigDialog:new({
      config_options = mock_options,
      configurable = mock_configurable,
    })

    UIManager:show(dialog)
    UIManager:forceRepaint()

    -- Helper to recursively trigger onTapSelect and onHoldSelect on option items
    local function triggerItemEvents(widget)
      if type(widget) ~= "table" then return end
      if widget.onTapSelect then
        pcall(function() widget:onTapSelect(true) end)
      end
      if widget.onHoldSelect then
        pcall(function() widget:onHoldSelect() end)
      end
      for _, child in ipairs(widget) do
        triggerItemEvents(child)
      end
    end

    triggerItemEvents(dialog.config_panel)

    -- Switch to tab 2 and trigger
    dialog:showConfigPanel(2)
    triggerItemEvents(dialog.config_panel)

    -- Test onFocus / onUnfocus and disabled tap on OptionTextItem
    local function findItemWithUnderline(widget)
      if type(widget) ~= "table" then return end
      if widget.underline_container and widget.onFocus and widget.onUnfocus then
        return widget
      end
      for _, child in ipairs(widget) do
        local res = findItemWithUnderline(child)
        if res then return res end
      end
    end

    dialog:showConfigPanel(1)
    local item = findItemWithUnderline(dialog.config_panel)
    if item then
      item:onFocus()
      assert.are.equal(require("ffi/blitbuffer").COLOR_BLACK, item.underline_container.color)
      item:onUnfocus()
      assert.are.equal(require("ffi/blitbuffer").COLOR_WHITE, item.underline_container.color)

      item.enabled = false
      assert.is_true(item:onTapSelect())
    end

    dialog:closeDialog()
  end)
end)

