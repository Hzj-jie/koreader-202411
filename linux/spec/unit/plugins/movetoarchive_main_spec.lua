describe("MoveToArchive main plugin module", function()
  local MoveToArchive, DataStorage, UIManager, FileManager, DocSettings
  local settings_file

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    DataStorage = require("datastorage")
    UIManager = require("ui/uimanager")
    FileManager = require("apps/filemanager/filemanager")
    DocSettings = require("docsettings")

    settings_file = DataStorage:getSettingsDir() .. "/move_to_archive_settings.lua"
    MoveToArchive = require("plugins/movetoarchive.koplugin/main")
  end)

  teardown(function()
    os.remove(settings_file)
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))
  end)

  before_each(function()
    os.remove(settings_file)
  end)

  after_each(function()
    os.remove(settings_file)
  end)

  it("should initialize MoveToArchive plugin and register actions", function()
    local mock_menu = { registerToMainMenu = function() end }
    local instance = MoveToArchive:new({ ui = { menu = mock_menu } })
    instance:init()

    assert.is_table(instance)
    assert.are.equal("movetoarchive", instance.name)
    assert.is_function(instance.onDispatcherRegisterActions)
    instance:onDispatcherRegisterActions()
  end)

  it("should build main menu structure and test callbacks", function()
    local mock_ui = {
      menu = { registerToMainMenu = function() end },
      document = { file = "/books/fiction/book1.epub" },
      onExit = function() end,
    }
    local instance = MoveToArchive:new({ ui = mock_ui })
    instance:init()
    instance.archive_dir_path = "/archive/"
    instance.last_copied_from_dir = "/books/fiction/"

    local menu_items = {}
    instance:addToMainMenu(menu_items)

    local sub_items = menu_items.move_to_archive.sub_item_table
    assert.is_table(sub_items)
    assert.are.equal(5, #sub_items)

    -- 1. enabled_func check
    assert.is_true(sub_items[1].enabled_func())
    instance.archive_dir_path = "/books/fiction/"
    assert.is_false(sub_items[1].enabled_func())
    instance.archive_dir_path = "/archive/"

    -- 2. Go to archive folder
    local util = require("frontend/util")
    local orig_dir_exists = util.directoryExists
    util.directoryExists = function(p) return true end

    local shown_path
    instance.openFileBrowser = function(self_i, p) shown_path = p end
    sub_items[3].callback()
    assert.are.equal("/archive/", shown_path)

    -- 3. Go to last copied from folder
    sub_items[4].callback()
    assert.are.equal("/books/fiction/", shown_path)

    util.directoryExists = orig_dir_exists

    -- 4. Set archive folder
    local DownloadMgr = require("ui/downloadmgr")
    local orig_chooseDir = DownloadMgr.chooseDir
    local choose_callback
    DownloadMgr.chooseDir = function(self_dm)
      self_dm.onConfirm("/new_archive")
    end
    sub_items[5].callback()
    assert.are.equal("/new_archive/", instance.archive_dir_path)
    DownloadMgr.chooseDir = orig_chooseDir
  end)

  it("should handle onMoveToArchive for move and copy operations", function()
    local orig_show = UIManager.show
    local shown_widgets = {}
    UIManager.show = function(self_uim, w) table.insert(shown_widgets, w) end

    local mock_ui = {
      menu = { registerToMainMenu = function() end },
      document = { file = "/books/fiction/book1.epub" },
      onExit = function() end,
    }
    local instance = MoveToArchive:new({ ui = mock_ui })
    instance:init()
    instance.archive_dir_path = "/archive/"

    -- Mock FileManager and DocSettings methods
    local copied = false
    local moved = false
    FileManager.copyFile = function(self_fm, src, dst) copied = true end
    FileManager.moveFile = function(self_fm, src, dst) moved = true end
    DocSettings.updateLocation = function(src, dst, is_copy) end

    -- 1. Copy operation
    instance:onMoveToArchive(true)
    assert.is_true(copied)
    local confirm_copy = shown_widgets[#shown_widgets]
    assert.is_table(confirm_copy)
    assert.is_function(confirm_copy.cancel_callback)
    confirm_copy.cancel_callback()

    -- 2. Move operation
    instance:onMoveToArchive(false)
    assert.is_true(moved)
    local confirm_move = shown_widgets[#shown_widgets]
    assert.is_table(confirm_move)

    -- 3. When archive_dir_path is nil
    instance.archive_dir_path = nil
    instance:onMoveToArchive(false)
    local confirm_no_archive = shown_widgets[#shown_widgets]
    assert.is_table(confirm_no_archive)
    assert.is_function(confirm_no_archive.ok_callback)

    UIManager.show = orig_show
  end)

  it("should open file browser under different FileManager states", function()
    local exited = false
    local mock_ui = {
      menu = { registerToMainMenu = function() end },
      document = { file = "/books/fiction/book1.epub" },
      onExit = function() exited = true end,
    }
    local instance = MoveToArchive:new({ ui = mock_ui })
    instance:init()

    -- 1. When FileManager.instance exists
    local reinit_path
    FileManager.instance = {
      reinit = function(self_fm, path) reinit_path = path end,
    }
    instance:openFileBrowser("/target/path")
    assert.is_true(exited)
    assert.are.equal("/target/path", reinit_path)

    -- 2. When FileManager.instance is nil
    FileManager.instance = nil
    local show_files_path
    FileManager.showFiles = function(self_fm, path) show_files_path = path end
    instance:openFileBrowser("/another/path")
    assert.are.equal("/another/path", show_files_path)
  end)
end)
