describe("docsettings module", function()
  local DataStorage, docsettings, docsettings_dir, ffiutil, lfs, util
  local getSidecarFile = function(doc_path)
    return docsettings:getSidecarDir(doc_path)
      .. "/"
      .. docsettings.getSidecarFilename(doc_path)
  end

  setup(function()
    require("commonrequire")
    DataStorage = require("datastorage")
    docsettings = require("docsettings")
    ffiutil = require("ffi/util")
    lfs = require("libs/libkoreader-lfs")
    util = require("util")

    docsettings_dir = DataStorage:getDocSettingsDir()
  end)

  it(
    "should generate sidecar folder path in book folder (by default)",
    function()
      G_reader_settings:delete("document_metadata_folder")
      assert.Equals("../../foo.sdr", docsettings:getSidecarDir("../../foo.pdf"))
      assert.Equals("/foo/bar.sdr", docsettings:getSidecarDir("/foo/bar.pdf"))
      assert.Equals("baz.sdr", docsettings:getSidecarDir("baz.pdf"))
    end
  )

  it("should generate sidecar folder path in book folder", function()
    G_reader_settings:save("document_metadata_folder", "doc")
    assert.Equals("../../foo.sdr", docsettings:getSidecarDir("../../foo.pdf"))
    assert.Equals("/foo/bar.sdr", docsettings:getSidecarDir("/foo/bar.pdf"))
    assert.Equals("baz.sdr", docsettings:getSidecarDir("baz.pdf"))
  end)

  it("should generate sidecar folder path in docsettings folder", function()
    G_reader_settings:save("document_metadata_folder", "dir")
    assert.Equals(
      docsettings_dir .. "/foo/bar.sdr",
      docsettings:getSidecarDir("/foo/bar.pdf")
    )
    assert.Equals(
      docsettings_dir .. "baz.sdr",
      docsettings:getSidecarDir("baz.pdf")
    )
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
    local doc_dir = docsettings:getSidecarDir(file)
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
    local doc_dir = docsettings:getSidecarDir(file)

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
    G_reader_settings:save("document_metadata_folder", "hash")
    local file = "/tmp/test_hash_doc.pdf"
    local f = io.open(file, "w")
    if f then
      f:write("%PDF-1.4 dummy pdf")
      f:close()
    end

    local sidecar_dir = docsettings:getSidecarDir(file)
    assert.is_truthy(sidecar_dir)
    assert.is_truthy(sidecar_dir:match("%.sdr$"))

    local d = docsettings:open(file)
    assert.is_not_nil(d)
    d:save("title", "Hash Book")
    d:flush()

    local sidecar_file = docsettings:findSidecarFile(file)
    assert.is_truthy(sidecar_file)
    local loaded = docsettings.openSettingsFile(sidecar_file)
    assert.is_not_nil(loaded)
    assert.are.equal("Hash Book", loaded.data.title)

    d:flushCustomMetadata(file)
    local hash_files = docsettings.findSidecarFilesInHashLocation()
    assert.is_table(hash_files)
    assert.are.equal(1, #hash_files)
    assert.are.equal(2, #hash_files[1])

    d:close()
    d:purge()
    os.remove(file)
    G_reader_settings:delete("document_metadata_folder")
  end)

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

      local file = "/tmp/test_hash_custom_doc.epub"
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
    it("does nothing when hash directory does not exist", function()
      local hash_dir = "/tmp/test_clean_hash_nonexistent"
      assert.has_no_errors(function()
        docsettings.cleanHashLocationIfEmpty(hash_dir)
      end)
      assert.is_false(util.directoryExists(hash_dir))
    end)

    it(
      "keeps hash directory intact when regular metadata file exists",
      function()
        local hash_dir = "/tmp/test_clean_hash_healthy"
        local sdr_dir = hash_dir .. "/ab/sample.sdr"
        util.makePath(sdr_dir)
        local file = sdr_dir .. "/metadata.epub.lua"
        local f = io.open(file, "w")
        if f then
          f:write("return {}")
          f:close()
        end

        docsettings.cleanHashLocationIfEmpty(hash_dir)
        assert.is_true(util.directoryExists(hash_dir))
        assert.is_true(util.fileExists(file))

        -- Cleanup
        os.remove(file)
        ffiutil.purgeDir(hash_dir)
      end
    )

    it("keeps hash directory intact when only custom assets exist", function()
      local hash_dir = "/tmp/test_clean_hash_custom"
      local sdr_dir = hash_dir .. "/ab/sample.sdr"
      util.makePath(sdr_dir)
      local custom_file = sdr_dir .. "/custom_metadata.lua"
      local f = io.open(custom_file, "w")
      if f then
        f:write("return {}")
        f:close()
      end

      docsettings.cleanHashLocationIfEmpty(hash_dir)
      assert.is_true(util.directoryExists(hash_dir))
      assert.is_true(util.fileExists(custom_file))

      -- Cleanup
      os.remove(custom_file)
      ffiutil.purgeDir(hash_dir)
    end)

    it(
      "removes hash directory and empty subdirectories when no files exist",
      function()
        local base_dir = "/tmp/test_clean_hash_base"
        local hash_dir = base_dir .. "/hashdocsettings"
        local sdr_dir = hash_dir .. "/ab/empty.sdr"
        util.makePath(sdr_dir)
        assert.is_true(util.directoryExists(sdr_dir))

        docsettings.cleanHashLocationIfEmpty(hash_dir)
        -- hash_dir and all subdirectories should be removed
        assert.is_false(util.directoryExists(hash_dir))
        -- base_dir parent directory must not be removed
        assert.is_true(util.directoryExists(base_dir))

        -- Cleanup
        ffiutil.purgeDir(base_dir)
      end
    )
  end)

  it("handles custom cover, custom metadata, and updateLocation", function()
    local file = "/tmp/test_custom_doc.epub"
    local d = docsettings:open(file)
    d:save("author", "Test Author")
    d:flush()

    local tmp_cover = "/tmp/test_cover.jpg"
    local f = io.open(tmp_cover, "w")
    if f then
      f:write("cover data")
      f:close()
    end

    d:flushCustomCover(file, tmp_cover)
    d:flushCustomMetadata(file)

    local found_cover = d:findCustomCoverFile(file)
    local found_meta = d:findCustomMetadataFile(file)
    assert.is_truthy(found_cover)
    assert.is_truthy(found_meta)

    -- Test updateLocation copy and move
    local new_file = "/tmp/test_custom_doc_moved.epub"
    docsettings.updateLocation(file, new_file, true) -- copy
    assert.is_true(docsettings:hasSidecarFile(new_file))

    -- cleanup
    docsettings.updateLocation(new_file, nil) -- delete
    docsettings.updateLocation(file, nil) -- delete
    os.remove(tmp_cover)
  end)

  it(
    "handles updateLocation when only custom files exist without sidecar file",
    function()
      local file = "/tmp/test_custom_only.epub"
      local new_file = "/tmp/test_custom_only_moved.epub"
      local tmp_cover = "/tmp/test_cover_only.jpg"
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

      docsettings.updateLocation(new_file, nil) -- delete
      docsettings.updateLocation(file, nil) -- delete
      os.remove(tmp_cover)
    end
  )

  describe("read-only storage fallbacks and notifications", function()
    local util = require("util")
    local UIManager = require("ui/uimanager")
    local original_isDirRW = util.isDirRW
    local orig_show = UIManager.show
    local shown_notifications

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
      os.remove("/tmp/test_ro_doc_1.epub")
      os.remove("/tmp/test_ro_doc_2.epub")
      os.remove("/tmp/test_ro_doc_3.epub")
      os.remove("/tmp/test_ro_doc_4.epub")
      os.remove("/tmp/test_ro_doc_5.epub")
    end)

    it(
      "falls back to dir location when doc location is read-only and notifies once",
      function()
        G_reader_settings:save("document_metadata_folder", "doc")
        local file = "/tmp/test_ro_doc_1.epub"
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
        local file = "/tmp/test_ro_doc_2.epub"
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
        local file = "/tmp/test_ro_doc_2.epub"
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
        local file = "/tmp/test_ro_doc_3.epub"
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
        local file = "/tmp/test_ro_doc_4.epub"
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
        local file = "/tmp/test_ro_custom.epub"
        createDummyFile(file)
        local d = docsettings:open(file)
        local tmp_cover = "/tmp/test_ro_cover.jpg"
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
        local file = "/tmp/test_ro_doc_5.epub"
        createDummyFile(file)
        local tmp_cover = "/tmp/test_ro_cov_mig.jpg"
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
        local file = "/tmp/test_ro_doc_dir_pref.epub"
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
        local file = "/tmp/test_ro_doc_dir_pref2.epub"
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
        local file = "/tmp/test_ro_doc_hash_pref.epub"
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
        local file = "/tmp/test_ro_doc_hash_pref2.epub"
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
        local file = "/tmp/test_ro_all_custom.epub"
        createDummyFile(file)
        local d = docsettings:open(file)
        local tmp_cover = "/tmp/test_ro_cov_fail.jpg"
        local f = io.open(tmp_cover, "w")
        if f then
          f:write("cover data")
          f:close()
        end

        util.isDirRW = function()
          return false
        end

        assert.is_nil(d:flushCustomCover(file, tmp_cover))
        assert.is_nil(d:flushCustomMetadata(file))

        d:close()
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
        assert.are.equal("doc", candidates[3].location)
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
        assert.are.equal("doc", candidates[4].location)
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
        assert.are.equal("doc", candidates[3].location)
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
        assert.are.equal("doc", candidates[4].location)
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
        assert.are.equal("doc", candidates[4].location)
        assert.is_truthy(candidates[4].file:match("sample%.epub%.lua$"))
        assert.are.equal("tmp", candidates[#candidates].location)
      end
    )

    it("returns empty table when doc_path is nil or empty", function()
      assert.are.same({}, docsettings:open(nil).candidates)
      assert.are.same({}, docsettings:open("").candidates)
    end)

    it(
      "falls back to default doc ordering when document_metadata_folder is unrecognized",
      function()
        G_reader_settings:save("document_metadata_folder", "invalid_val")
        local d = docsettings:open("/books/sample.epub")
        local candidates = d.candidates
        assert.are.equal("doc", candidates[1].location)
        assert.are.equal("dir", candidates[2].location)
        assert.are.equal("doc", candidates[3].location)
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

        G_reader_settings:save("document_metadata_folder", "doc")
        local file = "/tmp/test_lazy_md5.epub"
        local f = io.open(file, "w")
        if f then
          f:write("epub content")
          f:close()
        end

        -- Create sidecar in doc location
        local doc_sdr = "/tmp/test_lazy_md5.sdr"
        util.makePath(doc_sdr)
        local sidecar_file = doc_sdr .. "/metadata.epub.lua"
        local sf = io.open(sidecar_file, "w")
        if sf then
          sf:write('return { ["test"] = true }\n')
          sf:close()
        end

        -- Calling findSidecarFile / hasSidecarFile should find doc sidecar without hashing
        local found_file, loc = docsettings:findSidecarFile(file)
        assert.are.equal(sidecar_file, found_file)
        assert.are.equal("doc", loc)
        assert.are.equal(0, md5_calls)

        -- When sidecar does not exist in doc or dir, findSidecarFile falls through to hash
        os.remove(sidecar_file)
        util.removePath(doc_sdr)

        found_file = docsettings:findSidecarFile(file)
        assert.is_nil(found_file)
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
      local file = "/tmp/test_hash_cache.pdf"
      local f = io.open(file, "w")
      if f then
        f:write("%PDF-1.4 test content for md5 cache")
        f:close()
      end

      local hash_call_count = 0
      local orig_partialMD5 = util.partialMD5
      util.partialMD5 = function(p)
        hash_call_count = hash_call_count + 1
        return orig_partialMD5(p)
      end

      G_reader_settings:save("document_metadata_folder", "hash")
      local d1 = docsettings:open(file)
      local d2 = docsettings:open(file)
      util.partialMD5 = orig_partialMD5

      assert.are.equal(1, hash_call_count)
      assert.are.equal(d1.candidates[1].dir, d2.candidates[1].dir)
      os.remove(file)
    end)

    it(
      "removes corrupted or empty candidate file and falls back to next candidate",
      function()
        local file = "/tmp/test_corrupt.epub"
        local doc_sdr = "/tmp/test_corrupt.sdr"
        local dir_sdr = docsettings_dir .. "/tmp/test_corrupt.sdr"
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
        local base_dir = "/tmp/koreader_test_docsettings_"
          .. tostring(os.time())
        local sub_dir = base_dir .. "/docsettings/nested"
        local sdr_dir = sub_dir .. "/book.sdr"
        util.makePath(sdr_dir)
        assert.are.equal("directory", lfs.attributes(sdr_dir, "mode"))

        docsettings.removeSidecarDir(sdr_dir)

        assert.is_nil(lfs.attributes(sdr_dir, "mode"))
        assert.are.equal("directory", lfs.attributes(sub_dir, "mode"))
        util.removePath(base_dir)
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
        local parent_dir = "/tmp/koreader_test_standard_" .. tostring(os.time())
        local sdr_dir = parent_dir .. "/book.sdr"
        util.makePath(sdr_dir)
        assert.are.equal("directory", lfs.attributes(sdr_dir, "mode"))

        docsettings.removeSidecarDir(sdr_dir)

        assert.is_nil(lfs.attributes(sdr_dir, "mode"))
        assert.are.equal("directory", lfs.attributes(parent_dir, "mode"))
        lfs.rmdir(parent_dir)
      end
    )

    it(
      "handles nil, empty string, and non-existent path without error",
      function()
        assert.has_no_errors(function()
          docsettings.removeSidecarDir(nil)
          docsettings.removeSidecarDir("")
          docsettings.removeSidecarDir("/tmp/nonexistent_dir_path_12345")
        end)
      end
    )

    it("does not delete non-empty directory", function()
      local test_dir = "/tmp/koreader_nonempty_" .. tostring(os.time())
      local sdr_dir = test_dir .. "/book.sdr"
      util.makePath(sdr_dir)
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
      lfs.rmdir(test_dir)
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

  describe("findSidecarFile and isSidecarFileNotInPreferredLocation", function()
    local test_file = "/tmp/test_find_sidecar.epub"

    after_each(function()
      G_reader_settings:delete("document_metadata_folder")
      docsettings.updateLocation(test_file, nil)
      os.remove(test_file)
    end)

    it("returns nil when doc_path is nil or empty", function()
      local f, loc = docsettings:findSidecarFile(nil)
      assert.is_nil(f)
      assert.is_nil(loc)
      f, loc = docsettings:findSidecarFile("")
      assert.is_nil(f)
      assert.is_nil(loc)
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

      local f, loc = docsettings:findSidecarFile(test_file)
      assert.is_not_nil(f)
      assert.are.equal("doc", loc)
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
      local f, loc = docsettings:findSidecarFile(test_file)
      assert.is_not_nil(f)
      assert.are.equal("dir", loc)
      assert.is_true(docsettings.isSidecarFileNotInPreferredLocation(test_file))
    end)

    it("finds sidecar in legacy history", function()
      local hist_file = docsettings:getHistoryPath(test_file)
      local f_out = io.open(hist_file, "w")
      if f_out then
        f_out:write("return { ['title'] = 'Legacy' }\n")
        f_out:close()
      end

      local f, loc = docsettings:findSidecarFile(test_file)
      assert.are.equal(hist_file, f)
      assert.are.equal("hist", loc)
      assert.is_true(docsettings.isSidecarFileNotInPreferredLocation(test_file))

      os.remove(hist_file)
    end)
  end)

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

  describe("getCustomLocationCandidates", function()
    local test_doc = "/tmp/test_custom_cand.epub"

    before_each(function()
      local f = io.open(test_doc, "w")
      if f then
        f:write("dummy test epub")
        f:close()
      end
    end)

    after_each(function()
      docsettings.updateLocation(test_doc, nil)
      os.remove(test_doc)
      G_reader_settings:delete("document_metadata_folder")
    end)

    it(
      "returns all candidate directories when no sidecar file exists",
      function()
        local cands = docsettings:getCustomLocationCandidates(test_doc)
        assert.are.equal(3, #cands)
        assert.are.equal("/tmp/test_custom_cand.sdr", cands[1])
      end
    )

    it(
      "returns all candidate directories including hash when hash is preferred",
      function()
        G_reader_settings:save("document_metadata_folder", "hash")
        local cands = docsettings:getCustomLocationCandidates(test_doc)
        assert.are.equal(4, #cands)
      end
    )

    it("returns only existing sidecar dir when sidecar file exists", function()
      local d = docsettings:open(test_doc)
      d:save("page", 1)
      d:flush()
      d:close()

      local cands = docsettings:getCustomLocationCandidates(test_doc)
      assert.are.equal(1, #cands)
      assert.are.equal(docsettings:getSidecarDir(test_doc), cands[1])
    end)
  end)

  describe("updateLocation with read-only fallback", function()
    it(
      "falls back to next writable directory when new doc directory is read-only",
      function()
        local orig_file = "/tmp/test_upd_ro_orig.epub"
        local new_file = "/tmp/test_upd_ro_new.epub"
        local tmp_cover = "/tmp/test_upd_ro_cov.jpg"

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

        local orig_isDirRW = util.isDirRW
        local new_doc_sdr = docsettings:getSidecarDir(new_file)
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

        docsettings.updateLocation(new_file, nil)
        docsettings.updateLocation(orig_file, nil)
        os.remove(tmp_cover)
        os.remove(orig_file)
      end
    )

    it(
      "guards against nil new_sidecar_dir and warns user when all candidate storages are read-only",
      function()
        local UIManager = require("ui/uimanager")
        local orig_file = "/tmp/test_upd_all_ro_orig.epub"
        local new_file = "/tmp/test_upd_all_ro_new.epub"
        local tmp_cover = "/tmp/test_upd_all_ro_cov.jpg"

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
        local orig_show = UIManager.show
        UIManager.show = function(_, widget)
          shown_warning = widget
        end

        local orig_isDirRW = util.isDirRW
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

        docsettings.updateLocation(orig_file, nil)
        os.remove(tmp_cover)
        os.remove(orig_file)
      end
    )

    it(
      "removes referenced cache_file_path when deleting via updateLocation",
      function()
        local file = "/tmp/test_cache_del.epub"
        local dummy_cache = "/tmp/test_extracted_cache.bin"
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
        os.remove(file)
      end
    )

    it(
      "preserves hash-based sidecar on rename/move when hash location is preferred",
      function()
        G_reader_settings:save("document_metadata_folder", "hash")
        local file1 = "/tmp/test_hash_move_1.pdf"
        local file2 = "/tmp/test_hash_move_2.pdf"
        local f = io.open(file1, "w")
        if f then
          f:write("%PDF-1.4 dummy pdf content")
          f:close()
        end

        local d = docsettings:open(file1)
        d:save("page", 15)
        d:flush()
        d:close()

        local sidecar_before = docsettings:findSidecarFile(file1)
        assert.is_truthy(sidecar_before)

        -- Move operation should keep hash sidecar unchanged
        docsettings.updateLocation(file1, file2, false)
        assert.is_truthy(util.fileExists(sidecar_before))

        docsettings.updateLocation(file1, nil)
        os.remove(file1)
        G_reader_settings:delete("document_metadata_folder")
      end
    )
  end)

  describe("flush dynamic settings change", function()
    it(
      "refreshes candidates when document_metadata_folder changes after open",
      function()
        local UIManager = require("ui/uimanager")
        local file = "/tmp/test_flush_dyn.epub"
        local f = io.open(file, "w")
        if f then
          f:write("dummy")
          f:close()
        end

        G_reader_settings:save("document_metadata_folder", "doc")
        local d = docsettings:open(file)
        assert.are.equal("doc", d.candidates[1].location)

        -- Write initial settings to doc location
        d:save("page", 1)
        local initial_dir = d:flush()
        assert.are.equal(docsettings:getSidecarDir(file), initial_dir)

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
        assert.are.equal(docsettings_dir .. "/tmp/test_flush_dyn.sdr", new_dir)
        -- No read-only warning should be shown!
        assert.are.equal(0, #shown_notifications)

        -- Old sidecar in doc location should be purged
        assert.is_nil(lfs.attributes(initial_dir, "mode"))

        d:close()
        d:purge()
        os.remove(file)
        G_reader_settings:delete("document_metadata_folder")
      end
    )
  end)

  describe("selective purge", function()
    it(
      "selectively purges custom cover without deleting metadata.lua",
      function()
        local file = "/tmp/test_sel_purge.epub"
        local tmp_cover = "/tmp/test_sel_cov.jpg"
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

        local d = docsettings:open(file)
        d:save("title", "Selective Purge Test")
        d:flush()
        d:flushCustomCover(file, tmp_cover)

        local cover_file = d:findCustomCoverFile()
        local sidecar_file = docsettings:findSidecarFile(file)
        assert.is_truthy(cover_file)
        assert.is_truthy(sidecar_file)

        -- Purge ONLY custom cover
        d:purge(nil, { custom_cover_file = cover_file })
        assert.is_nil(d:findCustomCoverFile())
        assert.is_truthy(util.fileExists(sidecar_file))

        d:close()
        d:purge()
        os.remove(file)
        os.remove(tmp_cover)
      end
    )
  end)

  it("purge() succeeds on objects created by openSettingsFile", function()
    local obj = docsettings.openSettingsFile()
    assert.has_no_errors(function()
      obj:purge()
    end)
  end)
end)
