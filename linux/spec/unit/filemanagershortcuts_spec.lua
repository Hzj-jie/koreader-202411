describe("FileManagerShortcuts", function()
  local FileManagerShortcuts
  local mock_widget_container
  local mock_menu
  local mock_uimanager
  local mock_lfs
  local mock_ffi_util
  local mock_button_dialog
  local mock_info_message
  local mock_input_dialog
  local mock_path_chooser
  local mock_folder_shortcuts

  setup(function()
    require("commonrequire")
  end)

  before_each(function()
    mock_folder_shortcuts = {
      ["/path/to/folder1"] = { text = "Folder 1", time = 12345 },
      ["/path/to/folder2"] = { text = "Folder 2", time = 12346 },
    }

    _G.G_reader_settings = {
      readTableRef = function(self, key)
        if key == "folder_shortcuts" then
          return mock_folder_shortcuts
        end
        return {}
      end,
    }

    mock_widget_container = {
      extend = function(self, obj)
        obj = obj or {}
        setmetatable(obj, { __index = self })
        return obj
      end,
      new = function(self, obj)
        obj = obj or {}
        setmetatable(obj, { __index = self })
        if obj.init then
          obj:init()
        end
        return obj
      end,
    }
    package.loaded["ui/widget/container/widgetcontainer"] = mock_widget_container

    mock_menu = {
      new = function(self, args)
        args = args or {}
        setmetatable(args, { __index = self })
        return args
      end,
      switchItemTable = function(self, _nil, item_table, _minus_one)
        self.item_table = item_table
      end,
    }
    package.loaded["ui/widget/menu"] = mock_menu

    mock_uimanager = {
      shown_widgets = {},
      show = function(self, widget)
        table.insert(self.shown_widgets, widget)
      end,
      close = function(self, widget)
        for i, w in ipairs(self.shown_widgets) do
          if w == widget then
            table.remove(self.shown_widgets, i)
            break
          end
        end
      end,
    }
    package.loaded["ui/uimanager"] = mock_uimanager

    mock_lfs = {
      files = {
        ["/path/to/folder1"] = { mode = "directory" },
        ["/path/to/folder2"] = { mode = "directory" },
        ["/path/to/nonexistent"] = nil,
      },
      attributes = function(path, request)
        if mock_lfs.files[path] then
          if request == "mode" then
            return mock_lfs.files[path].mode
          end
          return mock_lfs.files[path]
        end
        return nil
      end,
    }
    package.loaded["libs/libkoreader-lfs"] = mock_lfs

    mock_ffi_util = {
      basename = function(path)
        return path:match("([^/]+)$") or path
      end,
    }
    package.loaded["ffi/util"] = mock_ffi_util

    mock_button_dialog = {
      new = function(self, args)
        return {
          is_button_dialog = true,
          title = args.title,
          buttons = args.buttons,
        }
      end,
    }
    package.loaded["ui/widget/buttondialog"] = mock_button_dialog

    mock_info_message = {
      new = function(self, args)
        return {
          is_info_message = true,
          text = args.text,
        }
      end,
    }
    package.loaded["ui/widget/infomessage"] = mock_info_message

    mock_input_dialog = {
      new = function(self, args)
        local obj = {
          is_input_dialog = true,
          title = args.title,
          input = args.input,
          description = args.description,
          buttons = args.buttons,
          getInputText = function(s)
            return s.input_text or s.input or ""
          end,
          disableButton = function(s, id)
            s.disabled_buttons = s.disabled_buttons or {}
            s.disabled_buttons[id] = true
            return true
          end,
          enableButton = function(s, id)
            s.disabled_buttons = s.disabled_buttons or {}
            s.disabled_buttons[id] = nil
            return true
          end,
          refreshButtons = function() end,
        }
        if args.edited_callback then
          -- trigger callback to simulate initial state
          args.edited_callback()
        end
        return obj
      end,
    }
    package.loaded["ui/widget/inputdialog"] = mock_input_dialog

    mock_path_chooser = {
      new = function(self, args)
        return {
          is_path_chooser = true,
          onConfirm = args.onConfirm,
        }
      end,
    }
    package.loaded["ui/widget/pathchooser"] = mock_path_chooser

    package.loaded["ui/bidi"] = {
      dirpath = function(p)
        return p
      end,
    }

    package.loaded["gettext"] = function(text)
      return text
    end

    FileManagerShortcuts = require("apps/filemanager/filemanagershortcuts")
  end)

  after_each(function()
    package.loaded["apps/filemanager/filemanagershortcuts"] = nil
    package.loaded["ui/widget/container/widgetcontainer"] = nil
    package.loaded["ui/widget/menu"] = nil
    package.loaded["ui/uimanager"] = nil
    package.loaded["libs/libkoreader-lfs"] = nil
    package.loaded["ffi/util"] = nil
    package.loaded["ui/widget/buttondialog"] = nil
    package.loaded["ui/widget/infomessage"] = nil
    package.loaded["ui/widget/inputdialog"] = nil
    package.loaded["ui/widget/pathchooser"] = nil
    package.loaded["ui/bidi"] = nil
    package.loaded["gettext"] = nil
    _G.G_reader_settings = nil
  end)

  describe("hasFolderShortcut", function()
    it("should return true if shortcut exists", function()
      local fms = FileManagerShortcuts:new()
      assert.is_true(fms:hasFolderShortcut("/path/to/folder1"))
    end)

    it("should return false if shortcut does not exist", function()
      local fms = FileManagerShortcuts:new()
      assert.is_false(fms:hasFolderShortcut("/path/to/nonexistent"))
    end)
  end)

  describe("updateItemTable", function()
    it("should populate shortcuts_menu with sorted shortcuts", function()
      local fms = FileManagerShortcuts:new()
      fms.shortcuts_menu = mock_menu:new()

      fms:updateItemTable()

      local expected = {
        { text = "Folder 1 (/path/to/folder1)", folder = "/path/to/folder1", name = "Folder 1" },
        { text = "Folder 2 (/path/to/folder2)", folder = "/path/to/folder2", name = "Folder 2" },
      }
      assert.are.same(expected, fms.shortcuts_menu.item_table)
    end)
  end)

  describe("onMenuChoice", function()
    it("should do nothing if folder does not exist", function()
      local fms = FileManagerShortcuts:new()
      local callback_called = false
      fms.select_callback = function(_path)
        callback_called = true
      end

      fms:onMenuChoice({ folder = "/path/to/nonexistent" })

      assert.is_false(callback_called)
    end)

    it("should call select_callback if defined", function()
      local fms = FileManagerShortcuts:new()
      local selected_folder
      fms.select_callback = function(path)
        selected_folder = path
      end

      fms:onMenuChoice({ folder = "/path/to/folder1" })

      assert.are.equal("/path/to/folder1", selected_folder)
    end)

    it("should change path in file_chooser if select_callback is nil and file_chooser exists", function()
      local fms = FileManagerShortcuts:new()
      local changed_to_path
      fms._manager = {
        ui = {
          file_chooser = {
            changeToPath = function(_self, path)
              changed_to_path = path
            end,
          },
        },
      }

      -- We need to call it as shortcuts_menu would call it, but here we can just set _manager on fms
      -- Wait, if we call fms:onMenuChoice directly, self is fms.
      -- In onMenuChoice:
      --   if self.select_callback then ...
      --   else if self._manager.ui.file_chooser then ...
      -- So if self is fms, and fms._manager is defined, it works.
      fms:onMenuChoice({ folder = "/path/to/folder1" })

      assert.are.equal("/path/to/folder1", changed_to_path)
    end)
  end)

  describe("removeShortcut", function()
    it("should remove shortcut and update menu", function()
      local fms = FileManagerShortcuts:new()
      fms.shortcuts_menu = mock_menu:new()

      fms:removeShortcut("/path/to/folder1")

      assert.is_nil(fms.folder_shortcuts["/path/to/folder1"])
      assert.is_true(fms.fm_updated)
      -- Should have updated item table (only folder2 remains)
      local expected = {
        { text = "Folder 2 (/path/to/folder2)", folder = "/path/to/folder2", name = "Folder 2" },
      }
      assert.are.same(expected, fms.shortcuts_menu.item_table)
    end)
  end)

  describe("editShortcut", function()
    it("should show InputDialog to rename existing shortcut", function()
      local fms = FileManagerShortcuts:new()
      fms.shortcuts_menu = mock_menu:new()

      fms:editShortcut("/path/to/folder1")

      assert.are.equal(1, #mock_uimanager.shown_widgets)
      local dialog = mock_uimanager.shown_widgets[1]
      assert.is_true(dialog.is_input_dialog)
      assert.are.equal("Enter folder shortcut name", dialog.title)
      assert.are.equal("Folder 1", dialog.input)
      assert.are.equal("/path/to/folder1", dialog.description)

      -- Find "Save" button
      local save_btn
      for _, row in ipairs(dialog.buttons) do
        for _, btn in ipairs(row) do
          if btn.text == "Save" then
            save_btn = btn
            break
          end
        end
      end
      assert.truthy(save_btn)

      -- Simulate user typing new name
      dialog.input_text = "New Folder 1 Name"
      -- We need to trigger edited_callback if we want to test button enabling/disabling,
      -- but in our mock we only ran it once in constructor.
      -- Actually, the callback is defined in spec, so we could trigger it if we had a way.
      -- But here we just want to test the Save callback.

      -- Trigger Save
      save_btn.callback()

      assert.are.equal("New Folder 1 Name", fms.folder_shortcuts["/path/to/folder1"].text)
      assert.is_true(fms.fm_updated)
    end)

    it("should show InputDialog to create new shortcut", function()
      local fms = FileManagerShortcuts:new()
      fms.shortcuts_menu = mock_menu:new()
      local post_callback_called = false
      local post_callback = function()
        post_callback_called = true
      end

      fms:editShortcut("/path/to/new_folder", post_callback)

      assert.are.equal(1, #mock_uimanager.shown_widgets)
      local dialog = mock_uimanager.shown_widgets[1]
      assert.is_true(dialog.is_input_dialog)
      assert.is_nil(dialog.input) -- new shortcut, no input
      -- hint should be basename of folder, but we don't test hint easily as it's in constructor args.

      local save_btn
      for _, row in ipairs(dialog.buttons) do
        for _, btn in ipairs(row) do
          if btn.text == "Save" then
            save_btn = btn
            break
          end
        end
      end

      dialog.input_text = "New Folder"
      save_btn.callback()

      assert.are.equal("New Folder", fms.folder_shortcuts["/path/to/new_folder"].text)
      assert.is_true(post_callback_called)
      assert.is_true(fms.fm_updated)
    end)
  end)

  describe("addShortcut", function()
    it("should show PathChooser and then editShortcut if new", function()
      local fms = FileManagerShortcuts:new()
      fms.ui = {
        getLastDirFile = function() return "/path/to" end
      }

      fms:addShortcut()

      assert.are.equal(1, #mock_uimanager.shown_widgets)
      local chooser = mock_uimanager.shown_widgets[1]
      assert.is_true(chooser.is_path_chooser)

      -- Confirm new path
      chooser.onConfirm("/path/to/new_folder")

      -- Should have closed chooser (wait, onConfirm doesn't close it automatically in our mock,
      -- but editShortcut will show InputDialog, so shown_widgets might have both or chooser is closed?
      -- In production, onConfirm callback usually closes it or it's closed by UIManager.
      -- Here editShortcut is called, which UIManager:shows InputDialog.
      -- So shown_widgets should now contain InputDialog.
      -- Let's check if editShortcut was called by checking if InputDialog is shown.
      -- Since we didn't mock UIManager to automatically close on click (we just call callbacks),
      -- both might be in shown_widgets if we didn't close chooser.
      -- Actually, in addShortcut:
      --   onConfirm = function(path)
      --     if self:hasFolderShortcut(path) then ...
      --     else self:editShortcut(path) end
      --   end
      -- It doesn't close path_chooser in onConfirm!
      -- Wait, PathChooser itself might close on confirm.
      -- But in our mock it doesn't.
      -- So we just check if InputDialog is now in shown_widgets.

      local input_dialog
      for _, w in ipairs(mock_uimanager.shown_widgets) do
        if w.is_input_dialog then
          input_dialog = w
          break
        end
      end
      assert.truthy(input_dialog)
      assert.are.equal("Enter folder shortcut name", input_dialog.title)
    end)

    it("should show InfoMessage if shortcut already exists", function()
      local fms = FileManagerShortcuts:new()
      fms.ui = {
        getLastDirFile = function() return "/path/to" end
      }

      fms:addShortcut()

      local chooser = mock_uimanager.shown_widgets[1]
      chooser.onConfirm("/path/to/folder1") -- already exists

      local info_message
      for _, w in ipairs(mock_uimanager.shown_widgets) do
        if w.is_info_message then
          info_message = w
          break
        end
      end
      assert.truthy(info_message)
      assert.are.equal("Shortcut already exists.", info_message.text)
    end)
  end)
end)
