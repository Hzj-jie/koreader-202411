local order = require("ui/elements/common_menu_order")({
  ["KOMenu:menu_buttons"] = {
    "navi",
    "typeset",
    "setting",
    "tools",
    "search",
    "filemanager",
    "main",
  },
  navi = {
    "table_of_contents",
    "bookmarks",
    "toggle_bookmark", -- if not Device:isTouchDevice()
    "bookmark_browsing_mode",
    "navi_settings",
    "----------------------------",
    "page_map",
    "hide_nonlinear_flows",
    "----------------------------",
    "book_map", -- if Device:isTouchDevice()
    "page_browser", -- if Device:isTouchDevice()
    "----------------------------",
    "go_to",
    "skim_to",
    "progress_sync",
    "autoturn",
    "----------------------------",
    "go_to_previous_location",
    "go_to_next_location",
  },
  navi_settings = {
    "toc_ticks_level_ignore",
    "----------------------------",
    "toc_items_per_page",
    "toc_items_font_size",
    "toc_items_show_chapter_length",
    "toc_items_with_dots",
    "----------------------------",
    "toc_alt_toc",
    "----------------------------",
    "handmade_toc",
    "handmade_hidden_flows",
    "handmade_settings",
    "----------------------------",
    "bookmarks_settings",
  },
  typeset = {
    "reset_document_settings",
    "save_document_settings",
    "----------------------------",
    "set_render_style",
    "style_tweaks",
    "----------------------------",
    "change_font",
    "typography",
    "----------------------------",
    "switch_zoom_mode",
    "----------------------------",
    "page_overlap",
    "speed_reading_module_perception_expander",
    "----------------------------",
    "highlight_options",
    "selection_text", -- if Device:hasDPad()
    "panel_zoom_options",
    "djvu_render_mode",
    "start_content_selection", -- if Device:hasDPad(), put this as last one so it is easy to select with "press" and "up" keys
  },
  filemanager = {},
})

table.insert(order.setting, "status_bar")
table.insert(order.screen, 2, "coverimage")
table.insert(order.document, "partial_rerendering")
for _, v in ipairs({
  "follow_links",
  "page_turns",
  "scrolling",
  "long_press",
}) do
  table.insert(order.taps_and_gestures, v)
end

for _, v in ipairs({
  "translate_current_page",
  "----------------------------",
  "find_book_in_calibre_catalog",
  "fulltext_search",
  "fulltext_search_findall_results",
  "bookmark_search",
}) do
  table.insert(order.search, v)
end

for _, v in ipairs({
  "translation_settings",
  "----------------------------",
  "fulltext_search_settings",
}) do
  table.insert(order.search_settings, v)
end

for _, v in ipairs({
  -- Reverse ordered
  "book_info",
  "book_status",
  "----------------------------",
}) do
  table.insert(order.main, 6, v)
end

return order
