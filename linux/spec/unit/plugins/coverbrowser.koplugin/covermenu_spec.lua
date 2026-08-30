describe("Coverbrowser CoverMenu module", function()
  local CoverMenu, BookInfoManager, UIManager

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    UIManager = require("ui/uimanager")
    BookInfoManager = require("plugins/coverbrowser.koplugin/bookinfomanager")
    BookInfoManager:init()
    CoverMenu = require("plugins/coverbrowser.koplugin/covermenu")
  end)

  after_each(function()
    UIManager._task_queue = {}
    UIManager._next_tick_tasks = {}
    while UIManager._window_stack and #UIManager._window_stack > 0 do
      local win = UIManager._window_stack[#UIManager._window_stack]
      if win and win.widget then
        UIManager:close(win.widget)
      else
        table.remove(UIManager._window_stack)
      end
    end
  end)

  describe("Initialization & Cache Management", function()
    it("should expose CoverMenu helper methods table", function()
      assert.is_table(CoverMenu)
      assert.is_function(CoverMenu.updateCache)
      assert.is_function(CoverMenu.updateItems)
      assert.is_function(CoverMenu.onClose)
    end)

    it("should update cover_info_cache correctly", function()
      local mock_menu = {
        cover_info_cache = {},
      }
      setmetatable(mock_menu, { __index = CoverMenu })

      -- Create entry for a file
      mock_menu:updateCache("/tmp/test.epub", "reading", true, 200)
      assert.is_table(mock_menu.cover_info_cache["/tmp/test.epub"])

      -- Update status
      mock_menu:updateCache("/tmp/test.epub", "complete")
      assert.are_equal("complete", mock_menu.cover_info_cache["/tmp/test.epub"][3])

      -- Remove status/cache
      mock_menu:updateCache("/tmp/test.epub", nil)
      assert.is_nil(mock_menu.cover_info_cache["/tmp/test.epub"])
    end)
  end)

  describe("Lifecycle and Event Handlers", function()
    it("should execute onClose cleanup gracefully", function()
      local mock_menu = {
        item_group = {
          free = function() end,
        },
        cover_info_cache = { ["/tmp/test"] = {} },
        items_update_action = function() end,
      }
      setmetatable(mock_menu, { __index = CoverMenu })

      mock_menu:onClose()
      assert.is_true(mock_menu._covermenu_onclose_done)
      assert.is_nil(mock_menu.cover_info_cache)
      assert.is_nil(mock_menu.items_update_action)

      -- Calling onClose a second time should be a no-op
      mock_menu:onClose()
    end)

    it("should handle onHistoryMenuHold and onCollectionsMenuHold button population", function()
      local ButtonDialog = require("ui/widget/buttondialog")
      local mock_hist = {
        book_props = {
          has_cover = true,
          has_meta = true,
          ignore_cover = false,
          ignore_meta = false,
        },
        histfile_dialog = ButtonDialog:new({
          title = "Book Dialog",
          width = 400,
          buttons = { { { text = "Dummy", callback = function() end } } },
        }),
        onMenuHold_orig = function() end,
        updateItems = function() end,
        updateCache = function() end,
      }
      setmetatable(mock_hist, { __index = CoverMenu })
      UIManager:show(mock_hist.histfile_dialog)

      mock_hist:onHistoryMenuHold({ file = "/tmp/test.epub" })
      assert.is_table(mock_hist.histfile_dialog)
      assert.is_true(#mock_hist.histfile_dialog.buttons >= 2)

      -- Trigger buttons callbacks
      for _, row in ipairs(mock_hist.histfile_dialog.buttons) do
        for _, btn in ipairs(row) do
          if btn.callback then
            pcall(btn.callback)
          end
        end
      end
      UIManager:closeIfShown(mock_hist.histfile_dialog)

      local mock_coll = {
        book_props = {
          has_cover = true,
          has_meta = true,
          ignore_cover = true,
          ignore_meta = true,
        },
        collfile_dialog = ButtonDialog:new({
          title = "Collection Dialog",
          width = 400,
          buttons = { { { text = "Dummy", callback = function() end } } },
        }),
        onMenuHold_orig = function() end,
        updateItems = function() end,
        updateCache = function() end,
      }
      setmetatable(mock_coll, { __index = CoverMenu })
      UIManager:show(mock_coll.collfile_dialog)

      mock_coll:onCollectionsMenuHold({ file = "/tmp/test.epub" })
      assert.is_table(mock_coll.collfile_dialog)
      assert.is_true(#mock_coll.collfile_dialog.buttons >= 2)

      for _, row in ipairs(mock_coll.collfile_dialog.buttons) do
        for _, btn in ipairs(row) do
          if btn.callback then
            pcall(btn.callback)
          end
        end
      end
      UIManager:closeIfShown(mock_coll.collfile_dialog)
    end)

    it("should handle tapPlus with extra extraction button", function()
      local ButtonDialog = require("ui/widget/buttondialog")
      CoverMenu._FileManager_tapPlus_orig = function(self_menu)
        self_menu.file_dialog = ButtonDialog:new({
          title = "Plus Menu",
          width = 400,
          buttons = { { { text = "Dummy", callback = function() end } } },
        })
        UIManager:show(self_menu.file_dialog)
      end

      local mock_fm = {}
      setmetatable(mock_fm, { __index = CoverMenu })
      mock_fm:tapPlus()

      assert.is_table(mock_fm.file_dialog)
      assert.is_true(#mock_fm.file_dialog.buttons >= 2)
      UIManager:closeIfShown(mock_fm.file_dialog)
    end)

    it("should handle updateItems, background extraction scheduling, and garbage collection", function()
      local Geom = require("ui/geometry")
      local extract_stub = stub(BookInfoManager, "extractInBackground", function() return true end)
      local extracting_stub = stub(BookInfoManager, "isExtractingInBackground", function() return false end)

      local mock_item = {
        filepath = "/tmp/bg_book.epub",
        cover_specs = { max_cover_w = 100, max_cover_h = 150 },
        bookinfo_found = false,
        text = "BG Book",
        _has_cover_image = true,
        update = function(self_i)
          self_i.bookinfo_found = true
        end,
        dimen = Geom:new({ x = 0, y = 0, w = 100, h = 150 }),
        [1] = { dimen = Geom:new({ x = 0, y = 0, w = 100, h = 150 }) },
      }

      local mock_menu = {
        dimen = Geom:new({ x = 0, y = 0, w = 600, h = 800 }),
        item_group = { clear = function() end },
        layout = {},
        path = "/tmp",
        page = 1,
        perpage = 10,
        path_items = {},
        page_info = { resetLayout = function() end },
        return_button = { resetLayout = function() end },
        content_group = { resetLayout = function() end },
        updatePageInfo = function() end,
        showParent = function() return nil end,
        _recalculateDimen = function() end,
        _updateItemsBuildUI = function(self_m)
          self_m.items_to_update = { mock_item }
          return 1
        end,
      }
      setmetatable(mock_menu, { __index = CoverMenu })

      -- Run updateItems 6 times to exercise GC trigger and background scheduling
      for _ = 1, 6 do
        mock_menu:updateItems(1)
      end

      -- Execute pending tasks in _task_queue
      while #UIManager._task_queue > 0 do
        local task = table.remove(UIManager._task_queue, 1)
        if task and task.action then
          pcall(task.action, unpack(task.args, 1, task.args.n or 0))
        end
      end

      if mock_menu.items_update_action then
        pcall(mock_menu.items_update_action)
      end

      extract_stub:revert()
      extracting_stub:revert()
    end)

    it("should handle showFileDialog wrapping with ignore metadata and cover options", function()
      local ButtonDialog = require("ui/widget/buttondialog")
      local set_prop_stub = stub(BookInfoManager, "setBookInfoProperties", function() end)
      local delete_stub = stub(BookInfoManager, "deleteBookInfo", function() end)

      local mock_fc = {
        path = "/tmp",
        showFileDialog = function(self_fc, item)
          self_fc.file_dialog = ButtonDialog:new({
            title = "File Options",
            title_align = "center",
            buttons = { { { text = "Open", callback = function() end } } },
          })
          UIManager:show(self_fc.file_dialog)
        end,
        book_props = {
          has_cover = true,
          has_meta = true,
          ignore_cover = false,
          ignore_meta = false,
        },
        updateCache = function() end,
      }
      setmetatable(mock_fc, { __index = CoverMenu })

      -- Call CoverMenu:updateItems which sets up showFileDialog substitution in nextTick
      mock_fc.item_group = { clear = function() end }
      mock_fc.page_info = { resetLayout = function() end }
      mock_fc.return_button = { resetLayout = function() end }
      mock_fc.content_group = { resetLayout = function() end }
      mock_fc.updatePageInfo = function() end
      mock_fc.showParent = function() return nil end
      mock_fc._recalculateDimen = function() end
      mock_fc._updateItemsBuildUI = function() return 1 end

      mock_fc:updateItems(1)

      -- Run nextTick to install showFileDialog_ours
      while #UIManager._task_queue > 0 do
        local task = table.remove(UIManager._task_queue, 1)
        if task and task.action then
          pcall(task.action, unpack(task.args, 1, task.args.n or 0))
        end
      end

      assert.is_function(mock_fc.showFileDialog_ours)

      -- Call showFileDialog on a file item
      mock_fc:showFileDialog({ path = "/tmp/test.epub" })
      assert.is_table(mock_fc.file_dialog)

      -- Execute button callbacks
      for _, row in ipairs(mock_fc.file_dialog.buttons) do
        for _, btn in ipairs(row) do
          if btn.callback then
            pcall(btn.callback)
          end
        end
      end

      UIManager:closeIfShown(mock_fc.file_dialog)
      set_prop_stub:revert()
      delete_stub:revert()
    end)
  end)
end)

