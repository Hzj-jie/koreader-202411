describe("TextEditor plugin", function()
  local TextEditor, editor
  local UIManager, Dispatcher, DocumentRegistry, util
  local temp_dir, temp_settings_path

  setup(function()
    require("commonrequire")
    TextEditor = require("plugins/texteditor.koplugin/main")
    UIManager = require("ui/uimanager")
    Dispatcher = require("dispatcher")
    DocumentRegistry = require("document/documentregistry")
    util = require("util")

    local DataStorage = require("datastorage")
    temp_dir = DataStorage:getDataDir() .. "/texteditor_unit_test_tmp"
    temp_settings_path = temp_dir .. "/text_editor_settings.lua"
    os.execute("mkdir -p " .. temp_dir)
  end)

  teardown(function()
    if temp_dir then
      os.execute("rm -rf " .. temp_dir)
    end
  end)

  before_each(function()
    os.remove(temp_settings_path)

    editor = TextEditor:new({
      ui = {
        menu = {
          registerToMainMenu = function() end,
        },
      },
      settings_file = temp_settings_path,
    })
    editor:init()
  end)

  after_each(function()
    os.remove(temp_settings_path)
  end)

  describe("initialization and defaults", function()
    it("initializes plugin metadata and default font settings", function()
      assert.is_table(TextEditor)
      assert.is_table(editor)
      assert.is_string(editor.name)
      assert.is_string(editor.fullname)
      assert.is_string(editor.normal_font)
      assert.is_string(editor.monospace_font)
      assert.is_number(editor.default_font_size)
    end)

    it(
      "registers document registry aux provider and supports all file types",
      function()
        local registered_provider = nil
        local old_add = DocumentRegistry.addAuxProvider
        DocumentRegistry.addAuxProvider = function(_, prov)
          registered_provider = prov
        end

        editor:registerDocumentRegistryAuxProvider()
        DocumentRegistry.addAuxProvider = old_add

        assert.is_table(registered_provider)
        assert.are.equal(editor.fullname, registered_provider.provider_name)
        assert.are.equal(editor.name, registered_provider.provider)
        assert.is_true(registered_provider.disable_file)
        assert.is_false(registered_provider.disable_type)
        assert.is_true(editor:isFileTypeSupported("test.txt"))
        assert.is_true(editor:isFileTypeSupported("test.lua"))
        assert.is_true(editor:isFileTypeSupported("test_no_ext"))
      end
    )
  end)

  describe("settings and menu", function()
    it("loads default settings and saves via onFlushSettings", function()
      editor:loadSettings()
      assert.is_table(editor.history)
      assert.are.equal(0, #editor.history)
      assert.is_table(editor.last_view_pos)

      editor.font_size = 28
      editor.qr_code_export = true
      editor:onFlushSettings()

      local LuaSettings = require("luasettings")
      local saved = LuaSettings:open(temp_settings_path)
      assert.are.equal(28, saved:read("font_size"))
      assert.is_true(saved:read("qr_code_export"))
    end)

    it("populates main menu item and sub menu items", function()
      local menu_items = {}
      editor:addToMainMenu(menu_items)
      assert.is_table(menu_items.text_editor)

      local sub_items = menu_items.text_editor.sub_item_table_func()
      assert.is_table(sub_items)
      assert.are.equal("Settings", sub_items[1].text)
      assert.is_table(sub_items[1].sub_item_table)
    end)
  end)

  describe("history management and file operations", function()
    it("adds items to history and enforces maximum history length", function()
      editor:loadSettings()
      editor.history_keep_size = 5
      for i = 1, 10 do
        editor:addToHistory(string.format("/path/to/file_%d.txt", i))
      end
      assert.are.equal(5, #editor.history)
      assert.are.equal("/path/to/file_10.txt", editor.history[1])
    end)

    it("saves and deletes file content cleanly", function()
      local test_file = temp_dir .. "/save_test.txt"
      local ok, err = editor:saveFileContent(test_file, "Hello World\nLine 2")
      assert.is_true(ok)
      assert.is_nil(err)

      local content = util.readFromFile(test_file, "rb")
      assert.are.equal("Hello World\nLine 2", content)

      local del_ok, del_err = editor:deleteFile(test_file)
      assert.is_true(del_ok)
      assert.is_nil(del_err)
      assert.is_false(util.fileExists(test_file))
    end)
  end)

  describe("failing tests exposing production bugs", function()
    it(
      "updates settings table when cleaning history (fails: line 235 history setting detachment)",
      function()
        editor:loadSettings()
        local hist_file = temp_dir .. "/history_entry.txt"
        editor:addToHistory(hist_file)
        assert.are.equal(1, #editor.history)
        assert.are.equal(1, #editor.settings:readTableRef("history"))

        local sub_items = editor:getSubMenuItems()
        local clean_item
        for _, item in ipairs(sub_items[1].sub_item_table) do
          if item.text == "Clean text editor history" then
            clean_item = item
            break
          end
        end
        assert.is_table(clean_item)

        local shown_box
        local old_show = UIManager.show
        UIManager.show = function(_, widget)
          shown_box = widget
        end

        clean_item.callback({
          updateItems = function() end,
        })
        UIManager.show = old_show

        assert.is_table(shown_box)
        shown_box.ok_callback()

        -- After cleaning history, both editor.history and editor.settings:readTableRef("history") must be empty:
        assert.are.same({}, editor.history)
        -- Production bug in texteditor main.lua line 235:
        -- ok_callback performs `self.history = {}`, which assigns a brand new table to `self.history`,
        -- detaching it from `self.settings.data["history"]`. The settings object still holds the old history list.
        assert.are.same({}, editor.settings:readTableRef("history"))
      end
    )

    it(
      "safely handles files with missing extension without crashing on lower() (fails: line 549)",
      function()
        editor:loadSettings()
        local no_ext_file = temp_dir .. "/Makefile"
        local f = io.open(no_ext_file, "w")
        if f then
          f:write("all:\n\techo test\n")
          f:close()
        end

        -- In main.lua line 548-549:
        -- local __, filetype = util.splitFileNameSuffix(filename)
        -- local is_lua = filetype:lower() == "lua"
        -- When a file has no extension, if util.splitFileNameSuffix returns nil for suffix:
        local orig_split = util.splitFileNameSuffix
        util.splitFileNameSuffix = function(file)
          local base, ext = orig_split(file)
          if ext == "" then
            return base, nil
          end
          return base, ext
        end

        local ok, err = pcall(function()
          editor:editFile(no_ext_file, false)
        end)

        util.splitFileNameSuffix = orig_split
        os.remove(no_ext_file)

        -- Production bug in main.lua line 549:
        -- Calling `filetype:lower()` without nil-checking crashes with
        -- `attempt to index local 'filetype' (a nil value)` when filetype is nil.
        assert.is_true(
          ok,
          "editFile should handle missing extension (nil filetype) safely: "
            .. tostring(err)
        )
      end
    )
  end)
end)
