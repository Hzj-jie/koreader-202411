describe("OPDS main plugin module", function()
  local OPDS, OPDSCatalog, Dispatcher, FileManager, UIManager

  setup(function()
    require("commonrequire")
    OPDS = require("plugins/opds.koplugin/main")
    OPDSCatalog = require("plugins/opds.koplugin/opdscatalog")
    Dispatcher = require("dispatcher")
    FileManager = require("apps/filemanager/filemanager")
    UIManager = require("ui/uimanager")
  end)

  local orig_showCatalog, orig_onExit
  local orig_close, orig_showFiles, orig_instance, orig_registerAction
  local catalog_shown, closed_widgets, shown_files, refreshed, registered_actions

  before_each(function()
    catalog_shown = false
    closed_widgets = {}
    shown_files = {}
    refreshed = false
    registered_actions = {}

    orig_showCatalog = OPDSCatalog.showCatalog
    orig_onExit = OPDSCatalog.onExit
    orig_close = UIManager.close
    orig_showFiles = FileManager.showFiles
    orig_instance = FileManager.instance
    orig_registerAction = Dispatcher.registerAction

    OPDSCatalog.showCatalog = function(_self)
      catalog_shown = true
    end
    UIManager.close = function(_self, widget)
      table.insert(closed_widgets, widget)
    end
    FileManager.showFiles = function(_self, dir)
      table.insert(shown_files, dir)
    end
    Dispatcher.registerAction = function(self_disp, name, val)
      registered_actions[name] = val
      return orig_registerAction(self_disp, name, val)
    end
  end)

  after_each(function()
    OPDSCatalog.showCatalog = orig_showCatalog
    OPDSCatalog.onExit = orig_onExit
    UIManager.close = orig_close
    FileManager.showFiles = orig_showFiles
    FileManager.instance = orig_instance
    Dispatcher.registerAction = orig_registerAction
    Dispatcher:removeAction("opds_show_catalog")
  end)

  it("should initialize OPDS plugin, register dispatcher actions, and register to main menu", function()
    local registered_to_menu = false
    local mock_ui = {
      menu = {
        registerToMainMenu = function(_self, plugin)
          if plugin.name == "opds" then
            registered_to_menu = true
          end
        end,
      },
    }

    local plugin = OPDS:new({ ui = mock_ui })
    assert.is_table(plugin)
    assert.are.equal("opds", plugin.name)
    assert.is_true(registered_to_menu)

    local action = registered_actions["opds_show_catalog"]
    assert.is_table(action)
    assert.are.equal("ShowOPDSCatalog", action.event)
    assert.is_true(action.filemanager)
  end)

  it("should add opds to main menu in FileManager mode and omit in Reader mode", function()
    local fm_ui = {
      view = nil,
      menu = { registerToMainMenu = function() end },
    }
    local fm_plugin = OPDS:new({ ui = fm_ui })

    local fm_menu_items = {}
    fm_plugin:addToMainMenu(fm_menu_items)
    assert.is_table(fm_menu_items.opds)
    assert.are.equal("OPDS catalog", fm_menu_items.opds.text)

    -- In Reader mode (view ~= nil), menu item should not be added
    local reader_ui = {
      view = { is_reader_view = true },
      menu = { registerToMainMenu = function() end },
    }
    local reader_plugin = OPDS:new({ ui = reader_ui })

    local reader_menu_items = {}
    reader_plugin:addToMainMenu(reader_menu_items)
    assert.is_nil(reader_menu_items.opds)
  end)

  it("should trigger showCatalog on callback and handle exit with FileManager.instance", function()
    local mock_ui = {
      menu = { registerToMainMenu = function() end },
      onRefresh = function() refreshed = true end,
    }
    local plugin = OPDS:new({ ui = mock_ui })

    local menu_items = {}
    plugin:addToMainMenu(menu_items)
    menu_items.opds.callback()

    assert.is_true(catalog_shown)

    -- Test OPDSCatalog:onExit when FileManager.instance is present
    FileManager.instance = { is_active = true }
    OPDSCatalog:onExit()

    assert.are.equal(1, #closed_widgets)
    assert.are.equal(OPDSCatalog, closed_widgets[1])
    assert.is_true(refreshed)
    assert.are.equal(0, #shown_files)
  end)

  it("should handle OPDSCatalog onExit by showing download dir when FileManager.instance is nil", function()
    local mock_ui = {
      menu = { registerToMainMenu = function() end },
      onRefresh = function() refreshed = true end,
    }
    local plugin = OPDS:new({ ui = mock_ui })

    local res = plugin:onShowOPDSCatalog()
    assert.is_true(res)
    assert.is_true(catalog_shown)

    FileManager.instance = nil
    G_reader_settings:save("download_dir", "/books/downloads")
    OPDSCatalog:onExit()

    assert.are.equal(1, #closed_widgets)
    assert.are.equal(OPDSCatalog, closed_widgets[1])
    assert.is_false(refreshed)
    assert.are.equal(1, #shown_files)
    assert.are.equal("/books/downloads", shown_files[1])
  end)
end)
