describe("OptionsUtil module", function()
  local OptionsUtil, UIManager

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    OptionsUtil = require("ui/data/optionsutil")
    UIManager = require("ui/uimanager")
  end)

  it("should expose optionsutil table and rotation constants", function()
    assert.is_table(OptionsUtil)
    assert.is_table(OptionsUtil.rotation_labels)
    assert.is_table(OptionsUtil.rotation_modes)
    assert.is_same(4, #OptionsUtil.rotation_labels)
  end)

  it("should evaluate enableIfEquals correctly", function()
    local configurable = { option1 = "val1", option2 = "val2" }
    assert.is_true(OptionsUtil.enableIfEquals(configurable, "option1", "val1"))
    assert.is_false(OptionsUtil.enableIfEquals(configurable, "option1", "val2"))
  end)

  it(
    "should format flex size string across different units and settings",
    function()
      assert.are.equal("", OptionsUtil.formatFlexSize(nil))
      assert.are.equal("auto", OptionsUtil.formatFlexSize("auto"))
      assert.is_string(OptionsUtil.formatFlexSize(12, nil))

      local formatted_pt = OptionsUtil.formatFlexSize(12, "pt")
      assert.is_string(formatted_pt)

      local formatted_mm = OptionsUtil.formatFlexSize(10, "mm")
      assert.is_string(formatted_mm)

      local formatted_in = OptionsUtil.formatFlexSize(2, "in")
      assert.is_string(formatted_in)

      local formatted_px = OptionsUtil.formatFlexSize(100, "px")
      assert.is_string(formatted_px)

      local formatted_custom = OptionsUtil.formatFlexSize(10, "cm")
      assert.is_string(formatted_custom)

      -- Test with dimension_units_append_px enabled
      G_reader_settings:save("dimension_units_append_px", true)
      local formatted_append_pt = OptionsUtil.formatFlexSize(12, "pt")
      assert.is_true(formatted_append_pt:find("%[") ~= nil)
      local formatted_append_px = OptionsUtil.formatFlexSize(100, "px")
      assert.is_true(formatted_append_px:find("%[") == nil)
      G_reader_settings:save("dimension_units_append_px", nil)

      -- Nil unit falls back to G_named_settings.dimension_units
      local fallback = OptionsUtil.formatFlexSize(15)
      assert.is_string(fallback)
    end
  )

  it("should handle showValues for toggle and values combinations", function()
    -- Toggle with table values & current table
    G_reader_settings:save("copt_margins", { 30, 30 })
    local opt_toggle_table = {
      name = "margins",
      name_text = "Margins",
      toggle = { "Small", "Large" },
      values = { { 10, 10 }, { 30, 30 } },
    }
    OptionsUtil.showValues({ margins = { 10, 10 } }, opt_toggle_table, "copt")

    -- Toggle with custom fallback when name_text_true_values is true
    G_reader_settings:save("copt_custom_val", 99)
    local opt_custom = {
      name = "custom_val",
      name_text = "Custom Val",
      name_text_true_values = true,
      toggle = { "One", "Two" },
      values = { 1, 2 },
      show_true_value_func = function(v)
        return v
      end,
    }
    OptionsUtil.showValues({ custom_val = 50 }, opt_custom, "copt")

    -- Toggle with custom fallback when name_text_true_values is false/nil
    local opt_custom_no_true = {
      name = "custom_val",
      name_text = "Custom Val",
      toggle = { "One", "Two" },
      values = { 1, 2 },
    }
    OptionsUtil.showValues({ custom_val = 50 }, opt_custom_no_true, "copt")

    -- Name_text_true_values formatting variants
    G_reader_settings:save("copt_size_num", 14)
    local opt_num_with_default = {
      name = "size_num",
      name_text = "Size Num",
      name_text_true_values = true,
      toggle = { "Small", "Medium" },
      values = { 10, 14 },
    }
    OptionsUtil.showValues({ size_num = 12 }, opt_num_with_default, "copt")

    G_reader_settings:save("copt_size_no_def", nil)
    local opt_num_no_default = {
      name = "size_no_def",
      name_text = "Size No Def",
      name_text_true_values = true,
      toggle = { "Small", "Medium" },
      values = { 10, 14 },
    }
    OptionsUtil.showValues({ size_no_def = 12 }, opt_num_no_default, "copt")

    G_reader_settings:save("copt_margins", nil)
    G_reader_settings:save("copt_custom_val", nil)
    G_reader_settings:save("copt_size_num", nil)
  end)

  it("should handle showValues for labels and values combinations", function()
    -- Labels with more_options_param.value_table
    G_reader_settings:save("copt_shifted", 1)
    local opt_shifted = {
      name = "shifted",
      name_text = "Shifted Option",
      labels = { "A", "B", "C" },
      values = { 0, 1, 2 },
      more_options_param = {
        value_table = { [1] = "Label1", [2] = "Label2", [3] = "Label3" },
        value_table_shift = 1,
      },
    }
    OptionsUtil.showValues({ shifted = 0 }, opt_shifted, "copt")

    -- Labels standard matching
    G_reader_settings:save("copt_standard", "val2")
    local opt_standard = {
      name = "standard",
      name_text_func = function(cfg)
        return "Standard: " .. cfg.standard
      end,
      help_text = "Some help text",
      help_text_func = function(cfg, doc)
        return "Additional help info"
      end,
      labels = { "First", "Second" },
      values = { "val1", "val2" },
      name_text_unit = "mm",
    }
    OptionsUtil.showValues({ standard = "val1" }, opt_standard, "copt")

    -- Labels with help_text_func returning nil
    local opt_no_more_help = {
      name = "standard",
      name_text = "Standard",
      help_text_func = function()
        return nil
      end,
      labels = { "First", "Second" },
      values = { "val1", "val2" },
    }
    OptionsUtil.showValues({ standard = "val1" }, opt_no_more_help, "copt")

    -- Show_true_value_func alone with values
    G_reader_settings:save("copt_func_only", 5)
    local opt_func_only = {
      name = "func_only",
      name_text = "Func Only",
      show_true_value_func = function(v)
        return "Val: " .. tostring(v)
      end,
      values = { 5, 10 },
    }
    OptionsUtil.showValues({ func_only = 10 }, opt_func_only, "copt")

    G_reader_settings:save("copt_shifted", nil)
    G_reader_settings:save("copt_standard", nil)
    G_reader_settings:save("copt_func_only", nil)
  end)

  it(
    "should show values and margin information dialogs with and without defaults",
    function()
      local configurable = {
        margin = { 10, 10 },
      }
      local margin_option = {
        name = "margin",
      }

      -- Without default
      G_reader_settings:save("copt_margin", nil)
      OptionsUtil.showValuesHMargins(configurable, margin_option)

      -- With default
      G_reader_settings:save("copt_margin", { 15, 20 })
      OptionsUtil.showValuesHMargins(configurable, margin_option)
      G_reader_settings:save("copt_margin", nil)
    end
  )

  it(
    "should generate and retrieve option text by event, value, and args",
    function()
      OptionsUtil.option_text_table = nil
      OptionsUtil.option_args_table = nil

      -- Auto generates option_text_table
      local text_rot = OptionsUtil:getOptionText("SetRotationMode", 0)
      assert.is_string(text_rot)

      -- Invalid / nil inputs
      assert.are.equal("", OptionsUtil:getOptionText(nil, 1))
      assert.are.equal("", OptionsUtil:getOptionText("SetRotationMode", nil))
      assert.are.equal("", OptionsUtil:getOptionText("NonExistentEvent", 1))

      -- Text lookup with args table
      OptionsUtil.option_text_table["CustomEvent"] = { "First", "Second" }
      OptionsUtil.option_args_table["CustomEvent"] = { "arg1", "arg2" }
      assert.are.equal(
        "Second",
        OptionsUtil:getOptionText("CustomEvent", "arg2")
      )

      -- Fallback when text not matched
      assert.are.equal(
        "unmatched",
        OptionsUtil:getOptionText("CustomEvent", "unmatched")
      )
    end
  )

  it(
    "should index options by name and attach Option methods in initOptions",
    function()
      local opt_a = { name = "opt_a", values = { 1, 2 } }
      local opt_b = { name = "opt_b", values = { "x", "y" } }
      local config_options = {
        prefix = "test",
        { options = { opt_a } },
        { options = { opt_b } },
      }

      assert.is_nil(OptionsUtil.initOptions(config_options))
      assert.are.equal(opt_a, config_options.opt_a)
      assert.are.equal(opt_b, config_options.opt_b)
      assert.are.equal("test", opt_a.prefix)
      assert.are.equal("test", opt_b.prefix)
      assert.is_function(opt_a.checkedPosition)
      assert.is_function(opt_a.apply)
      assert.is_function(opt_a.showDefaultConfirmBox)

      -- Non-idempotent: re-initializing fails
      assert.has.errors(function()
        OptionsUtil.initOptions(config_options)
      end)

      assert.has.errors(function()
        OptionsUtil.initOptions({ { options = { { name = "a" } } } })
      end)
      assert.has.errors(function()
        OptionsUtil.initOptions({
          prefix = "",
          { options = { { name = "a" } } },
        })
      end)
      assert.has.errors(function()
        OptionsUtil.initOptions({
          prefix = "p",
          { options = { { name = "" } } },
        })
      end)
      assert.has.errors(function()
        OptionsUtil.initOptions({
          prefix = "p",
          { options = { { name = "dup" }, { name = "dup" } } },
        })
      end)
      assert.has.errors(function()
        OptionsUtil.initOptions({
          prefix = "p",
          { options = { { name = "prefix" } } },
        })
      end)
      assert.has.errors(function()
        OptionsUtil.initOptions({
          prefix = "p",
          { options = { { name = "a", prefix = "existing" } } },
        })
      end)
      assert.has.errors(function()
        OptionsUtil.initOptions({
          prefix = "p",
          { options = { setmetatable({ name = "a" }, {}) } },
        })
      end)
    end
  )

  it("should find value position via option:checkedPosition", function()
    local config_options = {
      prefix = "test",
      {
        options = {
          { name = "bad" },
          { name = "status_line", values = { 1, 0 } },
          { name = "multi", values = { "low", false, "med", "high" } },
        },
      },
    }
    OptionsUtil.initOptions(config_options)

    assert.are.equal(
      1,
      config_options.status_line:checkedPosition({ status_line = 1 })
    )
    assert.are.equal(
      2,
      config_options.status_line:checkedPosition({ status_line = 0 })
    )
    assert.are.equal(1, config_options.multi:checkedPosition({ multi = "low" }))
    assert.are.equal(2, config_options.multi:checkedPosition({ multi = false }))
    assert.are.equal(3, config_options.multi:checkedPosition({ multi = "med" }))
    assert.are.equal(
      4,
      config_options.multi:checkedPosition({ multi = "high" })
    )

    assert.has.errors(function()
      config_options.bad:checkedPosition({})
    end)
    assert.has.errors(function()
      config_options.status_line:checkedPosition({})
    end)
    assert.has.errors(function()
      config_options.status_line:checkedPosition({ status_line = 2 })
    end)
    assert.has.errors(function()
      config_options.multi:checkedPosition({ multi = "unknown" })
    end)
  end)

  it("should broadcast events via option:apply", function()
    local events = {}
    local orig_broadcast = UIManager.broadcastEvent
    UIManager.broadcastEvent = function(_self, ev)
      table.insert(events, ev)
    end
    finally(function()
      UIManager.broadcastEvent = orig_broadcast
    end)

    local config_options = {
      prefix = "test",
      {
        options = {
          {
            name = "test_opt",
            values = { "off_val", "on_val" },
            event = "SetTestOpt",
            args = { false, true },
          },
          {
            name = "event_only",
            event = "TriggerOnly",
          },
        },
      },
    }
    OptionsUtil.initOptions(config_options)

    local applied_cb = function() end
    config_options.test_opt:apply(2, applied_cb)

    assert.are.equal(2, #events)
    assert.are.equal("onConfigChange", events[1].handler)
    assert.are.equal("test_opt", events[1].args[1])
    assert.are.equal("on_val", events[1].args[2])
    assert.are.equal("onSetTestOpt", events[2].handler)
    assert.are.equal(true, events[2].args[1])
    assert.are.equal(applied_cb, events[2].args[2])

    config_options.event_only:apply(1)
    assert.are.equal(3, #events)
    assert.are.equal("onTriggerOnly", events[3].handler)
    assert.is_nil(events[3].args[1])
  end)

  it(
    "should show default confirm box via option:showDefaultConfirmBox",
    function()
      local gettext = require("gettext")
      local T = require("ffi/util").template
      local shown_widgets = {}
      local mock_owner = {
        configurable = { flag = true },
        document = { doc_id = 1 },
        showWidget = function(_self, widget)
          table.insert(shown_widgets, widget)
        end,
      }
      local confirmed = false
      finally(function()
        G_reader_settings:delete("test_test_toggle_opt")
        G_reader_settings:delete("test_h_page_margins")
        G_reader_settings:delete("test_alt_opt")
        G_reader_settings:delete("test_dyn_opt")
      end)

      local config_options = {
        prefix = "test",
        {
          options = {
            {
              name = "test_toggle_opt",
              name_text = gettext("Test Toggle"),
              toggle = { gettext("off"), gettext("on") },
              values = { 1, 0 },
              args = { false, true },
            },
            {
              name = "h_page_margins",
              values = { { 10, 10 }, { 20, 20 } },
            },
            {
              name = "alt_opt",
              alt_name_text = gettext("Alt Name"),
              args = { "a", "b" },
            },
            {
              name = "dyn_opt",
              name_text_func = function(cfg, doc)
                return cfg.flag and doc.doc_id == 1 and gettext("Dynamic Opt")
                  or ""
              end,
              values = { { 1, 2 }, { 3, 4 } },
            },
          },
        },
      }
      OptionsUtil.initOptions(config_options)

      config_options.test_toggle_opt:showDefaultConfirmBox(
        mock_owner,
        2,
        function()
          confirmed = true
        end
      )
      assert.are.equal(1, #shown_widgets)
      assert.are.equal(
        T(
          gettext("Set default %1 to %2?"),
          config_options.test_toggle_opt.name_text,
          gettext("on")
        ),
        shown_widgets[1].text
      )
      assert.are.equal(gettext("Set as default"), shown_widgets[1].ok_text)
      shown_widgets[1].ok_callback()
      assert.are.equal(0, G_reader_settings:read("test_test_toggle_opt"))
      assert.is_true(confirmed)

      config_options.h_page_margins:showDefaultConfirmBox(mock_owner, 2)
      assert.are.equal(2, #shown_widgets)
      shown_widgets[2].ok_callback()
      assert.is_same({ 20, 20 }, G_reader_settings:read("test_h_page_margins"))

      config_options.alt_opt:showDefaultConfirmBox(mock_owner, 2)
      assert.are.equal(3, #shown_widgets)
      assert.are.equal(
        T(gettext("Set default %1 to %2?"), gettext("Alt Name"), "b"),
        shown_widgets[3].text
      )
      shown_widgets[3].ok_callback()
      assert.are.equal("b", G_reader_settings:read("test_alt_opt"))

      config_options.dyn_opt:showDefaultConfirmBox(mock_owner, 1)
      assert.are.equal(4, #shown_widgets)
      assert.are.is_truthy(
        shown_widgets[4].text:find(gettext("Dynamic Opt"), 1, true)
      )
      shown_widgets[4].ok_callback()
      assert.is_same({ 1, 2 }, G_reader_settings:read("test_dyn_opt"))

      config_options.test_toggle_opt:showDefaultConfirmBox(mock_owner, 1)
      assert.are.equal(5, #shown_widgets)
      shown_widgets[5].ok_callback()
      assert.are.equal(1, G_reader_settings:read("test_test_toggle_opt"))
    end
  )
end)
