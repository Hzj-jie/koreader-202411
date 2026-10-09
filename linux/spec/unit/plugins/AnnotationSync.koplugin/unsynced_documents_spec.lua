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

  -- Shows the pending books list and records every widget shown from then on
  -- (shown[1] is the list). Call the returned cleanup from the test's finally.
  local function open_pending_list()
    local menus = require("plugins/AnnotationSync.koplugin/menus")
    local shown = {}
    local old_show = UIManager.show
    UIManager.show = function(self, w, ...)
      table.insert(shown, w)
      return old_show(self, w, ...)
    end
    menus.show_pending_documents(sync_instance)
    return shown,
      function()
        UIManager.show = old_show
        for _, w in ipairs(shown) do
          UIManager:closeIfShown(w)
        end
      end
  end

  -- Taps the button labelled `text` in a ConfirmBox.
  local function tap(box, text)
    for _, row in ipairs(box[1][1][1][1][3].buttons) do
      for _, button in ipairs(row) do
        if button.text == text then
          return button.callback()
        end
      end
    end
    error("no button " .. text)
  end

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
    "'Sync' syncs the book in the background and keeps the list open",
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
      -- Tap "Sync".
      box[1][1][1][1][3].buttons[1][2].callback()

      assert.is_true(UIManager:isWindowWidget(menu))
      assert.is_false(UIManager:isWindowWidget(box))
      local menus_shown, texts = 0, {}
      for _, w in ipairs(shown) do
        if w.title == "Pending books" then
          menus_shown = menus_shown + 1
        elseif type(w.text) == "string" then
          table.insert(texts, w.text)
        end
      end
      assert.is_equal(1, menus_shown)
      assert.are.same({
        "Sync this book now?\n\njuliet.epub",
        "Syncing in the background: juliet.epub",
        "Synced: juliet.epub",
      }, texts)
      local _, pending = sync_instance.manager:getPendingChangedDocuments()
      assert.are.same({ other }, pending)
    end
  )

  it("'Cancel' closes the dialog and keeps the list open", function()
    sync_instance.manager:_writeChangedDocumentsFile({ readerui.document.file })
    local shown, cleanup = open_pending_list()
    finally(cleanup)
    local menu = shown[1]

    menu:onMenuSelect(menu.item_table[1])
    local box = shown[2]
    assert.is_true(UIManager:isWindowWidget(menu))
    tap(box, "Cancel")

    assert.is_false(UIManager:isWindowWidget(box))
    assert.is_true(UIManager:isWindowWidget(menu))
  end)

  it(
    "'Remove from list' updates the list in place and stays on its page",
    function()
      local files = {}
      for i = 1, 30 do
        table.insert(files, string.format("%s/book%02d.epub", test_data_dir, i))
      end
      sync_instance.manager:_writeChangedDocumentsFile(files)
      local shown, cleanup = open_pending_list()
      finally(cleanup)
      local menu = shown[1]
      menu:onNextPage()
      assert.is_equal(2, menu.page)

      -- The first book on page 2.
      local item = menu.item_table[menu.perpage + 1]
      menu:onMenuSelect(item)
      local box = shown[2]
      tap(box, "Remove from list")

      assert.is_false(UIManager:isWindowWidget(box))
      assert.is_true(UIManager:isWindowWidget(menu))
      assert.is_equal(2, menu.page)
      assert.is_equal(29, #menu.item_table)
      for _, it_ in ipairs(menu.item_table) do
        assert.are_not.equal(item.text, it_.text)
      end
      local count = sync_instance.manager:getPendingChangedDocuments()
      assert.is_equal(29, count)
      -- The list was updated, not shown again.
      local lists, texts = 0, {}
      for _, w in ipairs(shown) do
        if w.title == "Pending books" then
          lists = lists + 1
        elseif type(w.text) == "string" then
          table.insert(texts, w.text)
        end
      end
      assert.is_equal(1, lists)
      assert.are.same({
        "Sync this book now?\n\n" .. item.text,
        "Removed " .. item.text .. " from pending books.",
      }, texts)
    end
  )

  it("removing the last book keeps the empty list open", function()
    sync_instance.manager:_writeChangedDocumentsFile({ readerui.document.file })
    local shown, cleanup = open_pending_list()
    finally(cleanup)
    local menu = shown[1]

    menu:onMenuSelect(menu.item_table[1])
    tap(shown[2], "Remove from list")

    assert.is_true(UIManager:isWindowWidget(menu))
    assert.is_equal(0, #menu.item_table)
    assert.is_equal(0, (sync_instance.manager:getPendingChangedDocuments()))
  end)

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
