describe("Exporter main plugin module", function()
  local Exporter, Device, NetworkMgr, ReaderHighlight, UIManager, filemanagerutil, lfs, BaseExporter
  local mock_menu, mock_ui, exporter_instance

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    Device = require("device")
    NetworkMgr = require("ui/network/manager")
    ReaderHighlight = require("apps/reader/modules/readerhighlight")
    UIManager = require("ui/uimanager")
    filemanagerutil = require("apps/filemanager/filemanagerutil")
    lfs = require("libs/libkoreader-lfs")
    BaseExporter = require("plugins/exporter.koplugin/base")
    Exporter = require("plugins/exporter.koplugin/main")
  end)

  before_each(function()
    G_reader_settings:save("exporter", {
      html = { enabled = true },
      json = { enabled = false },
      readwise = { enabled = false },
    })

    mock_menu = { registerToMainMenu = stub() }
    mock_ui = {
      menu = mock_menu,
      document = { file = "/dummy/path/test.epub" },
      annotation = { updatePageNumbers = stub() },
      view = { document = { file = "/dummy/path/test.epub" } },
    }
    exporter_instance = Exporter:new({ ui = mock_ui, path = "plugins/exporter.koplugin" })
  end)

  describe("Initialization and Actions", function()
    it("should initialize Exporter plugin instance and register actions", function()
      assert.is_table(exporter_instance)
      assert.are.equal("exporter", exporter_instance.name)
      assert.stub(mock_menu.registerToMainMenu).was.called(1)
      assert.is_table(exporter_instance.targets)
      assert.is_not_nil(exporter_instance.parser)

      exporter_instance:onDispatcherRegisterActions()
    end)

    it("should check readiness flags correctly", function()
      exporter_instance.targets.html.settings.enabled = true
      assert.is_true(exporter_instance:isReady())
      assert.is_true(exporter_instance:isDocReady())
      assert.is_true(exporter_instance:isReadyToExport())

      exporter_instance.ui.document = nil
      assert.is_false(exporter_instance:isDocReady())
      assert.is_false(exporter_instance:isReadyToExport())

      for _, target in pairs(exporter_instance.targets) do
        target.settings.enabled = false
      end
      assert.is_false(exporter_instance:isReady())
    end)

    it("should check requiresNetwork flag correctly", function()
      for _, target in pairs(exporter_instance.targets) do
        target.settings.enabled = false
      end
      assert.is_nil(exporter_instance:requiresNetwork())

      if exporter_instance.targets.readwise then
        exporter_instance.targets.readwise.settings.token = "test_token"
        exporter_instance.targets.readwise.settings.enabled = true
        assert.is_true(exporter_instance:requiresNetwork())
      end
    end)
  end)

  describe("Export Operations", function()
    it("should handle onExportCurrentNotes", function()
      local run_with_stub = stub(UIManager, "runWith", function(self_u, fn, msg)
        if type(fn) == "function" then fn() end
      end)
      exporter_instance.targets.html.settings.enabled = true
      exporter_instance.ui.document = { file = "test.epub" }
      exporter_instance.getDocumentClippings = function() return { ["Test Book"] = {} } end

      local export_clip_stub = stub(exporter_instance, "exportClippings")
      exporter_instance:onExportCurrentNotes()
      assert.stub(run_with_stub).was.called(1)
      assert.stub(mock_ui.annotation.updatePageNumbers).was.called(1)
      assert.stub(export_clip_stub).was.called(1)

      run_with_stub:revert()
      export_clip_stub:revert()
    end)

    it("should handle onExportAllNotes", function()
      local run_with_stub = stub(UIManager, "runWith", function(self_u, fn, msg)
        if type(fn) == "function" then fn() end
      end)
      exporter_instance.targets.html.settings.enabled = true

      local parse_hist_stub = stub(exporter_instance.parser, "parseHistory")
      parse_hist_stub.returns({
        ["Book 1"] = { { { page = 1, time = 100, text = "Note 1", note = "" } } },
        ["Empty Book"] = {},
      })
      local export_clip_stub = stub(exporter_instance, "exportClippings")

      exporter_instance:onExportAllNotes()
      assert.stub(run_with_stub).was.called(1)
      assert.stub(export_clip_stub).was.called(1)

      run_with_stub:revert()
      parse_hist_stub:revert()
      export_clip_stub:revert()
    end)

    it("should handle exportFilesNotes", function()
      local run_with_stub = stub(UIManager, "runWith", function(self_u, fn, msg)
        if type(fn) == "function" then fn() end
      end)
      local parse_files_stub = stub(exporter_instance.parser, "parseFiles")
      parse_files_stub.returns({
        ["Book 1"] = { { { page = 1, time = 100, text = "Note 1" } } },
      })
      local export_clip_stub = stub(exporter_instance, "exportClippings")

      exporter_instance:exportFilesNotes({ ["/path/to/book.epub"] = true })
      assert.stub(run_with_stub).was.called(1)
      assert.stub(export_clip_stub).was.called(1)

      run_with_stub:revert()
      parse_files_stub:revert()
      export_clip_stub:revert()
    end)

    it("should execute exportClippings for local and remote targets", function()
      local show_stub = stub(UIManager, "show")

      for _, target in pairs(exporter_instance.targets) do
        target.settings.enabled = false
      end

      -- Test local target success & failure
      exporter_instance.targets.html.settings.enabled = true
      exporter_instance.targets.html.export = function() return true end
      exporter_instance.targets.html.getFilePath = function() return "/path/to/notes.html" end

      local fake_clippings = {
        ["Book 1"] = { { { text = "Sample Highlight" } } }
      }

      exporter_instance:exportClippings(fake_clippings)
      assert.stub(show_stub).was.called()

      -- Test remote target with network
      exporter_instance.targets.html.settings.enabled = false
      if exporter_instance.targets.readwise then
        exporter_instance.targets.readwise.settings.token = "valid_token"
        exporter_instance.targets.readwise.settings.enabled = true
        exporter_instance.targets.readwise.export = function() return true end
        local run_online_stub = stub(NetworkMgr, "runWhenOnline", function(self_n, fn)
          if type(fn) == "function" then fn() end
        end)

        exporter_instance:exportClippings(fake_clippings)
        assert.stub(run_online_stub).was.called(1)

        run_online_stub:revert()
      end

      show_stub:revert()
    end)
  end)

  describe("Main Menu and Submenus", function()
    it("should populate mainMenu items and test submenus", function()
      local menu_items = {}
      exporter_instance:addToMainMenu(menu_items)

      assert.is_table(menu_items.exporter)
      local sub_items = menu_items.exporter.sub_item_table
      assert.is_table(sub_items)
      assert.is_true(#sub_items > 4)

      -- Test highlight styles submenu
      local styles_item
      for _, item in ipairs(sub_items) do
        if item.text == "Choose highlight styles" then
          styles_item = item
          break
        end
      end
      assert.is_not_nil(styles_item)
      assert.is_table(styles_item.sub_item_table)
      for _, st in ipairs(styles_item.sub_item_table) do
        assert.is_true(st.checked_func())
        st.callback() -- uncheck
        st.callback() -- recheck
      end

      -- Test choose export folder callback
      local choose_folder_stub = stub(exporter_instance, "chooseFolder")
      local choose_folder_item
      for _, item in ipairs(sub_items) do
        if item.text == "Choose export folder" then
          choose_folder_item = item
          break
        end
      end
      assert.is_not_nil(choose_folder_item)
      choose_folder_item.callback()
      assert.stub(choose_folder_stub).was.called(1)
      choose_folder_stub:revert()

      -- Test use book folder toggle
      local book_folder_item
      for _, item in ipairs(sub_items) do
        if item.text == "Use book folder for single export" then
          book_folder_item = item
          break
        end
      end
      assert.is_not_nil(book_folder_item)
      assert.is_falsy(book_folder_item.checked_func())
      book_folder_item.callback()
      assert.is_true(book_folder_item.checked_func())
      book_folder_item.callback()
      assert.is_falsy(book_folder_item.checked_func())
    end)

    it("should handle _gotoFolder in filemanager and reader modes", function()
      -- 1. In filechooser mode
      exporter_instance.ui.file_chooser = { changeToPath = stub() }
      exporter_instance:_gotoFolder("/path/to/folder")
      assert.stub(exporter_instance.ui.file_chooser.changeToPath).was.called_with(match.is_table(), "/path/to/folder")

      -- 2. In reader mode
      exporter_instance.ui.file_chooser = nil
      exporter_instance.ui.onExit = stub()
      local FileManager = require("apps/filemanager/filemanager")
      local show_files_stub = stub(FileManager, "showFiles")

      exporter_instance:_gotoFolder("/path/to/folder")
      assert.stub(exporter_instance.ui.onExit).was.called(1)
      assert.stub(show_files_stub).was.called_with(FileManager, "/path/to/folder")

      show_files_stub:revert()
    end)

    it("should handle chooseFolder dialog trigger", function()
      local show_choose_stub = stub(filemanagerutil, "showChooseDialog")
      exporter_instance:chooseFolder()
      assert.stub(show_choose_stub).was.called(1)

      -- Exercise caller_callback
      local caller_cb = show_choose_stub.calls[1].vals[2]
      caller_cb("/new/export/path")
      local settings = G_reader_settings:readTableRef("exporter")
      assert.are.equal("/new/export/path", settings.clipping_dir)

      show_choose_stub:revert()
    end)
  end)
end)
