describe("BookShortcuts plugin main module", function()
  local BookShortcuts, Dispatcher, lfs, util

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    BookShortcuts = require("plugins/bookshortcuts.koplugin/main")
    Dispatcher = require("dispatcher")
    lfs = require("libs/libkoreader-lfs")
    util = require("util")
  end)

  it("should initialize BookShortcuts plugin instance", function()
    local mock_ui = {
      menu = {
        registerToMainMenu = function() end,
      },
    }
    local plugin = BookShortcuts:new({
      ui = mock_ui,
    })

    assert.is_table(plugin)
    assert.is_table(plugin.shortcuts)
  end)

  it("should add, retrieve, and delete shortcuts", function()
    local mock_ui = {
      menu = {
        registerToMainMenu = function() end,
      },
    }
    local plugin = BookShortcuts:new({
      ui = mock_ui,
    })

    local tmp_file = os.tmpname()
    plugin:addShortcut(tmp_file)
    assert.is_true(plugin.shortcuts.data[tmp_file])
    assert.is_true(plugin.updated)

    local menu_items = plugin:getSubMenuItems()
    assert.is_table(menu_items)
    assert.is_true(#menu_items >= 4)

    plugin:deleteShortcut(tmp_file)
    assert.is_nil(plugin.shortcuts.data[tmp_file])

    os.remove(tmp_file)
  end)

  it("should flush settings when updated", function()
    local mock_ui = {
      menu = {
        registerToMainMenu = function() end,
      },
    }
    local plugin = BookShortcuts:new({
      ui = mock_ui,
    })

    plugin.updated = true
    plugin:onFlushSettings()
    assert.is_false(plugin.updated)
  end)

  it("should build main menu item structure", function()
    local mock_ui = {
      menu = {
        registerToMainMenu = function() end,
      },
    }
    local plugin = BookShortcuts:new({
      ui = mock_ui,
    })

    local menu_items = {}
    plugin:addToMainMenu(menu_items)
    assert.is_table(menu_items.book_shortcuts)
    assert.is_function(menu_items.book_shortcuts.sub_item_table_func)

    local items = menu_items.book_shortcuts.sub_item_table_func()
    assert.is_table(items)
  end)

  it("should register actions with Dispatcher for existing paths", function()
    local mock_ui = {
      menu = { registerToMainMenu = function() end },
    }
    local plugin = BookShortcuts:new({
      ui = mock_ui,
    })

    local tmp_file = os.tmpname()
    local registered_actions = {}
    local old_reg = Dispatcher.registerAction
    Dispatcher.registerAction = function(self_d, name, action)
      registered_actions[name] = action
    end

    plugin.shortcuts.data = {
      [tmp_file] = true,
      ["/non/existent/path/book.epub"] = true,
    }

    plugin:onDispatcherRegisterActions()
    assert.is_table(registered_actions[tmp_file])
    assert.are.equal("BookShortcut", registered_actions[tmp_file].event)
    assert.is_nil(registered_actions["/non/existent/path/book.epub"])

    Dispatcher.registerAction = old_reg
    os.remove(tmp_file)
  end)

  it(
    "should open book directly on onBookShortcut when target is a file",
    function()
      local opened_file = nil
      local ReaderUI = require("apps/reader/readerui")
      local old_show_reader = ReaderUI.showReader
      ReaderUI.showReader = function(self_r, file)
        opened_file = file
      end

      local mock_ui = {
        menu = { registerToMainMenu = function() end },
      }
      local plugin = BookShortcuts:new({ ui = mock_ui })

      local tmp_file = os.tmpname()
      plugin:onBookShortcut(tmp_file)
      assert.are.equal(tmp_file, opened_file)

      ReaderUI.showReader = old_show_reader
      os.remove(tmp_file)
    end
  )

  it(
    "should default folder action to file browser (FM) when setting is unset [exposes production bug in BookShortcuts:onBookShortcut()]",
    function()
      local old_read = G_reader_settings.read
      local old_save = G_reader_settings.save
      G_reader_settings.read = function(self_s, key)
        if key == "BookShortcuts_directory_action" then
          return nil -- Unset, defaults to FM
        end
        return old_read(self_s, key)
      end

      local changed_path = nil
      local mock_ui = {
        menu = { registerToMainMenu = function() end },
        file_chooser = {
          changeToPath = function(self_fc, p)
            changed_path = p
          end,
        },
      }
      local plugin = BookShortcuts:new({ ui = mock_ui })

      local tmp_dir = os.tmpname()
      os.remove(tmp_dir)
      lfs.mkdir(tmp_dir)

      local items = plugin:getSubMenuItems()
      local folder_action_menu = items[2]
      local fm_radio = folder_action_menu.sub_item_table[2]

      -- Production bug: checked_func returns false when setting is unset
      assert.is_true(fm_radio.checked_func())

      -- Production bug: onBookShortcut falls back to ReadHistory instead of FM
      plugin:onBookShortcut(tmp_dir)
      assert.are.equal(tmp_dir, changed_path)

      lfs.rmdir(tmp_dir)
      G_reader_settings.read = old_read
      G_reader_settings.save = old_save
    end
  )
end)
