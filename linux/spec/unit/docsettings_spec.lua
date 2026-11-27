describe("docsettings module", function()
  local DataStorage, docsettings, docsettings_dir, ffiutil, gettext, lfs, logger, util
  local getSidecarDir = function(doc_path)
    return docsettings:open(doc_path).candidates[1].dir
  end
  local getSidecarFile = function(doc_path)
    return docsettings:open(doc_path).candidates[1].file
  end

  local function makeTempDir()
    local tmp = os.tmpname()
    os.remove(tmp)
    local dir = tmp .. "_docsettings"
    util.makePath(dir)
    return dir
  end

  setup(function()
    require("commonrequire")
    DataStorage = require("datastorage")
    docsettings = require("docsettings")
    ffiutil = require("ffi/util")
    gettext = require("gettext")
    lfs = require("libs/libkoreader-lfs")
    logger = require("logger")
    util = require("util")

    docsettings_dir = DataStorage:getDocSettingsDir()
  end)

  it(
    "should generate sidecar folder path in book folder (by default)",
    function()
      G_reader_settings:delete("document_metadata_folder")
      assert.Equals("../../foo.sdr", getSidecarDir("../../foo.pdf"))
      assert.Equals("/foo/bar.sdr", getSidecarDir("/foo/bar.pdf"))
      assert.Equals("baz.sdr", getSidecarDir("baz.pdf"))
    end
  )

  it("should generate sidecar folder path in book folder", function()
    G_reader_settings:save("document_metadata_folder", "doc")
    assert.Equals("../../foo.sdr", getSidecarDir("../../foo.pdf"))
    assert.Equals("/foo/bar.sdr", getSidecarDir("/foo/bar.pdf"))
    assert.Equals("baz.sdr", getSidecarDir("baz.pdf"))
  end)

  it("should generate sidecar folder path in docsettings folder", function()
    G_reader_settings:save("document_metadata_folder", "dir")
    assert.Equals(
      docsettings_dir .. "/foo/bar.sdr",
      getSidecarDir("/foo/bar.pdf")
    )
    assert.Equals(docsettings_dir .. "baz.sdr", getSidecarDir("baz.pdf"))
  end)

  it(
    "should generate sidecar folder path in tmp folder via DataStorage:getTmpDir",
    function()
      local orig_getTmpDir = DataStorage.getTmpDir
      DataStorage.getTmpDir = function()
        return "/custom/datastorage/tmp"
      end
      local candidates = docsettings:open("/foo/bar.pdf").candidates
      local tmp_cand
      for _, cand in ipairs(candidates) do
        if cand.location == "tmp" then
          tmp_cand = cand
          break
        end
      end
      DataStorage.getTmpDir = orig_getTmpDir
      assert.is_not_nil(tmp_cand)
      assert.are.equal(
        "/custom/datastorage/tmp/docsettings/foo/bar.sdr",
        tmp_cand.dir
      )
    end
  )

  it(
    "should return root storage dir for dir and hash, and assert on other locations",
    function()
      assert.Equals(docsettings_dir, docsettings.getSidecarStorage("dir"))
      assert.Equals(
        DataStorage:getDocSettingsHashDir(),
        docsettings.getSidecarStorage("hash")
      )
      assert.has_error(function()
        docsettings.getSidecarStorage("doc")
      end)
      assert.has_error(function()
        docsettings.getSidecarStorage("tmp")
      end)
      assert.has_error(function()
        docsettings.getSidecarStorage("unknown")
      end)
    end
  )

  it("should generate sidecar metadata file (book folder)", function()
    G_reader_settings:save("document_metadata_folder", "doc")
    assert.Equals(
      "../../foo.sdr/metadata.pdf.lua",
      getSidecarFile("../../foo.pdf")
    )
    assert.Equals(
      "/foo/bar.sdr/metadata.pdf.lua",
      getSidecarFile("/foo/bar.pdf")
    )
    assert.Equals("baz.sdr/metadata.epub.lua", getSidecarFile("baz.epub"))
  end)

  it("should generate sidecar metadata file (docsettings folder)", function()
    G_reader_settings:save("document_metadata_folder", "dir")
    assert.Equals(
      docsettings_dir .. "/foo/bar.sdr/metadata.pdf.lua",
      getSidecarFile("/foo/bar.pdf")
    )
    assert.Equals(
      docsettings_dir .. "baz.sdr/metadata.epub.lua",
      getSidecarFile("baz.epub")
    )
  end)

  it("should read legacy history file", function()
    G_reader_settings:delete("document_metadata_folder")
    local file = "file.pdf"
    local d = docsettings:open(file)
    local doc_dir = getSidecarDir(file)
    d:save("a", "b")
    d:save("c", "d")
    d:close()
    -- Now the sidecar file should be written.

    local legacy_files = {
      docsettings:getHistoryPath(file),
      doc_dir .. "/file.pdf.lua",
      "file.pdf.kpdfview.lua",
    }

    for _, f in ipairs(legacy_files) do
      assert.False(os.rename(doc_dir .. "/" .. d.sidecar_filename, f) == nil)
      d = docsettings:open(file)
      assert.True(os.remove(doc_dir .. "/" .. d.sidecar_filename) == nil)
      -- Legacy history files should not be removed before flush has been
      -- called.
      assert.Equals(lfs.attributes(f, "mode"), "file")
      assert.Equals(d:read("a"), "b")
      assert.Equals(d:read("c"), "d")
      assert.Equals(d:read("e"), nil)
      d:close()
      -- legacy history files should be removed as sidecar_file is
      -- preferred.
      assert.True(os.remove(f) == nil)
    end

    assert.False(os.remove(doc_dir .. "/" .. d.sidecar_filename) == nil)
    d:purge()
  end)

  it("should respect newest history file", function()
    local file = "file.pdf"
    local d = docsettings:open(file)
    local doc_dir = getSidecarDir(file)

    local legacy_files = {
      docsettings:getHistoryPath(file),
      doc_dir .. "/file.pdf.lua",
      "file.pdf.kpdfview.lua",
    }

    -- docsettings:flush will remove legacy files.
    for i, v in ipairs(legacy_files) do
      d:save("a", i)
      d:flush()
      assert.False(
        os.rename(doc_dir .. "/" .. d.sidecar_filename, v .. "1") == nil
      )
    end

    d:close()
    for _, v in ipairs(legacy_files) do
      assert.False(os.rename(v .. "1", v) == nil)
    end

    d = docsettings:open(file)
    assert.Equals(d:read("a"), #legacy_files)
    d:close()
    d:purge()
  end)

  it("should build correct legacy history path", function()
    local file = "/a/b/c--d/c.txt"
    local history_path = ffiutil.basename(docsettings:getHistoryPath(file))
    local path_from_history = docsettings:getPathFromHistory(history_path)
    local name_from_history = docsettings:getNameFromHistory(history_path)
    assert.is.same(file, path_from_history .. "/" .. name_from_history)
  end)

  it("handles hash sidecar location and hash directory", function()
    local tmp_dir = makeTempDir()
    finally(function()
      G_reader_settings:delete("document_metadata_folder")
      ffiutil.purgeDir(tmp_dir)
    end)

    G_reader_settings:save("document_metadata_folder", "hash")
    local file = tmp_dir .. "/test_hash_doc.pdf"
    local f = io.open(file, "w")
    if f then
      f:write("%PDF-1.4 dummy pdf")
      f:close()
    end

    local sidecar_dir = getSidecarDir(file)
    assert.is_truthy(sidecar_dir)
    assert.is_truthy(sidecar_dir:match("%.sdr$"))

    local d = docsettings:open(file)
    assert.is_not_nil(d)
    d:save("title", "Hash Book")
    d:flush()

    local sidecar_cand = docsettings:_findSidecarFile(file)
    assert.is_truthy(sidecar_cand)
    local loaded = docsettings.openSettingsFile(sidecar_cand.file)
    assert.is_not_nil(loaded)
    assert.are.equal("Hash Book", loaded.data.title)

    d:flushCustomMetadata(file)
    local hash_files = docsettings.findSidecarFilesInHashLocation()
    assert.is_table(hash_files)
    assert.are.equal(1, #hash_files)
    assert.is_string(hash_files[1].dir)
    assert.is_string(hash_files[1].metadata)
    assert.is_string(hash_files[1].custom_metadata)

    d:close()
    d:purge()
    os.remove(file)
    G_reader_settings:delete("document_metadata_folder")
  end)

  it(
    "findSidecarFilesInHashLocation lists custom-only and cover-only sidecars",
    function()
      local hash_dir = DataStorage:getDocSettingsHashDir()
      ffiutil.purgeDir(hash_dir)
      local custom_sdr = hash_dir .. "/ab/custom_only.sdr"
      util.makePath(custom_sdr)
      local custom_file = custom_sdr .. "/custom_metadata.lua"
      local f1 = io.open(custom_file, "w")
      f1:write("return {}")
      f1:close()

      local cover_sdr = hash_dir .. "/cd/cover_only.sdr"
      util.makePath(cover_sdr)
      local cover_file = cover_sdr .. "/cover.jpg"
      local f2 = io.open(cover_file, "w")
      f2:write("dummy cover")
      f2:close()

      local hash_files = docsettings.findSidecarFilesInHashLocation()
      assert.are.equal(2, #hash_files)

      local by_dir = {}
      for _, e in ipairs(hash_files) do
        by_dir[e.dir] = e
      end

      assert.is_not_nil(by_dir[custom_sdr])
      assert.is_nil(by_dir[custom_sdr].metadata)
      assert.is_equal(custom_file, by_dir[custom_sdr].custom_metadata)
      assert.is_nil(by_dir[custom_sdr].cover)

      assert.is_not_nil(by_dir[cover_sdr])
      assert.is_nil(by_dir[cover_sdr].metadata)
      assert.is_nil(by_dir[cover_sdr].custom_metadata)
      assert.is_equal(cover_file, by_dir[cover_sdr].cover)

      -- Cleanup
      ffiutil.purgeDir(hash_dir)
    end
  )

  it("isHashLocationEnabled returns true when hash directory exists", function()
    local hash_dir = DataStorage:getDocSettingsHashDir()
    ffiutil.purgeDir(hash_dir)
    assert.False(docsettings.isHashLocationEnabled())

    -- Create hash dir
    util.makePath(hash_dir)
    assert.True(docsettings.isHashLocationEnabled())

    -- Create empty subdirectories
    util.makePath(hash_dir .. "/ab/sub.sdr")
    assert.True(docsettings.isHashLocationEnabled())

    -- Cleanup
    ffiutil.purgeDir(hash_dir)
    assert.False(docsettings.isHashLocationEnabled())
  end)

  it(
    "finds hash-located custom metadata with no metadata.*.lua in the tree",
    function()
      local orig_pref = G_reader_settings:read("document_metadata_folder")
      G_reader_settings:save("document_metadata_folder", "doc")

      local hash_dir = DataStorage:getDocSettingsHashDir()
      ffiutil.purgeDir(hash_dir)

      local tmp_dir = makeTempDir()
      finally(function()
        ffiutil.purgeDir(tmp_dir)
      end)

      local file = tmp_dir .. "/test_hash_custom_doc.epub"
      local f = io.open(file, "w")
      if f then
        f:write("dummy book")
        f:close()
      end

      local hsh = util.partialMD5(file)
      local subpath = string.format("/%s/", hsh:sub(1, 2))
      local hash_sidecar = hash_dir .. subpath .. hsh .. ".sdr"
      util.makePath(hash_sidecar)

      local custom_metadata_file = hash_sidecar .. "/custom_metadata.lua"
      local f_custom = io.open(custom_metadata_file, "w")
      if f_custom then
        f_custom:write("return { title = 'Hash Custom Title' }")
        f_custom:close()
      end

      local found = docsettings:findCustomMetadataFile(file)
      assert.are_equal(custom_metadata_file, found)

      -- Cleanup
      os.remove(custom_metadata_file)
      os.remove(file)
      ffiutil.purgeDir(hash_dir)
      if orig_pref ~= nil then
        G_reader_settings:save("document_metadata_folder", orig_pref)
      else
        G_reader_settings:delete("document_metadata_folder")
      end
    end
  )

  describe("cleanHashLocationIfEmpty", function()
    local hash_dir = DataStorage:getDocSettingsHashDir()

    it("does nothing when hash directory does not exist", function()
      ffiutil.purgeDir(hash_dir)
      assert.has_no_errors(function()
        docsettings.cleanHashLocationIfEmpty()
      end)
      assert.is_false(util.directoryExists(hash_dir))
    end)

    it(
      "keeps hash directory intact when regular metadata file exists",
      function()
        ffiutil.purgeDir(hash_dir)
        local sdr_dir = hash_dir .. "/ab/sample.sdr"
        util.makePath(sdr_dir)
        local file = sdr_dir .. "/metadata.epub.lua"
        local f = io.open(file, "w")
        if f then
          f:write("return {}")
          f:close()
        end

        docsettings.cleanHashLocationIfEmpty()
        assert.is_true(util.directoryExists(hash_dir))
        assert.is_true(util.fileExists(file))

        -- Cleanup
        os.remove(file)
        ffiutil.purgeDir(hash_dir)
      end
    )

    it("keeps hash directory intact when only custom assets exist", function()
      ffiutil.purgeDir(hash_dir)
      local sdr_dir = hash_dir .. "/ab/sample.sdr"
      util.makePath(sdr_dir)
      local custom_file = sdr_dir .. "/custom_metadata.lua"
      local f = io.open(custom_file, "w")
      if f then
        f:write("return {}")
        f:close()
      end

      docsettings.cleanHashLocationIfEmpty()
      assert.is_true(util.directoryExists(hash_dir))
      assert.is_true(util.fileExists(custom_file))

      -- Cleanup
      os.remove(custom_file)
      ffiutil.purgeDir(hash_dir)
    end)

    it(
      "removes hash directory and empty subdirectories when no files exist",
      function()
        ffiutil.purgeDir(hash_dir)
        local sdr_dir = hash_dir .. "/ab/empty.sdr"
        util.makePath(sdr_dir)
        assert.is_true(util.directoryExists(sdr_dir))

        docsettings.cleanHashLocationIfEmpty()
        -- hash_dir and all subdirectories should be removed
        assert.is_false(util.directoryExists(hash_dir))

        -- Cleanup
        ffiutil.purgeDir(hash_dir)
      end
    )

    it("logs warning when removeEmptyTree fails", function()
      local orig_removeEmptyTree = util.removeEmptyTree
      local warn_called = false
      local orig_warn = logger.warn
      logger.warn = function(...)
        warn_called = true
      end
      util.removeEmptyTree = function()
        return nil, "permission denied"
      end

      docsettings.cleanHashLocationIfEmpty()
      assert.is_true(warn_called)

      util.removeEmptyTree = orig_removeEmptyTree
      logger.warn = orig_warn
    end)
  end)

  it("handles custom cover, custom metadata, and updateLocation", function()
    local tmp_dir = makeTempDir()
    finally(function()
      ffiutil.purgeDir(tmp_dir)
    end)

    local file = tmp_dir .. "/test_custom_doc.epub"
    local d = docsettings:open(file)
    d:save("author", "Test Author")
    d:flush()

    local tmp_cover = tmp_dir .. "/test_cover.jpg"
    local f = io.open(tmp_cover, "w")
    f:write("cover data")
    f:close()

    d:flushCustomCover(file, tmp_cover)
    d:flushCustomMetadata(file)

    local found_cover = d:findCustomCoverFile(file)
    local found_meta = d:findCustomMetadataFile(file)
    assert.is_truthy(found_cover)
    assert.is_truthy(found_meta)

    -- Test updateLocation copy and move
    local new_file = tmp_dir .. "/test_custom_doc_moved.epub"
    docsettings.updateLocation(file, new_file, true) -- copy
    assert.is_true(docsettings:hasSidecarFile(new_file))
    assert.is_true(docsettings:hasSidecarFile(file))
    assert.is_truthy(docsettings:findCustomCoverFile(file))
    assert.is_truthy(docsettings:findCustomMetadataFile(file))

    -- cleanup
    docsettings.updateLocation(new_file, nil) -- delete
    docsettings.updateLocation(file, nil) -- delete
    os.remove(tmp_cover)
  end)

  it(
    "handles updateLocation when only custom files exist without sidecar file",
    function()
      local tmp_dir = makeTempDir()
      finally(function()
        ffiutil.purgeDir(tmp_dir)
      end)

      local file = tmp_dir .. "/test_custom_only.epub"
      local new_file = tmp_dir .. "/test_custom_only_moved.epub"
      local tmp_cover = tmp_dir .. "/test_cover_only.jpg"
      docsettings.updateLocation(new_file, nil)
      docsettings.updateLocation(file, nil)
      os.remove(tmp_cover)
      local f = io.open(tmp_cover, "w")
      if f then
        f:write("cover binary")
        f:close()
      end

      local d = docsettings:open(file)
      d:flushCustomCover(file, tmp_cover)
      d:flushCustomMetadata(file)

      assert.is_false(docsettings:hasSidecarFile(file))
      assert.is_truthy(docsettings:findCustomCoverFile(file))
      assert.is_truthy(docsettings:findCustomMetadataFile(file))

      docsettings.updateLocation(file, new_file, true) -- copy
      assert.is_false(docsettings:hasSidecarFile(new_file))
      assert.is_truthy(docsettings:findCustomCoverFile(new_file))
      assert.is_truthy(docsettings:findCustomMetadataFile(new_file))
      assert.is_truthy(docsettings:findCustomCoverFile(file))
      assert.is_truthy(docsettings:findCustomMetadataFile(file))

      docsettings.updateLocation(new_file, nil) -- delete
      docsettings.updateLocation(file, nil) -- delete
      os.remove(tmp_cover)
    end
  )

  it(
    "preserves original custom cover and metadata when move copyFile fails",
    function()
      local test_dir = makeTempDir()
      finally(function()
        ffiutil.purgeDir(test_dir)
      end)
      local orig_dir = test_dir .. "/orig"
      local new_dir = test_dir .. "/new"
      lfs.mkdir(orig_dir)
      lfs.mkdir(new_dir)

      local book = orig_dir .. "/book.epub"
      local f = io.open(book, "w")
      f:write("dummy book")
      f:close()

      local book_sdr = orig_dir .. "/book.sdr"
      lfs.mkdir(book_sdr)
      local cover_file = book_sdr .. "/cover.png"
      f = io.open(cover_file, "w")
      f:write("cover data")
      f:close()

      local meta_file = book_sdr .. "/custom_metadata.lua"
      f = io.open(meta_file, "w")
      f:write("return {}")
      f:close()

      local new_book = new_dir .. "/book.epub"

      local orig_copyFile = ffiutil.copyFile
      ffiutil.copyFile = function(src, dst)
        if src == cover_file or src == meta_file then
          return "copy failed: disk full"
        end
        return orig_copyFile(src, dst)
      end

      local notified = {}
      local UIManager = require("ui/uimanager")
      local orig_show = UIManager.show
      UIManager.show = function(_, widget)
        table.insert(notified, widget)
      end

      docsettings.updateLocation(book, new_book, false) -- move operation

      assert.is_true(util.fileExists(cover_file))
      assert.is_true(util.fileExists(meta_file))
      assert.is_true(#notified >= 2)

      ffiutil.copyFile = orig_copyFile
      UIManager.show = orig_show
      util.removePath(test_dir)
    end
  )

  describe("read-only storage fallbacks and notifications", function()
    local util = require("util")
    local UIManager = require("ui/uimanager")
    local original_isDirRW = util.isDirRW
    local orig_show = UIManager.show
    local shown_notifications
    local ro_temp_dir

    local function createDummyFile(path)
      local f = io.open(path, "w")
      if f then
        f:write("dummy epub content")
        f:close()
      end
    end

    local function getCandsMap(file)
      local map = {}
      for _, cand in ipairs(docsettings:open(file).candidates) do
        if cand.dir and not map[cand.location] then
          map[cand.location] = cand.dir
        end
      end
      return map
    end

    local orig_isHash = docsettings.isHashLocationEnabled

    before_each(function()
      ro_temp_dir = makeTempDir()
      shown_notifications = {}
      UIManager.show = function(_, widget)
        table.insert(shown_notifications, widget)
      end
    end)

    after_each(function()
      util.isDirRW = original_isDirRW
      UIManager.show = orig_show
      docsettings.isHashLocationEnabled = orig_isHash
      G_reader_settings:delete("document_metadata_folder")
      ffiutil.purgeDir(ro_temp_dir)
    end)

    it(
      "falls back to dir location when doc location is read-only and notifies once",
      function()
        G_reader_settings:save("document_metadata_folder", "doc")
        local file = ro_temp_dir .. "/test_ro_doc_1.epub"
        createDummyFile(file)
        local d = docsettings:open(file)
        local cands = getCandsMap(file)

        util.isDirRW = function(dir, create)
          if dir == cands.doc then
            return false
          end
          return original_isDirRW(dir, create)
        end

        d:save("page", 42)
        local saved_dir = d:flush()
        assert.are.equal(cands.dir, saved_dir)
        assert.are.equal(1, #shown_notifications)
        assert.is_truthy(
          shown_notifications[1].text:find("alternate storage location")
        )

        -- Second flush should not re-notify
        d:save("page", 43)
        d:flush()
        assert.are.equal(1, #shown_notifications)

        d:close()
        d:purge()
      end
    )

    it(
      "falls back to hash location when both doc and dir locations are read-only and hash is enabled",
      function()
        docsettings.isHashLocationEnabled = function()
          return true
        end
        G_reader_settings:save("document_metadata_folder", "doc")
        local file = ro_temp_dir .. "/test_ro_doc_2.epub"
        createDummyFile(file)
        local d = docsettings:open(file)
        local cands = getCandsMap(file)

        util.isDirRW = function(dir, create)
          if dir == cands.doc or dir == cands.dir then
            return false
          end
          return original_isDirRW(dir, create)
        end

        d:save("page", 100)
        local saved_dir = d:flush()
        assert.are.equal(cands.hash, saved_dir)
        assert.are.equal(1, #shown_notifications)
        assert.is_truthy(
          shown_notifications[1].text:find("alternate storage location")
        )

        d:close()
        d:purge()
      end
    )

    it(
      "falls back to temporary location when doc and dir are read-only and hash location is disabled",
      function()
        docsettings.isHashLocationEnabled = function()
          return false
        end
        G_reader_settings:save("document_metadata_folder", "doc")
        local file = ro_temp_dir .. "/test_ro_doc_2.epub"
        createDummyFile(file)
        local d = docsettings:open(file)
        local cands = getCandsMap(file)

        assert.is_nil(cands.hash)

        util.isDirRW = function(dir, create)
          if dir == cands.doc or dir == cands.dir then
            return false
          end
          return original_isDirRW(dir, create)
        end

        d:save("page", 150)
        local saved_dir = d:flush()
        assert.are.equal(cands.tmp, saved_dir)
        assert.are.equal(1, #shown_notifications)
        assert.is_truthy(shown_notifications[1].text:find("temporary storage"))

        d:close()
        d:purge()
      end
    )

    it(
      "falls back to temporary location when all permanent locations are read-only",
      function()
        docsettings.isHashLocationEnabled = function()
          return true
        end
        G_reader_settings:save("document_metadata_folder", "doc")
        local file = ro_temp_dir .. "/test_ro_doc_3.epub"
        createDummyFile(file)
        local d = docsettings:open(file)
        local cands = getCandsMap(file)

        util.isDirRW = function(dir, create)
          if dir == cands.doc or dir == cands.dir or dir == cands.hash then
            return false
          end
          return original_isDirRW(dir, create)
        end

        d:save("page", 200)
        local saved_dir = d:flush()
        assert.are.equal(cands.tmp, saved_dir)
        assert.are.equal(1, #shown_notifications)
        assert.is_truthy(shown_notifications[1].text:find("temporary storage"))

        d:close()
        d:purge()
      end
    )

    it(
      "falls back to in-memory mode when all storage locations are read-only",
      function()
        G_reader_settings:save("document_metadata_folder", "doc")
        local file = ro_temp_dir .. "/test_ro_doc_4.epub"
        createDummyFile(file)
        local d = docsettings:open(file)

        util.isDirRW = function()
          return false
        end

        d:save("page", 300)
        local saved_dir = d:flush()
        assert.is_nil(saved_dir)
        assert.are.equal(1, #shown_notifications)
        assert.is_truthy(
          shown_notifications[1].text:find("completely read%-only")
        )

        d:close()
      end
    )

    it(
      "falls back to next writable location for flushCustomCover and flushCustomMetadata",
      function()
        local file = ro_temp_dir .. "/test_ro_custom.epub"
        createDummyFile(file)
        local d = docsettings:open(file)
        local tmp_cover = ro_temp_dir .. "/test_ro_cover.jpg"
        local f = io.open(tmp_cover, "w")
        if f then
          f:write("cover data")
          f:close()
        end

        util.isDirRW = function(dir, create)
          if dir == d.candidates[1].dir then
            return false
          end
          return original_isDirRW(dir, create)
        end

        assert.is_true(d:flushCustomCover(file, tmp_cover))
        assert.is_true(d:flushCustomMetadata(file))

        d:close()
        d:purge()
        os.remove(tmp_cover)
        os.remove(file)
      end
    )

    it(
      "migrates existing custom cover and metadata to fallback directory on flush",
      function()
        local file = ro_temp_dir .. "/test_ro_doc_5.epub"
        createDummyFile(file)
        local tmp_cover = ro_temp_dir .. "/test_ro_cov_mig.jpg"
        local f = io.open(tmp_cover, "w")
        if f then
          f:write("cover data")
          f:close()
        end

        local d = docsettings:open(file)
        local cands = getCandsMap(file)
        d:save("page", 5)
        d:flushCustomCover(file, tmp_cover)
        d:flushCustomMetadata(file)
        d:flush()

        local orig_cover = d:findCustomCoverFile()
        local orig_meta = d:findCustomMetadataFile()
        assert.is_true(util.stringStartsWith(orig_cover, cands.doc))
        assert.is_true(util.stringStartsWith(orig_meta, cands.doc))

        util.isDirRW = function(dir, create)
          if dir == cands.doc then
            return false
          end
          return original_isDirRW(dir, create)
        end

        d:save("page", 10)
        local saved_dir = d:flush()
        assert.are.equal(cands.dir, saved_dir)

        local new_cover = d:findCustomCoverFile()
        local new_meta = d:findCustomMetadataFile()
        assert.is_true(util.stringStartsWith(new_cover, cands.dir))
        assert.is_true(util.stringStartsWith(new_meta, cands.dir))

        d:close()
        d:purge()
        os.remove(tmp_cover)
        os.remove(file)
      end
    )

    it(
      "falls back to hash location when dir is preferred and dir location is read-only",
      function()
        docsettings.isHashLocationEnabled = function()
          return true
        end
        G_reader_settings:save("document_metadata_folder", "dir")
        local file = ro_temp_dir .. "/test_ro_doc_dir_pref.epub"
        createDummyFile(file)
        local d = docsettings:open(file)
        local cands = getCandsMap(file)

        util.isDirRW = function(dir, create)
          if dir == cands.dir then
            return false
          end
          return original_isDirRW(dir, create)
        end

        d:save("page", 50)
        local saved_dir = d:flush()
        assert.are.equal(cands.hash, saved_dir)
        assert.are.equal(1, #shown_notifications)
        assert.is_truthy(
          shown_notifications[1].text:find("alternate storage location")
        )

        d:close()
        d:purge()
        os.remove(file)
      end
    )

    it(
      "falls back to doc location when dir is preferred and both dir and hash are read-only",
      function()
        docsettings.isHashLocationEnabled = function()
          return true
        end
        G_reader_settings:save("document_metadata_folder", "dir")
        local file = ro_temp_dir .. "/test_ro_doc_dir_pref2.epub"
        createDummyFile(file)
        local d = docsettings:open(file)
        local cands = getCandsMap(file)

        util.isDirRW = function(dir, create)
          if dir == cands.dir or dir == cands.hash then
            return false
          end
          return original_isDirRW(dir, create)
        end

        d:save("page", 60)
        local saved_dir = d:flush()
        assert.are.equal(cands.doc, saved_dir)
        assert.are.equal(1, #shown_notifications)
        assert.is_truthy(
          shown_notifications[1].text:find("alternate storage location")
        )

        d:close()
        d:purge()
        os.remove(file)
      end
    )

    it(
      "falls back to dir location when hash is preferred and hash location is read-only",
      function()
        G_reader_settings:save("document_metadata_folder", "hash")
        local file = ro_temp_dir .. "/test_ro_doc_hash_pref.epub"
        createDummyFile(file)
        local d = docsettings:open(file)
        local cands = getCandsMap(file)

        util.isDirRW = function(dir, create)
          if dir == cands.hash then
            return false
          end
          return original_isDirRW(dir, create)
        end

        d:save("page", 70)
        local saved_dir = d:flush()
        assert.are.equal(cands.dir, saved_dir)
        assert.are.equal(1, #shown_notifications)
        assert.is_truthy(
          shown_notifications[1].text:find("alternate storage location")
        )

        d:close()
        d:purge()
        os.remove(file)
      end
    )

    it(
      "falls back to doc location when hash is preferred and both hash and dir are read-only",
      function()
        G_reader_settings:save("document_metadata_folder", "hash")
        local file = ro_temp_dir .. "/test_ro_doc_hash_pref2.epub"
        createDummyFile(file)
        local d = docsettings:open(file)
        local cands = getCandsMap(file)

        util.isDirRW = function(dir, create)
          if dir == cands.hash or dir == cands.dir then
            return false
          end
          return original_isDirRW(dir, create)
        end

        d:save("page", 80)
        local saved_dir = d:flush()
        assert.are.equal(cands.doc, saved_dir)
        assert.are.equal(1, #shown_notifications)
        assert.is_truthy(
          shown_notifications[1].text:find("alternate storage location")
        )

        d:close()
        d:purge()
        os.remove(file)
      end
    )

    it(
      "returns nil for flushCustomCover and flushCustomMetadata when all locations are read-only",
      function()
        local file = ro_temp_dir .. "/test_ro_all_custom.epub"
        createDummyFile(file)
        local d = docsettings:open(file)
        local tmp_cover = ro_temp_dir .. "/test_ro_cov_fail.jpg"
        local f = io.open(tmp_cover, "w")
        if f then
          f:write("cover data")
          f:close()
        end

        local UIManager = require("ui/uimanager")
        local shown_messages = {}
        local orig_show = UIManager.show
        UIManager.show = function(_, widget)
          table.insert(shown_messages, widget.text)
        end

        util.isDirRW = function()
          return false
        end

        assert.is_nil(d:flushCustomCover(file, tmp_cover))
        assert.are.equal(1, #shown_messages)
        assert.is_truthy(
          shown_messages[1]:match("Storage is completely read%-only")
        )

        assert.is_nil(d:flushCustomMetadata(file))
        assert.are.equal(2, #shown_messages)
        assert.is_truthy(
          shown_messages[2]:match("Storage is completely read%-only")
        )

        UIManager.show = orig_show
        d:close()
        os.remove(tmp_cover)
        os.remove(file)
      end
    )

    it(
      "shows error message when copyFile or writeToFile fails in custom flush",
      function()
        local file = ro_temp_dir .. "/test_fail_custom_write.epub"
        createDummyFile(file)
        local d = docsettings:open(file)
        local tmp_cover = ro_temp_dir .. "/test_fail_cov.jpg"
        local f = io.open(tmp_cover, "w")
        if f then
          f:write("cover data")
          f:close()
        end

        local UIManager = require("ui/uimanager")
        local shown_messages = {}
        local orig_show = UIManager.show
        UIManager.show = function(_, widget)
          table.insert(shown_messages, widget.text)
        end

        local orig_copyFile = ffiutil.copyFile
        ffiutil.copyFile = function()
          return "simulated copy failure"
        end

        assert.is_nil(d:flushCustomCover(file, tmp_cover))
        assert.are.equal(1, #shown_messages)
        assert.is_truthy(shown_messages[1]:match("Failed to save custom cover"))

        ffiutil.copyFile = orig_copyFile

        local orig_writeToFile = util.writeToFile
        util.writeToFile = function()
          return false
        end

        assert.is_nil(d:flushCustomMetadata(file))
        assert.are.equal(2, #shown_messages)
        assert.is_truthy(
          shown_messages[2]:match("Failed to save custom metadata")
        )

        util.writeToFile = orig_writeToFile
        UIManager.show = orig_show
        d:close()
        os.remove(tmp_cover)
        os.remove(file)
      end
    )

    it(
      "shows notification when custom cover or metadata falls back to alternate or tmp storage",
      function()
        local file = ro_temp_dir .. "/test_custom_fallback.epub"
        createDummyFile(file)
        local d = docsettings:open(file)
        local tmp_cover = ro_temp_dir .. "/test_cov_fallback.jpg"
        local f = io.open(tmp_cover, "w")
        if f then
          f:write("cover data")
          f:close()
        end

        local UIManager = require("ui/uimanager")
        local shown_notifications = {}
        local orig_show = UIManager.show
        UIManager.show = function(_, widget)
          table.insert(shown_notifications, widget.text)
        end

        -- Mock doc location as unwritable so it falls back to dir location
        local doc_sdr = getSidecarDir(file)
        local orig_isDirRW = util.isDirRW
        util.isDirRW = function(dir, create)
          if dir == doc_sdr then
            return false
          end
          return orig_isDirRW(dir, create)
        end

        assert.is_true(d:flushCustomCover(file, tmp_cover))
        assert.are.equal(1, #shown_notifications)
        assert.is_truthy(
          shown_notifications[1]:match("alternate storage location")
        )

        assert.is_true(d:flushCustomMetadata(file))
        assert.are.equal(2, #shown_notifications)
        assert.is_truthy(
          shown_notifications[2]:match("alternate storage location")
        )

        util.isDirRW = orig_isDirRW
        UIManager.show = orig_show
        d:close()
        d:purge()
        docsettings.updateLocation(file, nil)
        os.remove(tmp_cover)
        os.remove(file)
      end
    )

    it(
      "shows info message when custom cover or metadata falls back to tmp storage",
      function()
        local file = ro_temp_dir .. "/test_custom_tmp_fallback.epub"
        createDummyFile(file)
        local d = docsettings:open(file)
        local tmp_cover = ro_temp_dir .. "/test_cov_tmp.jpg"
        local f = io.open(tmp_cover, "w")
        if f then
          f:write("cover data")
          f:close()
        end

        local UIManager = require("ui/uimanager")
        local shown_messages = {}
        local orig_show = UIManager.show
        UIManager.show = function(_, widget)
          table.insert(shown_messages, widget.text)
        end

        -- Mock all locations as unwritable except tmp
        local base_tmp = DataStorage:getTmpDir()
        local cands = getCandsMap(file)
        local orig_isDirRW = util.isDirRW
        util.isDirRW = function(dir, create)
          if
            dir ~= cands.doc
            and base_tmp
            and util.stringStartsWith(dir, base_tmp)
          then
            return orig_isDirRW(dir, create)
          end
          return false
        end

        assert.is_true(d:flushCustomCover(file, tmp_cover))
        assert.are.equal(1, #shown_messages)
        assert.is_truthy(
          shown_messages[1]:match("saved to temporary storage and may be lost")
        )

        assert.is_true(d:flushCustomMetadata(file))
        assert.are.equal(2, #shown_messages)
        assert.is_truthy(
          shown_messages[2]:match("saved to temporary storage and may be lost")
        )

        util.isDirRW = orig_isDirRW
        UIManager.show = orig_show
        d:close()
        d:purge()
        docsettings.updateLocation(file, nil)
        os.remove(tmp_cover)
        os.remove(file)
      end
    )
  end)

  describe("candidates ordering in open", function()
    local orig_partialMD5
    local orig_isHash
    before_each(function()
      orig_partialMD5 = util.partialMD5
      orig_isHash = docsettings.isHashLocationEnabled
      util.partialMD5 = function()
        return "b3fb8f4f8448160365087d6ca05c7fa2"
      end
    end)

    after_each(function()
      util.partialMD5 = orig_partialMD5
      docsettings.isHashLocationEnabled = orig_isHash
      G_reader_settings:delete("document_metadata_folder")
    end)

    it(
      "orders candidates correctly when document_metadata_folder is doc",
      function()
        G_reader_settings:save("document_metadata_folder", "doc")
        local d = docsettings:open("/books/sample.epub")
        local candidates = d.candidates
        assert.are.equal("doc", candidates[1].location)
        assert.is_truthy(candidates[1].file:match("metadata%.epub%.lua$"))
        assert.are.equal("dir", candidates[2].location)
        -- When hash location is not enabled, hash candidate is omitted
        assert.are.equal("doc_legacy", candidates[3].location)
        assert.is_truthy(candidates[3].file:match("sample%.epub%.lua$"))
        assert.are.equal("tmp", candidates[#candidates].location)
      end
    )

    it(
      "includes hash candidate in doc order when hash location is enabled",
      function()
        docsettings.isHashLocationEnabled = function()
          return true
        end
        G_reader_settings:save("document_metadata_folder", "doc")
        local d = docsettings:open("/books/sample.epub")
        local candidates = d.candidates
        assert.are.equal("doc", candidates[1].location)
        assert.is_truthy(candidates[1].file:match("metadata%.epub%.lua$"))
        assert.are.equal("dir", candidates[2].location)
        assert.are.equal("hash", candidates[3].location)
        assert.are.equal("doc_legacy", candidates[4].location)
        assert.is_truthy(candidates[4].file:match("sample%.epub%.lua$"))
        assert.are.equal("tmp", candidates[#candidates].location)
      end
    )

    it(
      "orders candidates correctly when document_metadata_folder is dir",
      function()
        G_reader_settings:save("document_metadata_folder", "dir")
        local d = docsettings:open("/books/sample.epub")
        local candidates = d.candidates
        assert.are.equal("dir", candidates[1].location)
        assert.are.equal("doc", candidates[2].location)
        assert.is_truthy(candidates[2].file:match("metadata%.epub%.lua$"))
        assert.are.equal("doc_legacy", candidates[3].location)
        assert.is_truthy(candidates[3].file:match("sample%.epub%.lua$"))
        assert.are.equal("tmp", candidates[#candidates].location)
      end
    )

    it(
      "includes hash candidate in dir order when hash location is enabled",
      function()
        docsettings.isHashLocationEnabled = function()
          return true
        end
        G_reader_settings:save("document_metadata_folder", "dir")
        local d = docsettings:open("/books/sample.epub")
        local candidates = d.candidates
        assert.are.equal("dir", candidates[1].location)
        assert.are.equal("hash", candidates[2].location)
        assert.are.equal("doc", candidates[3].location)
        assert.is_truthy(candidates[3].file:match("metadata%.epub%.lua$"))
        assert.are.equal("doc_legacy", candidates[4].location)
        assert.is_truthy(candidates[4].file:match("sample%.epub%.lua$"))
        assert.are.equal("tmp", candidates[#candidates].location)
      end
    )

    it(
      "orders candidates correctly when document_metadata_folder is hash",
      function()
        G_reader_settings:save("document_metadata_folder", "hash")
        local d = docsettings:open("/books/sample.epub")
        local candidates = d.candidates
        assert.are.equal("hash", candidates[1].location)
        assert.are.equal("dir", candidates[2].location)
        assert.are.equal("doc", candidates[3].location)
        assert.is_truthy(candidates[3].file:match("metadata%.epub%.lua$"))
        assert.are.equal("doc_legacy", candidates[4].location)
        assert.is_truthy(candidates[4].file:match("sample%.epub%.lua$"))
        assert.are.equal("tmp", candidates[#candidates].location)
      end
    )

    it("asserts when doc_path is nil or empty", function()
      assert.has_error(function()
        docsettings:open(nil)
      end)
      assert.has_error(function()
        docsettings:open("")
      end)
    end)

    it(
      "falls back to default doc ordering when document_metadata_folder is unrecognized",
      function()
        G_reader_settings:save("document_metadata_folder", "invalid_val")
        local d = docsettings:open("/books/sample.epub")
        local candidates = d.candidates
        assert.are.equal("doc", candidates[1].location)
        assert.are.equal("dir", candidates[2].location)
        assert.are.equal("doc_legacy", candidates[3].location)
        assert.is_truthy(candidates[3].file:match("sample%.epub%.lua$"))
        assert.are.equal("tmp", candidates[#candidates].location)
      end
    )

    it("appends temporary storage directory as last candidate", function()
      local d = docsettings:open("/books/sample.epub")
      local tmp_cand = d.candidates[#d.candidates]
      assert.is_not_nil(tmp_cand)
      assert.are.equal("tmp", tmp_cand.location)
      assert.are.equal(
        DataStorage:getTmpDir() .. "/docsettings/books/sample.sdr",
        tmp_cand.dir
      )
    end)

    it("omits tmp candidate when getTmpDir() equals getDataDir()", function()
      local orig_getTmp = DataStorage.getTmpDir
      DataStorage.getTmpDir = function(self)
        return self:getDataDir()
      end
      local d = docsettings:open("/books/sample.epub")
      for _, cand in ipairs(d.candidates) do
        assert.are_not.equal("tmp", cand.location)
      end
      DataStorage.getTmpDir = orig_getTmp
    end)

    it(
      "evaluates hash candidate lazily only when earlier candidates are exhausted",
      function()
        docsettings.isHashLocationEnabled = function()
          return true
        end
        local md5_calls = 0
        local orig_md5 = util.partialMD5
        util.partialMD5 = function(p)
          md5_calls = md5_calls + 1
          return orig_md5(p)
        end

        local tmp_dir = makeTempDir()
        finally(function()
          util.partialMD5 = orig_md5
          G_reader_settings:delete("document_metadata_folder")
          ffiutil.purgeDir(tmp_dir)
        end)

        G_reader_settings:save("document_metadata_folder", "doc")
        local file = tmp_dir .. "/test_lazy_md5.epub"
        local f = io.open(file, "w")
        if f then
          f:write("epub content")
          f:close()
        end

        -- Create sidecar in doc location
        local doc_sdr = tmp_dir .. "/test_lazy_md5.sdr"
        util.makePath(doc_sdr)
        local sidecar_file = doc_sdr .. "/metadata.epub.lua"
        local sf = io.open(sidecar_file, "w")
        if sf then
          sf:write('return { ["test"] = true }\n')
          sf:close()
        end

        -- Calling _findSidecarFile / hasSidecarFile should find doc sidecar without hashing
        local found_cand = docsettings:_findSidecarFile(file)
        assert.is_not_nil(found_cand)
        assert.are.equal(sidecar_file, found_cand.file)
        assert.are.equal("doc", found_cand.location)
        assert.are.equal(0, md5_calls)

        -- When sidecar does not exist in doc or dir, _findSidecarFile falls through to hash
        os.remove(sidecar_file)
        util.removePath(doc_sdr)

        found_cand = docsettings:_findSidecarFile(file)
        assert.is_nil(found_cand)
        -- Fallback to hash invoked partialMD5
        assert.are.equal(1, md5_calls)

        os.remove(file)
        util.partialMD5 = orig_md5
      end
    )

    it("populates candidates on instance when opened", function()
      local d = docsettings:open("/tmp/test_candidate_instance.epub")
      assert.is_not_nil(d.candidates)
      assert.is_truthy(d.candidates[1].dir:find("test_candidate_instance"))
      d:close()
    end)

    it("handles document paths without file extension", function()
      local d = docsettings:open("/tmp/book_without_ext")
      local candidates = d.candidates
      assert.are.equal("/tmp/book_without_ext.sdr", candidates[1].dir)
      assert.are.equal(
        "/tmp/book_without_ext.sdr/metadata._.lua",
        candidates[1].file
      )
      assert.are.equal(
        docsettings_dir .. "/tmp/book_without_ext.sdr",
        candidates[2].dir
      )
    end)

    it(
      "handles documents named metadata.<ext> without duplicate candidates",
      function()
        local d = docsettings:open("/tmp/metadata.epub")
        assert.is_not_nil(d.candidates)
        local seen = {}
        for _, cand in ipairs(d.candidates) do
          assert.is_not_nil(cand.file)
          assert.are_not.equal("", cand.file)
          assert.is_nil(seen[cand.file])
          seen[cand.file] = true
        end
        d:close()
      end
    )

    it(
      "handles unhashable documents when util.partialMD5 returns nil",
      function()
        local orig_md5 = util.partialMD5
        util.partialMD5 = function()
          return nil
        end
        G_reader_settings:save("document_metadata_folder", "hash")
        local d = docsettings:open("/tmp/unhashable_doc.pdf")
        local hash_cand = d.candidates[1]
        assert.are.equal("hash", hash_cand.location)
        assert.is_nil(hash_cand.file)
        assert.is_nil(hash_cand.dir)

        d:save("title", "Unhashable")
        local saved_dir = d:flush()
        util.partialMD5 = orig_md5
        assert.are.equal(
          docsettings_dir .. "/tmp/unhashable_doc.sdr",
          saved_dir
        )
        d:close()
        d:purge()
      end
    )

    it("reuses cached partial MD5 hash on repeated calls", function()
      local tmp_dir = makeTempDir()
      local orig_partialMD5 = util.partialMD5
      finally(function()
        util.partialMD5 = orig_partialMD5
        G_reader_settings:delete("document_metadata_folder")
        ffiutil.purgeDir(tmp_dir)
      end)

      local file = tmp_dir .. "/test_hash_cache.pdf"
      local f = io.open(file, "w")
      if f then
        f:write("%PDF-1.4 test content for md5 cache")
        f:close()
      end

      local hash_call_count = 0
      util.partialMD5 = function(p)
        hash_call_count = hash_call_count + 1
        return orig_partialMD5(p)
      end

      G_reader_settings:save("document_metadata_folder", "hash")
      local d1 = docsettings:open(file)
      local d2 = docsettings:open(file)

      assert.are.equal(1, hash_call_count)
      assert.are.equal(d1.candidates[1].dir, d2.candidates[1].dir)
    end)

    it(
      "removes corrupted or empty candidate file and falls back to next candidate",
      function()
        local tmp_dir = makeTempDir()
        local file = tmp_dir .. "/test_corrupt.epub"
        local doc_sdr = tmp_dir .. "/test_corrupt.sdr"
        local dir_sdr = docsettings_dir .. doc_sdr
        finally(function()
          docsettings.removeSidecarDir(dir_sdr)
          ffiutil.purgeDir(tmp_dir)
        end)
        local f = io.open(file, "w")
        if f then
          f:write("dummy")
          f:close()
        end
        util.makePath(doc_sdr)
        util.makePath(dir_sdr)

        -- doc candidate has corrupted/empty file
        local f1 = io.open(doc_sdr .. "/metadata.epub.lua", "w")
        f1:write("return {}\n")
        f1:close()

        -- dir candidate has valid settings
        local f2 = io.open(dir_sdr .. "/metadata.epub.lua", "w")
        f2:write('return { ["page"] = 42, ["doc_path"] = "' .. file .. '" }\n')
        f2:close()

        local d = docsettings:open(file)
        assert.are.equal(42, d:read("page"))
        -- Corrupt/empty file was cleaned up from disk
        assert.is_nil(lfs.attributes(doc_sdr .. "/metadata.epub.lua", "mode"))

        d:close()
        d:purge()
        docsettings.removeSidecarDir(doc_sdr)
        docsettings.removeSidecarDir(dir_sdr)
        os.remove(file)
      end
    )
  end)

  describe("removeSidecarDir", function()
    it(
      "keeps parent directory even when path contains /docsettings/ substring",
      function()
        local base_dir = makeTempDir()
        local sub_dir = base_dir .. "/docsettings/nested"
        local sdr_dir = sub_dir .. "/book.sdr"
        util.makePath(sdr_dir)
        finally(function()
          ffiutil.purgeDir(base_dir)
        end)
        assert.are.equal("directory", lfs.attributes(sdr_dir, "mode"))

        docsettings.removeSidecarDir(sdr_dir)

        assert.is_nil(lfs.attributes(sdr_dir, "mode"))
        assert.are.equal("directory", lfs.attributes(sub_dir, "mode"))
      end
    )

    it(
      "prunes empty parent directories when removing sidecar directory inside DOCSETTINGS_DIR",
      function()
        local sub_dir = docsettings_dir .. "/test_author/test_book"
        local sdr_dir = sub_dir .. "/book.sdr"
        util.makePath(sdr_dir)
        assert.are.equal("directory", lfs.attributes(sdr_dir, "mode"))

        docsettings.removeSidecarDir(sdr_dir)

        assert.is_nil(lfs.attributes(sdr_dir, "mode"))
        -- Empty parent directories inside DOCSETTINGS_DIR should be pruned
        assert.is_nil(lfs.attributes(sub_dir, "mode"))
        assert.is_nil(lfs.attributes(docsettings_dir .. "/test_author", "mode"))
      end
    )

    it(
      "keeps parent directory when removing standard sidecar directory",
      function()
        local parent_dir = makeTempDir()
        local sdr_dir = parent_dir .. "/book.sdr"
        util.makePath(sdr_dir)
        finally(function()
          ffiutil.purgeDir(parent_dir)
        end)
        assert.are.equal("directory", lfs.attributes(sdr_dir, "mode"))

        docsettings.removeSidecarDir(sdr_dir)

        assert.is_nil(lfs.attributes(sdr_dir, "mode"))
        assert.are.equal("directory", lfs.attributes(parent_dir, "mode"))
      end
    )

    it(
      "handles nil, empty string, and non-existent path without error",
      function()
        assert.has_no_errors(function()
          docsettings.removeSidecarDir(nil)
          docsettings.removeSidecarDir("")
          docsettings.removeSidecarDir("/nonexistent/koreader_dir_path_12345")
        end)
      end
    )

    it("does not delete non-empty directory", function()
      local test_dir = makeTempDir()
      local sdr_dir = test_dir .. "/book.sdr"
      util.makePath(sdr_dir)
      finally(function()
        ffiutil.purgeDir(test_dir)
      end)
      local test_file = sdr_dir .. "/keepme.txt"
      local f = io.open(test_file, "w")
      if f then
        f:write("keep")
        f:close()
      end

      docsettings.removeSidecarDir(sdr_dir)
      assert.are.equal("directory", lfs.attributes(sdr_dir, "mode"))

      os.remove(test_file)
      docsettings.removeSidecarDir(sdr_dir)
      assert.is_nil(lfs.attributes(sdr_dir, "mode"))
    end)
  end)

  describe("getSidecarFilename", function()
    it("extracts extension suffix for filename", function()
      assert.are.equal(
        "metadata.pdf.lua",
        docsettings.getSidecarFilename("/path/to/doc.pdf")
      )
      assert.are.equal(
        "metadata.epub.lua",
        docsettings.getSidecarFilename("/path/to/doc.epub")
      )
    end)

    it("uses underscore suffix when filename has no extension", function()
      assert.are.equal(
        "metadata._.lua",
        docsettings.getSidecarFilename("/path/to/doc_no_ext")
      )
    end)
  end)

  describe(
    "_findSidecarFile and isSidecarFileNotInPreferredLocation",
    function()
      local find_temp_dir, test_file

      before_each(function()
        find_temp_dir = makeTempDir()
        test_file = find_temp_dir .. "/test_find_sidecar.epub"
      end)

      after_each(function()
        G_reader_settings:delete("document_metadata_folder")
        docsettings.updateLocation(test_file, nil)
        ffiutil.purgeDir(find_temp_dir)
      end)

      it("returns nil when doc_path is nil or empty", function()
        assert.is_nil(docsettings:_findSidecarFile(nil))
        assert.is_nil(docsettings:_findSidecarFile(""))
      end)

      it(
        "returns false for isSidecarFileNotInPreferredLocation when file does not exist",
        function()
          assert.is_false(
            docsettings.isSidecarFileNotInPreferredLocation(
              "/nonexistent/file.epub"
            )
          )
        end
      )

      it("detects sidecar file in preferred location", function()
        G_reader_settings:save("document_metadata_folder", "doc")
        local d = docsettings:open(test_file)
        d:save("title", "Preferred Location Test")
        d:flush()
        d:close()

        local cand = docsettings:_findSidecarFile(test_file)
        assert.is_not_nil(cand)
        assert.are.equal("doc", cand.location)
        assert.is_false(
          docsettings.isSidecarFileNotInPreferredLocation(test_file)
        )
      end)

      it("detects sidecar file in non-preferred location", function()
        G_reader_settings:save("document_metadata_folder", "dir")
        local d = docsettings:open(test_file)
        d:save("title", "Non-preferred Test")
        d:flush()
        d:close()

        G_reader_settings:save("document_metadata_folder", "doc")
        local cand = docsettings:_findSidecarFile(test_file)
        assert.is_not_nil(cand)
        assert.are.equal("dir", cand.location)
        assert.is_true(
          docsettings.isSidecarFileNotInPreferredLocation(test_file)
        )
      end)

      it("finds sidecar in legacy history", function()
        local hist_file = docsettings:getHistoryPath(test_file)
        local f_out = io.open(hist_file, "w")
        if f_out then
          f_out:write("return { ['title'] = 'Legacy' }\n")
          f_out:close()
        end

        local cand = docsettings:_findSidecarFile(test_file)
        assert.is_not_nil(cand)
        assert.are.equal(hist_file, cand.file)
        assert.are.equal("hist", cand.location)
        assert.is_true(
          docsettings.isSidecarFileNotInPreferredLocation(test_file)
        )

        os.remove(hist_file)
      end)

      it("finds sidecar in legacy doc format", function()
        G_reader_settings:save("document_metadata_folder", "doc")
        local stem = test_file:match("(.*)%.") or test_file
        local doc_sdr = stem .. ".sdr"
        util.makePath(doc_sdr)
        local doc_legacy_file = doc_sdr
          .. "/"
          .. ffiutil.basename(test_file)
          .. ".lua"
        local f_out = io.open(doc_legacy_file, "w")
        if f_out then
          f_out:write("return { ['title'] = 'Legacy Doc' }\n")
          f_out:close()
        end

        local cand = docsettings:_findSidecarFile(test_file)
        assert.is_not_nil(cand)
        assert.are.equal(doc_legacy_file, cand.file)
        assert.are.equal("doc_legacy", cand.location)
        assert.is_true(
          docsettings.isSidecarFileNotInPreferredLocation(test_file)
        )

        os.remove(doc_legacy_file)
        util.removePath(doc_sdr)
      end)
    end
  )

  describe("history path conversion", function()
    it("handles getHistoryPath with nil and empty string", function()
      assert.are.equal("", docsettings:getHistoryPath(nil))
      assert.are.equal("", docsettings:getHistoryPath(""))
    end)

    it("handles getPathFromHistory edge cases", function()
      assert.are.equal("", docsettings:getPathFromHistory(nil))
      assert.are.equal("", docsettings:getPathFromHistory(""))
      assert.are.equal("", docsettings:getPathFromHistory("invalid.lua.old"))
      assert.are.equal("", docsettings:getPathFromHistory("no_brackets.lua"))
    end)

    it("handles getNameFromHistory edge cases", function()
      assert.are.equal("", docsettings:getNameFromHistory(nil))
      assert.are.equal("", docsettings:getNameFromHistory(""))
      assert.are.equal("", docsettings:getNameFromHistory("invalid.lua.old"))
      assert.are.equal("", docsettings:getNameFromHistory("no_brackets.lua"))
    end)

    it("handles history filenames with multiple hashes or symbols", function()
      local hist = "[#sdcard#Books#] My #1 Book.lua"
      assert.are.equal("/sdcard/Books", docsettings:getPathFromHistory(hist))
      assert.are.equal("My #1 Book", docsettings:getNameFromHistory(hist))
    end)

    it(
      "converts valid history path back and forth with getFileFromHistory",
      function()
        local doc_path = "/sdcard/Books/My Book.epub"
        local hist_path = docsettings:getHistoryPath(doc_path)
        local hist_name = ffiutil.basename(hist_path)
        assert.are.equal(doc_path, docsettings:getFileFromHistory(hist_name))
        assert.is_nil(docsettings:getFileFromHistory("invalid.lua"))
      end
    )
  end)

  describe("getCustomLocationCandidate", function()
    local cand_temp_dir, test_doc

    before_each(function()
      cand_temp_dir = makeTempDir()
      test_doc = cand_temp_dir .. "/test_custom_cand.epub"
      local f = io.open(test_doc, "w")
      if f then
        f:write("dummy test epub")
        f:close()
      end
    end)

    after_each(function()
      docsettings.updateLocation(test_doc, nil)
      G_reader_settings:delete("document_metadata_folder")
      ffiutil.purgeDir(cand_temp_dir)
    end)

    it(
      "returns first writable candidate directory when no sidecar file exists",
      function()
        local cand = docsettings:getCustomLocationCandidate(test_doc)
        assert.is_table(cand)
        assert.are.equal(cand_temp_dir .. "/test_custom_cand.sdr", cand.dir)
      end
    )

    it("returns hash directory when hash is preferred", function()
      G_reader_settings:save("document_metadata_folder", "hash")
      local cand = docsettings:getCustomLocationCandidate(test_doc)
      assert.is_table(cand)
      assert.are.equal(getSidecarDir(test_doc), cand.dir)
    end)

    it("returns existing sidecar dir when sidecar file exists", function()
      local d = docsettings:open(test_doc)
      d:save("page", 1)
      d:flush()
      d:close()

      local cand = docsettings:getCustomLocationCandidate(test_doc)
      assert.is_table(cand)
      assert.are.equal(getSidecarDir(test_doc), cand.dir)
    end)

    it(
      "falls back to next writable directory when existing sidecar dir is not writable",
      function()
        local d = docsettings:open(test_doc)
        d:save("page", 1)
        d:flush()
        d:close()

        local existing_sdr = getSidecarDir(test_doc)
        local orig_isDirRW = util.isDirRW
        util.isDirRW = function(dir, create)
          if dir == existing_sdr then
            return false
          end
          return orig_isDirRW(dir, create)
        end

        local cand = docsettings:getCustomLocationCandidate(test_doc)
        util.isDirRW = orig_isDirRW

        assert.is_table(cand)
        assert.are_not.equal(existing_sdr, cand.dir)
      end
    )
  end)

  describe("updateLocation with read-only fallback", function()
    it(
      "falls back to next writable directory when new doc directory is read-only",
      function()
        local tmp_dir = makeTempDir()
        local orig_isDirRW = util.isDirRW
        finally(function()
          util.isDirRW = orig_isDirRW
          docsettings.updateLocation(tmp_dir .. "/test_upd_ro_new.epub", nil)
          docsettings.updateLocation(tmp_dir .. "/test_upd_ro_orig.epub", nil)
          ffiutil.purgeDir(tmp_dir)
        end)
        local orig_file = tmp_dir .. "/test_upd_ro_orig.epub"
        local new_file = tmp_dir .. "/test_upd_ro_new.epub"
        local tmp_cover = tmp_dir .. "/test_upd_ro_cov.jpg"

        local f = io.open(tmp_cover, "w")
        if f then
          f:write("cover data")
          f:close()
        end

        local d = docsettings:open(orig_file)
        d:save("title", "Update RO Test")
        d:flush()
        d:flushCustomCover(orig_file, tmp_cover)
        d:close()

        local new_doc_sdr = getSidecarDir(new_file)
        util.isDirRW = function(dir, create)
          if dir == new_doc_sdr then
            return false
          end
          return orig_isDirRW(dir, create)
        end

        docsettings.updateLocation(orig_file, new_file, true)
        util.isDirRW = orig_isDirRW

        local found_cover = docsettings:findCustomCoverFile(new_file)
        assert.is_truthy(found_cover)
        assert.is_false(util.stringStartsWith(found_cover, new_doc_sdr))
      end
    )

    it(
      "guards against nil new_sidecar_dir and warns user when all candidate storages are read-only",
      function()
        local tmp_dir = makeTempDir()
        local UIManager = require("ui/uimanager")
        local orig_show = UIManager.show
        local orig_isDirRW = util.isDirRW
        local orig_file = tmp_dir .. "/test_upd_all_ro_orig.epub"
        local new_file = tmp_dir .. "/test_upd_all_ro_new.epub"
        local tmp_cover = tmp_dir .. "/test_upd_all_ro_cov.jpg"
        finally(function()
          util.isDirRW = orig_isDirRW
          UIManager.show = orig_show
          docsettings.updateLocation(orig_file, nil)
          ffiutil.purgeDir(tmp_dir)
        end)

        local f = io.open(tmp_cover, "w")
        if f then
          f:write("cover data")
          f:close()
        end

        local d = docsettings:open(orig_file)
        d:save("title", "All RO Test")
        d:flush()
        d:flushCustomCover(orig_file, tmp_cover)
        d:close()

        local shown_warning = nil
        UIManager.show = function(_, widget)
          shown_warning = widget
        end

        util.isDirRW = function()
          return false
        end

        -- Call updateLocation with move (copy = false)
        assert.has_no_errors(function()
          docsettings.updateLocation(orig_file, new_file, false)
        end)

        util.isDirRW = orig_isDirRW
        UIManager.show = orig_show

        -- Check warning was shown
        assert.is_not_nil(shown_warning)
        assert.is_truthy(
          shown_warning.text:find(
            "Failed to save book settings to the new location"
          )
        )

        -- Original sidecar and custom cover must still exist (not purged)
        assert.is_true(docsettings:hasSidecarFile(orig_file))
        assert.is_truthy(docsettings:findCustomCoverFile(orig_file))
      end
    )

    it(
      "removes referenced cache_file_path when deleting via updateLocation",
      function()
        local tmp_dir = makeTempDir()
        finally(function()
          ffiutil.purgeDir(tmp_dir)
        end)
        local file = tmp_dir .. "/test_cache_del.epub"
        local dummy_cache = tmp_dir .. "/test_extracted_cache.bin"
        local f = io.open(file, "w")
        if f then
          f:write("dummy")
          f:close()
        end
        local fc = io.open(dummy_cache, "w")
        if fc then
          fc:write("cached data")
          fc:close()
        end

        local d = docsettings:open(file)
        d:save("cache_file_path", dummy_cache)
        d:flush()
        d:close()

        assert.is_truthy(lfs.attributes(dummy_cache, "mode"))
        docsettings.updateLocation(file, nil) -- delete
        assert.is_nil(lfs.attributes(dummy_cache, "mode"))
      end
    )

    it(
      "preserves hash-based sidecar on rename/move when hash location is preferred",
      function()
        local tmp_dir = makeTempDir()
        local file1 = tmp_dir .. "/test_hash_move_1.pdf"
        local file2 = tmp_dir .. "/test_hash_move_2.pdf"
        finally(function()
          docsettings.updateLocation(file1, nil)
          G_reader_settings:delete("document_metadata_folder")
          ffiutil.purgeDir(tmp_dir)
        end)
        G_reader_settings:save("document_metadata_folder", "hash")
        local f = io.open(file1, "w")
        if f then
          f:write("%PDF-1.4 dummy pdf content")
          f:close()
        end

        local d = docsettings:open(file1)
        d:save("page", 15)
        d:flush()
        d:close()

        local sidecar_before = docsettings:_findSidecarFile(file1)
        assert.is_truthy(sidecar_before)

        -- Move operation should keep hash sidecar unchanged
        docsettings.updateLocation(file1, file2, false)
        assert.is_truthy(util.fileExists(sidecar_before.file))
      end
    )
  end)

  describe("flush dynamic settings change", function()
    it(
      "refreshes candidates when document_metadata_folder changes after open",
      function()
        local UIManager = require("ui/uimanager")
        local tmp_dir = makeTempDir()
        local file = tmp_dir .. "/test_flush_dyn.epub"
        local d
        finally(function()
          if d then
            d:close()
            d:purge()
          end
          G_reader_settings:delete("document_metadata_folder")
          ffiutil.purgeDir(tmp_dir)
        end)
        local f = io.open(file, "w")
        if f then
          f:write("dummy")
          f:close()
        end

        G_reader_settings:save("document_metadata_folder", "doc")
        d = docsettings:open(file)
        assert.are.equal("doc", d.candidates[1].location)

        -- Write initial settings to doc location
        d:save("page", 1)
        local initial_dir = d:flush()
        assert.are.equal(getSidecarDir(file), initial_dir)

        -- Dynamically change preferred setting to dir (internal storage)
        G_reader_settings:save("document_metadata_folder", "dir")

        local shown_notifications = {}
        local orig_show = UIManager.show
        UIManager.show = function(_, widget)
          table.insert(shown_notifications, widget)
        end

        d:save("page", 2)
        local new_dir = d:flush()

        UIManager.show = orig_show

        -- Wrote to internal storage because flush refreshed candidates
        assert.are.equal(
          docsettings_dir .. tmp_dir .. "/test_flush_dyn.sdr",
          new_dir
        )
        -- No read-only warning should be shown!
        assert.are.equal(0, #shown_notifications)

        -- Old sidecar in doc location should be purged
        assert.is_nil(lfs.attributes(initial_dir, "mode"))
      end
    )
  end)

  describe("selective purge", function()
    it(
      "selectively purges custom cover without deleting metadata.lua",
      function()
        local tmp_dir = makeTempDir()
        local file = tmp_dir .. "/test_sel_purge.epub"
        local tmp_cover = tmp_dir .. "/test_sel_cov.jpg"
        local d
        finally(function()
          if d then
            d:close()
            d:purge()
          end
          ffiutil.purgeDir(tmp_dir)
        end)
        local f1 = io.open(file, "w")
        if f1 then
          f1:write("dummy book")
          f1:close()
        end
        local f2 = io.open(tmp_cover, "w")
        if f2 then
          f2:write("cover data")
          f2:close()
        end

        d = docsettings:open(file)
        d:save("title", "Selective Purge Test")
        d:flush()
        d:flushCustomCover(file, tmp_cover)

        local cover_file = d:findCustomCoverFile()
        local sidecar_cand = docsettings:_findSidecarFile(file)
        assert.is_truthy(cover_file)
        assert.is_truthy(sidecar_cand)

        -- Purge ONLY custom cover
        d:purge(nil, { custom_cover_file = cover_file })
        assert.is_nil(d:findCustomCoverFile())
        assert.is_truthy(util.fileExists(sidecar_cand.file))
      end
    )
  end)

  it("purge() succeeds on objects created by openSettingsFile", function()
    local obj = docsettings.openSettingsFile()
    assert.has_no_errors(function()
      obj:purge()
    end)
  end)

  describe("Defect verifications", function()
    local orig_metadata_folder

    before_each(function()
      orig_metadata_folder = G_reader_settings:read("document_metadata_folder")
    end)

    after_each(function()
      if orig_metadata_folder ~= nil then
        G_reader_settings:save("document_metadata_folder", orig_metadata_folder)
      else
        G_reader_settings:delete("document_metadata_folder")
      end
    end)

    it(
      "correctly handles getSidecarFilename and candidate dir matching across / in dot-directories",
      function()
        G_reader_settings:save("document_metadata_folder", "doc")
        local doc_path = "/home/user/.books/README"
        assert.are.equal(
          "metadata._.lua",
          docsettings.getSidecarFilename(doc_path)
        )
        assert.are.equal(
          "/home/user/.books/README.sdr",
          getSidecarDir(doc_path)
        )
      end
    )

    it(
      "recovers file path with getFileFromHistory for folder names with square brackets",
      function()
        local doc_path = "/books/[Sci-Fi]/Dune.epub"
        local hist_path = docsettings:getHistoryPath(doc_path)
        local _, hist_name = util.splitFilePathName(hist_path)
        assert.are.equal(doc_path, docsettings:getFileFromHistory(hist_name))
      end
    )

    it("asserts doc_path is a non-empty string in DocSettings:open", function()
      assert.has_error(function()
        docsettings:open(nil)
      end, "DocSettings: doc_path must not be nil or empty")
      assert.has_error(function()
        docsettings:open("")
      end, "DocSettings: doc_path must not be nil or empty")
    end)

    it(
      "asserts when flush is called on an instance created by openSettingsFile",
      function()
        local inst =
          docsettings.openSettingsFile("/nonexistent/dummy_settings.lua")
        assert.has_error(function()
          inst:flush()
        end, "DocSettings: doc_path must not be nil or empty")
      end
    )

    it(
      "shows notification when copyFile fails during flush with custom metadata and preserves file",
      function()
        local tmp_dir = makeTempDir()
        local doc_path = tmp_dir .. "/test_copy_fail_doc.epub"
        local fake_meta = tmp_dir .. "/fake_custom_metadata.lua"
        local inst = docsettings:open(doc_path)
        local orig_getCustomMetadata = inst.getCustomMetadataFile
        local orig_copyFile = ffiutil.copyFile
        local removed = false
        local orig_remove = os.remove
        local UIManager = require("ui/uimanager")
        local orig_show = UIManager.show
        local shown_notification

        finally(function()
          inst.getCustomMetadataFile = orig_getCustomMetadata
          ffiutil.copyFile = orig_copyFile
          os.remove = orig_remove
          UIManager.show = orig_show
          ffiutil.purgeDir(tmp_dir)
        end)

        inst.getCustomMetadataFile = function()
          return fake_meta
        end
        ffiutil.copyFile = function()
          return "permission denied"
        end
        os.remove = function(file)
          if file == fake_meta then
            removed = true
          end
          return orig_remove(file)
        end
        UIManager.show = function(_, widget)
          shown_notification = widget
        end

        inst:flush()
        assert.truthy(shown_notification)
        assert.are.equal(
          gettext("Failed to save custom metadata to disk."),
          shown_notification.text
        )
        assert.is_false(removed)
      end
    )

    it(
      "shows notification when copyFile fails during flush with custom cover and preserves file",
      function()
        local tmp_dir = makeTempDir()
        local doc_path = tmp_dir .. "/test_copy_cover_fail_doc.epub"
        local fake_cover = tmp_dir .. "/fake_custom_cover.png"
        local inst = docsettings:open(doc_path)
        local orig_getCustomCover = inst.getCustomCoverFile
        local orig_copyFile = ffiutil.copyFile
        local removed = false
        local orig_remove = os.remove
        local UIManager = require("ui/uimanager")
        local orig_show = UIManager.show
        local shown_notification

        finally(function()
          inst.getCustomCoverFile = orig_getCustomCover
          ffiutil.copyFile = orig_copyFile
          os.remove = orig_remove
          UIManager.show = orig_show
          ffiutil.purgeDir(tmp_dir)
        end)

        inst.getCustomCoverFile = function()
          return fake_cover
        end
        ffiutil.copyFile = function()
          return "permission denied"
        end
        os.remove = function(file)
          if file == fake_cover then
            removed = true
          end
          return orig_remove(file)
        end
        UIManager.show = function(_, widget)
          shown_notification = widget
        end

        inst:flush()
        assert.truthy(shown_notification)
        assert.are.equal(
          gettext("Failed to save custom cover to disk."),
          shown_notification.text
        )
        assert.is_false(removed)
      end
    )
  end)

  describe("getStatus", function()
    local orig_metadata_folder
    local temp_root

    local function writeFile(path, content)
      local dir = util.splitFilePathName(path)
      if dir ~= "" then
        util.makePath(dir)
      end
      local f = assert(io.open(path, "wb"))
      f:write(content)
      f:close()
    end

    before_each(function()
      orig_metadata_folder = G_reader_settings:read("document_metadata_folder")
      local tmp = os.tmpname()
      os.remove(tmp)
      temp_root = tmp .. "_getstatus"
      util.makePath(temp_root)
    end)

    after_each(function()
      if orig_metadata_folder ~= nil then
        G_reader_settings:save("document_metadata_folder", orig_metadata_folder)
      else
        G_reader_settings:delete("document_metadata_folder")
      end
      ffiutil.purgeDir(temp_root)
    end)

    it("asserts doc_path is a non-empty string", function()
      assert.has_error(function()
        docsettings.getStatus(nil)
      end, "DocSettings: doc_path must not be nil or empty")
      assert.has_error(function()
        docsettings.getStatus("")
      end, "DocSettings: doc_path must not be nil or empty")
    end)

    it("returns 'new' when no sidecar file exists", function()
      G_reader_settings:save("document_metadata_folder", "doc")
      local doc_path = temp_root .. "/missing.epub"
      assert.are.equal("new", docsettings.getStatus(doc_path))
    end)

    it("returns stored summary.status written by DocSettings", function()
      G_reader_settings:save("document_metadata_folder", "doc")
      local doc_path = temp_root .. "/written.epub"
      local d = docsettings:open(doc_path)
      finally(function()
        d:purge()
      end)

      for _, expected_status in ipairs({
        "reading",
        "abandoned",
        "complete",
        "custom_status",
      }) do
        d:save("summary", {
          modified = "2026-11-11",
          note = "Great chapters",
          rating = 5,
          status = expected_status,
        })
        d:save("last_page", 42)
        d:flush()

        assert.are.equal(expected_status, docsettings.getStatus(doc_path))
      end
    end)

    it(
      "returns 'reading' when valid non-empty sidecar lacks summary.status",
      function()
        G_reader_settings:save("document_metadata_folder", "doc")

        local no_summary_doc = temp_root .. "/no_summary.epub"
        local d1 = docsettings:open(no_summary_doc)
        d1:save("last_page", 15)
        d1:save("stats", { pages = 100 })
        d1:flush()
        finally(function()
          d1:purge()
        end)
        assert.are.equal("reading", docsettings.getStatus(no_summary_doc))

        local non_table_doc = temp_root .. "/non_table_summary.epub"
        local sidecar_file =
          non_table_doc:gsub("%.epub$", ".sdr/metadata.epub.lua")
        finally(function()
          os.remove(sidecar_file)
          docsettings.removeSidecarDir(temp_root .. "/non_table_summary.sdr")
        end)
        writeFile(
          sidecar_file,
          'return {\n  ["last_page"] = 1,\n  ["summary"] = "invalid",\n}\n'
        )
        assert.are.equal("reading", docsettings.getStatus(non_table_doc))

        local empty_summary_doc = temp_root .. "/empty_summary.epub"
        local d2 = docsettings:open(empty_summary_doc)
        d2:save("last_page", 3)
        d2:save("summary", {})
        d2:flush()
        finally(function()
          d2:purge()
        end)
        assert.are.equal("reading", docsettings.getStatus(empty_summary_doc))

        local empty_status_doc = temp_root .. "/empty_status.epub"
        local d3 = docsettings:open(empty_status_doc)
        d3:save("summary", { status = "" })
        d3:flush()
        finally(function()
          d3:purge()
        end)
        assert.are.equal("reading", docsettings.getStatus(empty_status_doc))
      end
    )

    it(
      "follows MRU and priority order like DocSettings:open and stops at newest valid sidecar",
      function()
        G_reader_settings:save("document_metadata_folder", "doc")
        local doc_path = temp_root .. "/mru_priority.epub"
        writeFile(doc_path, "dummy epub")
        local sdr_name = docsettings.getSidecarFilename(doc_path)
        local doc_sidecar = temp_root .. "/mru_priority.sdr/" .. sdr_name
        local dir_sidecar = docsettings_dir
          .. temp_root
          .. "/mru_priority.sdr/"
          .. sdr_name
        finally(function()
          os.remove(doc_sidecar)
          os.remove(dir_sidecar)
          docsettings.removeSidecarDir(temp_root .. "/mru_priority.sdr")
          docsettings.removeSidecarDir(
            docsettings_dir .. temp_root .. "/mru_priority.sdr"
          )
        end)

        writeFile(
          doc_sidecar,
          'return {\n  ["summary"] = {\n    ["status"] = "reading",\n  },\n}\n'
        )
        writeFile(
          dir_sidecar,
          'return {\n  ["summary"] = {\n    ["status"] = "abandoned",\n  },\n}\n'
        )

        -- Equal mtime -> higher priority ("doc") wins
        lfs.touch(doc_sidecar, 1000, 1000)
        lfs.touch(dir_sidecar, 1000, 1000)
        assert.are.equal("reading", docsettings.getStatus(doc_path))

        -- Newer mtime ("dir") wins over higher priority ("doc")
        lfs.touch(dir_sidecar, 2000, 2000)
        assert.are.equal("abandoned", docsettings.getStatus(doc_path))

        -- Newer valid sidecar WITHOUT summary returns "reading" instead of older candidate's status
        writeFile(doc_sidecar, 'return {\n  ["last_page"] = 99,\n}\n')
        lfs.touch(doc_sidecar, 3000, 3000)
        assert.are.equal("reading", docsettings.getStatus(doc_path))
      end
    )

    it(
      "skips empty and corrupt candidates to next valid candidate, returning 'new' if all fail",
      function()
        G_reader_settings:save("document_metadata_folder", "doc")
        local doc_path = temp_root .. "/skip_corrupt.epub"
        local sdr_name = docsettings.getSidecarFilename(doc_path)
        local doc_sidecar = temp_root .. "/skip_corrupt.sdr/" .. sdr_name
        local dir_sidecar = docsettings_dir
          .. temp_root
          .. "/skip_corrupt.sdr/"
          .. sdr_name
        finally(function()
          os.remove(doc_sidecar)
          os.remove(dir_sidecar)
          docsettings.removeSidecarDir(temp_root .. "/skip_corrupt.sdr")
          docsettings.removeSidecarDir(
            docsettings_dir .. temp_root .. "/skip_corrupt.sdr"
          )
        end)

        writeFile(
          dir_sidecar,
          'return {\n  ["summary"] = {\n    ["status"] = "complete",\n  },\n}\n'
        )
        lfs.touch(dir_sidecar, 1000, 1000)

        -- Zero-byte empty file candidate
        writeFile(doc_sidecar, "")
        lfs.touch(doc_sidecar, 1500, 1500)
        assert.are.equal("complete", docsettings.getStatus(doc_path))

        -- Empty table candidate
        writeFile(doc_sidecar, "return {}\n")
        lfs.touch(doc_sidecar, 2000, 2000)
        assert.are.equal("complete", docsettings.getStatus(doc_path))

        -- Corrupt Lua candidate
        writeFile(doc_sidecar, "return { broken syntax")
        lfs.touch(doc_sidecar, 3000, 3000)
        assert.are.equal("complete", docsettings.getStatus(doc_path))

        -- When all candidates are empty or corrupt, returns "new"
        writeFile(dir_sidecar, "return {}\n")
        lfs.touch(dir_sidecar, 1000, 1000)
        writeFile(doc_sidecar, "return { broken syntax")
        lfs.touch(doc_sidecar, 3000, 3000)
        assert.are.equal("new", docsettings.getStatus(doc_path))

        writeFile(doc_sidecar, "")
        assert.are.equal("new", docsettings.getStatus(doc_path))
      end
    )

    it(
      "reads status from legacy doc_legacy, hist, and kpdfview locations",
      function()
        G_reader_settings:save("document_metadata_folder", "doc")

        local doc_path = temp_root .. "/legacy_book.pdf"
        local doc_legacy_file = temp_root
          .. "/legacy_book.sdr/legacy_book.pdf.lua"
        local hist_file = docsettings:getHistoryPath(doc_path)
        local kpdfview_file = doc_path .. ".kpdfview.lua"
        finally(function()
          os.remove(doc_legacy_file)
          os.remove(hist_file)
          os.remove(kpdfview_file)
          docsettings.removeSidecarDir(temp_root .. "/legacy_book.sdr")
        end)

        writeFile(
          doc_legacy_file,
          'return {\n  ["summary"] = {\n    ["status"] = "abandoned",\n  },\n}\n'
        )
        assert.are.equal("abandoned", docsettings.getStatus(doc_path))
        os.remove(doc_legacy_file)

        writeFile(
          hist_file,
          'return {\n  ["summary"] = {\n    ["status"] = "reading",\n    ["note"] = "hist note",\n  },\n  ["annotations"] = {},\n}\n'
        )
        assert.are.equal("reading", docsettings.getStatus(doc_path))
        os.remove(hist_file)

        writeFile(
          kpdfview_file,
          'return {\n  ["summary"] = {\n    ["status"] = "complete",\n  },\n}\n'
        )
        assert.are.equal("complete", docsettings.getStatus(doc_path))
      end
    )
  end)

  describe("updateLocation in-place move and custom files", function()
    local temp_root, orig_pref

    before_each(function()
      temp_root = makeTempDir()
      orig_pref = G_reader_settings:read("document_metadata_folder")
    end)

    after_each(function()
      if orig_pref ~= nil then
        G_reader_settings:save("document_metadata_folder", orig_pref)
      else
        G_reader_settings:delete("document_metadata_folder")
      end
      ffiutil.purgeDir(temp_root)
      ffiutil.purgeDir(docsettings_dir .. temp_root)
    end)

    local function createBook(name)
      local path = temp_root .. "/" .. name
      local f = assert(io.open(path, "wb"))
      f:write("book content " .. name)
      f:close()
      return path
    end

    local function createTempCover(name, content)
      local path = temp_root .. "/" .. name
      local f = assert(io.open(path, "wb"))
      f:write(content)
      f:close()
      return path
    end

    it(
      "preserves sidecar data on same-path updateLocation between doc and dir",
      function()
        local book = createBook("move_both_ways.epub")

        G_reader_settings:save("document_metadata_folder", "doc")
        local doc_dir = getSidecarDir(book)
        local doc_file = getSidecarFile(book)
        local ds = docsettings:open(book)
        ds:save("last_page", 42)
        ds:flush()
        ds:close()
        assert.is_true(util.fileExists(doc_file))

        -- Move from doc -> dir
        G_reader_settings:save("document_metadata_folder", "dir")
        local dir_dir = getSidecarDir(book)
        local dir_file = getSidecarFile(book)
        docsettings.updateLocation(book, book)

        assert.is_true(util.fileExists(dir_file))
        assert.is_false(util.fileExists(doc_file))
        assert.is_nil(lfs.attributes(doc_dir, "mode"))
        assert.are.equal(42, docsettings:open(book):read("last_page"))

        -- Move back from dir -> doc
        G_reader_settings:save("document_metadata_folder", "doc")
        docsettings.updateLocation(book, book)

        assert.is_true(util.fileExists(doc_file))
        assert.is_false(util.fileExists(dir_file))
        assert.is_nil(lfs.attributes(dir_dir, "mode"))
        assert.are.equal(42, docsettings:open(book):read("last_page"))
      end
    )

    it(
      "moves sidecar, custom cover, and custom metadata together on same-path updateLocation",
      function()
        local book = createBook("move_with_custom.epub")
        local src_cover = createTempCover("src_cover.png", "png-cover-bytes")

        G_reader_settings:save("document_metadata_folder", "doc")
        local doc_dir = getSidecarDir(book)
        local doc_file = getSidecarFile(book)
        local ds = docsettings:open(book)
        ds:save("last_page", 77)
        ds:flush()
        ds:close()
        assert.is_true(docsettings:flushCustomCover(book, src_cover))
        local custom_meta = docsettings.openSettingsFile()
        custom_meta:save("doc_props", { title = "Custom Title" })
        assert.is_true(custom_meta:flushCustomMetadata(book))

        -- Move doc -> dir
        G_reader_settings:save("document_metadata_folder", "dir")
        local dir_dir = getSidecarDir(book)
        local dir_file = getSidecarFile(book)
        docsettings.updateLocation(book, book)

        assert.is_true(util.fileExists(dir_file))
        assert.is_false(util.fileExists(doc_file))
        assert.is_nil(lfs.attributes(doc_dir, "mode"))
        assert.are.equal(77, docsettings:open(book):read("last_page"))
        local dir_cover = docsettings:findCustomCoverFile(book)
        local dir_meta = docsettings:findCustomMetadataFile(book)
        assert.is_true(util.stringStartsWith(dir_cover, dir_dir .. "/"))
        assert.is_true(util.stringStartsWith(dir_meta, dir_dir .. "/"))
        assert.are.equal("png-cover-bytes", util.readFromFile(dir_cover))
        assert.are.equal(
          "Custom Title",
          docsettings.openSettingsFile(dir_meta):read("doc_props").title
        )

        -- Move dir -> doc
        G_reader_settings:save("document_metadata_folder", "doc")
        docsettings.updateLocation(book, book)

        assert.is_true(util.fileExists(doc_file))
        assert.is_false(util.fileExists(dir_file))
        assert.is_nil(lfs.attributes(dir_dir, "mode"))
        assert.are.equal(77, docsettings:open(book):read("last_page"))
        local back_cover = docsettings:findCustomCoverFile(book)
        local back_meta = docsettings:findCustomMetadataFile(book)
        assert.is_true(util.stringStartsWith(back_cover, doc_dir .. "/"))
        assert.is_true(util.stringStartsWith(back_meta, doc_dir .. "/"))
        assert.are.equal("png-cover-bytes", util.readFromFile(back_cover))
        assert.are.equal(
          "Custom Title",
          docsettings.openSettingsFile(back_meta):read("doc_props").title
        )
      end
    )

    it(
      "removes old sidecar, custom cover, and custom metadata on rename",
      function()
        local orig_book = createBook("rename_orig.epub")
        local new_book = createBook("rename_dest.epub")
        local src_cover = createTempCover("rename_cover.png", "rename-cover")

        G_reader_settings:save("document_metadata_folder", "doc")
        local orig_dir = getSidecarDir(orig_book)
        local new_dir = getSidecarDir(new_book)
        local ds = docsettings:open(orig_book)
        ds:save("last_page", 19)
        ds:flush()
        ds:close()
        assert.is_true(docsettings:flushCustomCover(orig_book, src_cover))
        local custom_meta = docsettings.openSettingsFile()
        custom_meta:save("doc_props", { title = "Renamed Book" })
        assert.is_true(custom_meta:flushCustomMetadata(orig_book))

        docsettings.updateLocation(orig_book, new_book, false)

        assert.is_nil(lfs.attributes(orig_dir, "mode"))
        assert.is_nil(docsettings:findCustomCoverFile(orig_book))
        assert.is_nil(docsettings:findCustomMetadataFile(orig_book))
        assert.are.equal(19, docsettings:open(new_book):read("last_page"))
        local new_cover = docsettings:findCustomCoverFile(new_book)
        local new_meta = docsettings:findCustomMetadataFile(new_book)
        assert.is_true(util.stringStartsWith(new_cover, new_dir .. "/"))
        assert.is_true(util.stringStartsWith(new_meta, new_dir .. "/"))
        assert.are.equal("rename-cover", util.readFromFile(new_cover))
        assert.are.equal(
          "Renamed Book",
          docsettings.openSettingsFile(new_meta):read("doc_props").title
        )
      end
    )

    it(
      "preserves custom cover and custom metadata already in the destination folder",
      function()
        local book = createBook("custom_already_in_dest.epub")
        local src_cover = createTempCover("dest_cover.png", "already-there")

        -- Place custom cover and custom metadata in dir first (no sidecar yet)
        G_reader_settings:save("document_metadata_folder", "dir")
        local dir_dir = getSidecarDir(book)
        local dir_file = getSidecarFile(book)
        assert.is_true(docsettings:flushCustomCover(book, src_cover))
        local custom_meta = docsettings.openSettingsFile()
        custom_meta:save("doc_props", { title = "Dest Meta" })
        assert.is_true(custom_meta:flushCustomMetadata(book))

        -- Create sidecar in doc without moving custom files from dir
        G_reader_settings:save("document_metadata_folder", "doc")
        local doc_dir = getSidecarDir(book)
        local doc_file = getSidecarFile(book)
        local ds = docsettings:open(book)
        ds:save("last_page", 55)
        ds:flush(nil, true)
        assert.is_true(util.fileExists(doc_file))

        -- Move sidecar into dir where custom cover and custom metadata already live
        G_reader_settings:save("document_metadata_folder", "dir")
        assert.is_true(
          util.stringStartsWith(
            docsettings:findCustomCoverFile(book),
            dir_dir .. "/"
          )
        )
        assert.is_true(
          util.stringStartsWith(
            docsettings:findCustomMetadataFile(book),
            dir_dir .. "/"
          )
        )
        docsettings.updateLocation(book, book)

        assert.is_true(util.fileExists(dir_file))
        assert.is_false(util.fileExists(doc_file))
        assert.is_nil(lfs.attributes(doc_dir, "mode"))
        assert.are.equal(55, docsettings:open(book):read("last_page"))
        local kept_cover = docsettings:findCustomCoverFile(book)
        local kept_meta = docsettings:findCustomMetadataFile(book)
        assert.is_true(util.stringStartsWith(kept_cover, dir_dir .. "/"))
        assert.is_true(util.stringStartsWith(kept_meta, dir_dir .. "/"))
        assert.are.equal("already-there", util.readFromFile(kept_cover))
        assert.are.equal(
          "Dest Meta",
          docsettings.openSettingsFile(kept_meta):read("doc_props").title
        )
      end
    )

    it(
      "preserves original sidecar and custom files on rename when flush writeToFile fails",
      function()
        local UIManager = require("ui/uimanager")
        local orig_writeToFile = util.writeToFile
        local orig_show = UIManager.show
        finally(function()
          util.writeToFile = orig_writeToFile
          UIManager.show = orig_show
        end)

        local orig_book = createBook("flush_fail_rename_orig.epub")
        local new_book = createBook("flush_fail_rename_dest.epub")
        local src_cover =
          createTempCover("flush_fail_rename_cover.png", "orig-cover")

        G_reader_settings:save("document_metadata_folder", "doc")
        local orig_file = getSidecarFile(orig_book)
        local new_dir = getSidecarDir(new_book)
        local ds = docsettings:open(orig_book)
        ds:save("last_page", 31)
        ds:flush()
        ds:close()
        assert.is_true(docsettings:flushCustomCover(orig_book, src_cover))
        local custom_meta = docsettings.openSettingsFile()
        custom_meta:save("doc_props", { title = "Keep Original" })
        assert.is_true(custom_meta:flushCustomMetadata(orig_book))
        local orig_cover = docsettings:findCustomCoverFile(orig_book)
        local orig_meta = docsettings:findCustomMetadataFile(orig_book)

        local shown_texts = {}
        UIManager.show = function(_, widget)
          if widget and widget.text then
            table.insert(shown_texts, widget.text)
          end
        end
        util.writeToFile = function()
          return false
        end

        docsettings.updateLocation(orig_book, new_book, false)

        util.writeToFile = orig_writeToFile
        UIManager.show = orig_show

        assert.is_true(util.fileExists(orig_file))
        assert.are.equal(31, docsettings:open(orig_book):read("last_page"))
        assert.is_true(util.fileExists(orig_cover))
        assert.are.equal("orig-cover", util.readFromFile(orig_cover))
        assert.is_true(util.fileExists(orig_meta))
        assert.is_false(util.isDirContainingFiles(new_dir))
        assert.is_false(docsettings:hasSidecarFile(new_book))
        assert.is_nil(docsettings:findCustomCoverFile(new_book))
        assert.is_nil(docsettings:findCustomMetadataFile(new_book))
        local found_msg = false
        for _, text in ipairs(shown_texts) do
          if
            text
            == gettext(
              "Failed to save book settings to the new location. Original settings have been preserved."
            )
          then
            found_msg = true
            break
          end
        end
        assert.is_true(found_msg)
      end
    )

    it(
      "preserves original sidecar and custom files on in-place move when flush writeToFile fails",
      function()
        local UIManager = require("ui/uimanager")
        local orig_writeToFile = util.writeToFile
        local orig_show = UIManager.show
        finally(function()
          util.writeToFile = orig_writeToFile
          UIManager.show = orig_show
        end)

        local book = createBook("flush_fail_inplace.epub")
        local src_cover =
          createTempCover("flush_fail_inplace_cover.png", "inplace-cover")

        G_reader_settings:save("document_metadata_folder", "doc")
        local doc_file = getSidecarFile(book)
        local ds = docsettings:open(book)
        ds:save("last_page", 88)
        ds:flush()
        ds:close()
        assert.is_true(docsettings:flushCustomCover(book, src_cover))
        local custom_meta = docsettings.openSettingsFile()
        custom_meta:save("doc_props", { title = "Inplace Keep" })
        assert.is_true(custom_meta:flushCustomMetadata(book))
        local orig_cover = docsettings:findCustomCoverFile(book)
        local orig_meta = docsettings:findCustomMetadataFile(book)

        G_reader_settings:save("document_metadata_folder", "dir")
        local dir_dir = getSidecarDir(book)
        local dir_file = getSidecarFile(book)

        local shown_texts = {}
        UIManager.show = function(_, widget)
          if widget and widget.text then
            table.insert(shown_texts, widget.text)
          end
        end
        util.writeToFile = function()
          return false
        end

        docsettings.updateLocation(book, book)

        util.writeToFile = orig_writeToFile
        UIManager.show = orig_show

        assert.is_true(util.fileExists(doc_file))
        assert.are.equal(88, docsettings:open(book):read("last_page"))
        assert.is_true(util.fileExists(orig_cover))
        assert.are.equal("inplace-cover", util.readFromFile(orig_cover))
        assert.is_true(util.fileExists(orig_meta))
        assert.is_false(util.fileExists(dir_file))
        assert.is_false(util.isDirContainingFiles(dir_dir))
        local found_msg = false
        for _, text in ipairs(shown_texts) do
          if
            text
            == gettext(
              "Failed to save book settings to the new location. Original settings have been preserved."
            )
          then
            found_msg = true
            break
          end
        end
        assert.is_true(found_msg)
      end
    )

    it(
      "keeps data in current location when preferred writeToFile fails and flush falls back",
      function()
        local orig_writeToFile = util.writeToFile
        finally(function()
          util.writeToFile = orig_writeToFile
        end)

        local book = createBook("flush_partial_fallback.epub")
        local src_cover =
          createTempCover("flush_partial_cover.png", "partial-cover")

        G_reader_settings:save("document_metadata_folder", "doc")
        local doc_file = getSidecarFile(book)
        local ds = docsettings:open(book)
        ds:save("last_page", 64)
        ds:flush()
        ds:close()
        assert.is_true(docsettings:flushCustomCover(book, src_cover))
        local orig_cover = docsettings:findCustomCoverFile(book)

        G_reader_settings:save("document_metadata_folder", "dir")
        local dir_file = getSidecarFile(book)

        util.writeToFile = function(content, filepath, ...)
          if filepath == dir_file then
            return false
          end
          return orig_writeToFile(content, filepath, ...)
        end

        docsettings.updateLocation(book, book)
        util.writeToFile = orig_writeToFile

        assert.is_true(util.fileExists(doc_file))
        assert.is_false(util.fileExists(dir_file))
        assert.are.equal(64, docsettings:open(book):read("last_page"))
        assert.is_true(util.fileExists(orig_cover))
        assert.are.equal("partial-cover", util.readFromFile(orig_cover))
      end
    )

    it(
      "migrates sidecar and custom files between doc and hash on same-path updateLocation",
      function()
        local book = createBook("move_doc_hash.epub")
        local src_cover =
          createTempCover("move_doc_hash_cover.png", "hash-move-cover")
        local hash_dir
        finally(function()
          if hash_dir then
            ffiutil.purgeDir(hash_dir)
            docsettings.cleanHashLocationIfEmpty()
          end
        end)

        G_reader_settings:save("document_metadata_folder", "doc")
        local doc_dir = getSidecarDir(book)
        local doc_file = getSidecarFile(book)
        local ds = docsettings:open(book)
        ds:save("last_page", 42)
        ds:flush()
        ds:close()
        assert.is_true(docsettings:flushCustomCover(book, src_cover))
        local custom_meta = docsettings.openSettingsFile()
        custom_meta:save("doc_props", { title = "Hash Move" })
        assert.is_true(custom_meta:flushCustomMetadata(book))

        -- Move doc -> hash
        G_reader_settings:save("document_metadata_folder", "hash")
        hash_dir = getSidecarDir(book)
        local hash_file = getSidecarFile(book)
        docsettings.updateLocation(book, book)

        assert.is_true(util.fileExists(hash_file))
        assert.is_false(util.fileExists(doc_file))
        assert.is_nil(lfs.attributes(doc_dir, "mode"))
        assert.are.equal(42, docsettings:open(book):read("last_page"))
        local hash_cover = docsettings:findCustomCoverFile(book)
        local hash_meta = docsettings:findCustomMetadataFile(book)
        assert.is_true(util.stringStartsWith(hash_cover, hash_dir .. "/"))
        assert.is_true(util.stringStartsWith(hash_meta, hash_dir .. "/"))
        assert.are.equal("hash-move-cover", util.readFromFile(hash_cover))
        assert.are.equal(
          "Hash Move",
          docsettings.openSettingsFile(hash_meta):read("doc_props").title
        )

        -- Move back hash -> doc
        G_reader_settings:save("document_metadata_folder", "doc")
        docsettings.updateLocation(book, book)

        assert.is_true(util.fileExists(doc_file))
        assert.is_false(util.fileExists(hash_file))
        assert.is_nil(lfs.attributes(hash_dir, "mode"))
        assert.are.equal(42, docsettings:open(book):read("last_page"))
        assert.is_true(
          util.stringStartsWith(
            docsettings:findCustomCoverFile(book),
            doc_dir .. "/"
          )
        )
        assert.is_true(
          util.stringStartsWith(
            docsettings:findCustomMetadataFile(book),
            doc_dir .. "/"
          )
        )
      end
    )

    it(
      "keeps doc and dir storage modes on rename without false fallback notification",
      function()
        local UIManager = require("ui/uimanager")
        local orig_show = UIManager.show
        local shown = {}
        local hash_dir
        finally(function()
          UIManager.show = orig_show
          if hash_dir then
            ffiutil.purgeDir(hash_dir)
            docsettings.cleanHashLocationIfEmpty()
          end
        end)
        UIManager.show = function(_, widget)
          table.insert(shown, widget)
        end

        -- doc sidecar + custom cover renamed while hash is preferred
        local doc_orig = createBook("keep_doc_orig.epub")
        local doc_dest = temp_root .. "/keep_doc_dest.epub"
        local src_cover =
          createTempCover("keep_doc_cover.png", "keep-doc-cover")
        G_reader_settings:save("document_metadata_folder", "doc")
        local doc_orig_dir = getSidecarDir(doc_orig)
        local ds1 = docsettings:open(doc_orig)
        ds1:save("last_page", 11)
        ds1:flush()
        ds1:close()
        assert.is_true(docsettings:flushCustomCover(doc_orig, src_cover))

        G_reader_settings:save("document_metadata_folder", "hash")
        hash_dir = getSidecarDir(doc_orig)
        assert(os.rename(doc_orig, doc_dest))
        docsettings.updateLocation(doc_orig, doc_dest, false)

        assert.is_nil(lfs.attributes(doc_orig_dir, "mode"))
        assert.is_nil(lfs.attributes(hash_dir, "mode"))
        assert.is_true(
          util.fileExists(temp_root .. "/keep_doc_dest.sdr/metadata.epub.lua")
        )
        assert.are.equal(11, docsettings:open(doc_dest):read("last_page"))
        assert.is_true(
          util.stringStartsWith(
            docsettings:findCustomCoverFile(doc_dest),
            temp_root .. "/keep_doc_dest.sdr/"
          )
        )
        assert.are.equal(0, #shown)

        -- dir sidecar renamed while doc is preferred
        local dir_orig = createBook("keep_dir_orig.epub")
        local dir_dest = temp_root .. "/keep_dir_dest.epub"
        G_reader_settings:save("document_metadata_folder", "dir")
        local dir_orig_dir = getSidecarDir(dir_orig)
        local dir_dest_file = getSidecarFile(dir_dest)
        local ds2 = docsettings:open(dir_orig)
        ds2:save("last_page", 22)
        ds2:flush()
        ds2:close()

        G_reader_settings:save("document_metadata_folder", "doc")
        local doc_dest_file = getSidecarFile(dir_dest)
        assert(os.rename(dir_orig, dir_dest))
        docsettings.updateLocation(dir_orig, dir_dest, false)

        assert.is_nil(lfs.attributes(dir_orig_dir, "mode"))
        assert.is_false(util.fileExists(doc_dest_file))
        assert.is_true(util.fileExists(dir_dest_file))
        assert.are.equal(22, docsettings:open(dir_dest):read("last_page"))
        assert.are.equal(0, #shown)
      end
    )

    it(
      "keeps doc sidecar independent on copy while hash is preferred",
      function()
        local UIManager = require("ui/uimanager")
        local orig_show = UIManager.show
        local shown = {}
        local hash_dir
        finally(function()
          UIManager.show = orig_show
          if hash_dir then
            ffiutil.purgeDir(hash_dir)
            docsettings.cleanHashLocationIfEmpty()
          end
        end)
        UIManager.show = function(_, widget)
          table.insert(shown, widget)
        end

        local orig = createBook("copy_doc_while_hash_orig.epub")
        local copy_book = temp_root .. "/copy_doc_while_hash_copy.epub"
        G_reader_settings:save("document_metadata_folder", "doc")
        local orig_file = getSidecarFile(orig)
        local copy_file = getSidecarFile(copy_book)
        local ds = docsettings:open(orig)
        ds:save("last_page", 33)
        ds:flush()
        ds:close()

        G_reader_settings:save("document_metadata_folder", "hash")
        hash_dir = getSidecarDir(orig)
        assert.is_nil(ffiutil.copyFile(orig, copy_book))
        docsettings.updateLocation(orig, copy_book, true)

        assert.is_true(util.fileExists(orig_file))
        assert.is_true(util.fileExists(copy_file))
        assert.is_nil(lfs.attributes(hash_dir, "mode"))
        assert.are.equal(33, docsettings:open(orig):read("last_page"))
        assert.are.equal(33, docsettings:open(copy_book):read("last_page"))
        assert.are.equal(0, #shown)
      end
    )

    it(
      "preserves hash sidecar untouched on copy while doc is preferred",
      function()
        local UIManager = require("ui/uimanager")
        local orig_show = UIManager.show
        local shown = {}
        local hash_dir
        finally(function()
          UIManager.show = orig_show
          if hash_dir then
            ffiutil.purgeDir(hash_dir)
            docsettings.cleanHashLocationIfEmpty()
          end
        end)
        UIManager.show = function(_, widget)
          table.insert(shown, widget)
        end

        local orig = createBook("copy_hash_while_doc_orig.epub")
        local copy_book = temp_root .. "/copy_hash_while_doc_copy.epub"
        local src_cover =
          createTempCover("copy_hash_cover.png", "hash-copy-cover")
        G_reader_settings:save("document_metadata_folder", "hash")
        hash_dir = getSidecarDir(orig)
        local hash_file = getSidecarFile(orig)
        local ds = docsettings:open(orig)
        ds:save("last_page", 44)
        ds:flush()
        ds:close()
        assert.is_true(docsettings:flushCustomCover(orig, src_cover))
        local orig_mtime = lfs.attributes(hash_file, "modification")

        G_reader_settings:save("document_metadata_folder", "doc")
        assert.is_nil(ffiutil.copyFile(orig, copy_book))
        docsettings.updateLocation(orig, copy_book, true)

        assert.is_true(util.fileExists(hash_file))
        assert.are.equal(orig_mtime, lfs.attributes(hash_file, "modification"))
        assert.is_false(util.fileExists(getSidecarFile(copy_book)))
        assert.is_false(util.fileExists(getSidecarFile(orig)))
        assert.are.equal(44, docsettings:open(orig):read("last_page"))
        assert.are.equal(44, docsettings:open(copy_book):read("last_page"))
        assert.is_true(
          util.stringStartsWith(
            docsettings:findCustomCoverFile(orig),
            hash_dir .. "/"
          )
        )
        assert.are.equal(0, #shown)
      end
    )

    it(
      "keeps hash sidecar on rename while cleaning stale doc leftovers and handles extension changes",
      function()
        local UIManager = require("ui/uimanager")
        local orig_show = UIManager.show
        local shown = {}
        local hash_dir1, hash_dir2
        finally(function()
          UIManager.show = orig_show
          if hash_dir1 then
            ffiutil.purgeDir(hash_dir1)
          end
          if hash_dir2 then
            ffiutil.purgeDir(hash_dir2)
          end
          docsettings.cleanHashLocationIfEmpty()
        end)
        UIManager.show = function(_, widget)
          table.insert(shown, widget)
        end

        -- Same extension: hash active + stale older doc sidecar + stray doc custom cover
        local orig1 = createBook("hash_rename_mixed_orig.epub")
        local dest1 = temp_root .. "/hash_rename_mixed_dest.epub"
        local stray_cover =
          createTempCover("hash_rename_stray.png", "stray-doc-cover")
        G_reader_settings:save("document_metadata_folder", "doc")
        local stale_doc_dir = getSidecarDir(orig1)
        local stale_doc_file = getSidecarFile(orig1)
        local ds_doc = docsettings:open(orig1)
        ds_doc:save("last_page", 5)
        ds_doc:flush()
        ds_doc:close()
        assert.is_true(docsettings:flushCustomCover(orig1, stray_cover))
        lfs.touch(stale_doc_file, 1000, 1000)

        G_reader_settings:save("document_metadata_folder", "hash")
        hash_dir1 = getSidecarDir(orig1)
        local hash_file1 = getSidecarFile(orig1)
        util.makePath(hash_dir1)
        util.writeToFile(
          'return {\n  ["last_page"] = 55,\n}\n',
          hash_file1,
          false
        )
        lfs.touch(hash_file1, 2000, 2000)

        G_reader_settings:save("document_metadata_folder", "doc")
        assert(os.rename(orig1, dest1))
        docsettings.updateLocation(orig1, dest1, false)

        assert.is_true(util.fileExists(hash_file1))
        assert.is_nil(lfs.attributes(stale_doc_dir, "mode"))
        assert.is_false(util.fileExists(getSidecarFile(dest1)))
        assert.are.equal(55, docsettings:open(dest1):read("last_page"))
        local moved_cover = docsettings:findCustomCoverFile(dest1)
        assert.is_true(util.stringStartsWith(moved_cover, hash_dir1 .. "/"))
        assert.are.equal("stray-doc-cover", util.readFromFile(moved_cover))
        assert.are.equal(0, #shown)

        -- Changed extension: metadata.epub.lua -> metadata.zip.lua inside <md5>.sdr
        local orig2 = createBook("hash_rename_ext.epub")
        local dest2 = temp_root .. "/hash_rename_ext.zip"
        local ext_cover =
          createTempCover("hash_ext_cover.png", "hash-ext-cover")
        G_reader_settings:save("document_metadata_folder", "hash")
        hash_dir2 = getSidecarDir(orig2)
        local old_hash_file = getSidecarFile(orig2)
        local ds2 = docsettings:open(orig2)
        ds2:save("last_page", 66)
        ds2:flush()
        ds2:close()
        assert.is_true(docsettings:flushCustomCover(orig2, ext_cover))

        G_reader_settings:save("document_metadata_folder", "doc")
        assert(os.rename(orig2, dest2))
        docsettings.updateLocation(orig2, dest2, false)

        local new_hash_file = hash_dir2 .. "/metadata.zip.lua"
        assert.is_true(util.fileExists(new_hash_file))
        assert.is_false(util.fileExists(old_hash_file))
        assert.is_false(util.fileExists(getSidecarFile(dest2)))
        assert.are.equal(66, docsettings:open(dest2):read("last_page"))
        assert.is_true(
          util.stringStartsWith(
            docsettings:findCustomCoverFile(dest2),
            hash_dir2 .. "/"
          )
        )
        assert.are.equal(0, #shown)
      end
    )

    it(
      "preserves custom-only book storage mode on rename while hash is preferred",
      function()
        local orig = createBook("custom_only_keep_doc_orig.epub")
        local dest = temp_root .. "/custom_only_keep_doc_dest.epub"
        local src_cover =
          createTempCover("custom_only_keep_cover.png", "custom-only-cover")
        local hash_dir
        finally(function()
          if hash_dir then
            ffiutil.purgeDir(hash_dir)
            docsettings.cleanHashLocationIfEmpty()
          end
        end)

        G_reader_settings:save("document_metadata_folder", "doc")
        local orig_dir = getSidecarDir(orig)
        local dest_dir = getSidecarDir(dest)
        assert.is_true(docsettings:flushCustomCover(orig, src_cover))
        local custom_meta = docsettings.openSettingsFile()
        custom_meta:save("doc_props", { title = "Custom Only" })
        assert.is_true(custom_meta:flushCustomMetadata(orig))

        G_reader_settings:save("document_metadata_folder", "hash")
        hash_dir = getSidecarDir(orig)
        assert(os.rename(orig, dest))
        docsettings.updateLocation(orig, dest, false)

        assert.is_nil(lfs.attributes(orig_dir, "mode"))
        assert.is_nil(lfs.attributes(hash_dir, "mode"))
        assert.is_false(docsettings:hasSidecarFile(dest))
        assert.is_true(
          util.stringStartsWith(
            docsettings:findCustomCoverFile(dest),
            dest_dir .. "/"
          )
        )
        assert.is_true(
          util.stringStartsWith(
            docsettings:findCustomMetadataFile(dest),
            dest_dir .. "/"
          )
        )
      end
    )

    it(
      "does not create an empty destination sidecar when source only had a corrupt sidecar",
      function()
        local orig = createBook("corrupt_only_orig.epub")
        local dest = temp_root .. "/corrupt_only_dest.epub"
        G_reader_settings:save("document_metadata_folder", "doc")
        local orig_dir = getSidecarDir(orig)
        local orig_file = getSidecarFile(orig)
        util.makePath(orig_dir)
        util.writeToFile("return { broken syntax", orig_file, false)

        assert(os.rename(orig, dest))
        docsettings.updateLocation(orig, dest, false)

        assert.is_false(util.fileExists(orig_file))
        assert.is_nil(lfs.attributes(orig_dir, "mode"))
        assert.is_false(docsettings:hasSidecarFile(dest))
      end
    )
  end)
end)
