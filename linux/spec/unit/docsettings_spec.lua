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
      local dir = docsettings:getSidecarDir("/foo/bar.pdf", "tmp")
      DataStorage.getTmpDir = orig_getTmpDir
      assert.are.equal("/custom/datastorage/tmp/docsettings/foo/bar.sdr", dir)
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
    d:save("a", "b")
    d:save("c", "d")
    d:close()
    -- Now the sidecar file should be written.

    local legacy_files = {
      docsettings:getHistoryPath(file),
      d.doc_sidecar_dir .. "/file.pdf.lua",
      "file.pdf.kpdfview.lua",
    }

    for _, f in ipairs(legacy_files) do
      assert.False(
        os.rename(d.doc_sidecar_dir .. "/" .. d.sidecar_filename, f) == nil
      )
      d = docsettings:open(file)
      assert.True(
        os.remove(d.doc_sidecar_dir .. "/" .. d.sidecar_filename) == nil
      )
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

    assert.False(
      os.remove(d.doc_sidecar_dir .. "/" .. d.sidecar_filename) == nil
    )
    d:purge()
  end)

  it("should respect newest history file", function()
    local file = "file.pdf"
    local d = docsettings:open(file)

    local legacy_files = {
      docsettings:getHistoryPath(file),
      d.doc_sidecar_dir .. "/file.pdf.lua",
      "file.pdf.kpdfview.lua",
    }

    -- docsettings:flush will remove legacy files.
    for i, v in ipairs(legacy_files) do
      d:save("a", i)
      d:flush()
      assert.False(
        os.rename(d.doc_sidecar_dir .. "/" .. d.sidecar_filename, v .. "1")
          == nil
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
    local sidecar_dir = docsettings:getSidecarDir(file, "hash")
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

    local hash_files = docsettings.findSidecarFilesInHashLocation()
    assert.is_table(hash_files)

    d:close()
    d:purge()
    G_reader_settings:delete("document_metadata_folder")
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

    before_each(function()
      shown_notifications = {}
      UIManager.show = function(_, widget)
        table.insert(shown_notifications, widget)
      end
    end)

    after_each(function()
      util.isDirRW = original_isDirRW
      UIManager.show = orig_show
      G_reader_settings:delete("document_metadata_folder")
      os.remove("/tmp/test_ro_doc_1.epub")
      os.remove("/tmp/test_ro_doc_2.epub")
      os.remove("/tmp/test_ro_doc_3.epub")
      os.remove("/tmp/test_ro_doc_4.epub")
    end)

    it(
      "falls back to dir location when doc location is read-only and notifies once",
      function()
        G_reader_settings:save("document_metadata_folder", "doc")
        local file = "/tmp/test_ro_doc_1.epub"
        createDummyFile(file)
        local d = docsettings:open(file)

        util.isDirRW = function(dir, create)
          if dir == d.doc_sidecar_dir then
            return false
          end
          return original_isDirRW(dir, create)
        end

        d:save("page", 42)
        local saved_dir = d:flush()
        assert.are.equal(d.dir_sidecar_dir, saved_dir)
        assert.are.equal(1, #shown_notifications)
        assert.is_truthy(shown_notifications[1].text:find("internal storage"))

        -- Second flush should not re-notify
        d:save("page", 43)
        d:flush()
        assert.are.equal(1, #shown_notifications)

        d:close()
        d:purge()
      end
    )

    it(
      "falls back to hash location when both doc and dir locations are read-only",
      function()
        G_reader_settings:save("document_metadata_folder", "doc")
        local file = "/tmp/test_ro_doc_2.epub"
        createDummyFile(file)
        local d = docsettings:open(file)

        util.isDirRW = function(dir, create)
          if dir == d.doc_sidecar_dir or dir == d.dir_sidecar_dir then
            return false
          end
          return original_isDirRW(dir, create)
        end

        d:save("page", 100)
        local saved_dir = d:flush()
        assert.are.equal(d.hash_sidecar_dir, saved_dir)
        assert.are.equal(1, #shown_notifications)
        assert.is_truthy(shown_notifications[1].text:find("internal storage"))

        d:close()
        d:purge()
      end
    )

    it(
      "falls back to temporary location when all permanent locations are read-only",
      function()
        G_reader_settings:save("document_metadata_folder", "doc")
        local file = "/tmp/test_ro_doc_3.epub"
        createDummyFile(file)
        local d = docsettings:open(file)

        util.isDirRW = function(dir, create)
          if
            dir == d.doc_sidecar_dir
            or dir == d.dir_sidecar_dir
            or dir == d.hash_sidecar_dir
          then
            return false
          end
          return original_isDirRW(dir, create)
        end

        d:save("page", 200)
        local saved_dir = d:flush()
        assert.are.equal(d.tmp_sidecar_dir, saved_dir)
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
          if dir == d.doc_sidecar_dir then
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
  end)

  describe("getLocationCandidates ordering", function()
    after_each(function()
      G_reader_settings:delete("document_metadata_folder")
    end)

    it(
      "orders candidates correctly when document_metadata_folder is doc",
      function()
        G_reader_settings:save("document_metadata_folder", "doc")
        local candidates =
          docsettings:getLocationCandidates("/books/sample.epub")
        assert.are.equal(4, #candidates)
        assert.are.equal("doc", candidates[1].location)
        assert.are.equal("dir", candidates[2].location)
        assert.are.equal("hash", candidates[3].location)
        assert.are.equal("tmp", candidates[4].location)
      end
    )

    it(
      "orders candidates correctly when document_metadata_folder is dir",
      function()
        G_reader_settings:save("document_metadata_folder", "dir")
        local candidates =
          docsettings:getLocationCandidates("/books/sample.epub")
        assert.are.equal(4, #candidates)
        assert.are.equal("dir", candidates[1].location)
        assert.are.equal("hash", candidates[2].location)
        assert.are.equal("doc", candidates[3].location)
        assert.are.equal("tmp", candidates[4].location)
      end
    )

    it(
      "orders candidates correctly when document_metadata_folder is hash",
      function()
        G_reader_settings:save("document_metadata_folder", "hash")
        local candidates =
          docsettings:getLocationCandidates("/books/sample.epub")
        assert.are.equal(4, #candidates)
        assert.are.equal("hash", candidates[1].location)
        assert.are.equal("dir", candidates[2].location)
        assert.are.equal("doc", candidates[3].location)
        assert.are.equal("tmp", candidates[4].location)
      end
    )
  end)

  describe("removeSidecarDir", function()
    it(
      "prunes empty parent directories when sidecar path contains /docsettings/",
      function()
        local base_dir = "/tmp/koreader_test_docsettings_"
          .. tostring(os.time())
        local sub_dir = base_dir .. "/docsettings/nested"
        local sdr_dir = sub_dir .. "/book.sdr"
        util.makePath(sdr_dir)
        assert.are.equal("directory", lfs.attributes(sdr_dir, "mode"))

        docsettings.removeSidecarDir(sdr_dir)

        assert.is_nil(lfs.attributes(sdr_dir, "mode"))
        assert.is_nil(lfs.attributes(sub_dir, "mode"))
        util.removePath(base_dir)
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
  end)
end)
