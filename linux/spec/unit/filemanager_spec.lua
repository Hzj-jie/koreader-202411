describe("FileManager module", function()
  local FileManager, lfs, docsettings, UIManager, Screen, util, ffi
  setup(function()
    require("commonrequire")
    require("document/canvascontext"):init(require("device"))
    FileManager = require("apps/filemanager/filemanager")
    Screen = require("device").screen
    UIManager = require("ui/uimanager")
    docsettings = require("docsettings")
    lfs = require("libs/libkoreader-lfs")
    util = require("ffi/util")
    ffi = require("ffi")
  end)
  after_each(function()
    if FileManager.instance then
      pcall(function()
        FileManager.instance:onExit()
      end)
      FileManager.instance = nil
    end
    UIManager:quit()
  end)
  it("should show file manager", function()
    UIManager:quit()
    local filemanager = FileManager:new({
      dimen = Screen:getSize(),
      root_path = "spec/unit/data",
    })
    UIManager:scheduleIn(1, function()
      filemanager:onExit()
    end)
    UIManager:run()
  end)
  it("should show error on non-existent file", function()
    local filemanager = FileManager:new({
      dimen = Screen:getSize(),
      root_path = "spec/unit/data",
    })
    local old_show = UIManager.show
    local tmp_fn = "/abc/123/test/foo.bar.baz.tmp.epub.pdf"
    UIManager.show = function(self, w)
      assert.Equals(w.text, "File not found:\n" .. tmp_fn)
    end
    assert.is_nil(lfs.attributes(tmp_fn))
    filemanager:showDeleteFileDialog(tmp_fn)
    UIManager.show = old_show
    filemanager:onExit()
  end)
  it("should not delete not empty sidecar folder", function()
    local filemanager = FileManager:new({
      dimen = Screen:getSize(),
      root_path = "spec/unit/data",
    })

    local tmp_fn = util.realpath("spec/unit/data")
      .. "/2col.test.tmp."
      .. tostring(ffi.C.getpid())
      .. ".foo"
    util.copyFile("spec/unit/data/2col.pdf", tmp_fn)

    local tmp_sidecar = docsettings:getSidecarDir(tmp_fn)
    require("util").makePath(tmp_sidecar)
    local tmp_sidecar_file = tmp_sidecar
      .. "/"
      .. docsettings.getSidecarFilename(tmp_fn)
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
      assert.Equals(w.text, "Deleted file:\n" .. tmp_fn)
    end
    filemanager:deleteFile(tmp_fn, true)
    UIManager.show = old_show
    filemanager:onExit()

    -- make sure sdr folder exists
    assert.is_nil(lfs.attributes(tmp_fn))
    assert.is_not_nil(lfs.attributes(tmp_sidecar))
    os.remove(tmp_sidecar_file)
    os.remove(tmp_sidecar_file_foo)
    os.remove(tmp_sidecar)
    os.remove(tmp_fn)
  end)
  it("should delete document with its settings", function()
    local filemanager = FileManager:new({
      dimen = Screen:getSize(),
      root_path = "spec/unit/data",
    })

    local tmp_fn = util.realpath("spec/unit/data")
      .. "/2col.test.tmp."
      .. tostring(ffi.C.getpid())
      .. ".pdf"
    util.copyFile("spec/unit/data/2col.pdf", tmp_fn)

    local tmp_sidecar = docsettings:getSidecarDir(tmp_fn)
    require("util").makePath(tmp_sidecar)
    local tmp_sidecar_file = tmp_sidecar
      .. "/"
      .. docsettings.getSidecarFilename(tmp_fn)
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
      assert.Equals(w.text, "Deleted file:\n" .. tmp_fn)
    end
    filemanager:deleteFile(tmp_fn, true)
    UIManager.show = old_show
    filemanager:onExit()

    assert.is_nil(lfs.attributes(tmp_fn))
    assert.is_nil(lfs.attributes(tmp_sidecar))
    assert.is_nil(lfs.attributes(tmp_history))
  end)

  it(
    "should handle pasteFileFromClipboard safely when clipboard is empty",
    function()
      local filemanager = FileManager:new({
        dimen = Screen:getSize(),
        root_path = "spec/unit/data",
      })

      filemanager.clipboard = nil

      -- This should not crash
      filemanager:pasteFileFromClipboard()

      filemanager:onExit()
    end
  )

  it(
    "should handle deleteSelectedFiles safely when selected_files is empty/nil",
    function()
      local filemanager = FileManager:new({
        dimen = Screen:getSize(),
        root_path = "spec/unit/data",
      })
      filemanager.selected_files = nil
      filemanager:deleteSelectedFiles()
      filemanager:onExit()
    end
  )

  it(
    "should handle pasteSelectedFiles safely when selected_files is empty/nil",
    function()
      local filemanager = FileManager:new({
        dimen = Screen:getSize(),
        root_path = "spec/unit/data",
      })
      filemanager.selected_files = nil
      filemanager:pasteSelectedFiles(true)
      filemanager:onExit()
    end
  )

  it(
    "should handle showSelectedFilesList safely when selected_files is empty/nil",
    function()
      local filemanager = FileManager:new({
        dimen = Screen:getSize(),
        root_path = "spec/unit/data",
      })
      filemanager.selected_files = nil
      local old_show = UIManager.show
      UIManager.show = function(self, w)
        if w.close_callback then
          w.close_callback()
        end
      end
      filemanager:showSelectedFilesList()
      UIManager.show = old_show
      filemanager:onExit()
    end
  )

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
    local filemanager = FileManager:new({
      dimen = Screen:getSize(),
      root_path = "spec/unit/data",
    })

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

    filemanager:onExit()
  end)

  it("should switch tabs on swipe left & right on FileManagerMenu", function()
    UIManager:quit()

    local filemanager = FileManager:new({
      dimen = Screen:getSize(),
      root_path = "spec/unit/data",
    })

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

    filemanager:onExit()
  end)

  it("should close TouchMenu on swipe north", function()
    local filemanager = FileManager:new({
      dimen = Screen:getSize(),
    })

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

    filemanager:onExit()
  end)

  it("should close TouchMenu on tapping up button", function()
    local filemanager = FileManager:new({
      dimen = Screen:getSize(),
    })

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

    filemanager:onExit()
  end)

  it(
    "should cycle through multiple tabs on successive swipe west gestures",
    function()
      local filemanager = FileManager:new({
        dimen = Screen:getSize(),
      })

      while #UIManager._window_stack > 1 do
        UIManager:close(
          UIManager._window_stack[#UIManager._window_stack].widget
        )
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

      local tabs_visited = {}
      local initial_tab = touch_menu.cur_tab
      tabs_visited[initial_tab] = true

      local current_tab = initial_tab
      -- We try to switch tab 3 times and expect to see 3 different tabs
      for step = 1, 3 do
        local limit = 10
        local count = 0
        local prev_tab = current_tab
        while touch_menu.cur_tab == prev_tab and count < limit do
          local center_x = touch_menu.dimen.x + touch_menu.dimen.w / 2
          local center_y = touch_menu.dimen.y + touch_menu.dimen.h / 2
          local swipe_left_event =
            Event:new("Gesture", {
              ges = "swipe",
              direction = "west",
              pos = Geom:new({ x = center_x, y = center_y }),
              time = require("ui/time").monotonic()
                + (step * 10 + count) * 1000,
            }):asUserInput()
          UIManager:userInput(swipe_left_event)
          count = count + 1
        end
        current_tab = touch_menu.cur_tab
        assert.is_not.same(prev_tab, current_tab)
        assert.is.same(2, #UIManager._window_stack)
        tabs_visited[current_tab] = true
      end

      local visited_count = 0
      for _ in pairs(tabs_visited) do
        visited_count = visited_count + 1
      end
      assert.is_true(visited_count > 1)

      filemanager:onExit()
    end
  )

  it("should return current directory or nil based on instance", function()
    assert.is_nil(FileManager:getCurrentDir())
    local filemanager = FileManager:new({
      dimen = Screen:getSize(),
      root_path = "spec/unit/data",
    })
    assert.is_not_nil(FileManager:getCurrentDir())
    filemanager:onExit()
    assert.is_nil(FileManager:getCurrentDir())
  end)

  it("should set clipboard and cutfile flag correctly", function()
    local filemanager = FileManager:new({
      dimen = Screen:getSize(),
      root_path = "spec/unit/data",
    })
    filemanager:copyFileNameToClipboard("test.epub")
    assert.is.same("test.epub", filemanager.clipboard)
    assert.is_false(filemanager.cutfile)

    filemanager:cutFile("test2.epub")
    assert.is.same("test2.epub", filemanager.clipboard)
    assert.is_true(filemanager.cutfile)
    filemanager:onExit()
  end)

  it("should toggle selection mode", function()
    local filemanager = FileManager:new({
      dimen = Screen:getSize(),
      root_path = "spec/unit/data",
    })
    assert.is_nil(filemanager.selected_files)
    filemanager:onToggleSelectMode()
    assert.is_not_nil(filemanager.selected_files)

    filemanager:onToggleSelectMode()
    assert.is_nil(filemanager.selected_files)
    filemanager:onExit()
  end)

  it("should return display mode and sort by actions", function()
    local filemanager = FileManager:new({
      dimen = Screen:getSize(),
      root_path = "spec/unit/data",
    })
    local names, texts = FileManager.getDisplayModeActions()
    assert.is_true(#names > 0)
    assert.is_true(#texts > 0)
    assert.is.same("classic", names[1])

    local sort_names, sort_texts = FileManager.getSortByActions()
    assert.is_true(#sort_names > 0)
    assert.is_true(#sort_texts > 0)
    filemanager:onExit()
  end)

  it("should handle reverse and mixed sorting settings", function()
    local filemanager = FileManager:new({
      dimen = Screen:getSize(),
      root_path = "spec/unit/data",
    })
    assert.is_true(filemanager:onSetReverseSorting(true))
    assert.is_true(G_reader_settings:isTrue("reverse_collate"))

    assert.is_true(filemanager:onSetMixedSorting(true))
    assert.is_true(G_reader_settings:isTrue("collate_mixed"))

    filemanager:onSetReverseSorting(false)
    filemanager:onSetMixedSorting(false)
    filemanager:onExit()
  end)

  it("should handle file copy/move helper functions", function()
    local filemanager = FileManager:new({
      dimen = Screen:getSize(),
      root_path = "spec/unit/data",
    })
    local tmp_dir = "spec/unit/data/fm_test_tmp"
    local copy_dir = "spec/unit/data/fm_test_tmp_copy"
    util.purgeDir(tmp_dir)
    util.purgeDir(copy_dir)
    lfs.mkdir(tmp_dir)

    local src_file = "spec/unit/data/2col.pdf"
    local copy_file = tmp_dir .. "/copy.pdf"
    local move_file = tmp_dir .. "/move.pdf"

    assert.is_true(filemanager:copyFile(src_file, copy_file))
    assert.is_not_nil(lfs.attributes(copy_file))

    assert.is_true(filemanager:moveFile(copy_file, move_file))
    assert.is_nil(lfs.attributes(copy_file))
    assert.is_not_nil(lfs.attributes(move_file))

    assert.is_true(filemanager:copyRecursive(tmp_dir, copy_dir))
    assert.is_not_nil(lfs.attributes(copy_dir))

    filemanager:onExit()
    util.purgeDir(tmp_dir)
    util.purgeDir(copy_dir)
  end)

  it(
    "should return early when rename target matches original basename",
    function()
      local filemanager = FileManager:new({
        dimen = Screen:getSize(),
        root_path = "spec/unit/data",
      })
      filemanager:renameFile("spec/unit/data/2col.pdf", "2col.pdf", true)
      filemanager:onExit()
    end
  )

  it("should trigger refresh and home handlers", function()
    local filemanager = FileManager:new({
      dimen = Screen:getSize(),
      root_path = "spec/unit/data",
    })
    assert.is_true(filemanager:onHome())
    filemanager:onRefreshContent()
    filemanager:onBookMetadataChanged()
    filemanager:onExit()
  end)

  it("should update title bar path correctly with shortcut status", function()
    local filemanager = FileManager:new({
      dimen = Screen:getSize(),
      root_path = "spec/unit/data",
    })
    filemanager:updateTitleBarPath("spec/unit/data")
    assert.is_not_nil(filemanager.title_bar.subtitle)
    filemanager:onExit()
  end)

  it("should open folder menu dialog on onShowFolderMenu", function()
    local filemanager = FileManager:new({
      dimen = Screen:getSize(),
      root_path = "spec/unit/data",
    })
    local shown_widget
    local old_show = UIManager.show
    UIManager.show = function(self, w)
      shown_widget = w
    end
    filemanager:onShowFolderMenu()
    UIManager.show = old_show
    assert.is_not_nil(shown_widget)
    filemanager:onExit()
  end)

  it("should open plus menu in normal mode and select mode", function()
    local filemanager = FileManager:new({
      dimen = Screen:getSize(),
      root_path = "spec/unit/data",
    })
    local shown_widget
    local old_show = UIManager.show
    UIManager.show = function(self, w)
      shown_widget = w
    end

    -- Normal mode
    filemanager:onShowPlusMenu()
    assert.is_not_nil(shown_widget)
    assert.is_nil(shown_widget.select_mode)

    -- Select mode
    filemanager:onToggleSelectMode()
    filemanager.selected_files["spec/unit/data/2col.pdf"] = true
    shown_widget = nil
    filemanager:onShowPlusMenu()
    assert.is_not_nil(shown_widget)
    assert.is_true(shown_widget.select_mode)

    UIManager.show = old_show
    filemanager:onExit()
  end)

  it("should handle onSetDisplayMode and onSetSortBy", function()
    local filemanager = FileManager:new({
      dimen = Screen:getSize(),
      root_path = "spec/unit/data",
    })
    assert.is_true(filemanager:onSetDisplayMode("classic"))
    assert.is_true(filemanager:onSetSortBy("filename"))
    filemanager:onExit()
  end)

  it("should open create folder input dialog", function()
    local filemanager = FileManager:new({
      dimen = Screen:getSize(),
      root_path = "spec/unit/data",
    })
    local shown_widget
    local old_show = UIManager.show
    UIManager.show = function(self, w)
      shown_widget = w
    end
    filemanager:createFolder()
    UIManager.show = old_show
    assert.is_not_nil(shown_widget)
    filemanager:onExit()
  end)

  it("should open rename file dialog for file and folder", function()
    local filemanager = FileManager:new({
      dimen = Screen:getSize(),
      root_path = "spec/unit/data",
    })
    local shown_widget
    local old_show = UIManager.show
    UIManager.show = function(self, w)
      shown_widget = w
    end

    filemanager:showRenameFileDialog("spec/unit/data/2col.pdf", true)
    assert.is_not_nil(shown_widget)

    shown_widget = nil
    filemanager:showRenameFileDialog("spec/unit/data", false)
    assert.is_not_nil(shown_widget)

    UIManager.show = old_show
    filemanager:onExit()
  end)

  it("should show copy and move selected files confirmation dialogs", function()
    local filemanager = FileManager:new({
      dimen = Screen:getSize(),
      root_path = "spec/unit/data",
    })
    local shown_widget
    local old_show = UIManager.show
    UIManager.show = function(self, w)
      shown_widget = w
    end

    filemanager.cutfile = false
    filemanager:showCopyMoveSelectedFilesDialog(function() end)
    assert.is_not_nil(shown_widget)

    shown_widget = nil
    filemanager.cutfile = true
    filemanager:showCopyMoveSelectedFilesDialog(function() end)
    assert.is_not_nil(shown_widget)

    UIManager.show = old_show
    filemanager:onExit()
  end)

  it("should show open with dialog and invoke openFile callbacks", function()
    local filemanager = FileManager:new({
      dimen = Screen:getSize(),
      root_path = "spec/unit/data",
    })
    local shown_widget
    local old_show = UIManager.show
    UIManager.show = function(self, w)
      shown_widget = w
    end

    filemanager:showOpenWithDialog("spec/unit/data/2col.pdf")
    assert.is_not_nil(shown_widget)
    UIManager.show = old_show

    local doc_cb_called = false
    local old_showReader = require("apps/reader/readerui").showReader
    require("apps/reader/readerui").showReader = function() end

    filemanager:openFile("spec/unit/data/2col.pdf", nil, function()
      doc_cb_called = true
    end)
    assert.is_true(doc_cb_called)

    require("apps/reader/readerui").showReader = old_showReader
    filemanager:onExit()
  end)

  it("should handle rotation mode and swipe gestures", function()
    local filemanager = FileManager:new({
      dimen = Screen:getSize(),
      root_path = "spec/unit/data",
    })
    filemanager:onSetRotationMode(Screen.DEVICE_ROTATED_UPRIGHT)

    local prev_called, next_called = false, false
    filemanager.file_chooser.onPrevPage = function()
      prev_called = true
    end
    filemanager.file_chooser.onNextPage = function()
      next_called = true
    end

    filemanager:onSwipeFM({ direction = "west" })
    assert.is_true(next_called)

    filemanager:onSwipeFM({ direction = "east" })
    assert.is_true(prev_called)

    filemanager:onExit()
  end)

  it("should handle setHome confirmation dialog", function()
    local filemanager = FileManager:new({
      dimen = Screen:getSize(),
      root_path = "spec/unit/data",
    })
    local shown_widget
    local old_show = UIManager.show
    UIManager.show = function(self, w)
      shown_widget = w
    end

    filemanager:setHome("spec/unit/data")
    assert.is_not_nil(shown_widget)

    UIManager.show = old_show
    filemanager:onExit()
  end)

  it("should handle renameFile conflict logic and dialogs", function()
    local filemanager = FileManager:new({
      dimen = Screen:getSize(),
      root_path = "spec/unit/data",
    })

    local tmp_dir = "spec/unit/data/tmp_existing_dir"
    lfs.mkdir(tmp_dir)

    local shown_widgets = {}
    local old_show = UIManager.show
    UIManager.show = function(self, w)
      table.insert(shown_widgets, w)
    end

    -- Conflict: file to existing directory
    filemanager:renameFile("spec/unit/data/2col.pdf", "tmp_existing_dir", true)
    assert.is_true(#shown_widgets > 0)

    -- Conflict: directory to existing file
    shown_widgets = {}
    filemanager:renameFile(tmp_dir, "2col.pdf", false)
    assert.is_true(#shown_widgets > 0)

    -- Conflict: file to existing file (asks for overwrite)
    local tmp_fn1 = "spec/unit/data/tmp_rename1.pdf"
    local tmp_fn2 = "spec/unit/data/tmp_rename2.pdf"
    util.copyFile("spec/unit/data/2col.pdf", tmp_fn1)
    util.copyFile("spec/unit/data/2col.pdf", tmp_fn2)

    shown_widgets = {}
    filemanager:renameFile(tmp_fn1, "tmp_rename2.pdf", true)
    assert.is_true(#shown_widgets > 0)
    local confirm = shown_widgets[#shown_widgets]
    if confirm and confirm.ok_callback then
      confirm.ok_callback()
    end
    assert.is_nil(lfs.attributes(tmp_fn1))
    assert.is_not_nil(lfs.attributes(tmp_fn2))
    os.remove(tmp_fn2)
    lfs.rmdir(tmp_dir)

    UIManager.show = old_show
    filemanager:onExit()
  end)

  it("should handle showSelectedFilesList menu choices and holds", function()
    local filemanager = FileManager:new({
      dimen = Screen:getSize(),
      root_path = "spec/unit/data",
    })
    filemanager.selected_files = {
      ["spec/unit/data/2col.pdf"] = true,
    }

    local shown_menu
    local old_show = UIManager.show
    UIManager.show = function(self, w)
      shown_menu = w
    end

    filemanager:showSelectedFilesList()
    assert.is_not_nil(shown_menu)
    assert.is_not_nil(shown_menu.item_table)
    assert.are.equal(1, #shown_menu.item_table)

    -- Test select callback
    local changed_path
    filemanager.file_chooser.changeToPath = function(_self, p)
      changed_path = p
    end
    shown_menu.onMenuSelect(shown_menu, shown_menu.item_table[1])
    assert.is_not_nil(changed_path)

    UIManager.show = old_show
    filemanager:onExit()
  end)

  it("should handle showOpenWithDialog and file associations", function()
    local filemanager = FileManager:new({
      dimen = Screen:getSize(),
      root_path = "spec/unit/data",
    })

    local shown_widget
    local old_show = UIManager.show
    UIManager.show = function(self, w)
      shown_widget = w
    end

    filemanager:showOpenWithDialog("spec/unit/data/2col.pdf")
    assert.is_not_nil(shown_widget)

    -- Close dialog safely
    if shown_widget.buttons and shown_widget.buttons[#shown_widget.buttons] then
      local cancel_btn = shown_widget.buttons[#shown_widget.buttons][1]
      if cancel_btn and cancel_btn.callback then
        cancel_btn.callback()
      end
    end

    UIManager.show = old_show
    filemanager:onExit()
  end)

  describe(
    "pasteSelectedFiles, deleteSelectedFiles, createFolder, and deleteFile",
    function()
      local ReadHistory = require("readhistory")
      local ReadCollection = require("readcollection")
      local base_tmp

      before_each(function()
        local pid = tostring(ffi.C.getpid())
        base_tmp = util.realpath("spec/unit/data") .. "/tmp_fm_ops_" .. pid
        require("util").makePath(base_tmp)
      end)

      after_each(function()
        if base_tmp and lfs.attributes(base_tmp) then
          util.purgeDir(base_tmp)
        end
      end)

      it("should handle pasteSelectedFiles for copy and cut/move", function()
        local src_dir = base_tmp .. "/src"
        local dst_dir = base_tmp .. "/dst"
        require("util").makePath(src_dir)
        require("util").makePath(dst_dir)

        local f1 = src_dir .. "/f1.txt"
        local f2 = src_dir .. "/f2.txt"
        local dst_f2 = dst_dir .. "/f2.txt"
        local h1 = io.open(f1, "w")
        h1:write("f1")
        h1:close()
        local h2 = io.open(f2, "w")
        h2:write("f2")
        h2:close()
        local hd = io.open(dst_f2, "w")
        hd:write("dst f2")
        hd:close()

        local filemanager = FileManager:new({
          dimen = Screen:getSize(),
          root_path = base_tmp,
        })
        filemanager.file_chooser.path = dst_dir

        local shown_msg
        local old_show = UIManager.show
        UIManager.show = function(self, w)
          shown_msg = w
        end
        finally(function()
          UIManager.show = old_show
          filemanager:onExit()
        end)

        -- 1. Copy with overwrite = false: f1 copied, f2 skipped
        filemanager.cutfile = false
        filemanager.selected_files = {
          [f1] = true,
          [f2] = true,
        }
        filemanager:pasteSelectedFiles(false)

        assert.is_not_nil(lfs.attributes(dst_dir .. "/f1.txt"))
        assert.is_nil(filemanager.selected_files[f1])
        assert.is_true(filemanager.selected_files[f2])
        assert.is_not_nil(shown_msg)
        assert.is_true(shown_msg.text:find("1 file was not copied") ~= nil)

        -- 2. Move (cutfile = true) with overwrite = true and self-paste
        local self_paste_file = dst_dir .. "/f1.txt"
        filemanager.selected_files = {
          [self_paste_file] = true,
          [f2] = true,
        }
        filemanager.cutfile = true

        local hist_spy = spy.on(ReadHistory, "updateItems")
        local coll_spy = spy.on(ReadCollection, "updateItems")

        filemanager:pasteSelectedFiles(true)

        assert.is_not_nil(lfs.attributes(self_paste_file))
        assert.is_nil(lfs.attributes(f2))
        assert.is_not_nil(lfs.attributes(dst_dir .. "/f2.txt"))
        assert.spy(hist_spy).was.called()
        assert.spy(coll_spy).was.called()
        assert.is_nil(filemanager.selected_files)

        hist_spy:revert()
        coll_spy:revert()
      end)

      it(
        "should handle deleteSelectedFiles for all succeed and partial failure",
        function()
          local d1 = base_tmp .. "/d1.txt"
          local d2 = base_tmp .. "/d2.txt"
          local h1 = io.open(d1, "w")
          h1:write("d1")
          h1:close()
          local h2 = io.open(d2, "w")
          h2:write("d2")
          h2:close()

          local filemanager = FileManager:new({
            dimen = Screen:getSize(),
            root_path = base_tmp,
          })

          local hist_spy = spy.on(ReadHistory, "removeItems")
          local coll_spy = spy.on(ReadCollection, "removeItems")
          finally(function()
            hist_spy:revert()
            coll_spy:revert()
            filemanager:onExit()
          end)

          -- All succeed
          filemanager.selected_files = {
            [d1] = true,
            [d2] = true,
          }
          filemanager:deleteSelectedFiles()

          assert.is_nil(lfs.attributes(d1))
          assert.is_nil(lfs.attributes(d2))
          assert.spy(hist_spy).was.called()
          assert.spy(coll_spy).was.called()
          assert.is_nil(filemanager.selected_files)

          -- Partial failure
          local d3 = base_tmp .. "/d3.txt"
          local h3 = io.open(d3, "w")
          h3:write("d3")
          h3:close()
          local missing = base_tmp .. "/missing.txt"

          local shown_msg
          local old_show = UIManager.show
          UIManager.show = function(self, w)
            shown_msg = w
          end

          filemanager.selected_files = {
            [d3] = true,
            [missing] = true,
          }
          filemanager:deleteSelectedFiles()
          UIManager.show = old_show

          assert.is_nil(lfs.attributes(d3))
          assert.is_true(filemanager.selected_files[missing])
          assert.is_not_nil(shown_msg)
          assert.is_true(shown_msg.text:find("Failed to delete 1 file.") ~= nil)
        end
      )

      it("should handle createFolder with various input scenarios", function()
        local filemanager = FileManager:new({
          dimen = Screen:getSize(),
          root_path = base_tmp,
        })
        filemanager.file_chooser.path = base_tmp

        local shown_dialog
        local old_show = UIManager.show
        UIManager.show = function(self, w)
          shown_dialog = w
        end
        finally(function()
          UIManager.show = old_show
          filemanager:onExit()
        end)

        -- 1. Empty input is no-op
        filemanager:createFolder()
        assert.is_not_nil(shown_dialog)
        local create_btn = shown_dialog.buttons[1][2]
        shown_dialog:setInputText("")
        local close_spy = spy.on(UIManager, "close")
        create_btn.callback()
        assert.spy(close_spy).was_not.called()
        close_spy:revert()

        -- 2. Normal creation with refreshPath
        local refresh_spy = spy.on(filemanager.file_chooser, "refreshPath")
        shown_dialog:setInputText("new_sub")
        create_btn.callback()
        assert.are.equal(
          "directory",
          lfs.attributes(base_tmp .. "/new_sub", "mode")
        )
        assert.spy(refresh_spy).was.called()
        refresh_spy:revert()

        -- 3. Enter folder after creation
        local change_spy = spy.on(filemanager.file_chooser, "changeToPath")
        filemanager:createFolder()
        assert.is_not_nil(shown_dialog)
        local check_btn
        local function find_check_button(node)
          if type(node) == "table" then
            if node.checked ~= nil and type(node.checked) == "boolean" then
              return node
            end
            for _, child in ipairs(node) do
              local found = find_check_button(child)
              if found then
                return found
              end
            end
          end
        end
        check_btn = find_check_button(shown_dialog.layout)
          or find_check_button(shown_dialog)
        assert.is_not_nil(check_btn)
        check_btn.checked = true
        create_btn = shown_dialog.buttons[1][2]
        shown_dialog:setInputText("new_sub_enter")
        create_btn.callback()
        assert.are.equal(
          "directory",
          lfs.attributes(base_tmp .. "/new_sub_enter", "mode")
        )
        assert.spy(change_spy).was.called()
        change_spy:revert()

        -- 4. Failure when makePath returns false
        local common_util = require("util")
        local old_makePath = common_util.makePath
        common_util.makePath = function()
          return false
        end
        filemanager:createFolder()
        shown_dialog:setInputText("bad_sub")
        create_btn = shown_dialog.buttons[1][2]
        create_btn.callback()
        common_util.makePath = old_makePath

        assert.is_not_nil(shown_dialog)
        assert.is_true(
          shown_dialog.text:find("Failed to create folder:") ~= nil
        )
      end)

      it("should handle deleteFile for folders and error handling", function()
        local filemanager = FileManager:new({
          dimen = Screen:getSize(),
          root_path = base_tmp,
        })

        local shown_msg
        local old_show = UIManager.show
        UIManager.show = function(self, w)
          shown_msg = w
        end
        finally(function()
          UIManager.show = old_show
          filemanager:onExit()
        end)

        -- 1. Folder deletion
        local sub_dir = base_tmp .. "/sub_to_delete"
        require("util").makePath(sub_dir)
        local fh = io.open(sub_dir .. "/test.txt", "w")
        fh:write("x")
        fh:close()
        assert.are.equal("directory", lfs.attributes(sub_dir, "mode"))

        local ret = filemanager:deleteFile(sub_dir, false)
        assert.is_true(ret)
        assert.is_nil(lfs.attributes(sub_dir))

        -- 2. Failure path for nonexistent file
        local missing_file = base_tmp .. "/nonexistent_file.txt"
        local fail_ret = filemanager:deleteFile(missing_file, true)
        assert.is_nil(fail_ret)
        assert.is_not_nil(shown_msg)
        assert.is_true(shown_msg.text:find("Failed to delete:") ~= nil)
      end)
    end
  )
end)
