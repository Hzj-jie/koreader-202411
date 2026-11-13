describe("SdrList module", function()
  local DataStorage
  local DocSettings
  local Notification
  local SdrList
  local ffiutil
  local gettext
  local lfs
  local util
  local data_dir
  local home_dir
  local docsettings_dir
  local sdr_list_file
  local orig_get_data_dir
  local orig_get_docsettings_dir
  local orig_get_hash_dir
  local orig_named_settings

  local function writeDummy(path, content)
    util.makePath(ffiutil.dirname(path))
    local f = assert(io.open(path, "w"))
    f:write(content)
    f:close()
  end

  local function reloadModule()
    package.loaded["sdrlist"] = nil
    SdrList = require("sdrlist")
    return SdrList
  end

  setup(function()
    require("commonrequire")
    DataStorage = require("datastorage")
    DocSettings = require("docsettings")
    Notification = require("ui/widget/notification")
    ffiutil = require("ffi/util")
    gettext = require("gettext")
    lfs = require("libs/libkoreader-lfs")
    util = require("util")
  end)

  before_each(function()
    local root = os.tmpname()
    os.remove(root)
    assert(lfs.mkdir(root))

    data_dir = root .. "/data"
    home_dir = root .. "/books"
    docsettings_dir = data_dir .. "/docsettings"
    assert(lfs.mkdir(data_dir))
    assert(lfs.mkdir(home_dir))
    assert(lfs.mkdir(docsettings_dir))

    orig_get_data_dir = DataStorage.getDataDir
    orig_get_docsettings_dir = DataStorage.getDocSettingsDir
    orig_get_hash_dir = DataStorage.getDocSettingsHashDir
    DataStorage.getDataDir = function()
      return data_dir
    end
    DataStorage.getDocSettingsDir = function()
      return docsettings_dir
    end
    DataStorage.getDocSettingsHashDir = function()
      return data_dir .. "/hashdocsettings"
    end

    orig_named_settings = _G.G_named_settings
    _G.G_named_settings = {
      home_dir = function()
        return home_dir
      end,
      document_metadata_folder = function()
        return G_reader_settings:read("document_metadata_folder") or "doc"
      end,
    }
    G_reader_settings:save("document_metadata_folder", "doc")

    package.loaded["docsettings"] = nil
    DocSettings = require("docsettings")
    sdr_list_file = data_dir .. "/sdr_list.lua"
    reloadModule()
  end)

  after_each(function()
    G_reader_settings:delete("document_metadata_folder")
    DataStorage.getDataDir = orig_get_data_dir
    DataStorage.getDocSettingsDir = orig_get_docsettings_dir
    DataStorage.getDocSettingsHashDir = orig_get_hash_dir
    _G.G_named_settings = orig_named_settings
    package.loaded["sdrlist"] = nil
    package.loaded["docsettings"] = nil
    ffiutil.purgeDir(ffiutil.dirname(data_dir))
  end)

  it(
    "seeds once from existing ReadHistory entries that have sidecars and writes paths only",
    function()
      local book_with_sdr = home_dir .. "/with_sdr.epub"
      local book_no_sdr = home_dir .. "/no_sdr.epub"
      local ignored_log = home_dir .. "/crash.log"
      writeDummy(book_with_sdr, "epub")
      writeDummy(book_no_sdr, "epub")
      writeDummy(ignored_log, "log")
      writeDummy(
        home_dir .. "/with_sdr.sdr/metadata.epub.lua",
        'return { ["summary"] = { ["status"] = "reading" } }\n'
      )
      writeDummy(
        home_dir .. "/crash.sdr/metadata.log.lua",
        'return { ["summary"] = { ["status"] = "reading" } }\n'
      )

      local hist_data = {
        { file = book_with_sdr, time = 100 },
        { file = book_no_sdr, time = 200 },
        { file = ignored_log, time = 300 },
      }
      writeDummy(
        data_dir .. "/history.lua",
        "return " .. require("dump")(hist_data)
      )

      local files = SdrList:getFiles()
      assert.are.same({ book_with_sdr }, files)
      assert.is_true(util.fileExists(sdr_list_file))

      local persisted = dofile(sdr_list_file)
      assert.are.same({ book_with_sdr }, persisted)
      assert.is_string(persisted[1])

      -- Remove sidecar-bearing book manually from cache and add another:
      -- reloading must NOT re-seed from ReadHistory once sdr_list.lua exists.
      SdrList:removeItem(book_with_sdr)
      reloadModule()
      assert.are.same({}, SdrList:getFiles())
    end
  )

  it("handles addItem, removeItem, updateItem, and folder prefix ops", function()
    assert.are.same({}, SdrList:getFiles())

    local b1 = home_dir .. "/sub/a.epub"
    local b2 = home_dir .. "/sub2/b.pdf"
    local ignored = home_dir .. "/quickstart-en.html"
    local hidden = home_dir .. "/.DS_Store"
    local hidden_dir_book = home_dir .. "/.Trash/hidden_book.epub"
    local nested_trash_book = home_dir .. "/.Trash/sub/hidden_book.epub"
    local sdr_dir_book = home_dir .. "/foo.sdr/nested.epub"
    local nested_sdr_book = home_dir .. "/foo.sdr/sub/nested.epub"
    local real_home = ffiutil.realpath(home_dir)
    local rb1 = real_home .. "/sub/a.epub"
    local rb2 = real_home .. "/sub2/b.pdf"
    writeDummy(b1, "1")
    writeDummy(b2, "2")

    local write_stub = spy.on(util, "writeToFile")
    finally(function()
      write_stub:revert()
    end)

    assert.is_false(SdrList:ignoreFile(hidden_dir_book))
    assert.is_true(SdrList:ignorePath(hidden_dir_book))
    assert.is_true(SdrList:ignorePath(nested_trash_book))
    assert.is_true(SdrList:ignorePath(sdr_dir_book))
    assert.is_true(SdrList:ignorePath(nested_sdr_book))
    assert.is_false(SdrList:addItem(ignored))
    assert.is_false(SdrList:addItem(hidden))
    assert.is_false(SdrList:addItem(hidden_dir_book))
    assert.is_false(SdrList:addItem(nested_trash_book))
    assert.is_false(SdrList:addItem(sdr_dir_book))
    assert.is_false(SdrList:addItem(nested_sdr_book))
    assert.spy(util.writeToFile).was_not_called()

    assert.is_true(SdrList:addItem(b1))
    assert.spy(util.writeToFile).was_called(1)
    assert.is_false(SdrList:addItem(b1)) -- O(1) short-circuit, no disk write
    assert.spy(util.writeToFile).was_called(1)

    assert.is_true(SdrList:addItem(b2))
    assert.are.same({ rb1, rb2 }, SdrList:getFiles())

    -- Copy keeps original and adds destination
    local b1_copy = home_dir .. "/sub/a_copy.epub"
    local rb1_copy = real_home .. "/sub/a_copy.epub"
    assert.is_true(SdrList:updateItem(b1, b1_copy, true))
    assert.is_true(SdrList:hasFile(rb1))
    assert.is_true(SdrList:hasFile(rb1_copy))

    -- Move removes original and keeps destination
    local b1_moved = home_dir .. "/sub/a_moved.epub"
    local rb1_moved = real_home .. "/sub/a_moved.epub"
    assert.is_true(SdrList:updateItem(b1_copy, b1_moved, false))
    assert.is_false(SdrList:hasFile(b1_copy))
    assert.is_true(SdrList:hasFile(b1_moved))

    -- Folder prefix rename must not rewrite sibling prefix (/sub vs /sub2)
    assert.is_true(
      SdrList:updateItemsByPath(real_home .. "/sub", real_home .. "/renamed")
    )
    assert.is_true(SdrList:hasFile(real_home .. "/renamed/a.epub"))
    assert.is_true(SdrList:hasFile(real_home .. "/renamed/a_moved.epub"))
    assert.is_true(SdrList:hasFile(rb2))

    -- Folder prefix copy keeps originals and adds only copied items with sidecars
    local copied_a = real_home .. "/copied/a.epub"
    local copied_moved = real_home .. "/copied/a_moved.epub"
    writeDummy(copied_a, "1")
    writeDummy(copied_moved, "2")
    writeDummy(
      real_home .. "/copied/a.sdr/metadata.epub.lua",
      'return { ["summary"] = { ["status"] = "reading" } }\n'
    )
    assert.is_true(
      SdrList:updateItemsByPath(
        real_home .. "/renamed",
        real_home .. "/copied",
        true
      )
    )
    assert.is_true(SdrList:hasFile(real_home .. "/renamed/a.epub"))
    assert.is_true(SdrList:hasFile(real_home .. "/renamed/a_moved.epub"))
    assert.is_true(SdrList:hasFile(copied_a))
    assert.is_false(SdrList:hasFile(copied_moved))
    assert.is_true(SdrList:removeItem(copied_a))

    -- Folder prefix delete must not delete /sub2
    assert.is_true(SdrList:removeItemsByPath(real_home .. "/renamed"))
    assert.are.same({ rb2 }, SdrList:getFiles())
    assert.is_false(SdrList:removeItemsByPath(real_home .. "/renamed"))

    -- Single remove
    assert.is_true(SdrList:removeItem(b2))
    assert.are.same({}, SdrList:getFiles())
    assert.is_false(SdrList:removeItem(b2))
  end)

  it(
    "preserves existing cache and notifies on write or corrupt read failures",
    function()
      local b1 = home_dir .. "/keep.epub"
      assert.is_true(SdrList:addItem(b1))

      local notify_stub = stub(Notification, "notify")
      local write_stub = stub(util, "writeToFile", function()
        return false
      end)
      finally(function()
        notify_stub:revert()
        write_stub:revert()
      end)

      assert.is_false(SdrList:addItem(home_dir .. "/fail.epub"))
      assert.stub(Notification.notify).was_called(1)
      assert.stub(Notification.notify).was_called_with(
        Notification,
        gettext("Failed to save reading status collection index.")
      )
      assert.are.same({ b1 }, dofile(sdr_list_file))

      writeDummy(sdr_list_file, "this is not valid lua {{{")
      assert.is_false(SdrList:reload(true))
      assert.stub(Notification.notify).was_called(2)
      assert.stub(Notification.notify).was_called_with(
        Notification,
        gettext("Failed to load reading status collection index.")
      )
    end
  )

  it(
    "rebuilds index without -type d across doc, dir, and valid hash entries",
    function()
      local real_home = ffiutil.realpath(home_dir)
      local doc_book = real_home .. "/doc_book.epub"
      local dir_book = real_home .. "/nested/dir_book.pdf"
      local hash_book = real_home .. "/hash_book.epub"
      local missing_book = real_home .. "/deleted_book.epub"
      local orphan_book = real_home .. "/orphan_book.epub"
      local trash_book = real_home .. "/.Trash/trashed_book.epub"
      local nested_trash_book = real_home .. "/.Trash/sub/nested_trashed.epub"

      writeDummy(doc_book, "doc book")
      writeDummy(dir_book, "dir book")
      writeDummy(hash_book, "hash book content for partial md5")
      writeDummy(missing_book, "temp")
      writeDummy(trash_book, "trashed book")
      writeDummy(nested_trash_book, "nested trashed book")

      -- Create doc-mode sidecar
      writeDummy(
        real_home .. "/doc_book.sdr/metadata.epub.lua",
        'return { ["summary"] = { ["status"] = "reading" } }\n'
      )
      -- Create ignored hidden parent dir sidecar
      writeDummy(
        real_home .. "/.Trash/trashed_book.sdr/metadata.epub.lua",
        'return { ["summary"] = { ["status"] = "reading" } }\n'
      )
      writeDummy(
        real_home .. "/.Trash/sub/nested_trashed.sdr/metadata.epub.lua",
        'return { ["summary"] = { ["status"] = "reading" } }\n'
      )
      -- Create orphan .sdr (book file absent)
      writeDummy(
        real_home .. "/orphan_book.sdr/metadata.epub.lua",
        'return { ["summary"] = { ["status"] = "reading" } }\n'
      )
      -- Create dir-mode sidecar under docsettings_dir
      writeDummy(
        docsettings_dir .. dir_book:gsub("%.pdf$", ".sdr") .. "/metadata.pdf.lua",
        'return { ["summary"] = { ["status"] = "complete" } }\n'
      )

      -- Create hash-mode sidecar
      G_reader_settings:save("document_metadata_folder", "hash")
      local ds_hash = DocSettings:open(hash_book)
      ds_hash:save("summary", { status = "abandoned" })
      ds_hash:flush()
      ds_hash:close()
      G_reader_settings:save("document_metadata_folder", "doc")

      -- Seed stale deleted hash entry + deleted doc entry before rebuild
      SdrList:addItem(missing_book)
      os.remove(missing_book)
      assert.is_true(SdrList:hasFile(hash_book))
      assert.is_true(SdrList:hasFile(missing_book))

      local cmds = {}
      local orig_popen = io.popen
      local popen_stub = stub(io, "popen", function(cmd, mode)
        table.insert(cmds, cmd)
        return orig_popen(cmd, mode)
      end)
      local notify_stub
      finally(function()
        popen_stub:revert()
        if notify_stub then
          notify_stub:revert()
        end
      end)

      assert.is_true(SdrList:rebuildFromDisk())
      assert.is_true(#cmds >= 1)
      for _, cmd in ipairs(cmds) do
        assert.is_nil(cmd:find("-type d", 1, true))
      end

      assert.are.same({ doc_book, hash_book, dir_book }, SdrList:getFiles())
      assert.is_false(SdrList:hasFile(orphan_book))
      assert.is_false(SdrList:hasFile(missing_book))
      assert.is_false(SdrList:hasFile(trash_book))
      assert.is_false(SdrList:hasFile(nested_trash_book))

      -- On io.popen failure, notify and keep existing cached paths
      popen_stub:revert()
      popen_stub = stub(io, "popen", function()
        return nil, "spawn failed"
      end)
      notify_stub = stub(Notification, "notify")

      assert.is_false(SdrList:rebuildFromDisk())
      assert.stub(Notification.notify).was_called(1)
      assert.stub(Notification.notify).was_called_with(
        Notification,
        gettext("Failed to scan metadata files for reading status collections.")
      )
      assert.are.same({ doc_book, hash_book, dir_book }, SdrList:getFiles())
    end
  )
end)
