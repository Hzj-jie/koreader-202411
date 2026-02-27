local Device = require("device")
local gettext = require("gettext")
local Screen = Device.screen

local eink_settings_table = {
  text = gettext("E-ink settings"),
  sub_item_table = {},
}

if Device:hasEinkScreen() then
  for _, v in pairs(require("ui/elements/refresh_menu_table")) do
    table.insert(eink_settings_table.sub_item_table, v)
  end
end

table.insert(eink_settings_table.sub_item_table, {
  -- Need localization
  text = gettext("Use lower refresh rate when appropriate"),
  -- Need localization
  help_text = gettext(
    "E-ink may laggy when refreshing, avoid refreshing the screen for the intermedia states, e.g. when scrolling, can be beneficial to reduce the laggy or blur.\nA reloading of the book may be needed to take effect."
  ),
  checked_func = function()
    return G_named_settings.low_pan_rate()
  end,
  callback = function()
    G_named_settings.flip.low_pan_rate()
  end,
})

table.insert(eink_settings_table.sub_item_table, {
  text = gettext("Avoid mandatory black flashes in UI"),
  -- Need localization
  help_text = gettext(
    "Fully rendering a black area can be slow and increase the blur on the E-ink, avoiding full refreshes of the black areas may improve the device responsiveness in exchange of potentially observing partially rendered black areas, especially on menus and buttons."
  ),
  checked_func = function()
    return G_reader_settings:nilOrTrue("avoid_flashing_ui")
  end,
  callback = function()
    G_reader_settings:flipNilOrTrue("avoid_flashing_ui")
  end,
})

if Device:hasEinkScreen() then
  if (Screen.wf_level_max or 0) > 0 then
    table.insert(
      eink_settings_table.sub_item_table,
      require("ui/elements/waveform_level")
    )
  end
end

return eink_settings_table
