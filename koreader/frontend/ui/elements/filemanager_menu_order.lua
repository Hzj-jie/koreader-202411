local order = require("ui/elements/common_menu_order")({
  ["KOMenu:menu_buttons"] = {
    "filemanager_settings",
    "setting",
    "tools",
    "search",
    "plus_menu",
    "main",
  },
  filemanager_settings = {
    "filemanager_display_mode",
    "filebrowser_settings",
    "----------------------------",
    "sort_by",
    "reverse_sorting",
    "sort_mixed",
    "----------------------------",
    "start_with",
  },
  plus_menu = {},
})

table.insert(order.document, 2, "document_metadata_location_move")
table.insert(order.tools, 5, "cloud_storage")
for _, v in ipairs({
  "advanced_settings",
  "developer_options",
}) do
  table.insert(order.tools, v)
end

for _, v in ipairs({
  "file_search",
  "file_search_results",
  "find_book_in_calibre_catalog",
  "----------------------------",
  "opds",
}) do
  table.insert(order.search, v)
end

return order
