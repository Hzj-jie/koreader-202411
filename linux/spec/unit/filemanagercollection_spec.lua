describe("filemanagercollection", function()
  local FileManagerCollection
  local mock_read_collection
  local mock_confirm_box
  local mock_info_message
  local mock_input_dialog
  local mock_menu
  local mock_button_dialog
  local mock_sort_widget
  local mock_ui
  local mock_gettext
  local match = require("luassert.match")


  setup(function()
    require("commonrequire")
  end)

  before_each(function()
    _G.G_named_settings = {
      home_dir = function() return "/home/user" end
    }

    mock_read_collection = {
      default_collection_name = "favorites",
      coll = {
        favorites = {
          { text = "Book 1", file = "/books/book1.epub", order = 1 },
          { text = "Book 2", file = "/books/book2.pdf", order = 2 },
        },
        ["Sci-Fi"] = {
          { text = "Book 3", file = "/books/book3.epub", order = 1 },
        }
      },
      coll_order = {
        favorites = 1,
        ["Sci-Fi"] = 2,
      },
      removeItem = spy.new(function(self, file, coll_name)
        local list = mock_read_collection.coll[coll_name]
        if not list then return end
        for i, item in ipairs(list) do
          if item.file == file then
            table.remove(list, i)
            break
          end
        end
      end),
      addItem = spy.new(function(self, file, coll_name)
        if not mock_read_collection.coll[coll_name] then
          mock_read_collection.coll[coll_name] = {}
        end
        local list = mock_read_collection.coll[coll_name]
        table.insert(list, { text = file:match("([^/]+)$"), file = file, order = #list + 1 })
      end),
      isFileInCollection = spy.new(function(self, file, coll_name)
        local list = mock_read_collection.coll[coll_name] or {}
        for _, item in ipairs(list) do
          if item.file == file then return true end
        end
        return false
      end),
      getOrderedCollection = spy.new(function(self, coll_name)
        return mock_read_collection.coll[coll_name] or {}
      end),
      updateCollectionOrder = spy.new(function(self, coll_name, item_table)
        mock_read_collection.coll[coll_name] = item_table
      end),
      getCollectionsWithFile = spy.new(function(self, file)
        local res = {}
        for name, list in pairs(mock_read_collection.coll) do
          for _, item in ipairs(list) do
            if item.file == file then
              res[name] = true
              break
            end
          end
        end
        return res
      end),
      removeCollection = spy.new(function(self, name)
        mock_read_collection.coll[name] = nil
        mock_read_collection.coll_order[name] = nil
      end),
      renameCollection = spy.new(function(self, old_name, new_name)
        mock_read_collection.coll[new_name] = mock_read_collection.coll[old_name]
        mock_read_collection.coll[old_name] = nil
        mock_read_collection.coll_order[new_name] = mock_read_collection.coll_order[old_name]
        mock_read_collection.coll_order[old_name] = nil
      end),
      addCollection = spy.new(function(self, name)
        mock_read_collection.coll[name] = {}
        mock_read_collection.coll_order[name] = 100
      end),
      updateCollectionListOrder = spy.new(function() end),
      addRemoveItemMultiple = spy.new(function() end),
      addItemsMultiple = spy.new(function() end),
    }
    package.loaded["readcollection"] = mock_read_collection

    package.loaded["ui/bidi"] = {
      filename = function(s) return s end,
    }

    package.loaded["device"] = {
      hasKeyboard = function() return true end,
      canExecuteScript = function() return false end,
    }

    package.loaded["docsettings"] = {
      hasSidecarFile = function() return false end,
      open = function() return {} end,
    }

    package.loaded["apps/filemanager/filemanagerutil"] = {
      genStatusButtonsRow = function() return { text = "Mock Status Row" } end,
      genResetSettingsButton = function() return { text = "Mock Reset Button" } end,
      genBookInformationButton = function() return { text = "Mock Info Button" } end,
      genShowFolderButton = function() return { text = "Mock Show Folder Button" } end,
      genBookCoverButton = function() return { text = "Mock Cover Button" } end,
      genBookDescriptionButton = function() return { text = "Mock Desc Button" } end,
    }

    mock_menu = {
      new = spy.new(function(self, args)
        local obj = {
          is_menu = true,
          subtitle = args.subtitle,
          onMenuSelect = args.onMenuSelect,
          onMenuChoice = args.onMenuChoice,
          onMenuHold = args.onMenuHold,
          ui = args.ui,
          _manager = args._manager,
          collection_name = args.collection_name,
          paths = {},
          switchItemTable = spy.new(function(s, title, item_table, idx, dummy, subtitle) -- luacheck: ignore 212
            s.title = title
            s.item_table = item_table
            s.subtitle = subtitle
          end),
          updateItems = spy.new(function() end),
          showWidget = function(self, widget, ...)
            require("ui/uimanager"):show(widget, ...)
          end,
        }
        return obj
      end)
    }
    package.loaded["ui/widget/menu"] = mock_menu

    mock_confirm_box = {
      new = spy.new(function(self, args)
        return {
          is_confirm_box = true,
          text = args.text,
          ok_text = args.ok_text,
          ok_callback = args.ok_callback,
        }
      end)
    }
    package.loaded["ui/widget/confirmbox"] = mock_confirm_box

    mock_info_message = {
      new = spy.new(function(self, args)
        return {
          is_info_message = true,
          text = args.text,
        }
      end)
    }
    package.loaded["ui/widget/infomessage"] = mock_info_message

    mock_input_dialog = {
      new = spy.new(function(self, args)
        local obj
        obj = {
          is_input_dialog = true,
          title = args.title,
          input = args.input,
          buttons = args.buttons,
          getInputText = function() return obj.mock_input_value or args.input or "" end,
        }
        return obj
      end)
    }
    package.loaded["ui/widget/inputdialog"] = mock_input_dialog

    mock_button_dialog = {
      new = spy.new(function(self, args)
        return {
          is_button_dialog = true,
          title = args.title,
          buttons = args.buttons,
        }
      end)
    }
    package.loaded["ui/widget/buttondialog"] = mock_button_dialog

    mock_sort_widget = {
      new = spy.new(function(self, args)
        return {
          is_sort_widget = true,
          title = args.title,
          item_table = args.item_table,
          callback = args.callback,
        }
      end)
    }
    package.loaded["ui/widget/sortwidget"] = mock_sort_widget

    local last_shown_widget
    local last_closed_widget
    package.loaded["ui/uimanager"] = {
      broadcastEvent = spy.new(function() end),
      show = spy.new(function(self, widget)
        last_shown_widget = widget
      end),
      close = spy.new(function(self, widget)
        last_closed_widget = widget
      end),
      forceRepaint = spy.new(function() end),
      getLastShownWidget = function() return last_shown_widget end,
      getLastClosedWidget = function() return last_closed_widget end,
    }

    mock_gettext = setmetatable({
      ngettext = function(sing, plur, n) return n == 1 and sing or plur end,
    }, {
      __call = function(self, text) return text end
    })
    package.loaded["gettext"] = mock_gettext

    package.loaded["ffi/util"] = {
      template = function(tmpl, ...)
        local args = { ... }
        return tmpl:gsub("%%(%d+)", function(n)
          return tostring(args[tonumber(n)])
        end)
      end
    }

    package.loaded["util"] = {
      tableSize = function(t)
        local count = 0
        for _ in pairs(t) do count = count + 1 end
        return count
      end,
      tableDeepCopy = function(t)
        local copy = {}
        for k, v in pairs(t) do
          if type(v) == "table" then
            copy[k] = package.loaded["util"].tableDeepCopy(v)
          else
            copy[k] = v
          end
        end
        return copy
      end
    }

    mock_ui = {
      menu = {
        registerToMainMenu = spy.new(function() end),
      },
      file_chooser = {
        refreshPath = spy.new(function() end),
      },
      bookinfo = {
        extendProps = function(props, _file) return props end,
      }
    }

    package.loaded["apps/filemanager/filemanagercollection"] = nil
    FileManagerCollection = require("apps/filemanager/filemanagercollection")
  end)

  after_each(function()
    package.loaded["apps/filemanager/filemanagercollection"] = nil
    package.loaded["readcollection"] = nil
    package.loaded["ui/bidi"] = nil
    package.loaded["device"] = nil
    package.loaded["docsettings"] = nil
    package.loaded["apps/filemanager/filemanagerutil"] = nil
    package.loaded["ui/widget/menu"] = nil
    package.loaded["ui/widget/confirmbox"] = nil
    package.loaded["ui/widget/infomessage"] = nil
    package.loaded["ui/widget/inputdialog"] = nil
    package.loaded["ui/widget/buttondialog"] = nil
    package.loaded["ui/widget/sortwidget"] = nil
    package.loaded["ui/uimanager"] = nil
    package.loaded["gettext"] = nil
    package.loaded["ffi/util"] = nil
    package.loaded["util"] = nil
    _G.G_named_settings = nil
  end)

  it("should register to main menu on init", function()
    local manager = FileManagerCollection:new{ ui = mock_ui }
    assert.spy(mock_ui.menu.registerToMainMenu).was.called_with(mock_ui.menu, manager)
  end)

  it("should populate main menu items", function()
    local manager = FileManagerCollection:new{ ui = mock_ui }
    local menu_items = {}
    manager:addToMainMenu(menu_items)

    assert.truthy(menu_items.favorites)
    assert.are.equal("Favorites", menu_items.favorites.text)
    assert.truthy(menu_items.collections)
    assert.are.equal("Collections", menu_items.collections.text)
  end)

  describe("onShowColl (Viewing a collection)", function()
    it("should show the collection menu with items sorted by order", function()
      local manager = FileManagerCollection:new{ ui = mock_ui }

      local UIManager = require("ui/uimanager")
      UIManager.show:clear()

      manager:onShowColl("favorites")

      assert.spy(UIManager.show).was.called(1)
      local menu = UIManager.getLastShownWidget()
      assert.is_true(menu.is_menu)
      assert.are.equal("favorites", menu.collection_name)

      -- Verify items loaded and sorted (already sorted in mock: 1 then 2)
      assert.are.equal("Favorites (2)", menu.title)
      assert.are.equal(2, #menu.item_table)
      assert.are.equal("Book 1", menu.item_table[1].text)
      assert.are.equal("Book 2", menu.item_table[2].text)
    end)
  end)

  describe("onMenuChoice", function()
    it("should open file if not currently viewing a document", function()
      local manager = FileManagerCollection:new{ ui = mock_ui }
      mock_ui.document = nil
      mock_ui.openFile = spy.new(function() end)

      local item = { file = "/books/book1.epub" }
      manager:onMenuChoice(item)

      assert.spy(mock_ui.openFile).was.called_with(mock_ui, "/books/book1.epub")
    end)

    it("should switch document if viewing a different document", function()
      local manager = FileManagerCollection:new{ ui = mock_ui }
      mock_ui.document = { file = "/books/book2.pdf" }
      mock_ui.switchDocument = spy.new(function() end)

      local item = { file = "/books/book1.epub" }
      manager:onMenuChoice(item)

      assert.spy(mock_ui.switchDocument).was.called_with(mock_ui, "/books/book1.epub")
    end)
  end)

  describe("onMenuHold (context menu for a book in collection)", function()
    it("should show options including removal from collection", function()
      local manager = FileManagerCollection:new{ ui = mock_ui }
      manager.coll_menu = mock_menu:new({
        collection_name = "favorites",
        ui = mock_ui,
        _manager = manager,
      })
      manager.coll_menu.close_callback = spy.new(function() end)

      local UIManager = require("ui/uimanager")

      UIManager.show:clear()

      local item = { text = "Book 1", file = "/books/book1.epub", idx = 1 }
      local mock_menu_inst = {
        _manager = manager,
        ui = mock_ui,
        collection_name = "favorites",
        showWidget = function(self, widget, ...)
          UIManager:show(widget, ...)
        end,
      }
      manager.onMenuHold(mock_menu_inst, item)

      assert.spy(UIManager.show).was.called(1)
      local dialog = UIManager.getLastShownWidget()
      assert.is_true(dialog.is_button_dialog)
      assert.are.equal("Book 1", dialog.title)

      -- buttons layout:
      -- Row 1: Status buttons row
      -- Row 3: Reset settings, Add to Collection
      -- Row 4: Delete, Remove from collection
      -- Row 5: Show Folder, Book Info
      -- Row 6: Cover, Description
      assert.are.equal(6, #dialog.buttons)
      assert.are.equal("Remove from collection", dialog.buttons[4][2].text)

      -- Trigger remove callback
      spy.on(manager, "updateItemTable")
      dialog.buttons[4][2].callback()

      assert.spy(mock_read_collection.removeItem).was.called_with(match._, "/books/book1.epub", "favorites")
      assert.spy(manager.updateItemTable).was.called(1)
      assert.is_true(manager.files_updated)
    end)
  end)

  describe("showCollDialog (options for the viewing collection)", function()
    it("should show dialog with arrange and add options", function()
      local manager = FileManagerCollection:new{ ui = mock_ui }
      manager.coll_menu = {
        collection_name = "favorites",
        close_callback = spy.new(function() end)
      }

      local UIManager = require("ui/uimanager")
      UIManager.show:clear()

      manager:showCollDialog()

      assert.spy(UIManager.show).was.called(1)
      local dialog = UIManager.getLastShownWidget()
      assert.is_true(dialog.is_button_dialog)

      -- buttons:
      -- Row 1: Collections button
      -- Row 3: Arrange books
      -- Row 4: Add book to collection
      assert.are.equal(4, #dialog.buttons)
      assert.are.equal("Arrange books in collection", dialog.buttons[3][1].text)
      assert.are.equal("Add a book to collection", dialog.buttons[4][1].text)
    end)
  end)

  describe("onShowCollList (Viewing collections list)", function()
    it("should show collections list in normal mode", function()
      local manager = FileManagerCollection:new{ ui = mock_ui }

      local UIManager = require("ui/uimanager")
      UIManager.show:clear()

      manager:onShowCollList()

      assert.spy(UIManager.show).was.called(1)
      local menu = UIManager.getLastShownWidget()
      assert.is_true(menu.is_menu)
      assert.are.equal("appbar.menu", menu.onLeftButtonTap_icon or "appbar.menu") -- is normal mode icon

      assert.are.equal("Collections (2)", menu.title)
      assert.are.equal(2, #menu.item_table)
      assert.are.equal("Favorites", menu.item_table[1].text)
      assert.are.equal("favorites", menu.item_table[1].name)
      assert.are.equal(2, menu.item_table[1].mandatory) -- count of favorites is 2

      assert.are.equal("Sci-Fi", menu.item_table[2].text)
      assert.are.equal("Sci-Fi", menu.item_table[2].name)
      assert.are.equal(1, menu.item_table[2].mandatory) -- count is 1
    end)

    it("should show collections list in select mode for a book", function()
      local manager = FileManagerCollection:new{ ui = mock_ui }

      local UIManager = require("ui/uimanager")
      UIManager.show:clear()

      -- Let's select for "Book 1" (which is only in favorites)
      manager:onShowCollList("/books/book1.epub")

      assert.spy(UIManager.show).was.called(1)
      local menu = UIManager.getLastShownWidget()
      assert.is_true(menu.is_menu)

      assert.truthy(manager.selected_collections)
      assert.is_true(manager.selected_collections.favorites)
      assert.is_nil(manager.selected_collections["Sci-Fi"])

      -- item 1 (favorites) has checkmark
      assert.are.equal(manager.checkmark, menu.item_table[1].mandatory)
      -- item 2 (Sci-Fi) has spaces
      assert.are.equal("  ", menu.item_table[2].mandatory)
    end)
  end)

  describe("onCollListChoice", function()
    it("should open collection in normal mode", function()
      local manager = FileManagerCollection:new{ ui = mock_ui }
      manager.selected_collections = nil -- normal mode

      spy.on(manager, "onShowColl")

      local item = { name = "Sci-Fi" }
      local mock_menu_inst = {
        _manager = manager,
        ui = mock_ui,
      }
      manager.onCollListChoice(mock_menu_inst, item)

      assert.spy(manager.onShowColl).was.called_with(match._, "Sci-Fi")
    end)

    it("should toggle checkmark in select mode", function()
      local manager = FileManagerCollection:new{ ui = mock_ui }
      manager.selected_collections = { favorites = true } -- select mode
      manager.checkmark = "X"

      local item_table = {
        { name = "favorites", mandatory = "X", idx = 1 },
        { name = "Sci-Fi", mandatory = "  ", idx = 2 }
      }
      manager.coll_list = {
        item_table = item_table,
        switchItemTable = spy.new(function() end)
      }

      local mock_menu_inst = {
        _manager = manager,
        ui = mock_ui,
        item_table = item_table,
      }

      -- Choice 1: Toggle off Favorites
      manager.onCollListChoice(mock_menu_inst, item_table[1])
      assert.are.equal("  ", item_table[1].mandatory)
      assert.is_nil(manager.selected_collections.favorites)

      -- Choice 2: Toggle on Sci-Fi
      manager.onCollListChoice(mock_menu_inst, item_table[2])
      assert.are.equal("X", item_table[2].mandatory)
      assert.is_true(manager.selected_collections["Sci-Fi"])
    end)
  end)

  describe("addCollection", function()
    it("should prompt for name and call ReadCollection to add", function()
      local manager = FileManagerCollection:new{ ui = mock_ui }
      manager.coll_list = {
        item_table = {},
        switchItemTable = spy.new(function() end)
      }

      local UIManager = require("ui/uimanager")
      UIManager.show:clear()

      manager:addCollection()

      assert.spy(UIManager.show).was.called(1)
      local dialog = UIManager.getLastShownWidget()
      assert.is_true(dialog.is_input_dialog)
      assert.are.equal("Enter collection name", dialog.title)

      -- Submit name "New Coll"
      dialog.mock_input_value = "New Coll"
      dialog.buttons[1][2].callback() -- Save button

      assert.spy(mock_read_collection.addCollection).was.called_with(match._, "New Coll")
      assert.are.equal(1, #manager.coll_list.item_table)
      assert.are.equal("New Coll", manager.coll_list.item_table[1].name)
    end)
  end)

  describe("uimanagedCleanUp", function()
    it("closes coll_menu, collfile_dialog, and coll_list automatically", function()
      local fmc = FileManagerCollection:new{ ui = mock_ui }
      local dummy_menu = { name = "dummy_menu" }
      local dummy_dialog = { name = "dummy_dialog" }
      local dummy_list = { name = "dummy_list" }
      local stub = require("luassert.stub")
      local UIManager = require("ui/uimanager")

      stub(UIManager, "closeIfShown")

      fmc:showWidget(dummy_menu)
      fmc:showWidget(dummy_dialog)
      fmc:showWidget(dummy_list)

      fmc.coll_menu = dummy_menu
      fmc.collfile_dialog = dummy_dialog
      fmc.coll_list = dummy_list

      fmc:uimanagedCleanUp()

      assert.is_nil(fmc.coll_menu)
      assert.is_nil(fmc.collfile_dialog)
      assert.is_nil(fmc.coll_list)

      assert.stub(UIManager.closeIfShown).was_called_with(UIManager, dummy_menu)
      assert.stub(UIManager.closeIfShown).was_called_with(UIManager, dummy_dialog)
      assert.stub(UIManager.closeIfShown).was_called_with(UIManager, dummy_list)

      UIManager.closeIfShown:revert()
    end)
  end)
end)
