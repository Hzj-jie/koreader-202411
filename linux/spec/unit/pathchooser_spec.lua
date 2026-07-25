describe("PathChooser widget", function()
  local PathChooser, Device, UIManager, Screen, ffiutil, lfs, spy, stub

  local sample_file = "spec/unit/data/2col.pdf"
  local sample_dir = "spec/unit/data"

  setup(function()
    require("commonrequire")
    require("document/canvascontext"):init(require("device"))
    PathChooser = require("ui/widget/pathchooser")
    Device = require("device")
    UIManager = require("ui/uimanager")
    Screen = Device.screen
    ffiutil = require("ffi/util")
    lfs = require("libs/libkoreader-lfs")
    spy = require("luassert.spy")
    stub = require("luassert.stub")
  end)

  local function createChooser(opts)
    opts = opts or {}
    opts.dimen = opts.dimen or Screen:getSize()
    opts.path = opts.path or sample_dir
    opts.refreshPath = opts.refreshPath or function() end
    return PathChooser:new(opts)
  end

  describe("init() options and titles", function()
    it(
      "should set title for select_directory=true and select_file=true",
      function()
        local pc = createChooser({
          title = true,
          select_directory = true,
          select_file = true,
        })
        assert.is_string(pc.title)
        assert.is_not_nil(pc.title:find("Long%-press to choose"))
      end
    )

    it(
      "should set title for select_directory=true and select_file=false",
      function()
        local pc = createChooser({
          title = true,
          select_directory = true,
          select_file = false,
        })
        assert.is_not_nil(pc.title:find("folder"))
      end
    )

    it(
      "should set title for select_directory=false and select_file=true",
      function()
        local pc = createChooser({
          title = true,
          select_directory = false,
          select_file = true,
        })
        assert.is_not_nil(pc.title:find("file"))
      end
    )

    it("should keep custom string title", function()
      local pc = createChooser({
        title = "Select Destination",
      })
      assert.is_same("Select Destination", pc.title)
    end)

    it("should filter out files when show_files=false", function()
      local pc = createChooser({
        show_files = false,
      })
      assert.is_function(pc.file_filter)
      assert.is_false(pc.file_filter("file.txt"))
      assert.is_false(pc.show_unsupported)
    end)

    it(
      "should set show_unsupported=false when file_filter is provided",
      function()
        local custom_filter = function(file)
          return file:match("%.epub$")
        end
        local pc = createChooser({
          file_filter = custom_filter,
        })
        assert.is_false(pc.show_unsupported)
      end
    )

    it(
      "should set show_current_dir_for_hold when select_directory=true",
      function()
        local pc = createChooser({
          select_directory = true,
        })
        assert.is_true(pc.show_current_dir_for_hold)
      end
    )

    it("should wire title bar left icon and handlers", function()
      local pc = createChooser()
      assert.is_same("home", pc.title_bar_left_icon)

      local go_home_spy = stub(pc, "goHome")
      pc.onLeftButtonTap()
      assert.stub(go_home_spy).was_called()
      go_home_spy:revert()

      local plus_menu_spy = stub(pc, "showPlusMenu")
      pc.onLeftButtonHold()
      assert.stub(plus_menu_spy).was_called()
      plus_menu_spy:revert()
    end)
  end)

  describe("onMenuSelect()", function()
    it("should handle current dir item '/.' on touch device", function()
      local pc = createChooser({
        select_directory = true,
      })
      local is_touch_stub = stub(Device, "isTouchDevice").returns(true)
      local hold_spy = stub(pc, "onMenuHold")

      local res = pc:onMenuSelect({ path = sample_dir .. "/." })
      assert.is_true(res)
      assert.stub(hold_spy).was_not_called()

      is_touch_stub:revert()
      hold_spy:revert()
    end)

    it(
      "should call onMenuHold for current dir item '/.' on non-touch device when select_directory=true",
      function()
        local pc = createChooser({
          select_directory = true,
        })
        local is_touch_stub = stub(Device, "isTouchDevice").returns(false)
        local hold_spy = stub(pc, "onMenuHold")

        local res = pc:onMenuSelect({ path = sample_dir .. "/." })
        assert.is_true(res)
        assert.stub(hold_spy).was_called()

        is_touch_stub:revert()
        hold_spy:revert()
      end
    )

    it("should fallback to root path '/' when realpath is nil", function()
      local pc = createChooser()
      local change_path_stub = stub(pc, "changeToPath")
      local realpath_stub = stub(ffiutil, "realpath").returns(nil)

      local res = pc:onMenuSelect({ path = "/nonexistent_path_xyz123" })
      assert.is_true(res)
      assert.stub(change_path_stub).was_called_with(pc, "/")

      realpath_stub:revert()
      change_path_stub:revert()
    end)

    it(
      "should fallback to root path '/' when lfs attributes are nil",
      function()
        local pc = createChooser()
        local change_path_stub = stub(pc, "changeToPath")
        local realpath_stub = stub(ffiutil, "realpath").returns("/dummy_path")
        local attr_stub = stub(lfs, "attributes").returns(nil)

        local res = pc:onMenuSelect({ path = "/dummy_path" })
        assert.is_true(res)
        assert.stub(change_path_stub).was_called_with(pc, "/")

        realpath_stub:revert()
        attr_stub:revert()
        change_path_stub:revert()
      end
    )

    it(
      "should handle file item selection on non-touch vs touch device",
      function()
        local pc = createChooser({
          select_file = true,
        })

        -- Touch device: doesn't hold
        local is_touch_stub = stub(Device, "isTouchDevice").returns(true)
        local hold_spy = stub(pc, "onMenuHold")

        local res1 = pc:onMenuSelect({ path = sample_file })
        assert.is_true(res1)
        assert.stub(hold_spy).was_not_called()

        is_touch_stub:revert()
        hold_spy:revert()

        -- Non-touch device: calls onMenuHold
        is_touch_stub = stub(Device, "isTouchDevice").returns(false)
        hold_spy = stub(pc, "onMenuHold")

        local res2 = pc:onMenuSelect({ path = sample_file })
        assert.is_true(res2)
        assert.stub(hold_spy).was_called()

        is_touch_stub:revert()
        hold_spy:revert()
      end
    )

    it("should navigate into directory if sub_table is not empty", function()
      local pc = createChooser()

      local change_path_stub = stub(pc, "changeToPath")
      local gen_items_stub =
        stub(pc, "genItemTableFromPath").returns({ { text = "file.txt" } })

      local res = pc:onMenuSelect({ path = sample_dir })
      assert.is_true(res)
      assert.stub(change_path_stub).was_called()

      change_path_stub:revert()
      gen_items_stub:revert()
    end)

    it("should not navigate into directory if sub_table is empty", function()
      local pc = createChooser()

      local change_path_stub = stub(pc, "changeToPath")
      local gen_items_stub = stub(pc, "genItemTableFromPath").returns({})

      local res = pc:onMenuSelect({ path = sample_dir })
      assert.is_true(res)
      assert.stub(change_path_stub).was_not_called()

      change_path_stub:revert()
      gen_items_stub:revert()
    end)
  end)

  describe("onMenuHold()", function()
    it("should return early for invalid or non-existent path", function()
      local pc = createChooser()
      local show_widget_stub = stub(pc, "showWidget")

      pc:onMenuHold({ path = "/nonexistent_path_xyz123" })
      assert.stub(show_widget_stub).was_not_called()

      show_widget_stub:revert()
    end)

    it("should return early when holding file and select_file=false", function()
      local pc = createChooser({
        select_file = false,
      })
      local show_widget_stub = stub(pc, "showWidget")

      pc:onMenuHold({ path = sample_file })
      assert.stub(show_widget_stub).was_not_called()

      show_widget_stub:revert()
    end)

    it(
      "should return early when holding directory and select_directory=false",
      function()
        local pc = createChooser({
          select_directory = false,
        })
        local show_widget_stub = stub(pc, "showWidget")

        pc:onMenuHold({ path = sample_dir })
        assert.stub(show_widget_stub).was_not_called()

        show_widget_stub:revert()
      end
    )

    it(
      "should show dialog for file holding with detailed_file_info=true",
      function()
        local pc = createChooser({
          select_file = true,
          detailed_file_info = true,
        })
        local show_widget_stub = stub(pc, "showWidget")

        pc:onMenuHold({ path = sample_file })
        assert.stub(show_widget_stub).was_called()
        assert.is_table(pc.button_dialog)
        assert.is_not_nil(pc.button_dialog.title:find("File size:"))
        assert.is_not_nil(pc.button_dialog.title:find("Last modified:"))

        show_widget_stub:revert()
      end
    )

    it(
      "should show dialog for file holding with detailed_file_info=false",
      function()
        local pc = createChooser({
          select_file = true,
          detailed_file_info = false,
        })
        local show_widget_stub = stub(pc, "showWidget")

        pc:onMenuHold({ path = sample_file })
        assert.stub(show_widget_stub).was_called()
        assert.is_table(pc.button_dialog)
        assert.is_nil(pc.button_dialog.title:find("File size:"))

        show_widget_stub:revert()
      end
    )

    it(
      "should show dialog for directory holding and strip '/.' suffix",
      function()
        local pc = createChooser({
          select_directory = true,
        })
        local show_widget_stub = stub(pc, "showWidget")

        pc:onMenuHold({ path = sample_dir .. "/." })
        assert.stub(show_widget_stub).was_called()
        assert.is_table(pc.button_dialog)
        assert.is_not_nil(pc.button_dialog.title:find("Choose this folder%?"))

        show_widget_stub:revert()
      end
    )

    it("should show dialog for other path mode", function()
      local pc = createChooser()
      local attr_stub = stub(lfs, "attributes").returns({ mode = "fifo" })
      local show_widget_stub = stub(pc, "showWidget")

      pc:onMenuHold({ path = sample_file })
      assert.stub(show_widget_stub).was_called()
      assert.is_table(pc.button_dialog)
      assert.is_not_nil(pc.button_dialog.title:find("Choose this path%?"))

      attr_stub:revert()
      show_widget_stub:revert()
    end)

    it("should close dialog on Cancel button tap", function()
      local pc = createChooser({
        select_directory = true,
      })
      stub(pc, "showWidget")
      local close_ui_spy = stub(UIManager, "close")

      pc:onMenuHold({ path = sample_dir })
      local cancel_btn = pc.button_dialog.buttons[1][1]
      assert.is_same("Cancel", cancel_btn.text)
      cancel_btn.callback()

      assert.stub(close_ui_spy).was_called_with(UIManager, pc.button_dialog)

      close_ui_spy:revert()
    end)

    it(
      "should invoke onConfirm callback and close widgets on Choose button tap",
      function()
        local confirmed_path = nil
        local pc = createChooser({
          select_directory = true,
          onConfirm = function(p)
            confirmed_path = p
          end,
        })
        stub(pc, "showWidget")
        local close_ui_spy = stub(UIManager, "close")

        pc:onMenuHold({ path = sample_dir })
        local choose_btn = pc.button_dialog.buttons[1][2]
        assert.is_same("Choose", choose_btn.text)
        choose_btn.callback()

        assert.is_string(confirmed_path)
        assert.is_true(#confirmed_path > 0)
        assert.stub(close_ui_spy).was_called_with(UIManager, pc.button_dialog)
        assert.stub(close_ui_spy).was_called_with(UIManager, pc)

        close_ui_spy:revert()
      end
    )
  end)

  describe("showPlusMenu()", function()
    it("should trigger Folder shortcuts callback and change path", function()
      local pc = createChooser()
      local dialog_captured = nil
      local show_widget_stub = stub(pc, "showWidget", function(self_arg, widget)
        dialog_captured = widget
      end)
      local close_ui_spy = stub(UIManager, "close")
      local change_path_stub = stub(pc, "changeToPath")

      local FileManagerShortcuts =
        require("apps/filemanager/filemanagershortcuts")
      local shortcuts_stub = stub(
        FileManagerShortcuts,
        "onShowFolderShortcutsDialog",
        function(self_arg, select_cb)
          select_cb("/target/path")
        end
      )

      pc:showPlusMenu()
      assert.is_table(dialog_captured)
      local shortcut_btn = dialog_captured.buttons[1][1]
      assert.is_not_nil(shortcut_btn.text:find("Folder shortcuts"))
      shortcut_btn.callback()

      assert.stub(close_ui_spy).was_called_with(UIManager, dialog_captured)
      assert.stub(shortcuts_stub).was_called()
      assert.stub(change_path_stub).was_called_with(pc, "/target/path")

      show_widget_stub:revert()
      close_ui_spy:revert()
      change_path_stub:revert()
      shortcuts_stub:revert()
    end)

    it("should trigger New folder callback", function()
      local pc = createChooser()
      local dialog_captured = nil
      local show_widget_stub = stub(pc, "showWidget", function(self_arg, widget)
        dialog_captured = widget
      end)
      local close_ui_spy = stub(UIManager, "close")

      local FileManager = require("apps/filemanager/filemanager")
      local create_folder_stub = stub(FileManager, "createFolder")

      pc:showPlusMenu()
      assert.is_table(dialog_captured)
      local new_folder_btn = dialog_captured.buttons[2][1]
      assert.is_not_nil(new_folder_btn.text:find("New folder"))
      new_folder_btn.callback()

      assert.stub(close_ui_spy).was_called_with(UIManager, dialog_captured)
      assert.is_same(pc, FileManager.file_chooser)
      assert.stub(create_folder_stub).was_called()

      show_widget_stub:revert()
      close_ui_spy:revert()
      create_folder_stub:revert()
    end)
  end)
end)
