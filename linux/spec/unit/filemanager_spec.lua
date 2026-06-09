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

    it("should switch tabs on swipe left & right on FileManagerMenu", function()
        UIManager:quit()

        local filemanager = FileManager:new{
            dimen = Screen:getSize(),
            root_path = "spec/unit/data",
        }

        -- Close any initial loading info/notifications
        while #UIManager._window_stack > 1 do
            UIManager:close(UIManager._window_stack[#UIManager._window_stack].widget)
        end

        -- Force UIManager to layout and paint all widgets so dimensions are set correctly
        UIManager:forceRepaint()

        -- Simulate tapping at the top of the screen to open the TouchMenu
        local Event = require("ui/event")
        local Geom = require("ui/geometry")
        local tap_event = Event:new("Gesture", {
            ges = "tap",
            pos = Geom:new({ x = Screen:getWidth() / 2, y = 10 }),
            time = require("ui/time").monotonic(),
        }):asUserInput()

        UIManager:userInput(tap_event)

        assert.is.same(2, #UIManager._window_stack)

        local menu_container = UIManager._window_stack[2].widget
        local touch_menu = menu_container[1]
        assert.is_not_nil(touch_menu)

        local initial_tab = touch_menu.cur_tab
        assert.is_not_nil(initial_tab)
        local page_num = touch_menu.page_num

        -- Swipe left (west) page_num times to go to the next tab
        for i = 1, page_num do
            local center_x = touch_menu.dimen.x + touch_menu.dimen.w / 2
            local center_y = touch_menu.dimen.y + touch_menu.dimen.h / 2
            local swipe_left_event = Event:new("Gesture", {
                ges = "swipe",
                direction = "west",
                pos = Geom:new({ x = center_x, y = center_y }),
                time = require("ui/time").monotonic() + i * 1000,
            }):asUserInput()
            UIManager:userInput(swipe_left_event)
        end

        assert.is.same(2, #UIManager._window_stack)

        local next_tab = touch_menu.cur_tab

        -- Swipe right (east) once to go back to the previous tab (since page reset to 1 on tab switch)
        local center_x = touch_menu.dimen.x + touch_menu.dimen.w / 2
        local center_y = touch_menu.dimen.y + touch_menu.dimen.h / 2
        local swipe_right_event = Event:new("Gesture", {
            ges = "swipe",
            direction = "east",
            pos = Geom:new({ x = center_x, y = center_y }),
            time = require("ui/time").monotonic(),
        }):asUserInput()
        UIManager:userInput(swipe_right_event)

        assert.is.same(2, #UIManager._window_stack)

        local final_tab = touch_menu.cur_tab

        assert.is_not.same(initial_tab, next_tab)
        assert.is.same(initial_tab, final_tab)

        filemanager:onClose()
    end)

    it("should close TouchMenu on swipe north", function()
        local filemanager = FileManager:new{
            dimen = Screen:getSize(),
        }

        while #UIManager._window_stack > 1 do
            UIManager:close(UIManager._window_stack[#UIManager._window_stack].widget)
        end
        UIManager:forceRepaint()

        -- Simulate tapping at the top of the screen to open the TouchMenu
        local Event = require("ui/event")
        local Geom = require("ui/geometry")
        local tap_event = Event:new("Gesture", {
            ges = "tap",
            pos = Geom:new({ x = Screen:getWidth() / 2, y = 10 }),
            time = require("ui/time").monotonic(),
        }):asUserInput()

        UIManager:userInput(tap_event)

        assert.is.same(2, #UIManager._window_stack)
        local menu_container = UIManager._window_stack[2].widget
        local touch_menu = menu_container[1]
        assert.is_not_nil(touch_menu)

        -- Swipe north on TouchMenu
        local center_x = touch_menu.dimen.x + touch_menu.dimen.w / 2
        local center_y = touch_menu.dimen.y + touch_menu.dimen.h / 2
        local swipe_north_event = Event:new("Gesture", {
            ges = "swipe",
            direction = "north",
            pos = Geom:new({ x = center_x, y = center_y }),
            time = require("ui/time").monotonic(),
        }):asUserInput()
        UIManager:userInput(swipe_north_event)

        -- Menu should be closed, so stack size should be back to 1 (only FileManager)
        assert.is.same(1, #UIManager._window_stack)

        filemanager:onClose()
    end)

    it("should close TouchMenu on tapping up button", function()
        local filemanager = FileManager:new{
            dimen = Screen:getSize(),
        }

        while #UIManager._window_stack > 1 do
            UIManager:close(UIManager._window_stack[#UIManager._window_stack].widget)
        end
        UIManager:forceRepaint()

        -- Simulate tapping at the top of the screen to open the TouchMenu
        local Event = require("ui/event")
        local Geom = require("ui/geometry")
        local tap_event = Event:new("Gesture", {
            ges = "tap",
            pos = Geom:new({ x = Screen:getWidth() / 2, y = 10 }),
            time = require("ui/time").monotonic(),
        }):asUserInput()

        UIManager:userInput(tap_event)

        assert.is.same(2, #UIManager._window_stack)
        local menu_container = UIManager._window_stack[2].widget
        local touch_menu = menu_container[1]
        assert.is_not_nil(touch_menu)

        -- Force repaint to ensure positions are calculated
        UIManager:forceRepaint()

        -- Find up button
        local up_button = touch_menu.footer[1][1]
        assert.is_not_nil(up_button)

        -- Simulate tap on up button
        local pos = up_button.dimen
        local tap_up_event = Event:new("Gesture", {
            ges = "tap",
            pos = Geom:new({ x = pos.x + pos.w / 2, y = pos.y + pos.h / 2 }),
            time = require("ui/time").monotonic(),
        }):asUserInput()
        UIManager:userInput(tap_up_event)

        -- Menu should be closed
        assert.is.same(1, #UIManager._window_stack)

        filemanager:onClose()
    end)
end)

