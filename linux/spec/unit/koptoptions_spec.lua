describe("KoptOptions", function()
  local KoptOptions
  local Screen

  setup(function()
    require("commonrequire")
    KoptOptions = require("ui/data/koptoptions")
    Screen = require("device").screen
  end)

  local function findOption(name)
    for _, group in ipairs(KoptOptions) do
      if group.options then
        for _, opt in ipairs(group.options) do
          if opt.name == name then
            return opt
          end
        end
      end
    end
    return nil
  end

  it("should have valid KoptOptions structure", function()
    assert.are.equal("kopt", KoptOptions.prefix)
    assert.is_true(#KoptOptions > 0)
  end)

  it("should handle rotation_mode item_icons_func and current_func", function()
    local opt = findOption("rotation_mode")
    assert.truthy(opt)

    local orig_getRotationMode = Screen.getRotationMode
    Screen.getRotationMode = function() return Screen.DEVICE_ROTATED_UPRIGHT end
    local icons_ur = opt.item_icons_func()
    assert.are.same({ "rotation.P.90CCW", "rotation.P.0UR", "rotation.P.90CW", "rotation.P.180UD" }, icons_ur)
    assert.are.equal(Screen.DEVICE_ROTATED_UPRIGHT, opt.current_func())

    Screen.getRotationMode = function() return Screen.DEVICE_ROTATED_UPSIDE_DOWN end
    local icons_ud = opt.item_icons_func()
    assert.are.same({ "rotation.P.90CW", "rotation.P.180UD", "rotation.P.90CCW", "rotation.P.0UR" }, icons_ud)

    Screen.getRotationMode = function() return Screen.DEVICE_ROTATED_CLOCKWISE end
    local icons_cw = opt.item_icons_func()
    assert.are.same({ "rotation.L.90CCW", "rotation.L.0UR", "rotation.L.90CW", "rotation.L.180UD" }, icons_cw)

    Screen.getRotationMode = function() return Screen.DEVICE_ROTATED_COUNTER_CLOCKWISE end
    local icons_ccw = opt.item_icons_func()
    assert.are.same({ "rotation.L.90CW", "rotation.L.180UD", "rotation.L.90CCW", "rotation.L.0UR" }, icons_ccw)

    Screen.getRotationMode = orig_getRotationMode
  end)

  it("should handle zoom_range_number name_text_func, enabled_func, show_func, and show_true_value_func", function()
    local opt = findOption("zoom_range_number")
    assert.truthy(opt)

    local conf_rows = { zoom_mode_genus = 1, text_wrap = 0 }
    local conf_cols = { zoom_mode_genus = 2, text_wrap = 0 }
    local conf_other = { zoom_mode_genus = 0, text_wrap = 1 }

    assert.truthy(opt.name_text_func(conf_rows))
    assert.truthy(opt.name_text_func(conf_cols))

    assert.is_true(opt.enabled_func(conf_rows))
    assert.is_false(opt.enabled_func(conf_other))

    assert.is_true(opt.show_func(conf_rows))
    assert.is_true(opt.show_func(conf_cols))
    assert.is_false(opt.show_func(conf_other))

    assert.are.equal("2.5", opt.show_true_value_func(2.5))
  end)

  it("should handle zoom_factor show_func and enabled_func", function()
    local opt = findOption("zoom_factor")
    assert.truthy(opt)

    local conf_0 = { zoom_mode_genus = 0, text_wrap = 0 }
    local conf_1 = { zoom_mode_genus = 1, text_wrap = 0 }

    assert.is_true(opt.show_func(conf_0))
    assert.is_false(opt.show_func(conf_1))
    assert.is_true(opt.enabled_func(conf_0))
    assert.are.equal("1.5", opt.show_true_value_func(1.5))
  end)

  it("should handle font_fine_tune and word_spacing enabled_func and callbacks", function()
    local opt_ft = findOption("font_fine_tune")
    assert.truthy(opt_ft)

    assert.is_true(opt_ft.enabled_func({ text_wrap = 1 }))
    assert.is_false(opt_ft.enabled_func({ text_wrap = 0 }))

    local called_show = false
    local optionsutil = require("ui/data/optionsutil")
    local orig_show = optionsutil.showValues
    optionsutil.showValues = function(c, o, p)
      called_show = true
    end

    opt_ft.name_text_hold_callback({}, opt_ft, "kopt")
    assert.is_true(called_show)

    optionsutil.showValues = orig_show

    local opt_ws = findOption("word_spacing")
    assert.truthy(opt_ws)
    assert.is_true(opt_ws.enabled_func({ text_wrap = 1 }))
    assert.is_false(opt_ws.enabled_func({ text_wrap = 0 }))
  end)
end)
