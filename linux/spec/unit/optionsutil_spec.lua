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

  it("should format flex size string across different units and settings", function()
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
  end)

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
      show_true_value_func = function(v) return v end,
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
      name_text_func = function(cfg) return "Standard: " .. cfg.standard end,
      help_text = "Some help text",
      help_text_func = function(cfg, doc) return "Additional help info" end,
      labels = { "First", "Second" },
      values = { "val1", "val2" },
      name_text_unit = "mm",
    }
    OptionsUtil.showValues({ standard = "val1" }, opt_standard, "copt")

    -- Labels with help_text_func returning nil
    local opt_no_more_help = {
      name = "standard",
      name_text = "Standard",
      help_text_func = function() return nil end,
      labels = { "First", "Second" },
      values = { "val1", "val2" },
    }
    OptionsUtil.showValues({ standard = "val1" }, opt_no_more_help, "copt")

    -- Show_true_value_func alone with values
    G_reader_settings:save("copt_func_only", 5)
    local opt_func_only = {
      name = "func_only",
      name_text = "Func Only",
      show_true_value_func = function(v) return "Val: " .. tostring(v) end,
      values = { 5, 10 },
    }
    OptionsUtil.showValues({ func_only = 10 }, opt_func_only, "copt")

    G_reader_settings:save("copt_shifted", nil)
    G_reader_settings:save("copt_standard", nil)
    G_reader_settings:save("copt_func_only", nil)
  end)

  it("should show values and margin information dialogs with and without defaults", function()
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
  end)

  it("should generate and retrieve option text by event, value, and args", function()
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
    assert.are.equal("Second", OptionsUtil:getOptionText("CustomEvent", "arg2"))

    -- Fallback when text not matched
    assert.are.equal("unmatched", OptionsUtil:getOptionText("CustomEvent", "unmatched"))
  end)
end)
