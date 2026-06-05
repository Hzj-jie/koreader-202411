describe("FileManager module", function()
    local FileManager, lfs, docsettings, UIManager, Screen, util
    setup(function()
        require("commonrequire")
        package.unloadAll()
        require("document/canvascontext"):init(require("device"))
        FileManager = require("apps/filemanager/filemanager")
        Screen = require("device").screen
        UIManager = require("ui/uimanager")
        docsettings = require("docsettings")
        lfs = require("libs/libkoreader-lfs")
        util = require("ffi/util")
    end)
    after_each(function()
        if FileManager.instance then
            FileManager.instance:onClose()
        end
        UIManager:quit()
    end)
    it("should show file manager", function()
        UIManager:quit()
        local filemanager = FileManager:new{
            dimen = Screen:getSize(),
            root_path = "spec/unit/data",
        }
        UIManager:scheduleIn(1, function() filemanager:onClose() end)
        UIManager:run()
    end)
    it("should show error on non-existent file", function()
        local filemanager = FileManager:new{
            dimen = Screen:getSize(),
            root_path = "spec/unit/data",
        }
        local old_show = UIManager.show
        local tmp_fn = "/abc/123/test/foo.bar.baz.tmp.epub.pdf"
        UIManager.show = function(self, w)
            assert.Equals(w.text, "File not found:\n"..tmp_fn)
        end
        assert.is_nil(lfs.attributes(tmp_fn))
        filemanager:showDeleteFileDialog(tmp_fn)
        UIManager.show = old_show
        filemanager:onClose()
    end)
    it("should not delete not empty sidecar folder", function()
        local filemanager = FileManager:new{
            dimen = Screen:getSize(),
            root_path = "spec/unit/data",
        }

        local tmp_fn = "spec/unit/data/2col.test.tmp.foo"
        util.copyFile("spec/unit/data/2col.pdf", tmp_fn)

        local tmp_sidecar = docsettings:getSidecarDir(util.realpath(tmp_fn))
        lfs.mkdir(tmp_sidecar)
        local tmp_sidecar_file = docsettings:getSidecarDir(util.realpath(tmp_fn)).."/"..docsettings.getSidecarFilename(util.realpath(tmp_fn))
        local tmp_sidecar_file_foo = tmp_sidecar_file .. ".foo" -- non-docsettings file
        local tmpsf = io.open(tmp_sidecar_file, "w")
        tmpsf:write("{}")
        tmpsf:close()
        util.copyFile(tmp_sidecar_file, tmp_sidecar_file_foo)
        local old_show = UIManager.show

        -- make sure file exists
        assert.is_not_nil(lfs.attributes(tmp_fn))
        assert.is_not_nil(lfs.attributes(tmp_sidecar))
        assert.is_not_nil(lfs.attributes(tmp_sidecar_file))
        assert.is_not_nil(lfs.attributes(tmp_sidecar_file_foo))

        UIManager.show = function(self, w)
            assert.Equals(w.text, "Deleted file:\n"..tmp_fn)
        end
        filemanager:deleteFile(tmp_fn, true)
        UIManager.show = old_show
        filemanager:onClose()

        -- make sure sdr folder exists
        assert.is_nil(lfs.attributes(tmp_fn))
        assert.is_not_nil(lfs.attributes(tmp_sidecar))
        os.remove(tmp_sidecar_file_foo)
        os.remove(tmp_sidecar)
    end)
    it("should delete document with its settings", function()
        local filemanager = FileManager:new{
            dimen = Screen:getSize(),
            root_path = "spec/unit/data",
        }

        local tmp_fn = "spec/unit/data/2col.test.tmp.pdf"
        util.copyFile("spec/unit/data/2col.pdf", tmp_fn)

        local tmp_sidecar = docsettings:getSidecarDir(util.realpath(tmp_fn))
        lfs.mkdir(tmp_sidecar)
        local tmp_sidecar_file = docsettings:getSidecarDir(util.realpath(tmp_fn)).."/"..docsettings.getSidecarFilename(util.realpath(tmp_fn))
        local tmpsf = io.open(tmp_sidecar_file, "w")
        tmpsf:write("{}")
        tmpsf:close()
        lfs.mkdir(require("datastorage"):getHistoryDir())
        local tmp_history = docsettings:getHistoryPath(tmp_fn)
        local tmpfp = io.open(tmp_history, "w")
        tmpfp:write("{}")
        tmpfp:close()
        local old_show = UIManager.show

        -- make sure file exists
        assert.is_not_nil(lfs.attributes(tmp_fn))
        assert.is_not_nil(lfs.attributes(tmp_sidecar))
        assert.is_not_nil(lfs.attributes(tmp_history))

        UIManager.show = function(self, w)
            assert.Equals(w.text, "Deleted file:\n"..tmp_fn)
        end
        filemanager:deleteFile(tmp_fn, true)
        UIManager.show = old_show
        filemanager:onClose()

        assert.is_nil(lfs.attributes(tmp_fn))
        assert.is_nil(lfs.attributes(tmp_sidecar))
        assert.is_nil(lfs.attributes(tmp_history))
    end)

    it("should handle pasteFileFromClipboard safely when clipboard is empty", function()
        local filemanager = FileManager:new{
            dimen = Screen:getSize(),
            root_path = "spec/unit/data",
        }

        filemanager.clipboard = nil

        -- This should not crash
        filemanager:pasteFileFromClipboard()

        filemanager:onClose()
    end)

    it("should handle deleteSelectedFiles safely when selected_files is empty/nil", function()
        local filemanager = FileManager:new{
            dimen = Screen:getSize(),
            root_path = "spec/unit/data",
        }
        filemanager.selected_files = nil
        filemanager:deleteSelectedFiles()
        filemanager:onClose()
    end)

    it("should handle pasteSelectedFiles safely when selected_files is empty/nil", function()
        local filemanager = FileManager:new{
            dimen = Screen:getSize(),
            root_path = "spec/unit/data",
        }
        filemanager.selected_files = nil
        filemanager:pasteSelectedFiles(true)
        filemanager:onClose()
    end)

    it("should handle showSelectedFilesList safely when selected_files is empty/nil", function()
        local filemanager = FileManager:new{
            dimen = Screen:getSize(),
            root_path = "spec/unit/data",
        }
        filemanager.selected_files = nil
        local old_show = UIManager.show
        UIManager.show = function(self, w)
            if w.close_callback then
                w.close_callback()
            end
        end
        filemanager:showSelectedFilesList()
        UIManager.show = old_show
        filemanager:onClose()
    end)

    it("getRandomFile should be random even when called quickly", function()
        local filemanagerutil = require("apps/filemanager/filemanagerutil")
        local dir = "spec/unit/data"
        local match_func = function(file)
            return file:match("%.pdf$") ~= nil
        end

        local results = {}
        for i = 1, 10 do
            table.insert(results, filemanagerutil.getRandomFile(dir, match_func))
        end

        local file = results[1]
        local identical_count = 1
        for i = 2, 10 do
            if results[i] == file then
                identical_count = identical_count + 1
            end
        end

        -- If this fails, it means they were all identical (deterministic)
        assert.is_true(identical_count < 10)
    end)

    it("moveBookMetadata should not loop forever on circular symlinks", function()
        local filemanager = FileManager:new{
            dimen = Screen:getSize(),
            root_path = "spec/unit/data",
        }

        local temp_dir = "spec/unit/data/loop_test"
        local ffiutil = require("ffi/util")
        ffiutil.purgeDir(temp_dir) -- Clean up any leftovers from crashed runs

        lfs.mkdir(temp_dir)
        local target_dir = temp_dir .. "/dir"
        lfs.mkdir(target_dir)
        local link_path = target_dir .. "/link"
        -- Create circular symlink: dir/link -> dir
        -- We use relative link to make it work
        os.execute("ln -s . " .. link_path)

        local old_show = UIManager.show
        UIManager.show = function(self, w)
            if w.ok_callback then
                w.ok_callback()
            elseif w.close_callback then
                w.close_callback()
            end
        end

        local old_path = filemanager.file_chooser.path
        filemanager.file_chooser.path = ffiutil.realpath(temp_dir)

        -- This should not hang
        filemanager.bookinfo:moveBookMetadata()

        filemanager.file_chooser.path = old_path
        UIManager.show = old_show
        ffiutil.purgeDir(temp_dir)

        filemanager:onClose()
    end)
end)

