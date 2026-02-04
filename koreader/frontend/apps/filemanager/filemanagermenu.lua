local BD = require("ui/bidi")
local CenterContainer = require("ui/widget/container/centercontainer")
local CommonMenu = require("apps/common_menu")
local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local Event = require("ui/event")
local FFIUtil = require("ffi/util")
local InputContainer = require("ui/widget/container/inputcontainer")
local KeyValuePage = require("ui/widget/keyvaluepage")
local PluginLoader = require("pluginloader")
local Size = require("ui/size")
local SpinWidget = require("ui/widget/spinwidget")
local UIManager = require("ui/uimanager")
local Screen = Device.screen
local dbg = require("dbg")
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local gettext = require("gettext")
local lfs = require("libs/libkoreader-lfs")
local util = require("util")
local T = FFIUtil.template

local FileManagerMenu = InputContainer:extend({
  tab_item_table = nil,
  menu_items = nil, -- table, mandatory
  registered_widgets = nil,
})

function FileManagerMenu:init()
  self.menu_items = {
    ["KOMenu:menu_buttons"] = {
      -- top menu
    },
    -- items in top menu
    filemanager_settings = {
      icon = "appbar.filebrowser",
    },
    setting = {
      icon = "appbar.settings",
    },
    tools = {
      icon = "appbar.tools",
    },
    search = {
      icon = "appbar.search",
    },
    main = {
      icon = "appbar.menu",
    },
  }

  self.registered_widgets = {}

  self:registerKeyEvents()

  self.activation_menu = G_named_settings.activate_menu()
end

function FileManagerMenu:registerKeyEvents()
  if not Device:hasKeys() then
    return
  end
  self.key_events.ShowMenu = { { "Menu" } }
  if Device:hasScreenKB() then
    self.key_events.OpenLastDoc = { { "ScreenKB", "Back" } }
  end
  self.key_events.ShowKeyboardShortcuts = { { "Shift", "S" } }
end

FileManagerMenu.onPhysicalKeyboardConnected = FileManagerMenu.registerKeyEvents

-- NOTE: FileManager emits a SetDimensions on init, it's our only caller
function FileManagerMenu:initGesListener()
  if not Device:isTouchDevice() then
    return
  end

  local DTAP_ZONE_MENU = G_defaults:read("DTAP_ZONE_MENU")
  local DTAP_ZONE_MENU_EXT = G_defaults:read("DTAP_ZONE_MENU_EXT")
  self:registerTouchZones({
    {
      id = "filemanager_tap",
      ges = "tap",
      screen_zone = {
        ratio_x = DTAP_ZONE_MENU.x,
        ratio_y = DTAP_ZONE_MENU.y,
        ratio_w = DTAP_ZONE_MENU.w,
        ratio_h = DTAP_ZONE_MENU.h,
      },
      handler = function(ges)
        return self:onTapShowMenu(ges)
      end,
    },
    {
      id = "filemanager_ext_tap",
      ges = "tap",
      screen_zone = {
        ratio_x = DTAP_ZONE_MENU_EXT.x,
        ratio_y = DTAP_ZONE_MENU_EXT.y,
        ratio_w = DTAP_ZONE_MENU_EXT.w,
        ratio_h = DTAP_ZONE_MENU_EXT.h,
      },
      overrides = {
        "filemanager_tap",
      },
      handler = function(ges)
        return self:onTapShowMenu(ges)
      end,
    },
    {
      id = "filemanager_swipe",
      ges = "swipe",
      screen_zone = {
        ratio_x = DTAP_ZONE_MENU.x,
        ratio_y = DTAP_ZONE_MENU.y,
        ratio_w = DTAP_ZONE_MENU.w,
        ratio_h = DTAP_ZONE_MENU.h,
      },
      overrides = {
        "rolling_swipe",
        "paging_swipe",
      },
      handler = function(ges)
        return self:onSwipeShowMenu(ges)
      end,
    },
    {
      id = "filemanager_ext_swipe",
      ges = "swipe",
      screen_zone = {
        ratio_x = DTAP_ZONE_MENU_EXT.x,
        ratio_y = DTAP_ZONE_MENU_EXT.y,
        ratio_w = DTAP_ZONE_MENU_EXT.w,
        ratio_h = DTAP_ZONE_MENU_EXT.h,
      },
      overrides = {
        "filemanager_swipe",
      },
      handler = function(ges)
        return self:onSwipeShowMenu(ges)
      end,
    },
  })
end

function FileManagerMenu:onOpenLastDoc()
  local last_file = G_reader_settings:read("lastfile")
  if not last_file or lfs.attributes(last_file, "mode") ~= "file" then
    local InfoMessage = require("ui/widget/infomessage")
    UIManager:show(InfoMessage:new({
      text = gettext("Cannot open last document"),
    }))
    return
  end

  -- Only close menu if we were called from the menu
  if self.menu_container then
    -- Mimic's FileManager's onShowingReader refresh optimizations
    self.ui.tearing_down = true
    self.ui.dithered = nil
    self:_closeFileManagerMenu()
  end

  local ReaderUI = require("apps/reader/readerui")
  ReaderUI:showReader(last_file)
end

function FileManagerMenu:setUpdateItemTable()
  local FileChooser = self.ui.file_chooser

  -- setting tab
  self.menu_items.filebrowser_settings = {
    text = gettext("Settings"),
    sub_item_table = {
      {
        text = gettext("Show finished books"),
        checked_func = function()
          return FileChooser.show_finished
        end,
        callback = function()
          FileChooser:toggleShowFilesMode("show_finished")
        end,
      },
      {
        text = gettext("Show hidden files"),
        checked_func = function()
          return FileChooser.show_hidden
        end,
        callback = function()
          FileChooser:toggleShowFilesMode("show_hidden")
        end,
      },
      {
        text = gettext("Show unsupported files"),
        checked_func = function()
          return FileChooser.show_unsupported
        end,
        callback = function()
          FileChooser:toggleShowFilesMode("show_unsupported")
        end,
        separator = true,
      },
      {
        text = gettext("Classic mode settings"),
        sub_item_table = {
          {
            text_func = function()
              return T(
                gettext("Items per page: %1"),
                G_reader_settings:read("items_per_page") or FileChooser.items_per_page_default
              )
            end,
            help_text = gettext([[This sets the number of items per page in:
- File browser, history and favorites in 'classic' display mode
- Search results and folder shortcuts
- File and folder selection
- Calibre and OPDS browsers/search results]]),
            callback = function(touchmenu_instance)
              local default_value = FileChooser.items_per_page_default
              local current_value = G_reader_settings:read("items_per_page") or default_value
              local widget = SpinWidget:new({
                title_text = gettext("Items per page"),
                value = current_value,
                value_min = 6,
                value_max = 30,
                default_value = default_value,
                keep_shown_on_apply = true,
                callback = function(spin)
                  G_reader_settings:save("items_per_page", spin.value, default_value)
                  FileChooser:refreshPath()
                  touchmenu_instance:updateItems()
                end,
              })
              UIManager:show(widget)
            end,
          },
          {
            text_func = function()
              return T(gettext("Item font size: %1"), FileChooser.font_size)
            end,
            callback = function(touchmenu_instance)
              local current_value = FileChooser.font_size
              local default_value = FileChooser.getItemFontSize(
                G_reader_settings:read("items_per_page") or FileChooser.items_per_page_default
              )
              local widget = SpinWidget:new({
                title_text = gettext("Item font size"),
                value = current_value,
                value_min = 10,
                value_max = 72,
                default_value = default_value,
                keep_shown_on_apply = true,
                callback = function(spin)
                  -- We can't know if the user has set a size or hit "Use default", but
                  -- assume that if it is the default font size, he will prefer to have
                  -- our default font size if he later updates per-page
                  G_reader_settings:save("items_font_size", spin.value, default_value)
                  FileChooser:refreshPath()
                  touchmenu_instance:updateItems()
                end,
              })
              UIManager:show(widget)
            end,
          },
          {
            text = gettext("Shrink item font size to fit more text"),
            checked_func = function()
              return G_reader_settings:isTrue("items_multilines_show_more_text")
            end,
            callback = function()
              G_reader_settings:flipNilOrFalse("items_multilines_show_more_text")
              self.ui:onRefresh()
            end,
            separator = true,
          },
          {
            text = gettext("Show opened files in bold"),
            checked_func = function()
              return G_named_settings.show_file_in_bold() == "opened"
            end,
            callback = function()
              if G_named_settings.show_file_in_bold() == "opened" then
                G_named_settings.set.show_file_in_bold("none")
              else
                G_named_settings.set.show_file_in_bold("opened")
              end
              self.ui:onRefresh()
            end,
          },
          {
            text = gettext("Show new (not yet opened) files in bold"),
            checked_func = function()
              return G_named_settings.show_file_in_bold() == "new"
            end,
            callback = function()
              if G_named_settings.show_file_in_bold() == "new" then
                G_named_settings.set.show_file_in_bold("none")
              else
                G_named_settings.set.show_file_in_bold("new")
              end
              self.ui:onRefresh()
            end,
          },
        },
      },
      {
        text = gettext("History settings"),
        sub_item_table = {
          {
            text = gettext("Shorten date/time"),
            checked_func = function()
              return G_reader_settings:isTrue("history_datetime_short")
            end,
            callback = function()
              G_reader_settings:flipNilOrFalse("history_datetime_short")
              require("readhistory"):updateDateTimeString()
            end,
          },
          {
            text = gettext("Freeze last read date of finished books"),
            checked_func = function()
              return G_reader_settings:nilOrTrue("history_freeze_finished_books")
            end,
            callback = function()
              G_reader_settings:flipNilOrTrue("history_freeze_finished_books")
            end,
            separator = true,
          },
          {
            text = gettext("Clear history of deleted files"),
            callback = function()
              UIManager:show(ConfirmBox:new({
                text = gettext("Clear history of deleted files?"),
                ok_text = gettext("Clear"),
                ok_callback = function()
                  require("readhistory"):clearMissing()
                end,
              }))
            end,
          },
          {
            text = gettext("Auto-remove deleted or purged items from history"),
            checked_func = function()
              return G_reader_settings:isTrue("autoremove_deleted_items_from_history")
            end,
            callback = function()
              G_reader_settings:flipNilOrFalse("autoremove_deleted_items_from_history")
            end,
            separator = true,
          },
          {
            text = gettext("Show filename in Open last/previous menu items"),
            checked_func = function()
              return G_reader_settings:isTrue("open_last_menu_show_filename")
            end,
            callback = function()
              G_reader_settings:flipNilOrFalse("open_last_menu_show_filename")
            end,
          },
        },
      },
      {
        text = gettext("Home folder settings"),
        sub_item_table = {
          {
            text = gettext("Set home folder"),
            callback = function()
              filemanagerutil.showChooseDialog(gettext("Current home folder:"), function(path)
                G_reader_settings:save("home_dir", path)
                self.ui:updateTitleBarPath()
              end, G_reader_settings:read("home_dir"), require("util").backup_dir())
            end,
          },
          {
            text = gettext("Shorten home folder"),
            checked_func = function()
              return G_reader_settings:nilOrTrue("shorten_home_dir")
            end,
            callback = function()
              G_reader_settings:flipNilOrTrue("shorten_home_dir")
              self.ui:updateTitleBarPath()
            end,
            help_text = gettext([[
"Shorten home folder" will display the home folder itself as "Home" instead of its full path.

Assuming the home folder is:
`/mnt/onboard/.books`
A subfolder will be shortened from:
`/mnt/onboard/.books/Manga/Cells at Work`
To:
`Manga/Cells at Work`.]]),
          },
          {
            text = gettext("Lock home folder"),
            enabled_func = function()
              return G_reader_settings:has("home_dir")
            end,
            checked_func = function()
              return G_reader_settings:isTrue("lock_home_folder")
            end,
            callback = function()
              G_reader_settings:flipNilOrFalse("lock_home_folder")
              self.ui:onRefresh()
            end,
          },
        },
        separator = true,
      },
      {
        text_func = function()
          local default_value = KeyValuePage.getDefaultItemsPerPage()
          local current_value = G_reader_settings:read("keyvalues_per_page") or default_value
          return T(gettext("Info lists items per page: %1"), current_value)
        end,
        help_text = gettext([[This sets the number of items per page in:
- Book information
- Dictionary and Wikipedia lookup history
- Reading statistics details
- A few other plugins]]),
        keep_menu_open = true,
        callback = function(touchmenu_instance)
          local default_value = KeyValuePage.getDefaultItemsPerPage()
          local current_value = G_reader_settings:read("keyvalues_per_page") or default_value
          local widget = SpinWidget:new({
            value = current_value,
            value_min = 10,
            value_max = 30,
            default_value = default_value,
            title_text = gettext("Info lists items per page"),
            callback = function(spin)
              G_reader_settings:save("keyvalues_per_page", spin.value, default_value)
              touchmenu_instance:updateItems()
            end,
          })
          UIManager:show(widget)
        end,
      },
    },
  }

  for _, widget in pairs(self.registered_widgets) do
    widget:addToMainMenu(self.menu_items)
  end

  self.menu_items.sort_by = self:getSortingMenuTable()
  self.menu_items.reverse_sorting = {
    text = gettext("Reverse sorting"),
    checked_func = function()
      return G_reader_settings:isTrue("reverse_collate")
    end,
    callback = function()
      G_reader_settings:flipNilOrFalse("reverse_collate")
      FileChooser:refreshPath()
    end,
  }
  self.menu_items.sort_mixed = {
    text = gettext("Folders and files mixed"),
    enabled_func = function()
      local collate = FileChooser:getCollate()
      return collate.can_collate_mixed
    end,
    checked_func = function()
      local collate = FileChooser:getCollate()
      return collate.can_collate_mixed and G_reader_settings:isTrue("collate_mixed")
    end,
    callback = function()
      G_reader_settings:flipNilOrFalse("collate_mixed")
      FileChooser:refreshPath()
    end,
  }
  self.menu_items.start_with = self:getStartWithMenuTable()

  if Device:supportsScreensaver() then
    self.menu_items.screensaver = {
      text = gettext("Sleep screen"),
      sub_item_table = require("ui/elements/screensaver_menu"),
    }
  end

  -- insert common settings
  for k, v in pairs(require("ui/elements/common_settings_menu_table")) do
    self.menu_items[k] = v
  end

  -- Settings > Navigation; this mostly concerns physical keys, and applies *everywhere*
  if Device:hasKeys() then
    self.menu_items.physical_buttons_setup = require("ui/elements/physical_buttons")
  end

  -- settings tab - Document submenu
  self.menu_items.document_metadata_location_move = {
    text = gettext("Move book metadata"),
    keep_menu_open = true,
    callback = function()
      self.ui.bookinfo:moveBookMetadata()
    end,
  }

  -- tools tab
  self.menu_items.plugin_management = {
    text = gettext("Plugin management"),
    sub_item_table = PluginLoader:genPluginManagerSubItem(),
  }

  self.menu_items.cloud_storage = require("ui/elements/cloud_storage_menu_table")

  self.menu_items.file_search = {
    -- @translators Search for files by name.
    text = gettext("File search"),
    help_text = gettext([[Search a book by filename in the current or home folder and its subfolders.

Wildcards for one '?' or more '*' characters can be used.
A search for '*' will show all files.

The sorting order is the same as in filemanager.

Tap a book in the search results to open it.]]),
    callback = function()
      self.ui.filesearcher:onShowFileSearch()
    end,
  }
  self.menu_items.file_search_results = {
    text = gettext("Last file search results"),
    callback = function()
      self.ui.filesearcher:onShowSearchResults()
    end,
  }

  -- main menu tab
  self.menu_items.open_previous_document = {
    text_func = function()
      if not G_reader_settings:isTrue("open_last_menu_show_filename") or G_reader_settings:hasNot("lastfile") then
        return gettext("Open last document")
      end
      local last_file = G_reader_settings:read("lastfile")
      local path, file_name = util.splitFilePathName(last_file) -- luacheck: no unused
      return T(gettext("Last: %1"), BD.filename(file_name))
    end,
    enabled_func = function()
      return G_reader_settings:has("lastfile")
    end,
    callback = function()
      self:onOpenLastDoc()
    end,
    hold_callback = function()
      local last_file = G_reader_settings:read("lastfile")
      UIManager:show(ConfirmBox:new({
        text = T(gettext("Would you like to open the last document: %1?"), BD.filepath(last_file)),
        ok_text = gettext("OK"),
        ok_callback = function()
          self:onOpenLastDoc()
        end,
      }))
    end,
  }
  -- insert common info
  for k, v in pairs(require("ui/elements/common_info_menu_table")) do
    self.menu_items[k] = v
  end
  -- insert common exit for filemanager
  for k, v in pairs(require("ui/elements/common_exit_menu_table")) do
    self.menu_items[k] = v
  end
  if not Device:isTouchDevice() then
    -- add a shortcut on non touch-device
    -- because this menu is not accessible otherwise
    self.menu_items.plus_menu = {
      icon = "plus",
      remember = false,
      callback = function()
        self:_closeFileManagerMenu()
        self.ui:tapPlus()
      end,
    }
  end

  self.tab_item_table =
    require("ui/menusorter"):mergeAndSort("filemanager", self.menu_items, require("ui/elements/filemanager_menu_order"))
end
dbg:guard(FileManagerMenu, "setUpdateItemTable", function(self)
  local mock_menu_items = {}
  for _, widget in pairs(self.registered_widgets) do
    -- make sure addToMainMenu works in debug mode
    widget:addToMainMenu(mock_menu_items)
  end
end)

function FileManagerMenu:getSortingMenuTable()
  local sub_item_table = {}
  for k, v in pairs(self.ui.file_chooser.collates) do
    table.insert(sub_item_table, {
      text = v.text,
      menu_order = v.menu_order,
      checked_func = function()
        local _, id = self.ui.file_chooser:getCollate()
        return k == id
      end,
      callback = function()
        G_reader_settings:save("collate", k)
        self.ui.file_chooser:clearSortingCache()
        self.ui.file_chooser:refreshPath()
      end,
    })
  end
  table.sort(sub_item_table, function(a, b)
    return a.menu_order < b.menu_order
  end)
  return {
    text_func = function()
      local collate = self.ui.file_chooser:getCollate()
      return T(gettext("Sort by: %1"), collate.text)
    end,
    sub_item_table = sub_item_table,
  }
end

function FileManagerMenu:getStartWithMenuTable()
  local start_withs = {
    { gettext("file browser"), "filemanager" },
    { gettext("history"), "history" },
    { gettext("favorites"), "favorites" },
    { gettext("folder shortcuts"), "folder_shortcuts" },
    { gettext("last file"), "last" },
  }
  local sub_item_table = {}
  for i, v in ipairs(start_withs) do
    table.insert(sub_item_table, {
      text = v[1],
      checked_func = function()
        return v[2] == (G_reader_settings:read("start_with") or "filemanager")
      end,
      callback = function()
        G_reader_settings:save("start_with", v[2])
      end,
      radio = true,
    })
  end
  return {
    text_func = function()
      local start_with = G_reader_settings:read("start_with") or "filemanager"
      for i, v in ipairs(start_withs) do
        if v[2] == start_with then
          return T(gettext("Start with: %1"), v[1])
        end
      end
    end,
    sub_item_table = sub_item_table,
  }
end

function FileManagerMenu:exitOrRestart(callback, force)
  CommonMenu:exitOrRestart(function()
    self:_closeFileManagerMenu()
  end, self.ui, callback)
end

function FileManagerMenu:onShowMenu(tab_index)
  if self.tab_item_table == nil then
    self:setUpdateItemTable()
  end

  if not tab_index then
    tab_index = G_reader_settings:read("filemanagermenu_tab_index") or 1
  end

  local menu_container = CenterContainer:new({
    ignore = "height",
    dimen = Screen:getSize(),
  })

  local main_menu
  if Device:isTouchDevice() or Device:hasDPad() then
    local TouchMenu = require("ui/widget/touchmenu")
    main_menu = TouchMenu:new({
      width = Screen:getWidth(),
      last_index = tab_index,
      tab_item_table = self.tab_item_table,
    })
  else
    local Menu = require("ui/widget/menu")
    main_menu = Menu:new({
      title = gettext("File manager menu"),
      item_table = Menu.itemTableFromTouchMenu(self.tab_item_table),
      width = Screen:getWidth() - (Size.margin.fullscreen_popout * 2),
    })
  end

  main_menu.close_callback = function()
    self:_closeFileManagerMenu()
  end

  menu_container[1] = main_menu
  -- maintain a reference to menu_container
  self.menu_container = menu_container
  UIManager:show(menu_container)
  return true
end

function FileManagerMenu:_closeFileManagerMenu()
  if not self.menu_container then
    return true
  end
  local last_tab_index = self.menu_container[1].last_index
  G_reader_settings:save("filemanagermenu_tab_index", last_tab_index, 1)
  UIManager:close(self.menu_container)
  self.menu_container = nil
  return true
end

function FileManagerMenu:_getTabIndexFromLocation(ges)
  if self.tab_item_table == nil then
    self:setUpdateItemTable()
  end
  local last_tab_index = G_reader_settings:read("filemanagermenu_tab_index") or 1
  if not ges then
    return last_tab_index
  -- if the start position is far right
  elseif ges.pos.x > Screen:getWidth() * (2 / 3) then
    return BD.mirroredUILayout() and 1 or #self.tab_item_table
  -- if the start position is far left
  elseif ges.pos.x < Screen:getWidth() * (1 / 3) then
    return BD.mirroredUILayout() and #self.tab_item_table or 1
  -- if center return the last index
  else
    return last_tab_index
  end
end

function FileManagerMenu:onTapShowMenu(ges)
  if self.activation_menu ~= "swipe" then
    self:onShowMenu(self:_getTabIndexFromLocation(ges))
    return true
  end
end

function FileManagerMenu:onSwipeShowMenu(ges)
  if self.activation_menu ~= "tap" and ges.direction == "south" then
    self:onShowMenu(self:_getTabIndexFromLocation(ges))
    return true
  end
end

function FileManagerMenu:onSetDimensions(dimen)
  -- This widget doesn't support in-place layout updates, so, close & reopen
  if self.menu_container then
    self:_closeFileManagerMenu()
    self:onShowMenu()
  end

  -- update gesture zones according to new screen dimen
  self:initGesListener()
end

function FileManagerMenu:onMenuSearch()
  self:onShowMenu()
  UIManager:broadcastEvent(Event:new("ShowMenuSearch"))
end

function FileManagerMenu:registerToMainMenu(widget)
  table.insert(self.registered_widgets, widget)
end

function FileManagerMenu:onShowKeyboardShortcuts()
  require("ui/elements/common_info_menu_table").keyboard_shortcuts.callback()
end

return FileManagerMenu
