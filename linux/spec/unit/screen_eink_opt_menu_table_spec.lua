describe("Screen Eink Opt Menu Table Spec", function()
  local EinkSettingsTable
  local Device

  setup(function()
    require("commonrequire")
    Device = require("device")
    EinkSettingsTable = require("ui/elements/screen_eink_opt_menu_table")
  end)

  it("should provide eink settings menu structure", function()
    assert.is_table(EinkSettingsTable)
    assert.is_string(EinkSettingsTable.text)
    assert.is_table(EinkSettingsTable.sub_item_table)
  end)

  it("should handle low_pan_rate and avoid_flashing_ui options", function()
    for _, item in ipairs(EinkSettingsTable.sub_item_table) do
      if item.callback then
        item.callback()
      end
      if item.checked_func then
        assert.is_boolean(item.checked_func())
      end
    end
  end)

  it("should support waveform_level when Screen.wf_level_max > 0", function()
    local Screen = Device.screen
    local orig_max = Screen.wf_level_max
    Screen.wf_level_max = 3
    package.loaded["ui/elements/waveform_level"] = nil
    local WaveformLevel = require("ui/elements/waveform_level")
    assert.is_table(WaveformLevel)
    assert.is_table(WaveformLevel.sub_item_table)
    assert.are_equal(4, #WaveformLevel.sub_item_table)

    for _, item in ipairs(WaveformLevel.sub_item_table) do
      item.callback()
      assert.is_boolean(item.checked_func())
    end

    Screen.wf_level_max = orig_max
  end)
end)
