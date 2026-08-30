describe("TextEditor plugin unit tests", function()
  local Dispatcher, DocumentRegistry, UIManager, Trapper, LuaSettings
  local TextEditor, editor
  local mock_ui
  local temp_dir, temp_settings_path

  setup(function()
    require("commonrequire")
    package.unloadAll()
    local DataStorage = require("datastorage")
    temp_dir = DataStorage:getDataDir() .. "/texteditor_spec_tmp"
    temp_settings_path = temp_dir .. "/text_editor.lua"
    require("document/canvascontext"):init(require("device"))
    os.execute("mkdir -p " .. temp_dir)
  end)

  teardown(function()
    if temp_dir then
      os.execute("rm -rf " .. temp_dir)
    end
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))
  end)

  before_each(function()
    Dispatcher = require("dispatcher")
    DocumentRegistry = require("document/documentregistry")
    UIManager = require("ui/uimanager")
    Trapper = require("ui/trapper")
    LuaSettings = require("luasettings")

    stub(Dispatcher, "registerAction")
    stub(DocumentRegistry, "addAuxProvider")
    stub(UIManager, "show")
    stub(UIManager, "close")
    stub(Trapper, "confirm")

    mock_ui = {
      menu = {
        registerToMainMenu = spy.new(function() end),
      },
    }

    -- Remove temporary settings file before each test
    os.remove(temp_settings_path)

    TextEditor = dofile("plugins/texteditor.koplugin/main.lua")
    editor = TextEditor:new({
      ui = mock_ui,
      settings_file = temp_settings_path,
    })
    editor:init()
    editor:loadSettings()
  end)

  after_each(function()
    Dispatcher.registerAction:revert()
    DocumentRegistry.addAuxProvider:revert()
    UIManager.show:revert()
    UIManager.close:revert()
    Trapper.confirm:revert()

    os.remove(temp_settings_path)
    package.unload("plugins/texteditor.koplugin/main")
  end)

  local function findShownWidget(predicate)
    for _, call in ipairs(UIManager.show.calls) do
      local widget = call.refs[2]
      if widget and predicate(widget) then
        return widget
      end
    end
    return nil
  end

  describe("Initialization & registration", function()
    it("registers dispatcher action, main menu, and aux provider", function()
      assert.stub(Dispatcher.registerAction).was_called()
      assert.spy(mock_ui.menu.registerToMainMenu).was_called()
      assert.stub(DocumentRegistry.addAuxProvider).was_called()

      local call = DocumentRegistry.addAuxProvider.calls[1]
      local aux_info = call.refs[2]
      assert.are.equal(editor.fullname, aux_info.provider_name)
      assert.are.equal(editor.name, aux_info.provider)
      assert.are.equal(30, aux_info.order)
      assert.is_true(aux_info.disable_file)
      assert.is_false(aux_info.disable_type)
    end)

    it("supports all file types", function()
      assert.is_true(editor:isFileTypeSupported("test.txt"))
      assert.is_true(editor:isFileTypeSupported("test.lua"))
      assert.is_true(editor:isFileTypeSupported("test.pdf"))
    end)
  end)

  describe("Settings management", function()
    it("loads default settings when file does not exist", function()
      assert.is_table(editor.settings)
      assert.is_table(editor.history)
      assert.is_table(editor.last_view_pos)
      assert.are.equal(editor.normal_font, editor.font_face)
      assert.are.equal(editor.default_font_size, editor.font_size)
      assert.is_true(editor.auto_para_direction)
      assert.is_false(editor.force_ltr_para_direction)
      assert.is_true(editor.qr_code_export)
      assert.is_true(editor.show_keyboard_on_start)
    end)

    it("flushes modified settings to disk", function()
      editor.font_size = 24
      editor.font_face = editor.monospace_font
      editor.auto_para_direction = false
      editor.force_ltr_para_direction = true
      editor.qr_code_export = false
      editor.show_keyboard_on_start = false
      editor.last_path = "/tmp"

      editor:onFlushSettings()

      -- Reload settings from disk into a fresh instance
      local settings_copy = LuaSettings:open(temp_settings_path)
      assert.are.equal(24, settings_copy:read("font_size"))
      assert.are.equal(editor.monospace_font, settings_copy:read("font_face"))
      assert.is_false(settings_copy:read("auto_para_direction"))
      assert.is_true(settings_copy:read("force_ltr_para_direction"))
      assert.is_false(settings_copy:read("qr_code_export"))
      assert.is_false(settings_copy:read("show_keyboard_on_start"))
      assert.are.equal("/tmp", settings_copy:read("last_path"))
    end)
  end)

  describe("History management", function()
    it("adds file to history and handles duplicates", function()
      editor:addToHistory("/file1.txt")
      editor:addToHistory("/file2.txt")
      assert.are.same({ "/file2.txt", "/file1.txt" }, editor.history)

      -- Add duplicate file1.txt -> should be moved to front
      editor:addToHistory("/file1.txt")
      assert.are.same({ "/file1.txt", "/file2.txt" }, editor.history)
    end)

    it("trims history when exceeding history_keep_size", function()
      for i = 1, editor.history_keep_size + 5 do
        editor:addToHistory("/file" .. i .. ".txt")
      end
      assert.are.equal(editor.history_keep_size, #editor.history)
      assert.are.equal("/file65.txt", editor.history[1])
    end)

    it("removes file from history and last_view_pos", function()
      editor:addToHistory("/file1.txt")
      editor:addToHistory("/file2.txt")
      editor.last_view_pos["/file1.txt"] = { 10, 5 }

      editor:removeFromHistory("/file1.txt")
      assert.are.same({ "/file2.txt" }, editor.history)
      assert.is_nil(editor.last_view_pos["/file1.txt"])
    end)
  end)

  describe("Menu and Submenu items", function()
    it("adds item to main menu", function()
      local menu_items = {}
      editor:addToMainMenu(menu_items)
      assert.is_table(menu_items.text_editor)
      assert.are.equal(editor.fullname, menu_items.text_editor.text)
      assert.is_function(menu_items.text_editor.sub_item_table_func)

      local items = menu_items.text_editor.sub_item_table_func()
      assert.is_table(items)
    end)

    it("builds submenu items with settings and history", function()
      editor:addToHistory(temp_dir .. "/hist1.txt")

      local items = editor:getSubMenuItems()
      assert.is_table(items)
      -- Expected structure: Settings, New file, Open file, plus 1 history item
      assert.are.equal(4, #items)
      assert.are.equal("Settings", items[1].text)
      assert.are.equal("New file", items[2].text)
      assert.are.equal("Open file", items[3].text)

      -- Check settings sub-items
      local settings_sub = items[1].sub_item_table
      assert.is_table(settings_sub)
      assert.are.equal(7, #settings_sub)

      -- Font size callback
      local font_size_item = settings_sub[1]
      assert.is_function(font_size_item.text_func)
      assert.is_string(font_size_item.text_func())
      font_size_item.callback({ updateItems = function() end })
      assert.stub(UIManager.show).was_called()
      UIManager.show:clear()

      -- Monospace font toggle callback
      local mono_item = settings_sub[2]
      assert.is_false(mono_item.checked_func())
      mono_item.callback()
      assert.are.equal(editor.monospace_font, editor.font_face)
      assert.is_true(mono_item.checked_func())
      mono_item.callback()
      assert.are.equal(editor.normal_font, editor.font_face)

      -- Auto para direction callback
      local auto_para_item = settings_sub[3]
      assert.is_true(auto_para_item.checked_func())
      auto_para_item.callback()
      assert.is_false(editor.auto_para_direction)

      -- Force LTR callback
      local force_ltr_item = settings_sub[4]
      force_ltr_item.callback()
      assert.is_true(editor.force_ltr_para_direction)

      -- Show keyboard callback
      local keyboard_item = settings_sub[5]
      assert.is_true(keyboard_item.checked_func())
      keyboard_item.callback()
      assert.is_false(editor.show_keyboard_on_start)

      -- Enable QR code export callback
      local qr_item = settings_sub[6]
      assert.is_true(qr_item.checked_func())
      qr_item.callback()
      assert.is_false(editor.qr_code_export)

      -- Clean history callback
      local clean_hist_item = settings_sub[7]
      assert.is_true(clean_hist_item.enabled_func())
      clean_hist_item.callback({ updateItems = function() end })
      assert.stub(UIManager.show).was_called()
      local confirm_box = findShownWidget(function(w)
        return w.ok_callback ~= nil
      end)
      assert.is_table(confirm_box)
      confirm_box.ok_callback()
      assert.are.same({}, editor.history)
      assert.are.same({}, editor.last_view_pos)
      UIManager.show:clear()
    end)

    it(
      "handles history item hold_callback to remove item from history",
      function()
        local hist_file = temp_dir .. "/exist_hist.txt"
        local f = io.open(hist_file, "w")
        if f then
          f:write("hello")
          f:close()
        end

        editor:addToHistory(hist_file)

        local items = editor:getSubMenuItems()
        local hist_item = items[4]
        local mock_menu = { updateItems = spy.new(function() end) }
        hist_item.hold_callback(mock_menu)

        local confirm_box = findShownWidget(function(w)
          return w.ok_callback ~= nil
        end)
        assert.is_table(confirm_box)
        confirm_box.ok_callback()

        assert.are.same({}, editor.history)
        assert.spy(mock_menu.updateItems).was_called()

        os.remove(hist_file)
      end
    )
  end)

  describe("File creation and selection", function()
    it("triggers newFile workflow", function()
      stub(editor, "checkEditFile")

      editor:newFile()
      local confirm_box = findShownWidget(function(w)
        return w.ok_callback ~= nil
      end)
      assert.is_table(confirm_box)

      UIManager.show:clear()
      confirm_box.ok_callback()

      -- Should show PathChooser
      local path_chooser = findShownWidget(function(w)
        return type(w.onConfirm) == "function"
      end)
      assert.is_table(path_chooser)

      UIManager.show:clear()
      -- Confirm path in PathChooser -> shows InputDialog for filename
      path_chooser.onConfirm(temp_dir)

      local input_dialog = findShownWidget(function(w)
        return type(w.getInputText) == "function"
      end)
      assert.is_table(input_dialog)

      -- Find buttons in input_dialog
      local cancel_btn, edit_btn
      for _, row in ipairs(input_dialog.buttons) do
        for _, btn in ipairs(row) do
          if btn.text == "Cancel" or btn.id == "close" then
            cancel_btn = btn
          elseif btn.text == "Edit" then
            edit_btn = btn
          end
        end
      end

      assert.is_table(cancel_btn)
      assert.is_table(edit_btn)

      -- Test Cancel button callback
      cancel_btn.callback()
      assert
        .stub(UIManager.close)
        .was_called_with(match.ref(UIManager), match.ref(input_dialog))

      -- Test Edit button callback
      stub(input_dialog, "getInputText")
      input_dialog.getInputText.returns(temp_dir .. "/new_test.txt")

      edit_btn.callback()
      assert
        .stub(editor.checkEditFile)
        .was_called_with(match.ref(editor), temp_dir .. "/new_test.txt", false, true)
      assert.are.equal(temp_dir, editor.last_path)

      editor.checkEditFile:revert()
    end)

    it("triggers chooseFile workflow", function()
      stub(editor, "checkEditFile")

      editor:chooseFile()
      local path_chooser = findShownWidget(function(w)
        return type(w.onConfirm) == "function"
      end)
      assert.is_table(path_chooser)

      path_chooser.onConfirm(temp_dir .. "/chosen.txt")

      assert.are.equal(temp_dir, editor.last_path)
      assert
        .stub(editor.checkEditFile)
        .was_called_with(match.ref(editor), temp_dir .. "/chosen.txt")

      editor.checkEditFile:revert()
    end)
  end)

  describe("File checking and edit validation", function()
    it(
      "prompts to create non-existent file when possibly_new_file is false",
      function()
        local non_exist = temp_dir .. "/non_exist.txt"
        editor:checkEditFile(non_exist, false, false)

        local confirm_box = findShownWidget(function(w)
          return w.ok_callback ~= nil
        end)
        assert.is_table(confirm_box)

        stub(editor, "checkEditFile")
        confirm_box.ok_callback()
        assert
          .stub(editor.checkEditFile)
          .was_called_with(match.ref(editor), non_exist, false, true)
        editor.checkEditFile:revert()
      end
    )

    it(
      "shows error message when non-existent file cannot be created",
      function()
        local invalid_path = "/invalid_dir_xyz/test.txt"
        editor:checkEditFile(invalid_path, false, true)

        local info_msg = findShownWidget(function(w)
          return type(w.text) == "string"
        end)
        assert.is_table(info_msg)
      end
    )

    it("shows error message when file is a directory", function()
      editor:checkEditFile(temp_dir, false, false)

      local info_msg = findShownWidget(function(w)
        return type(w.text) == "string"
      end)
      assert.is_table(info_msg)
    end)

    it("warns when opening a large file not from history", function()
      local large_file = temp_dir .. "/large.txt"
      local f = io.open(large_file, "w")
      if f then
        f:write(string.rep("x", 250000))
        f:close()
      end

      editor.min_file_size_warn = 200000
      editor:checkEditFile(large_file, false, false)

      local confirm_box = findShownWidget(function(w)
        return w.ok_callback ~= nil
      end)
      assert.is_table(confirm_box)

      stub(editor, "editFile")
      confirm_box.ok_callback()
      assert.stub(editor.editFile).was_called()
      editor.editFile:revert()

      os.remove(large_file)
    end)

    it("opens existing normal file directly", function()
      local test_file = temp_dir .. "/normal.txt"
      local f = io.open(test_file, "w")
      if f then
        f:write("content")
        f:close()
      end

      stub(editor, "editFile")
      editor:checkEditFile(test_file, false, false)
      assert.stub(editor.editFile).was_called()
      editor.editFile:revert()

      os.remove(test_file)
    end)
  end)

  describe("File operations & InputDialog callbacks", function()
    it("saves and deletes content correctly", function()
      local file_path = temp_dir .. "/saved.txt"
      local ok, err = editor:saveFileContent(file_path, "hello world")
      assert.is_true(ok)
      assert.is_nil(err)

      local f = io.open(file_path, "r")
      local content = f:read("*a")
      f:close()
      assert.are.equal("hello world", content)

      local del_ok, del_err = editor:deleteFile(file_path)
      assert.is_true(del_ok)
      assert.is_nil(del_err)
    end)

    it(
      "sets up InputDialog and handles save_callback for non-Lua file",
      function()
        local test_file = temp_dir .. "/doc.txt"
        local f = io.open(test_file, "w")
        if f then
          f:write("initial content")
          f:close()
        end

        editor:editFile(test_file, false)
        assert.stub(UIManager.show).was_called()
        assert.is_table(editor.input)

        local save_cb = editor.input.save_callback
        assert.is_function(save_cb)

        -- Saving non-empty text
        local ok, msg = save_cb("new content", false)
        assert.is_true(ok)
        assert.is_string(msg)

        local rf = io.open(test_file, "r")
        local read_content = rf:read("*a")
        rf:close()
        assert.are.equal("new content", read_content)

        os.remove(test_file)
      end
    )

    it("handles save_callback when readonly is true", function()
      local test_file = temp_dir .. "/readonly.txt"
      local f = io.open(test_file, "w")
      if f then
        f:write("read only")
        f:close()
      end

      editor:editFile(test_file, true)
      local save_cb = editor.input.save_callback

      local ok, msg = save_cb("change", false)
      assert.is_false(ok)
      assert.is_string(msg)

      os.remove(test_file)
    end)

    it(
      "handles save_callback for Lua syntax check success and failure",
      function()
        local lua_file = temp_dir .. "/test.lua"
        local f = io.open(lua_file, "w")
        if f then
          f:write("local a = 1")
          f:close()
        end

        editor:editFile(lua_file, false)
        local save_cb = editor.input.save_callback

        -- Valid Lua syntax
        local ok, msg = save_cb("local x = 42", false)
        assert.is_true(ok)
        assert.is_string(msg)

        -- Invalid Lua syntax with Trapper confirm "Save anyway"
        Trapper.confirm.returns(true)
        local ok_anyway, msg_anyway = save_cb("local x =", false)
        assert.is_true(ok_anyway)
        assert.is_string(msg_anyway)
        assert.stub(Trapper.confirm).was_called()

        -- Invalid Lua syntax with Trapper confirm "Do not save"
        Trapper.confirm.returns(false)
        local ok_nosave, msg_nosave = save_cb("local x =", false)
        assert.is_false(ok_nosave)
        assert.is_false(msg_nosave)

        os.remove(lua_file)
      end
    )

    it(
      "handles save_callback for empty content (delete or keep empty)",
      function()
        local empty_test_file = temp_dir .. "/empty_test.txt"
        local f = io.open(empty_test_file, "w")
        if f then
          f:write("some text")
          f:close()
        end

        editor:editFile(empty_test_file, false)
        local save_cb = editor.input.save_callback

        -- Trapper confirm -> Delete file
        Trapper.confirm.returns(true)
        local ok_del, msg_del = save_cb("", false)
        assert.is_true(ok_del)
        assert.is_string(msg_del)

        -- Re-create file for keep empty test
        f = io.open(empty_test_file, "w")
        if f then
          f:write("some text")
          f:close()
        end

        -- Trapper confirm -> Keep empty file
        Trapper.confirm.returns(false)
        local ok_keep, msg_keep = save_cb("", false)
        assert.is_true(ok_keep)
        assert.is_string(msg_keep)

        os.remove(empty_test_file)
      end
    )

    it(
      "handles view_pos_callback, reset_callback, and close_callback",
      function()
        local test_file = temp_dir .. "/callbacks.txt"
        local f = io.open(test_file, "w")
        if f then
          f:write("content for callbacks")
          f:close()
        end

        editor:editFile(test_file, false)
        local input = editor.input

        -- View position callback
        assert.is_function(input.view_pos_callback)
        local top, char = input.view_pos_callback()
        assert.is_nil(top)
        assert.is_nil(char)

        input.view_pos_callback(12, 34)
        top, char = input.view_pos_callback()
        assert.are.equal(12, top)
        assert.are.equal(34, char)

        -- Reset callback
        assert.is_function(input.reset_callback)
        local res_text, res_msg = input.reset_callback()
        assert.are.equal("content for callbacks", res_text)
        assert.is_string(res_msg)

        -- Close callback
        local done_called = false
        editor.whenDoneFunc = function()
          done_called = true
        end
        input.close_callback()
        assert.is_true(done_called)
        assert.is_nil(editor.whenDoneFunc)

        os.remove(test_file)
      end
    )

    it("handles Lua check and QR extra buttons in editFile", function()
      local lua_file = temp_dir .. "/button_test.lua"
      local f = io.open(lua_file, "w")
      if f then
        f:write("local a = 1")
        f:close()
      end

      editor.qr_code_export = true
      editor:editFile(lua_file, false)

      -- Find extra buttons in first row of buttons
      local lua_check_btn, qr_btn
      for _, btn in ipairs(editor.input.buttons[1]) do
        if btn.text == "Lua check" then
          lua_check_btn = btn
        elseif btn.text == "QR" then
          qr_btn = btn
        end
      end

      assert.is_table(lua_check_btn)
      assert.is_table(qr_btn)

      -- Stub getInputText on input
      stub(editor.input, "getInputText")

      -- Test Lua check button callback (syntax OK)
      editor.input.getInputText.returns("local a = 1")
      lua_check_btn.callback()
      assert.stub(UIManager.show).was_called()
      UIManager.show:clear()

      -- Test Lua check button callback (syntax failed)
      editor.input.getInputText.returns("local a =")
      lua_check_btn.callback()
      assert.stub(UIManager.show).was_called()
      UIManager.show:clear()

      -- Test QR button callback
      editor.input.getInputText.returns("hello QR")
      qr_btn.callback()
      assert.stub(UIManager.show).was_called()

      editor.input.getInputText:revert()
      os.remove(lua_file)
    end)
  end)

  describe("Helper methods & Callbacks", function()
    it("handles onOpenLastEditedFile with and without history", function()
      stub(editor, "checkEditFile")
      stub(editor, "chooseFile")

      -- Without history -> calls chooseFile
      editor.history = {}
      editor:onOpenLastEditedFile()
      assert.stub(editor.chooseFile).was_called()

      -- With history -> calls checkEditFile
      editor.history = { "/last_file.txt" }
      editor:onOpenLastEditedFile()
      assert
        .stub(editor.checkEditFile)
        .was_called_with(match.ref(editor), "/last_file.txt", true)

      editor.checkEditFile:revert()
      editor.chooseFile:revert()
    end)

    it("openFile delegates to checkEditFile", function()
      stub(editor, "checkEditFile")
      editor:openFile("/some/file.txt")
      assert
        .stub(editor.checkEditFile)
        .was_called_with(match.ref(editor), "/some/file.txt")
      editor.checkEditFile:revert()
    end)

    it("shows rotation menu in showMenu", function()
      local test_file = temp_dir .. "/showmenu.txt"
      local f = io.open(test_file, "w")
      if f then
        f:write("test")
        f:close()
      end

      editor:editFile(test_file, false)
      UIManager.show:clear()

      editor:showMenu()
      assert.stub(UIManager.show).was_called()
      local dialog = findShownWidget(function(w)
        return type(w.buttons) == "table"
      end)
      assert.is_table(dialog)

      os.remove(test_file)
    end)
  end)
end)
