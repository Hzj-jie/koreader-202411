describe("AnnotationSync manager book sync engine", function()
  local UIManager, AnnotationSyncPlugin, test_utils, json, util, utils
  local Notification, NetworkMgr, SyncService, DataStorage, docsettings, ConfirmBox
  local readerui, sync_instance, manager
  local test_data_dir = require("datastorage"):getDataDir() .. "/test_book_sync_tmp"
  local old_getDataDir
  local old_cloud_download_dir, old_cloud_server_object
  local restore_jobs
  local old_notify, old_show_msg
  local toasts, msgs
  local book_b, book_d, book_c

  local function ann(n)
    local items = {
      {
        pos0 = "/body/DocFragment[3]/body/div/div[1]/p/text().0",
        pos1 = "/body/DocFragment[3]/body/div/div[1]/p/text().72",
        text = "William Shakespeare",
      },
      {
        pos0 = "/body/DocFragment[3]/body/div/div[1]/p/text().210",
        pos1 = "/body/DocFragment[3]/body/div/div[1]/p/text().321",
        text = "national poet",
      },
      {
        pos0 = "/body/DocFragment[3]/body/div/div[1]/p/text().434",
        pos1 = "/body/DocFragment[3]/body/div/div[1]/p/text().540",
        text = "living language",
      },
    }
    local item = items[n]
    return {
      page = item.pos0,
      pos0 = item.pos0,
      pos1 = item.pos1,
      drawer = "lighten",
      color = "yellow",
      text = item.text,
      datetime = "2026-01-0" .. n .. " 10:00:00",
    }
  end

  local function write_sidecar(file, list)
    local ds = docsettings:open(file)
    ds:save("annotations", list)
    ds:flush()
  end

  local function sidecar(file)
    return docsettings:open(file):readTable("annotations") or {}
  end

  local function pending()
    return select(2, manager:getPendingChangedDocuments())
  end

  local function base(file)
    return utils.read_json(manager:getSyncCachePath(file))
  end

  local function tmp_json(file)
    return DataStorage:getTmpDir() .. "/" .. manager:_getAnnotationFilename(file)
  end

  setup(function()
    require("commonrequire")
    local plugin_path = "plugins/AnnotationSync.koplugin/?.lua"
    package.path = plugin_path .. ";" .. package.path

    test_utils = require("plugins/AnnotationSync.koplugin/test_utils")
    disable_plugins()

    UIManager = require("ui/uimanager")
    json = require("json")
    util = require("util")
    utils = require("plugins/AnnotationSync.koplugin/utils")
    Notification = require("ui/widget/notification")
    NetworkMgr = require("ui/network/manager")
    SyncService = require("apps/cloudstorage/syncservice")
    DataStorage = require("datastorage")
    docsettings = require("frontend/docsettings")
    ConfirmBox = require("ui/widget/confirmbox")
    AnnotationSyncPlugin = require("plugins/AnnotationSync.koplugin/main")

    old_getDataDir = test_utils.setup_test_env(test_data_dir)

    old_cloud_download_dir = G_reader_settings:read("cloud_download_dir")
    old_cloud_server_object = G_reader_settings:read("cloud_server_object")
    G_reader_settings:save("cloud_download_dir", "http://mock")
    G_reader_settings:save(
      "cloud_server_object",
      json.encode({ url = "http://mock", type = "webdav" })
    )

    readerui, sync_instance = test_utils.init_integration_context(
      "spec/front/unit/data/juliet.epub",
      AnnotationSyncPlugin
    )
    manager = sync_instance.manager

    book_b = test_data_dir .. "/book_b.epub"
    book_d = test_data_dir .. "/book_d.epub"
    book_c = test_data_dir .. "/book_c.epub"
  end)

  teardown(function()
    if readerui then
      readerui:onClose()
    end
    if old_cloud_download_dir then
      G_reader_settings:save("cloud_download_dir", old_cloud_download_dir)
    else
      G_reader_settings:delete("cloud_download_dir")
    end
    if old_cloud_server_object then
      G_reader_settings:save("cloud_server_object", old_cloud_server_object)
    else
      G_reader_settings:delete("cloud_server_object")
    end
    test_utils.teardown_test_env(test_data_dir, old_getDataDir)
    UIManager:quit()
    package.loaded["plugins/AnnotationSync.koplugin/main"] = nil
  end)

  before_each(function()
    os.remove(manager:changedDocumentsFile())
    manager.requested = {}
    manager.running = nil

    sync_instance.settings.network_auto_sync = false
    sync_instance.settings.use_filename = true
    sync_instance.settings.last_sync = "Never"

    restore_jobs = test_utils.run_jobs_inline()

    toasts = {}
    old_notify = Notification.notify
    Notification.notify = function(_, text)
      table.insert(toasts, text)
    end

    msgs = {}
    old_show_msg = utils.show_msg
    utils.show_msg = function(text)
      table.insert(msgs, text)
    end

    local ffiutil = require("ffi/util")
    os.execute("rm -rf " .. book_b:gsub("%.%w+$", ".sdr"))
    os.execute("rm -rf " .. book_d:gsub("%.%w+$", ".sdr"))
    ffiutil.copyFile("spec/front/unit/data/juliet.epub", book_b)
    ffiutil.copyFile("spec/front/unit/data/juliet.epub", book_d)
  end)

  after_each(function()
    restore_jobs()
    Notification.notify = old_notify
    utils.show_msg = old_show_msg

    sync_instance.settings.use_filename = false
    sync_instance.settings.network_auto_sync = false
    manager.running = nil
    manager.requested = {}

    os.remove(book_b)
    os.remove(book_d)
    os.remove(book_c)
    os.execute("rm -rf " .. book_b:gsub("%.%w+$", ".sdr"))
    os.execute("rm -rf " .. book_d:gsub("%.%w+$", ".sdr"))
    os.execute("rm -rf " .. book_c:gsub("%.%w+$", ".sdr"))
    os.execute("rm -f " .. DataStorage:getTmpDir() .. "/*.json*")
  end)

  it("Sync current book now on a closed book uploads it, makes the upload its merge base and says Synced", function()
    write_sidecar(book_b, { ann(1) })
    manager:_writeChangedDocumentsFile({ book_b })
    manager:syncNow(book_b)

    assert.are.same({
      "Syncing in the background: book_b.epub",
      "Synced: book_b.epub",
    }, toasts)
    assert.are.same({}, pending())
    local b = base(book_b)
    assert.is_not_nil(b)
    assert.are.equal(1, #b)
    assert.are.equal("William Shakespeare", b[1].text)
    assert.is_nil(docsettings:open(book_b):read("annotations_externally_modified"))
    assert.is_truthy(string.match(sync_instance.settings.last_sync, "^%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d$"))
    assert.is_nil(io.open(tmp_json(book_b), "r"))
    assert.is_nil(io.open(tmp_json(book_b) .. ".snapshot", "r"))
    assert.is_nil(io.open(tmp_json(book_b) .. ".uploaded", "r"))
    assert.is_nil(manager.running)
  end)

  it("a pending book deleted from disk is dropped, and auto sync goes on with the next book", function()
    sync_instance.settings.network_auto_sync = true
    local missing = test_data_dir .. "/gone.epub"
    write_sidecar(book_b, { ann(1) })
    manager:_writeChangedDocumentsFile({ missing, book_b })

    manager:_dispatchNextSync()

    assert.are.same({}, pending())
    assert.are.same({}, msgs)
    assert.is_not_nil(base(book_b))
    for _, toast in ipairs(toasts) do
      assert.is_falsy(string.match(toast, "^Synced:"))
    end
  end)

  it("Sync current book now on a book deleted from disk says so and drops it", function()
    local missing = test_data_dir .. "/gone.epub"
    manager:_writeChangedDocumentsFile({ missing })

    manager:syncNow(missing)

    assert.are.same({ "Cannot find gone.epub. Removed it from pending books." }, msgs)
    assert.are.same({}, pending())
    assert.is_nil(manager.running)
  end)

  it("a book that can't be read is skipped with a message and stays pending, and auto sync doesn't go on", function()
    sync_instance.settings.use_filename = false
    sync_instance.settings.network_auto_sync = true

    local ffiutil = require("ffi/util")
    os.execute("rm -rf " .. book_c:gsub("%.%w+$", ".sdr"))
    ffiutil.copyFile("spec/front/unit/data/juliet.epub", book_c)

    write_sidecar(book_c, { ann(1) })
    write_sidecar(book_b, { ann(2) })
    manager:_writeChangedDocumentsFile({ book_c, book_b })

    os.execute("chmod 000 " .. book_c)
    assert.is_nil(io.open(book_c, "rb"))

    finally(function()
      os.execute("chmod 644 " .. book_c)
    end)

    manager:syncNow(book_c)

    local found_msg = false
    for _, m in ipairs(msgs) do
      if string.find(m, "Cannot read book_c.epub. Skipped syncing it.") then
        found_msg = true
      end
    end
    assert.is_true(found_msg)
    assert.are.same({ book_b, book_c }, pending())
    assert.is_nil(base(book_b))
    assert.are.equal("Never", sync_instance.settings.last_sync)
    assert.is_nil(manager.running)
  end)

  it("a failed upload says so, keeps the book pending and doesn't start the next one", function()
    sync_instance.settings.network_auto_sync = true
    write_sidecar(book_b, { ann(1) })
    write_sidecar(book_d, { ann(2) })
    manager:_writeChangedDocumentsFile({ book_b, book_d })

    SyncService.sync = function(_, _, _, _, finish_cb)
      finish_cb(false)
    end

    finally(function()
      test_utils.mock_sync_service(SyncService)
    end)

    manager:syncNow(book_b)

    local found_msg = false
    for _, m in ipairs(msgs) do
      if string.find(m, "Failed to sync book_b.epub.") then
        found_msg = true
      end
    end
    assert.is_true(found_msg)
    assert.are.same({ book_d, book_b }, pending())
    assert.is_nil(base(book_b))
    assert.is_nil(base(book_d))
    assert.are.equal("Never", sync_instance.settings.last_sync)
    assert.is_nil(io.open(tmp_json(book_b) .. ".snapshot", "r"))
  end)

  it("an emptied book whose annotations are still in the cloud asks before restoring them", function()
    write_sidecar(book_b, {})
    local cloud_data = json.encode({ ann(1), ann(2) })
    util.writeToFile(cloud_data, manager:getSyncCachePath(book_b))
    util.writeToFile(cloud_data, tmp_json(book_b) .. ".income")
    manager:_writeChangedDocumentsFile({ book_b })

    local boxes = {}
    local orig_show = UIManager.show
    UIManager.show = function(self_ui, w, ...)
      if getmetatable(w) == ConfirmBox then
        table.insert(boxes, w)
      end
      return orig_show(self_ui, w, ...)
    end

    finally(function()
      UIManager.show = orig_show
      for _, b in ipairs(boxes) do
        UIManager:close(b)
      end
    end)

    manager:syncNow(book_b)

    assert.are.equal(1, #boxes)
    local box = boxes[1]
    assert.are.equal("Move to trash", box.ok_text)
    assert.are.equal("Restore", box.cancel_text)
    local expected_text = "book_b.epub has no annotations on this device, but 2 on your cloud storage. "
      .. "Restore them, or move them to the trash on all devices? "
      .. "Trashed annotations can be restored from 'Show deleted annotations'. "
      .. "Dismissing this dialog restores them as well."
    assert.are.equal(expected_text, box.text)
    assert.are.equal(0, #sidecar(book_b))
    assert.is_true(manager.running)
    for _, toast in ipairs(toasts) do
      assert.is_falsy(string.match(toast, "^Synced:"))
    end
  end)

  it("Restore puts the cloud annotations back into the emptied book", function()
    write_sidecar(book_b, {})
    local cloud_data = json.encode({ ann(1), ann(2) })
    util.writeToFile(cloud_data, manager:getSyncCachePath(book_b))
    util.writeToFile(cloud_data, tmp_json(book_b) .. ".income")
    manager:_writeChangedDocumentsFile({ book_b })

    local boxes = {}
    local orig_show = UIManager.show
    UIManager.show = function(self_ui, w, ...)
      if getmetatable(w) == ConfirmBox then
        table.insert(boxes, w)
      end
      return orig_show(self_ui, w, ...)
    end

    finally(function()
      UIManager.show = orig_show
      for _, b in ipairs(boxes) do
        UIManager:close(b)
      end
    end)

    manager:syncNow(book_b)

    assert.are.equal(1, #boxes)
    boxes[1].cancel_callback()

    local sc = sidecar(book_b)
    assert.are.equal(2, #sc)
    assert.are.same({ "William Shakespeare", "national poet" }, { sc[1].text, sc[2].text })
    assert.are.same({}, pending())
    assert.are.equal("Synced: book_b.epub", toasts[#toasts])
    assert.is_nil(manager.running)
  end)

  it("Move to trash uploads tombstones, keeps the book empty and lists them in Show deleted annotations", function()
    write_sidecar(book_b, {})
    local cloud_data = json.encode({ ann(1), ann(2) })
    util.writeToFile(cloud_data, manager:getSyncCachePath(book_b))
    util.writeToFile(cloud_data, tmp_json(book_b) .. ".income")
    manager:_writeChangedDocumentsFile({ book_b })

    local boxes = {}
    local orig_show = UIManager.show
    UIManager.show = function(self_ui, w, ...)
      if getmetatable(w) == ConfirmBox then
        table.insert(boxes, w)
      end
      return orig_show(self_ui, w, ...)
    end

    finally(function()
      UIManager.show = orig_show
      for _, b in ipairs(boxes) do
        UIManager:close(b)
      end
    end)

    manager:syncNow(book_b)

    assert.are.equal(1, #boxes)
    boxes[1].ok_callback()

    local b = base(book_b)
    assert.is_not_nil(b)
    assert.are.equal(2, #b)
    assert.is_true(b[1].deleted)
    assert.is_true(b[2].deleted)
    assert.are.equal(0, #sidecar(book_b))
    assert.are.equal(2, #manager:getDeletedAnnotations({ file = book_b }))
    assert.are.same({}, pending())
    assert.are.equal("Synced: book_b.epub", toasts[#toasts])
    assert.is_nil(manager.running)
  end)

  it("Sync all pending books syncs every pending book one by one without a toast per book", function()
    write_sidecar(book_b, { ann(1) })
    write_sidecar(book_d, { ann(2) })
    manager:_writeChangedDocumentsFile({ book_b, book_d })

    manager:syncAllChangedDocuments()

    assert.are.same({ "Syncing 2 books one by one in the background" }, toasts)
    assert.is_not_nil(base(book_b))
    assert.is_not_nil(base(book_d))
    assert.are.same({}, pending())
    assert.is_nil(next(manager.requested))
    assert.is_nil(manager.running)
  end)

  it("the queue starts nothing while a sync runs, and nothing unasked without auto sync or after a failure", function()
    manager:_writeChangedDocumentsFile({ book_b })
    manager.running = true
    manager.requested[book_b] = "Manual Sync"

    assert.is_false(manager:_dispatchNextSync())
    assert.are.equal("Manual Sync", manager.requested[book_b])

    manager.running = nil
    manager.requested = {}
    assert.is_false(manager:_dispatchNextSync())

    sync_instance.settings.network_auto_sync = true
    assert.is_false(manager:_dispatchNextSync(true))

    assert.are.same({ book_b }, pending())
    assert.is_nil(base(book_b))
  end)

  it("one sync of the open book writes the merged annotations into it once", function()
    readerui.annotation.annotations = { ann(1) }
    manager:_writeChangedDocumentsFile({ readerui.document.file })
    util.writeToFile(
      json.encode({ ann(2) }),
      tmp_json(readerui.document.file) .. ".income"
    )

    local count = 0
    local orig = AnnotationSyncPlugin.applySyncedAnnotations
    sync_instance.applySyncedAnnotations = function(self_plugin, ...)
      count = count + 1
      return orig(self_plugin, ...)
    end

    finally(function()
      sync_instance.applySyncedAnnotations = nil
      readerui.annotation.annotations = {}
    end)

    manager:syncNow(readerui.document.file)

    assert.are.equal("Synced: juliet.epub", toasts[#toasts])
    assert.are.equal(1, count)
    assert.are.equal(2, #readerui.annotation.annotations)
  end)

  it("a sync of the open book that changes nothing doesn't write it again", function()
    os.remove(manager:getSyncCachePath(readerui.document.file))
    readerui.annotation.annotations = { ann(1) }
    manager:_writeChangedDocumentsFile({ readerui.document.file })

    local count = 0
    local orig = AnnotationSyncPlugin.applySyncedAnnotations
    sync_instance.applySyncedAnnotations = function(self_plugin, ...)
      count = count + 1
      return orig(self_plugin, ...)
    end

    finally(function()
      sync_instance.applySyncedAnnotations = nil
      readerui.annotation.annotations = {}
    end)

    manager:syncNow(readerui.document.file)

    assert.are.equal("Synced: juliet.epub", toasts[#toasts])
    assert.are.equal(0, count)
    assert.are.equal(1, #base(readerui.document.file))
    assert.are.same({}, pending())
  end)
end)
