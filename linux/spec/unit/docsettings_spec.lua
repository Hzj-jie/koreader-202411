describe("docsettings module", function()
    local DataStorage, docsettings, docsettings_dir, ffiutil, lfs
    local getSidecarFile = function(doc_path)
        return docsettings:getSidecarDir(doc_path).."/"..docsettings.getSidecarFilename(doc_path)
    end

    setup(function()
        require("commonrequire")
        DataStorage = require("datastorage")
        docsettings = require("docsettings")
        ffiutil = require("ffi/util")
        lfs = require("libs/libkoreader-lfs")

        docsettings_dir = DataStorage:getDocSettingsDir()
    end)

    it("should generate sidecar folder path in book folder (by default)", function()
        G_reader_settings:delete("document_metadata_folder")
        assert.Equals("../../foo.sdr", docsettings:getSidecarDir("../../foo.pdf"))
        assert.Equals("/foo/bar.sdr", docsettings:getSidecarDir("/foo/bar.pdf"))
        assert.Equals("baz.sdr", docsettings:getSidecarDir("baz.pdf"))
    end)

    it("should generate sidecar folder path in book folder", function()
        G_reader_settings:save("document_metadata_folder", "doc")
        assert.Equals("../../foo.sdr", docsettings:getSidecarDir("../../foo.pdf"))
        assert.Equals("/foo/bar.sdr", docsettings:getSidecarDir("/foo/bar.pdf"))
        assert.Equals("baz.sdr", docsettings:getSidecarDir("baz.pdf"))
    end)

    it("should generate sidecar folder path in docsettings folder", function()
        G_reader_settings:save("document_metadata_folder", "dir")
        assert.Equals(docsettings_dir.."/foo/bar.sdr", docsettings:getSidecarDir("/foo/bar.pdf"))
        assert.Equals(docsettings_dir.."baz.sdr", docsettings:getSidecarDir("baz.pdf"))
    end)

    it("should generate sidecar metadata file (book folder)", function()
        G_reader_settings:save("document_metadata_folder", "doc")
        assert.Equals("../../foo.sdr/metadata.pdf.lua", getSidecarFile("../../foo.pdf"))
        assert.Equals("/foo/bar.sdr/metadata.pdf.lua", getSidecarFile("/foo/bar.pdf"))
        assert.Equals("baz.sdr/metadata.epub.lua", getSidecarFile("baz.epub"))
    end)

    it("should generate sidecar metadata file (docsettings folder)", function()
        G_reader_settings:save("document_metadata_folder", "dir")
        assert.Equals(docsettings_dir.."/foo/bar.sdr/metadata.pdf.lua", getSidecarFile("/foo/bar.pdf"))
        assert.Equals(docsettings_dir.."baz.sdr/metadata.epub.lua", getSidecarFile("baz.epub"))
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
            assert.False(os.rename(d.doc_sidecar_dir.."/"..d.sidecar_filename, f) == nil)
            d = docsettings:open(file)
            assert.True(os.remove(d.doc_sidecar_dir.."/"..d.sidecar_filename) == nil)
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

        assert.False(os.remove(d.doc_sidecar_dir.."/"..d.sidecar_filename) == nil)
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
            assert.False(os.rename(d.doc_sidecar_dir.."/"..d.sidecar_filename, v.."1") == nil)
        end

        d:close()
        for _, v in ipairs(legacy_files) do
            assert.False(os.rename(v.."1", v) == nil)
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


end)
