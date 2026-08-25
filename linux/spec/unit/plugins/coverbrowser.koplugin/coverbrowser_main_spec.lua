describe("CoverBrowser plugin main module", function()
  local CoverBrowser, BookInfoManager

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    BookInfoManager = require("plugins/coverbrowser.koplugin/bookinfomanager")
    BookInfoManager:init()
    CoverBrowser = require("plugins/coverbrowser.koplugin/main")
  end)

  describe("Initialization & Main Menu", function()
    it("should initialize CoverBrowser plugin instance and register to menu", function()
      local registered = false
      local mock_ui = {
        file_chooser = {
          nb_cols_portrait = 3,
          nb_rows_portrait = 3,
          nb_cols_landscape = 4,
          nb_rows_landscape = 2,
          files_per_page = 10,
          updateItems = function() end,
          _recalculateDimen = function() end,
          changeToPath = function() end,
          updateCache = function() end,
        },
        menu = {
          registerToMainMenu = function(self_menu, plugin)
            registered = true
          end,
        },
      }
      local cb = CoverBrowser:new({
        ui = mock_ui,
      })
      cb:init()
      assert.is_table(cb)
      assert.is_true(registered)
    end)

    it("should expose modes list", function()
      local mock_ui = {
        file_chooser = {},
        menu = {
          registerToMainMenu = function() end,
        },
      }
      local cb = CoverBrowser:new({
        ui = mock_ui,
      })
      assert.is_table(cb.modes)
      assert.is_true(#cb.modes >= 5)
    end)

    it("should handle main menu population and execute all callbacks", function()
      local mock_fc = {
        nb_cols_portrait = 3,
        nb_rows_portrait = 3,
        nb_cols_landscape = 4,
        nb_rows_landscape = 2,
        files_per_page = 10,
        display_mode_type = "mosaic",
        portrait_mode = true,
        updateItems = function() end,
        _recalculateDimen = function() end,
        changeToPath = function() end,
        updateCache = function() end,
      }
      local mock_ui = {
        file_chooser = mock_fc,
        menu = { registerToMainMenu = function() end },
      }
      local cb = CoverBrowser:new({ ui = mock_ui })
      cb:init()

      local menu_items = {
        filebrowser_settings = {
          sub_item_table = { {}, {}, {}, {}, {} }
        }
      }
      cb:addToMainMenu(menu_items)
      assert.is_table(menu_items.filemanager_display_mode)
      assert.is_table(menu_items.filemanager_display_mode.sub_item_table)

      local UIManager = require("ui/uimanager")
      local orig_show = UIManager.show
      UIManager.show = function(self_uim, widget)
        if widget and widget.ok_callback then
          -- avoid opening real confirmboxes in headless tests
        end
      end

      -- Exercise mode callbacks
      for _, item in ipairs(menu_items.filemanager_display_mode.sub_item_table) do
        if item.checked_func then item.checked_func() end
        if item.enabled_func then item.enabled_func() end
        if item.callback then pcall(item.callback) end
        if item.sub_item_table then
          for _, sub_item in ipairs(item.sub_item_table) do
            if sub_item.checked_func then sub_item.checked_func() end
            if sub_item.enabled_func then sub_item.enabled_func() end
            if sub_item.callback then pcall(sub_item.callback) end
          end
        end
      end

      -- Exercise filebrowser settings submenu callbacks
      for _, settings_item in ipairs(menu_items.filebrowser_settings.sub_item_table) do
        if settings_item.sub_item_table then
          for _, sub in ipairs(settings_item.sub_item_table) do
            if sub.text_func then sub.text_func() end
            if sub.checked_func then sub.checked_func() end
            if sub.callback then pcall(sub.callback) end
            if sub.sub_item_table then
              for _, nested in ipairs(sub.sub_item_table) do
                if nested.text_func then nested.text_func() end
                if nested.checked_func then nested.checked_func() end
                if nested.enabled_func then nested.enabled_func() end
                if nested.callback then pcall(nested.callback) end
              end
            end
          end
        end
      end
      UIManager.show = orig_show
    end)

    it("should handle display mode setters and switching", function()
      local mock_fc = {
        nb_cols_portrait = 3,
        nb_rows_portrait = 3,
        nb_cols_landscape = 4,
        nb_rows_landscape = 2,
        files_per_page = 10,
        updateItems = function() end,
        _recalculateDimen = function() end,
        changeToPath = function() end,
      }
      local mock_ui = {
        file_chooser = mock_fc,
        menu = { registerToMainMenu = function() end },
      }
      local cb = CoverBrowser:new({ ui = mock_ui })

      cb:setDisplayMode("mosaic_image")
      cb:setupFileManagerDisplayMode("mosaic_text")
      cb:setupFileManagerDisplayMode("list_image_meta")
      cb:setupFileManagerDisplayMode("list_only_meta")
      cb:setupFileManagerDisplayMode("list_image_filename")
      cb:setupFileManagerDisplayMode(nil) -- classic

      cb:setupHistoryDisplayMode("mosaic_image")
      cb:setupHistoryDisplayMode("list_image_meta")
      cb:setupHistoryDisplayMode(nil)

      cb:setupCollectionDisplayMode("mosaic_image")
      cb:setupCollectionDisplayMode("list_image_meta")
      cb:setupCollectionDisplayMode(nil)
    end)

    it("should handle event hooks like onDocSettingsItemsChanged and onInvalidateMetadataCache", function()
      local mock_fc = {
        updateCache = function() end,
        _recalculateDimen = function() end,
        changeToPath = function() end,
      }
      local mock_ui = {
        file_chooser = mock_fc,
        history = { hist_menu = { updateCache = function() end } },
        collections = { coll_menu = { updateCache = function() end } },
        menu = { registerToMainMenu = function() end },
      }
      local cb = CoverBrowser:new({ ui = mock_ui })

      cb:onInvalidateMetadataCache("/tmp/test.epub")
      cb:onDocSettingsItemsChanged("/tmp/test.epub", { summary = { status = "reading" } })
      cb:onDocSettingsItemsChanged("/tmp/test.epub", nil)

      local info = cb:getBookInfo("/tmp")
      assert.is_table(info)
    end)

    it("should handle grid/list size configuration dialogs and db maintenance actions", function()
      local UIManager = require("ui/uimanager")
      local shown_widgets = {}
      local orig_show = UIManager.show
      UIManager.show = function(self_uim, widget)
        table.insert(shown_widgets, widget)
        if widget.callback then
          -- Test DoubleSpinWidget or SpinWidget callback
          if widget.left_value and widget.right_value then
            pcall(widget.callback, 4, 5)
          elseif widget.value then
            pcall(widget.callback, { value = 12 })
          end
        end
        if widget.close_callback then
          pcall(widget.close_callback)
        end
        if widget.ok_callback then
          pcall(widget.ok_callback)
        end
      end

      local mock_fc = {
        nb_cols_portrait = 3,
        nb_rows_portrait = 3,
        nb_cols_landscape = 4,
        nb_rows_landscape = 2,
        files_per_page = 10,
        display_mode_type = "mosaic",
        portrait_mode = true,
        updateItems = function() end,
        _recalculateDimen = function() end,
        changeToPath = function() end,
        updateCache = function() end,
        path = "/tmp",
        showFileDialog_orig = function() end,
      }
      local mock_ui = {
        file_chooser = mock_fc,
        menu = { registerToMainMenu = function() end },
      }
      local cb = CoverBrowser:new({ ui = mock_ui })
      cb:init()

      local menu_items = {
        filebrowser_settings = { sub_item_table = { {}, {}, {}, {}, {} } }
      }
      cb:addToMainMenu(menu_items)

      -- Exercise filebrowser settings submenu callbacks that open Spin/Confirm dialogs
      for _, settings_item in ipairs(menu_items.filebrowser_settings.sub_item_table) do
        if settings_item.sub_item_table then
          for _, sub in ipairs(settings_item.sub_item_table) do
            if sub.callback then pcall(sub.callback) end
            if sub.sub_item_table then
              for _, nested in ipairs(sub.sub_item_table) do
                if nested.callback then pcall(nested.callback) end
              end
            end
          end
        end
      end

      -- Drain any tasks scheduled in nextTick from db operations
      while #UIManager._task_queue > 0 do
        local task = table.remove(UIManager._task_queue, 1)
        if task and task.action then
          pcall(task.action, unpack(task.args, 1, task.args.n or 0))
        end
      end

      cb:refreshFileManagerInstance()

      -- Test initGrid
      local mock_menu_grid = {}
      CoverBrowser.initGrid(mock_menu_grid, "mosaic_image")
      assert.are_equal("mosaic", mock_menu_grid.display_mode_type)
      assert.is_number(mock_menu_grid.nb_cols_portrait)

      CoverBrowser.initGrid(mock_menu_grid, "list_only_meta")
      assert.are_equal("list", mock_menu_grid.display_mode_type)

      CoverBrowser.initGrid(nil, "mosaic_image") -- nil safe

      UIManager.show = orig_show
    end)
  end)
end)

