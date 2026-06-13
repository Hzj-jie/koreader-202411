describe("filemanagermenu", function()
  local FileManagerMenu
  local mock_ui
  local mock_device
  local mock_reader_settings
  local mock_named_settings
  local mock_defaults
  local mock_gettext

  setup(function()
    require("commonrequire")
  end)

  before_each(function()
    mock_device = {
      screen = {
        getSize = function() return { w = 800, h = 600 } end,
        getWidth = function() return 800 end,
        getHeight = function() return 600 end,
      },
      hasKeyboard = function() return true end,
      hasKeys = function() return true end,
      hasFewKeys = function() return false end,
      hasScreenKB = function() return true end,
      isTouchDevice = function() return true end,
      supportsScreensaver = function() return true end,
    }
    package.loaded["device"] = mock_device

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
        if reader_settings_data[key] == nil then return true end
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
      activate_menu = spy.new(function() return named_settings_data.activate_menu end),
      show_file_in_bold = spy.new(function() return named_settings_data.show_file_in_bold end),
      set = {
        show_file_in_bold = spy.new(function(val) named_settings_data.show_file_in_bold = val end),
        collate = spy.new(function(val) named_settings_data.collate = val end),
      }
    }
    _G.G_named_settings = mock_named_settings

    mock_defaults = {
      read = spy.new(function(self, key)
        if key == "DTAP_ZONE_MENU" then
          return { x = 0, y = 0, w = 1, h = 0.1 }
        elseif key == "DTAP_ZONE_MENU_EXT" then
          return { x = 0, y = 0, w = 1, h = 0.2 }
        end
      end)
    }
    _G.G_defaults = mock_defaults

    package.loaded["ui/bidi"] = {
      filename = function(s) return s end,
      filepath = function(s) return s end,
      mirroredUILayout = function() return false end,
    }

    package.loaded["ui/widget/container/centercontainer"] = {
      new = spy.new(function(self, _args)
        local obj = { is_center_container = true }
        return setmetatable(obj, {
          __newindex = function(t, k, v) rawset(t, k, v) end,
          __index = function(t, k) return rawget(t, k) end
        })
      end)
    }

    package.loaded["ui/widget/container/inputcontainer"] = {
      new = function(s, args)
        local inst = setmetatable(args or {}, { __index = s })
        if inst.init then inst:init() end
        return inst
      end,
      extend = function(self, child)
        child = child or {}
        child.key_events = {}
        child.registerTouchZones = spy.new(function() end)
        return setmetatable(child, {
          __index = self,
        })
      end,
      showWidget = function(self, widget, ...)
        require("ui/uimanager"):show(widget, ...)
      end,
    }

    package.loaded["apps/common_menu"] = {
      exitOrRestart = spy.new(function(self, cb) cb() end),
    }

    package.loaded["ui/widget/confirmbox"] = {
      new = spy.new(function(self, args)
        return {
          is_confirm_box = true,
          text = args.text,
          ok_text = args.ok_text,
          ok_callback = args.ok_callback,
        }
      end)
    }

    package.loaded["ui/widget/infomessage"] = {
      new = spy.new(function(self, args)
        return {
          is_info_message = true,
          text = args.text,
        }
      end)
    }


    package.loaded["ui/event"] = {
      new = function(self, name) return { name = name } end,
    }

    package.loaded["ffi/util"] = {
      template = function(tmpl, ...)
        local args = { ... }
        return tmpl:gsub("%%(%d+)", function(n)
          return tostring(args[tonumber(n)])
        end)
      end
    }

    package.loaded["ui/widget/keyvaluepage"] = {
      getDefaultItemsPerPage = function() return 15 end,
    }

    package.loaded["pluginloader"] = {
      genPluginManagerSubItem = function() return {} end,
    }

    package.loaded["ui/size"] = {
      margin = { fullscreen_popout = 10 },
    }

    package.loaded["ui/widget/spinwidget"] = {
      new = spy.new(function(self, args) return args end),
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
      broadcastEvent = spy.new(function(self, ev)
        table.insert(broadcast_events, ev)
      end),
      getLastShownWidget = function() return last_shown_widget end,
      getLastClosedWidget = function() return last_closed_widget end,
      getBroadcastEvents = function() return broadcast_events end,
      clearBroadcastEvents = function() broadcast_events = {} end,
    }

    package.loaded["apps/filemanager/filemanagerutil"] = {
      showChooseDialog = spy.new(function() end),
    }

    package.loaded["libs/libkoreader-lfs"] = {
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

    package.loaded["util"] = {
      splitFilePathName = function(path)
        local dir, name = path:match("^(.-)([^/]*)$")
        return dir, name
      end,
      backup_dir = function() return "/backup" end,
    }

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
      end)
    }
    package.loaded["ui/elements/filemanager_menu_order"] = {}
    package.loaded["ui/elements/screensaver_menu"] = {}
    package.loaded["ui/elements/common_settings_menu_table"] = {}
    package.loaded["ui/elements/physical_buttons"] = {}
    package.loaded["ui/elements/cloud_storage_menu_table"] = {}
    package.loaded["ui/elements/common_info_menu_table"] = {
      keyboard_shortcuts = {
        callback = spy.new(function() end)
      }
    }
    package.loaded["ui/elements/common_exit_menu_table"] = {}

    mock_gettext = setmetatable({
      ngettext = function(sing, plur, n) return n == 1 and sing or plur end,
    }, {
      __call = function(self, text) return text end
    })
    package.loaded["gettext"] = mock_gettext

    mock_ui = {
      file_chooser = {
        show_finished = false,
        show_hidden = false,
        show_unsupported = false,
        items_per_page_default = 10,
        font_size = 16,
        getItemFontSize = function(_ipp) return 16 end,
        toggleShowFilesMode = spy.new(function() end),
        refreshPath = spy.new(function() end),
        getCollate = function()
          return { can_collate_mixed = true, text = "Alphabetic" }
        end,
        collates = {
          alphabetic = { text = "Alphabetic", menu_order = 1 }
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
    }

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
    local menu = FileManagerMenu:new{ ui = mock_ui }
    assert.truthy(menu.key_events.ShowMenu)
    assert.truthy(menu.key_events.OpenLastDoc)
    assert.truthy(menu.key_events.ShowKeyboardShortcuts)
  end)

  it("should register touch zones on initGesListener", function()
    local menu = FileManagerMenu:new{ ui = mock_ui }
    menu:initGesListener()
    assert.spy(menu.registerTouchZones).was.called(1)
  end)

  describe("onOpenLastDoc", function()
    it("should open last document if exists and close menu", function()
      local menu = FileManagerMenu:new{ ui = mock_ui }
      menu.menu_container = { is_center_container = true, [1] = { last_index = 1 } }

      local ReaderUI = { showReader = spy.new(function() end) }
      package.loaded["apps/reader/readerui"] = ReaderUI

      menu:onOpenLastDoc()

      assert.spy(ReaderUI.showReader).was.called_with(ReaderUI, "/books/book1.epub")
      assert.is_nil(menu.menu_container)
      package.loaded["apps/reader/readerui"] = nil
    end)

    it("should show info message if last document does not exist", function()
      local menu = FileManagerMenu:new{ ui = mock_ui }
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
      local menu = FileManagerMenu:new{ ui = mock_ui }
      menu:setUpdateItemTable()

      assert.truthy(menu.menu_items.filebrowser_settings)
      assert.truthy(menu.menu_items.file_search)
      assert.truthy(menu.menu_items.file_search_results)
      assert.truthy(menu.menu_items.open_previous_document)
    end)

    it("should toggle show finished files callback", function()
      local menu = FileManagerMenu:new{ ui = mock_ui }
      menu:setUpdateItemTable()

      local sub = menu.menu_items.filebrowser_settings.sub_item_table
      local show_finished_item = sub[1]
      assert.are.equal("Show finished books", show_finished_item.text)

      assert.is_false(show_finished_item.checked_func())
      show_finished_item.callback()
      assert.spy(mock_ui.file_chooser.toggleShowFilesMode).was.called_with(mock_ui.file_chooser, "show_finished")
    end)
  end)

  describe("onShowMenu", function()
    it("should show TouchMenu in touch device", function()
      local menu = FileManagerMenu:new{ ui = mock_ui }

      local UIManager = require("ui/uimanager")
      UIManager.show:clear()

      local TouchMenu = {
        new = spy.new(function(self, args)
          return { is_touch_menu = true, last_index = args.last_index }
        end)
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
  end)
end)
