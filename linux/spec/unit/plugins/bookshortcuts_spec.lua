describe("BookShortcuts plugin main module", function()
  local BookShortcuts

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    BookShortcuts = require("plugins/bookshortcuts.koplugin/main")
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
end)
