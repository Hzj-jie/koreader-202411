describe("filemanagermenu", function()
  local FileManagerMenu
  local mock_ui
  local mock_device
  local mock_reader_settings
  local mock_named_settings
  local mock_defaults
  local real_util

  setup(function()
    require("commonrequire")
    real_util = require("util")
  end)

  before_each(function()
    _G.DGENERIC_ICON_SIZE = 32
    mock_device = {
      screen = {
        getSize = function()
          return { w = 800, h = 600 }
        end,
        getWidth = function()
          return 800
        end,
        getHeight = function()
          return 600
        end,
        scaleBySize = function(self, size)
          return size or 32
        end,
        scaleByDPI = function(self, size)
          return size or 32
        end,
      },
      hasKeyboard = function()
        return true
      end,
      hasKeys = function()
        return true
      end,
      hasFewKeys = function()
        return true
      end,
      hasScreenKB = function()
        return true
      end,
      isTouchDevice = function()
        return true
      end,
      hasDPad = function()
        return false
      end,
      supportsScreensaver = function()
        return true
      end,
      isStartupScriptUpToDate = function()
        return true
      end,
      getPowerDevice = function()
        return {
          turnOnFrontlight = function() end,
        }
      end,
      input = {
        group = {
          Back = "Back",
          Menu = "Menu",
          PgFwd = "PgFwd",
          PgBack = "PgBack",
        },
      },
    }
    package.loaded["device"] = mock_device
    package.loaded["device/input"] = { group = { Back = "Back", Menu = "Menu" } }

    local reader_settings_data = {
      lastfile = "/books/book1.epub",
      items_per_page = 10,
      start_with = "filemanager",
      items_font_size = 20,
    }
    mock_reader_settings = {
      read = spy.new(function(self, key)
        return reader_settings_data[key]
      end),
      save = spy.new(function(self, key, val)
        reader_settings_data[key] = val
      end),
      isTrue = spy.new(function(self, key)
        return not not reader_settings_data[key]
      end),
      nilOrTrue = spy.new(function(self, key)
        if reader_settings_data[key] == nil then
          return true
        end
        return not not reader_settings_data[key]
      end),
      flipNilOrFalse = spy.new(function(self, key)
        reader_settings_data[key] = not reader_settings_data[key]
      end),
      flipNilOrTrue = spy.new(function(self, key)
        if reader_settings_data[key] == nil then
          reader_settings_data[key] = false
        else
          reader_settings_data[key] = not reader_settings_data[key]
        end
      end),
      has = spy.new(function(self, key)
        return reader_settings_data[key] ~= nil
      end),
      hasNot = spy.new(function(self, key)
        return reader_settings_data[key] == nil
      end),
    }
    _G.G_reader_settings = mock_reader_settings

    local named_settings_data = {
      activate_menu = "tap",
      show_file_in_bold = "opened",
      collate = "alphabetic",
    }
    mock_named_settings = {
      activate_menu = spy.new(function()
        return named_settings_data.activate_menu
      end),
      show_file_in_bold = spy.new(function()
        return named_settings_data.show_file_in_bold
      end),
      set = {
        show_file_in_bold = spy.new(function(val)
          named_settings_data.show_file_in_bold = val
        end),
        collate = spy.new(function(val)
          named_settings_data.collate = val
        end),
      },
    }
    _G.G_named_settings = mock_named_settings

    mock_defaults = {
      read = spy.new(function(self, key)
        if key == "DTAP_ZONE_MENU" then
          return { x = 0, y = 0, w = 1, h = 0.1 }
        elseif key == "DTAP_ZONE_MENU_EXT" then
          return { x = 0, y = 0, w = 1, h = 0.2 }
        elseif key == "DGLOBAL_CACHE_FREE_PROPORTION" then
          return 0.2
        elseif key == "DGLOBAL_CACHE_SIZE_MINIMUM" then
          return 8 * 1024 * 1024
        elseif key == "DGLOBAL_CACHE_SIZE_MAXIMUM" then
          return 64 * 1024 * 1024
        elseif key == "DHINTCOUNT" then
          return 10
        end
        return 0
      end),
    }
    _G.G_defaults = mock_defaults

    package.loaded["ui/bidi"] = setmetatable({
      filename = function(s)
        return s
      end,
      filepath = function(s)
        return s
      end,
      mirroredUILayout = function()
        return false
      end,
      rtlUIText = function()
        return false
      end,
      isRTL = function()
        return false
      end,
      wrapText = function(s)
        return s
      end,
      hasRTL = function()
        return false
      end,
      ltr = function(s)
        return s
      end,
      rtl = function(s)
        return s
      end,
    }, {
      __index = function(t, k)
        return function(s)
          return s
        end
      end,
    })

    package.loaded["ui/widget/container/centercontainer"] = {
      new = spy.new(function(self, _args)
        local obj = { is_center_container = true }
        return setmetatable(obj, {
          __newindex = function(t, k, v)
            rawset(t, k, v)
          end,
          __index = function(t, k)
            return rawget(t, k)
          end,
        })
      end),
    }

    package.loaded["ui/widget/container/inputcontainer"] = {
      new = function(s, args)
        local inst = setmetatable(args or {}, { __index = s })
        inst.ges_events = inst.ges_events or {}
        inst.key_events = inst.key_events or {}
        if inst.init then
          inst:init()
        end
        return inst
      end,
      extend = function(self, child)
        child = child or {}
        child.ges_events = child.ges_events or {}
        child.key_events = child.key_events or {}
        child.registerTouchZones = spy.new(function() end)
        return setmetatable(child, {
          __index = self,
        })
      end,
      showWidget = function(self, widget, ...)
        require("ui/uimanager"):show(widget, ...)
      end,
      myRange = function(self, ges)
        return { ges = ges }
      end,
    }

    package.loaded["apps/common_menu"] = {
      exitOrRestart = spy.new(function(self, before_exit, _ui, after_exit)
        if before_exit then
          before_exit()
        end
        if after_exit then
          after_exit()
        end
      end),
    }

    package.loaded["ui/widget/confirmbox"] = {
      new = spy.new(function(self, args)
        return {
          is_confirm_box = true,
          text = args.text,
          ok_text = args.ok_text,
          ok_callback = args.ok_callback,
        }
      end),
    }

    package.loaded["ui/widget/infomessage"] = {
      new = spy.new(function(self, args)
        return {
          is_info_message = true,
          text = args.text,
        }
      end),
    }

    package.loaded["ui/event"] = {
      new = function(self, name)
        return { name = name }
      end,
    }

    package.loaded["ffi/util"] = {
      template = function(tmpl, ...)
        local args = { ... }
        return tmpl:gsub("%%(%d+)", function(n)
          return tostring(args[tonumber(n)])
        end)
      end,
      joinPath = function(...)
        return table.concat({ ... }, "/")
      end,
      basename = function(path)
        return path:match("([^/]+)$") or path
      end,
      dirname = function(path)
        return path:match("^(.*)/") or ""
      end,
    }

    package.loaded["ui/widget/keyvaluepage"] = {
      getDefaultItemsPerPage = function()
        return 15
      end,
    }

    package.loaded["pluginloader"] = {
      menuItem = function()
        return {}
      end,
      genPluginManagerSubItem = function()
        return {}
      end,
    }

    package.loaded["ui/size"] = {
      border = {
        default = 1,
        thin = 1,
        button = 1,
        window = 1,
        thick = 2,
        inputtext = 2,
      },
      margin = {
        default = 5,
        tiny = 1,
        small = 2,
        title = 2,
        fine_tune = 3,
        fullscreen_popout = 10,
        button = 0,
      },
      padding = {
        default = 5,
        tiny = 1,
        small = 2,
        large = 10,
        button = 2,
        buttontable = 4,
        fullscreen = 15,
      },
      radius = {
        default = 2,
        window = 7,
        button = 7,
      },
      line = {
        thin = 1,
        medium = 1,
        thick = 2,
        focus_indicator = 5,
        progress = 7,
      },
      item = {
        height_default = 30,
        height_big = 40,
        height_large = 50,
      },
      span = {
        horizontal_default = 10,
        horizontal_small = 5,
        vertical_default = 2,
        vertical_large = 5,
      },
    }

    package.loaded["ui/widget/spinwidget"] = {
      new = spy.new(function(self, args)
        return args
      end),
    }

    local last_shown_widget
    local last_closed_widget
    local broadcast_events = {}
    package.loaded["ui/uimanager"] = {
      show = spy.new(function(self, widget)
        last_shown_widget = widget
      end),
      close = spy.new(function(self, widget)
        last_closed_widget = widget
      end),
      nextTick = spy.new(function(self, fn)
        fn()
      end),
      broadcastEvent = spy.new(function(self, ev)
        table.insert(broadcast_events, ev)
      end),
      getLastShownWidget = function()
        return last_shown_widget
      end,
      getLastClosedWidget = function()
        return last_closed_widget
      end,
      getBroadcastEvents = function()
        return broadcast_events
      end,
      clearBroadcastEvents = function()
        broadcast_events = {}
      end,
    }

    package.loaded["apps/filemanager/filemanagerutil"] = {
      showChooseDialog = spy.new(function() end),
    }

    package.loaded["libs/libkoreader-lfs"] = {
      mkdir = function() end,
      dir = function()
        return function()
          return nil
        end
      end,
      attributes = spy.new(function(path, mode)
        if path == "/books/book1.epub" then
          if mode == "mode" then
            return "file"
          end
          return { mode = "file" }
        end
        return nil
      end),
    }

    package.loaded["util"] = setmetatable({
      splitFilePathName = function(path)
        local dir, name = path:match("^(.-)([^/]*)$")
        return dir, name
      end,
      backup_dir = function()
        return "/backup"
      end,
      findFiles = function()
        return {}
      end,
      calcFreeMem = function()
        return 100 * 1024 * 1024
      end,
      getFileNameSuffix = function(str)
        return str and str:match("[^.]+$") or ""
      end,
    }, {
      __index = real_util or {},
    })

    package.loaded["dbg"] = {
      guard = function() end,
    }

    package.loaded["ui/menusorter"] = {
      mergeAndSort = spy.new(function(self, _name, menu_items, _order)
        local res = {}
        for k, v in pairs(menu_items) do
          table.insert(res, { text = v.text or k, name = k })
        end
        return res
      end),
    }
    package.loaded["ui/elements/filemanager_menu_order"] = {}
    package.loaded["ui/elements/screensaver_menu"] = {}
    package.loaded["ui/elements/common_settings_menu_table"] = {}
    package.loaded["ui/elements/physical_buttons"] = {}
    package.loaded["ui/elements/cloud_storage_menu_table"] = {}
    package.loaded["ui/elements/common_info_menu_table"] = {
      keyboard_shortcuts = {
        callback = spy.new(function() end),
      },
    }
    package.loaded["ui/elements/common_exit_menu_table"] = {}

    mock_gettext = setmetatable({
      ngettext = function(sing, plur, n)
        return n == 1 and sing or plur
      end,
    }, {
      __call = function(self, text)
        return text
      end,
    })
    package.loaded["gettext"] = mock_gettext

    mock_ui = {
      file_chooser = {
        show_finished = false,
        show_hidden = false,
        show_unsupported = false,
        items_per_page_default = 10,
        font_size = 16,
        getItemFontSize = function(_ipp)
          return 16
        end,
        toggleShowFilesMode = spy.new(function() end),
        refreshPath = spy.new(function() end),
        getCollate = function()
          return { can_collate_mixed = true, text = "Alphabetic" }
        end,
        collates = {
          alphabetic = { text = "Alphabetic", menu_order = 1 },
        },
        clearSortingCache = spy.new(function() end),
      },
      filesearcher = {
        onShowFileSearch = spy.new(function() end),
        onShowSearchResults = spy.new(function() end),
      },
      bookinfo = {
        moveBookMetadata = spy.new(function() end),
      },
      updateTitleBarPath = spy.new(function() end),
      onRefresh = spy.new(function() end),
      tapPlus = spy.new(function() end),
      onExit = spy.new(function() end),
    }

    package.loaded["ui/widget/touchmenu"] = nil
    package.loaded["ui/widget/menu"] = nil
    package.loaded["apps/filemanager/filemanagermenu"] = nil
    FileManagerMenu = require("apps/filemanager/filemanagermenu")
  end)

  after_each(function()
    package.loaded["apps/filemanager/filemanagermenu"] = nil
    package.loaded["device"] = nil
    package.loaded["ui/bidi"] = nil
    package.loaded["ui/widget/container/centercontainer"] = nil
    package.loaded["ui/widget/container/inputcontainer"] = nil
    package.loaded["apps/common_menu"] = nil
    package.loaded["ui/widget/confirmbox"] = nil
    package.loaded["ui/widget/infomessage"] = nil
    package.loaded["ui/event"] = nil
    package.loaded["ffi/util"] = nil
    package.loaded["ui/widget/keyvaluepage"] = nil
    package.loaded["pluginloader"] = nil
    package.loaded["ui/size"] = nil
    package.loaded["ui/widget/spinwidget"] = nil
    package.loaded["ui/uimanager"] = nil
    package.loaded["apps/filemanager/filemanagerutil"] = nil
    package.loaded["libs/libkoreader-lfs"] = nil
    package.loaded["util"] = nil
    package.loaded["dbg"] = nil
    package.loaded["ui/menusorter"] = nil
    package.loaded["ui/elements/filemanager_menu_order"] = nil
    package.loaded["ui/elements/screensaver_menu"] = nil
    package.loaded["ui/elements/common_settings_menu_table"] = nil
    package.loaded["ui/elements/physical_buttons"] = nil
    package.loaded["ui/elements/cloud_storage_menu_table"] = nil
    package.loaded["ui/elements/common_info_menu_table"] = nil
    package.loaded["ui/elements/common_exit_menu_table"] = nil
    package.loaded["gettext"] = nil
    _G.G_reader_settings = nil
    _G.G_named_settings = nil
    _G.G_defaults = nil
  end)

  it("should register key events on init", function()
    local menu = FileManagerMenu:new({ ui = mock_ui })
    assert.truthy(menu.key_events.ShowMenu)
    assert.truthy(menu.key_events.OpenLastDoc)
    assert.truthy(menu.key_events.ShowKeyboardShortcuts)
  end)

  it("should register touch zones on initGesListener", function()
    local menu = FileManagerMenu:new({ ui = mock_ui })
    menu:initGesListener()
    assert.spy(menu.registerTouchZones).was.called(1)
  end)

  describe("onOpenLastDoc", function()
    it("should open last document if exists and close menu", function()
      local menu = FileManagerMenu:new({ ui = mock_ui })
      menu.menu_container =
        { is_center_container = true, [1] = { last_index = 1 } }

      local ReaderUI = { showReader = spy.new(function() end) }
      package.loaded["apps/reader/readerui"] = ReaderUI

      menu:onOpenLastDoc()

      assert
        .spy(ReaderUI.showReader).was
        .called_with(ReaderUI, "/books/book1.epub")
      assert.is_nil(menu.menu_container)
      package.loaded["apps/reader/readerui"] = nil
    end)

    it("should show info message if last document does not exist", function()
      local menu = FileManagerMenu:new({ ui = mock_ui })
      G_reader_settings:save("lastfile", "/books/nonexistent.epub")

      local UIManager = require("ui/uimanager")
      UIManager.show:clear()

      menu:onOpenLastDoc()

      assert.spy(UIManager.show).was.called(1)
      local widget = UIManager.getLastShownWidget()
      assert.are.equal("Cannot open last document", widget.text)
    end)
  end)

  describe("setUpdateItemTable", function()
    it("should populate menu items correctly", function()
      local menu = FileManagerMenu:new({ ui = mock_ui })
      menu:setUpdateItemTable()

      assert.truthy(menu.menu_items.filebrowser_settings)
      assert.truthy(menu.menu_items.file_search)
      assert.truthy(menu.menu_items.file_search_results)
      assert.truthy(menu.menu_items.open_previous_document)
    end)

    it("should toggle show finished files callback", function()
      local menu = FileManagerMenu:new({ ui = mock_ui })
      menu:setUpdateItemTable()

      local sub = menu.menu_items.filebrowser_settings.sub_item_table
      local show_finished_item = sub[1]
      assert.are.equal("Show finished books", show_finished_item.text)

      assert.is_false(show_finished_item.checked_func())
      show_finished_item.callback()
      assert
        .spy(mock_ui.file_chooser.toggleShowFilesMode).was
        .called_with(mock_ui.file_chooser, "show_finished")
    end)
  end)

  describe("onShowMenu", function()
    it("should show TouchMenu in touch device", function()
      local menu = FileManagerMenu:new({ ui = mock_ui })

      local UIManager = require("ui/uimanager")
      UIManager.show:clear()

      local TouchMenu = {
        new = spy.new(function(self, args)
          return { is_touch_menu = true, last_index = args.last_index }
        end),
      }
      package.loaded["ui/widget/touchmenu"] = TouchMenu

      menu:onShowMenu(2)

      assert.spy(UIManager.show).was.called(1)
      local container = UIManager.getLastShownWidget()
      assert.is_true(container.is_center_container)
      assert.is_true(container[1].is_touch_menu)
      assert.are.equal(2, container[1].last_index)

      package.loaded["ui/widget/touchmenu"] = nil
    end)

    it("should show Menu in non-touch device", function()
      mock_device.isTouchDevice = function()
        return false
      end
      local menu = FileManagerMenu:new({ ui = mock_ui })

      local UIManager = require("ui/uimanager")
      UIManager.show:clear()

      local Menu = {
        itemTableFromTouchMenu = function(tbl)
          return tbl
        end,
        new = spy.new(function(self, args)
          return { is_menu = true, last_index = args.last_index }
        end),
      }
      package.loaded["ui/widget/menu"] = Menu

      menu:onShowMenu(1)

      assert.spy(UIManager.show).was.called(1)
      local container = UIManager.getLastShownWidget()
      assert.is_true(container.is_center_container)
      assert.is_true(container[1].is_menu)

      package.loaded["ui/widget/menu"] = nil
    end)
  end)

  describe("filebrowser sub_item_table callbacks and spin widgets", function()
    it("should test all filebrowser settings callbacks", function()
      local old_readhistory = package.loaded["readhistory"]
      package.loaded["readhistory"] = {
        updateDateTimeString = function() end,
        clearMissing = function() end,
      }
      local menu = FileManagerMenu:new({ ui = mock_ui })
      menu:setUpdateItemTable()

      local sub = menu.menu_items.filebrowser_settings.sub_item_table
      local mock_sub_menu = { updateItems = spy.new(function() end) }

      -- Find items by text/id
      for _, item in ipairs(sub) do
        if item.text_func and item.callback then
          local txt = item.text_func()
          assert.truthy(txt)
          -- Trigger callback which may show a SpinWidget
          item.callback(mock_sub_menu)
          local spin = require("ui/uimanager").getLastShownWidget()
          if spin and spin.callback then
            spin.value = 12
            spin.callback(spin)
          end
        elseif item.checked_func and item.callback then
          local _checked = item.checked_func()
          item.callback()
        end
      end
      package.loaded["readhistory"] = old_readhistory
    end)

    it("should test sorting and start with menu generators", function()
      local menu = FileManagerMenu:new({ ui = mock_ui })
      local sort_tbl = menu:getSortingMenuTable()
      assert.truthy(sort_tbl)
      assert.truthy(sort_tbl.text_func())
      for _, sub_itm in ipairs(sort_tbl.sub_item_table) do
        sub_itm.checked_func()
        sub_itm.callback()
      end

      local start_tbl = menu:getStartWithMenuTable()
      assert.truthy(start_tbl)
      assert.truthy(start_tbl.text_func())
      for _, sub_itm in ipairs(start_tbl.sub_item_table) do
        sub_itm.checked_func()
        sub_itm.callback()
      end
    end)
  end)

  describe("search, open last document, and plus menu items", function()
    it("should test file search callbacks", function()
      local menu = FileManagerMenu:new({ ui = mock_ui })
      menu:setUpdateItemTable()

      menu.menu_items.file_search.callback()
      assert.spy(mock_ui.filesearcher.onShowFileSearch).was.called()

      menu.menu_items.file_search_results.callback()
      assert.spy(mock_ui.filesearcher.onShowSearchResults).was.called()
    end)

    it(
      "should test open_previous_document text_func and hold_callback",
      function()
        local menu = FileManagerMenu:new({ ui = mock_ui })
        menu:setUpdateItemTable()

        local open_last = menu.menu_items.open_previous_document
        assert.truthy(open_last)
        assert.is_true(open_last.enabled_func())
        local text = open_last.text_func()
        assert.truthy(text)

        -- With open_last_menu_show_filename = true
        G_reader_settings:save("open_last_menu_show_filename", true)
        text = open_last.text_func()
        assert.truthy(text:find("Last:"))

        -- hold_callback
        open_last.hold_callback()
        local confirm = require("ui/uimanager").getLastShownWidget()
        assert.truthy(confirm.is_confirm_box)
        local opened = false
        menu.onOpenLastDoc = function()
          opened = true
        end
        confirm.ok_callback()
        assert.is_true(opened)
      end
    )

    it("should test plus_menu callback in non-touch device", function()
      mock_device.isTouchDevice = function()
        return false
      end
      local menu = FileManagerMenu:new({ ui = mock_ui })
      menu:setUpdateItemTable()
      assert.truthy(menu.menu_items.plus_menu)
      menu.menu_items.plus_menu.callback()
      assert.spy(mock_ui.tapPlus).was.called()
    end)
  end)

  describe("gestures, dimensions, search, and menu actions", function()
    it("should handle onTapShowMenu and onSwipeShowMenu gestures", function()
      local menu = FileManagerMenu:new({ ui = mock_ui })
      local shown = false
      menu.onShowMenu = function()
        shown = true
      end

      local tap_res = menu:onTapShowMenu({ pos = { x = 100, y = 50 } })
      assert.is_true(tap_res)
      assert.is_true(shown)

      shown = false
      menu.activation_menu = "swipe"
      local swipe_res = menu:onSwipeShowMenu({
        direction = "south",
        pos = { x = 100, y = 50 },
      })
      assert.is_true(swipe_res)
      assert.is_true(shown)
    end)

    it("should handle onMenuSearch and onShowKeyboardShortcuts", function()
      local menu = FileManagerMenu:new({ ui = mock_ui })
      menu.onShowMenu = function() end

      local UIManager = require("ui/uimanager")
      UIManager:clearBroadcastEvents()
      menu:onMenuSearch()
      local events = UIManager:getBroadcastEvents()
      assert.are.equal(1, #events)
      assert.are.equal("ShowMenuSearch", events[1].name)

      menu:onShowKeyboardShortcuts()
      local common_info = require("ui/elements/common_info_menu_table")
      assert.spy(common_info.keyboard_shortcuts.callback).was.called()
    end)

    it("should handle onSetDimensions and exitOrRestart", function()
      local menu = FileManagerMenu:new({ ui = mock_ui })
      local show_called = false
      menu.onShowMenu = function()
        show_called = true
      end
      menu.menu_container = { is_center_container = true, [1] = { last_index = 1 } }
      menu:onSetDimensions({ w = 800, h = 600 })
      assert.is_true(show_called)

      local exited = false
      menu:exitOrRestart(function()
        exited = true
      end)
      assert.is_true(exited)
    end)
  end)
end)
