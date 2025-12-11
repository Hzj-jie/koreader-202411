local Device = require("device")
local _ = require("gettext")
local Screen = Device.screen

local eink_settings_table = {
  text = _("E-ink settings"),
  sub_item_table = {
    {
      text = _("Use smaller panning rate"),
      checked_func = function()
        return G_named_settings.low_pan_rate()
      end,
      callback = function()
        G_named_settings.flip.low_pan_rate()
      end,
    },
    {
      text = _("Avoid mandatory black flashes in UI"),
      checked_func = function()
        return G_reader_settings:nilOrTrue("avoid_flashing_ui")
      end,
      callback = function()
        G_reader_settings:flipNilOrTrue("avoid_flashing_ui")
      end,
    },
  },
}

if Device:hasEinkScreen() then
  table.insert(
    eink_settings_table.sub_item_table,
    1,
    require("ui/elements/refresh_menu_table")
  )
  if (Screen.wf_level_max or 0) > 0 then
    table.insert(
      eink_settings_table.sub_item_table,
      require("ui/elements/waveform_level")
    )
  end
end

return eink_settings_table
