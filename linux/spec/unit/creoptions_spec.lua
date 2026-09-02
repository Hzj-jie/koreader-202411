describe("CreOptions", function()
  local CreOptions
  local Screen
  local credocument

  setup(function()
    require("commonrequire")
    CreOptions = require("ui/data/creoptions")
    Screen = require("device").screen
    credocument = require("document/credocument")
  end)

  local function findOption(name)
    for _, group in ipairs(CreOptions) do
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

  it("should have valid CreOptions structure", function()
    assert.are.equal("copt", CreOptions.prefix)
    assert.is_true(#CreOptions > 0)
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

  it("should handle visible_pages enabled_func", function()
    local opt = findOption("visible_pages")
    assert.truthy(opt)

    local mock_config = {
      view_mode = 0,
    }
    assert.is_true(opt.enabled_func(mock_config))

    mock_config.view_mode = 1
    assert.is_false(opt.enabled_func(mock_config))
  end)

  it("should handle show_true_value_func for various options", function()
    local opt_dpi = findOption("screen_dpi")
    if opt_dpi and opt_dpi.show_true_value_func then
      assert.truthy(opt_dpi.show_true_value_func(96))
      assert.truthy(opt_dpi.show_true_value_func(300))
      assert.are.equal("off", opt_dpi.show_true_value_func(0))
    end

    local opt_ls = findOption("line_spacing")
    if opt_ls and opt_ls.show_true_value_func then
      assert.truthy(opt_ls.show_true_value_func(100))
    end

    local opt_ws = findOption("word_spacing")
    if opt_ws and opt_ws.show_true_value_func then
      assert.truthy(opt_ws.show_true_value_func({ 100, 80 }))
    end

    local opt_we = findOption("word_expansion")
    if opt_we and opt_we.show_true_value_func then
      assert.truthy(opt_we.show_true_value_func(10))
    end

    local opt_fw = findOption("font_weight_class")
    if opt_fw and opt_fw.show_true_value_func then
      assert.truthy(opt_fw.show_true_value_func(0)) -- 400 = Regular
      assert.truthy(opt_fw.show_true_value_func(3)) -- 700 = Bold
      assert.truthy(opt_fw.show_true_value_func(0.5)) -- 450 = 450
    end
  end)

  it("should handle font_fine_tune name_text_hold_callback", function()
    local opt = findOption("font_fine_tune")
    assert.truthy(opt)
    local called_show = false
    local optionsutil = require("ui/data/optionsutil")
    local orig_show = optionsutil.showValues
    optionsutil.showValues = function(c, o, p)
      called_show = true
    end

    opt.name_text_hold_callback({}, opt, "copt")
    assert.is_true(called_show)

    optionsutil.showValues = orig_show
  end)

  it("should handle font_base_weight help_text_func", function()
    local opt = findOption("font_base_weight")
    assert.truthy(opt)

    local orig_init = credocument.engineInit
    credocument.engineInit = function()
      return {
        getFontFaceAvailableWeights = function(face)
          return { 400, 700 }
        end,
      }
    end

    local mock_doc = {
      getFontFace = function() return "Noto Serif" end,
    }

    local text = opt.help_text_func({}, mock_doc)
    assert.truthy(text)
    assert.truthy(text:find("Noto Serif"))

    credocument.engineInit = orig_init
  end)

  it("should handle embedded_fonts enabled_func and help_text_func", function()
    local opt = findOption("embedded_fonts")
    assert.truthy(opt)

    local mock_config = { embedded_css = 1 }
    local mock_doc_empty = {
      getEmbeddedFontList = function() return {} end,
    }
    local mock_doc_with_fonts = {
      getEmbeddedFontList = function()
        return {
          ["CustomFont-Regular"] = true,
          ["CustomFont-Italic"] = false,
        }
      end,
    }

    assert.is_falsy(opt.enabled_func(mock_config, mock_doc_empty))
    assert.is_true(opt.enabled_func(mock_config, mock_doc_with_fonts))

    assert.is_nil(opt.help_text_func({}, mock_doc_empty))
    local help_txt = opt.help_text_func({}, mock_doc_with_fonts)
    assert.truthy(help_txt)
    assert.truthy(help_txt:find("CustomFont%-Regular"))
    assert.truthy(help_txt:find("CustomFont%-Italic"))
  end)

  it("should handle nightmode_images show_func", function()
    local opt = findOption("nightmode_images")
    assert.truthy(opt)

    Screen.night_mode = true
    assert.is_true(opt.show_func())

    Screen.night_mode = false
    assert.is_false(opt.show_func())
  end)
end)
