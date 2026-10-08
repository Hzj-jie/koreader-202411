describe("Unsynced / Pending Documents Feature", function()
  local UIManager, SyncService
  local AnnotationSyncPlugin, test_utils, json, util
  local readerui, sync_instance
  local test_data_dir = require("datastorage"):getDataDir()
    .. "/test_unsynced_docs_tmp"
  local old_getDataDir

  setup(function()
    require("commonrequire")
    test_utils = require("plugins/AnnotationSync.koplugin/test_utils")
    disable_plugins()
    local plugin_path = "plugins/AnnotationSync.koplugin/?.lua"
    package.path = plugin_path .. ";" .. package.path

    UIManager = require("ui/uimanager")
    SyncService = require("apps/cloudstorage/syncservice")
    json = require("json")
    util = require("util")

    AnnotationSyncPlugin = require("plugins/AnnotationSync.koplugin/main")

    old_getDataDir = test_utils.setup_test_env(test_data_dir)
    os.execute("mkdir -p " .. test_data_dir .. "/plugins")

    G_reader_settings:save("cloud_download_dir", "http://mock-server")
    G_reader_settings:save(
      "cloud_server_object",
      json.encode({ url = "http://mock-server", type = "webdav" })
    )

    readerui, sync_instance = test_utils.init_integration_context(
      "spec/front/unit/data/juliet.epub",
      AnnotationSyncPlugin
    )
  end)

  teardown(function()
    if readerui then
      readerui:onClose()
    end
    test_utils.teardown_test_env(test_data_dir, old_getDataDir)
    UIManager:quit()
    package.loaded["plugins/AnnotationSync.koplugin/main"] = nil
    package.loaded["plugins/AnnotationSync.koplugin/menus"] = nil
  end)

  before_each(function()
    os.remove(sync_instance.manager:changedDocumentsFile())
  end)

  it(
    "verifies that Sync All keeps the files it failed to sync pending",
    function()
      -- 1. Setup two changed documents
      local file1 = readerui.document.file
      local file2 = test_data_dir .. "/missing_file.epub"

      -- Write a dummy file for file2 so it exists (otherwise it is automatically removed as missing)
      local f = io.open(file2, "w")
      f:write("dummy")
      f:close()

      sync_instance.manager:addToChangedDocumentsFile(file1)
      sync_instance.manager:addToChangedDocumentsFile(file2)

      -- 2. Mock SyncService to fail for both files
      local old_sync = SyncService.sync
      local restore_jobs = test_utils.run_jobs_inline()
      finally(function()
        SyncService.sync = old_sync
        restore_jobs()
        os.remove(file2)
      end)
      local tries = 0
      SyncService.sync = function(server, local_path, callback, is_silent, finish_cb)
        tries = tries + 1
        -- Simulate failure
        if finish_cb then
          finish_cb(false)
        end
        return nil
      end

      -- 3. Run Sync All
      sync_instance.manager:syncAllChangedDocuments()
      fastforward_ui_events()

      -- 4. Verify results
      assert.is_equal(2, tries)
      local count, pending = sync_instance.manager:getPendingChangedDocuments()
      assert.is_equal(2, count)
      assert.truthy(util.arrayContains(pending, file1))
      assert.truthy(util.arrayContains(pending, file2))
    end
  )

  it(
    "verifies that show_pending_documents constructs the menu and handles actions correctly",
    function()
      local file1 = readerui.document.file
      sync_instance.manager:addToChangedDocumentsFile(file1)

      local menus = require("plugins/AnnotationSync.koplugin/menus")
      local Menu = require("ui/widget/menu")
      local ConfirmBox = require("ui/widget/confirmbox")

      local Widget = require("ui/widget/widget")
      local Geom = require("ui/geometry")
      local MockWidget = Widget:extend({
        dimen = Geom:new({ w = 0, h = 0 }),
        onShow = function() end,
        paintTo = function() end,
        free = function() end,
        handleEvent = function() end,
      })
      local MockMenu = MockWidget:extend({
        debugStr = function()
          return "MockMenu"
        end,
      })
      local MockConfirmBox = MockWidget:extend({
        debugStr = function()
          return "MockConfirmBox"
        end,
      })

      local menu_shown = false
      local menu_items = {}
      local old_Menu_new = Menu.new
      Menu.new = function(this, o)
        menu_shown = true
        menu_items = o.item_table or {}
        return MockMenu:new(o)
      end

      local confirm_shown = false
      local confirm_opts = {}
      local old_ConfirmBox_new = ConfirmBox.new
      ConfirmBox.new = function(this, o)
        confirm_shown = true
        confirm_opts = o
        return MockConfirmBox:new(o)
      end

      -- 1. Show pending documents menu
      menus.show_pending_documents(sync_instance)

      assert.is_true(menu_shown)
      assert.is_equal(1, #menu_items)
      assert.is_equal("juliet.epub", menu_items[1].text)

      -- 2. Emulate tapping the document
      menu_items[1].callback()
      assert.is_true(confirm_shown)
      assert.truthy(confirm_opts.text:match("juliet%.epub"))
      assert.is_not_nil(confirm_opts.other_buttons)

      -- 3. Emulate clicking "Remove from list"
      confirm_opts.other_buttons[1][1].callback()

      -- Check that it is removed
      local count, _ = sync_instance.manager:getPendingChangedDocuments()
      assert.is_equal(0, count, "Document should be removed from changed list")

      -- Cleanup
      Menu.new = old_Menu_new
      ConfirmBox.new = old_ConfirmBox_new
    end
  )

  it(
    "'Sync now' syncs the book in the background and leaves the list closed",
    function()
      local juliet = readerui.document.file
      local other = test_data_dir .. "/other.epub"
      sync_instance.manager:addToChangedDocumentsFile(other)
      sync_instance.manager:addToChangedDocumentsFile(juliet)

      local menus = require("plugins/AnnotationSync.koplugin/menus")
      local shown = {}
      local old_show = UIManager.show
      local restore_jobs = test_utils.run_jobs_inline()
      finally(function()
        UIManager.show = old_show
        restore_jobs()
        for _, w in ipairs(shown) do
          UIManager:closeIfShown(w)
        end
      end)
      UIManager.show = function(self, w, ...)
        table.insert(shown, w)
        return old_show(self, w, ...)
      end

      menus.show_pending_documents(sync_instance)
      local menu = shown[1]
      -- Tap juliet.epub, sorted first.
      menu:onMenuSelect(menu.item_table[1])
      local box = shown[2]
      -- Tap "Sync now".
      box[1][1][1][1][3].buttons[1][2].callback()

      assert.is_false(UIManager:isWindowWidget(menu))
      assert.is_false(UIManager:isWindowWidget(box))
      local menus_shown, texts = 0, {}
      for _, w in ipairs(shown) do
        if w.title == "Pending Documents" then
          menus_shown = menus_shown + 1
        elseif type(w.text) == "string" then
          table.insert(texts, w.text)
        end
      end
      assert.is_equal(1, menus_shown)
      assert.are.same({
        "Do you want to sync this document?\n\njuliet.epub",
        "Syncing in the background: juliet.epub",
        "Synced: juliet.epub",
      }, texts)
      local _, pending = sync_instance.manager:getPendingChangedDocuments()
      assert.are.same({ other }, pending)
    end
  )

  it(
    "can scan opened books in readhistory across all sidecar storage methods",
    function()
      local readhistory = require("readhistory")
      local util = require("util")
      local old_hist = readhistory.hist
      readhistory.hist = util.tableDeepCopy(old_hist)

      local scan_dir = test_data_dir .. "/test_scan_lib"
      os.execute("mkdir -p " .. scan_dir .. "/book1.sdr")
      os.execute("touch " .. scan_dir .. "/book1.epub")
      os.execute("touch " .. scan_dir .. "/book1.sdr/metadata.epub.lua")

      table.insert(
        readhistory.hist,
        { file = scan_dir .. "/book1.epub", time = os.time() }
      )

      local count, added =
        sync_instance.manager:scanLibraryForUnsyncedDocuments()
      assert.is_true(count >= 1)
      assert.is_true(added[scan_dir .. "/book1.epub"])
      assert.is_true(sync_instance.manager:getPendingChangedDocuments() > 0)

      os.execute("rm -rf " .. scan_dir)
      readhistory.hist = old_hist
    end
  )

  it(
    "preserves existing queue order and appends newly discovered books during library scan",
    function()
      local readhistory = require("readhistory")
      local util = require("util")
      local old_hist = readhistory.hist
      readhistory.hist = util.tableDeepCopy(old_hist)

      local orig_dispatch = sync_instance.manager._dispatchNextSync
      sync_instance.manager._dispatchNextSync = function() end

      local scan_dir = test_data_dir .. "/test_scan_order"
      local doc_a = scan_dir .. "/book_a.epub"
      local doc_b = scan_dir .. "/book_b.epub"
      local doc_c = scan_dir .. "/book_c.epub"
      os.execute("mkdir -p " .. scan_dir .. "/book_b.sdr " .. scan_dir .. "/book_c.sdr")
      os.execute("touch " .. doc_a .. " " .. doc_b .. " " .. doc_c)
      os.execute("touch " .. scan_dir .. "/book_b.sdr/metadata.epub.lua " .. scan_dir .. "/book_c.sdr/metadata.epub.lua")

      finally(function()
        readhistory.hist = old_hist
        sync_instance.manager._dispatchNextSync = orig_dispatch
        os.execute("rm -rf " .. scan_dir)
      end)

      sync_instance.manager:_writeChangedDocumentsFile({ doc_a, doc_b })

      readhistory.hist = {
        { file = doc_b, time = os.time() },
        { file = doc_c, time = os.time() },
      }

      sync_instance.manager:scanLibraryForUnsyncedDocuments()

      assert.are.same(
        { doc_a, doc_b, doc_c },
        sync_instance.manager:_loadChangedDocuments()
      )
    end
  )
end)
