describe("CoverMenu plugin base module", function()
  local CoverMenu, DocSettings, UIManager, BookInfoManager

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    DocSettings = require("docsettings")
    UIManager = require("ui/uimanager")
    BookInfoManager = require("plugins/coverbrowser.koplugin/bookinfomanager")
    CoverMenu = require("plugins/coverbrowser.koplugin/covermenu")
  end)

  describe("updateCache", function()
    it(
      "should update cover info cache entries and handle doc settings",
      function()
        local obj = {
          cover_info_cache = {},
        }

        -- Stub DocSettings:open
        local old_open = DocSettings.open
        local mock_doc_settings = {
          read = function(self, key)
            if key == "doc_pages" then
              return 250
            elseif key == "percent_finished" then
              return 0.5
            end
          end,
          readTable = function(self, key)
            return { pages = 100 }
          end,
          readTableRef = function(self, key)
            if key == "summary" then
              return { status = "reading" }
            elseif key == "annotations" then
              return { { text = "note" } }
            elseif key == "highlight" then
              return {}
            end
            return {}
          end,
        }
        DocSettings.open = function()
          return mock_doc_settings
        end

        -- 1. Create with doc_pages
        CoverMenu.updateCache(obj, "test.epub", nil, true)
        assert.is_table(obj.cover_info_cache["test.epub"])
        assert.are.equal(250, obj.cover_info_cache["test.epub"][1])
        assert.are.equal(0.5, obj.cover_info_cache["test.epub"][2])
        assert.are.equal("reading", obj.cover_info_cache["test.epub"][3])
        assert.is_true(obj.cover_info_cache["test.epub"][4])

        -- 2. Fallback to stats.pages when doc_pages is nil
        mock_doc_settings.read = function(self, key)
          if key == "percent_finished" then
            return 0.2
          end
        end
        CoverMenu.updateCache(obj, "test_stats.epub", nil, true)
        assert.are.equal(100, obj.cover_info_cache["test_stats.epub"][1])

        -- 3. Modify existing cache status
        CoverMenu.updateCache(obj, "test.epub", "finished", false)
        assert.are.equal("finished", obj.cover_info_cache["test.epub"][3])

        -- 4. Delete cache entry
        CoverMenu.updateCache(obj, "test.epub", nil, false)
        assert.is_nil(obj.cover_info_cache["test.epub"])

        DocSettings.open = old_open
      end
    )
  end)

  describe("updateItems & background extraction", function()
    it("should schedule background extraction and poll item updates", function()
      local menu = {
        cover_info_cache = {},
        dimen = require("ui/geometry"):new({ x = 0, y = 0, w = 600, h = 800 }),
        layout = {},
        item_group = { clear = function() end, free = function() end },
        page_info = { resetLayout = function() end },
        return_button = { resetLayout = function() end },
        content_group = { resetLayout = function() end },
        _recalculateDimen = function() end,
        _updateItemsBuildUI = function(self)
          self.items_to_update = {
            {
              filepath = "book1.epub",
              cover_specs = {},
              text = "Book 1",
              bookinfo_found = true,
              _has_cover_image = true,
              refresh_dimen = require("ui/geometry"):new({
                x = 0,
                y = 0,
                w = 100,
                h = 100,
              }),
              update = function() end,
            },
            {
              filepath = "book2.epub",
              cover_specs = {},
              text = "Book 2",
              bookinfo_found = false,
              update = function() end,
            },
          }
          return 1
        end,
        updatePageInfo = function() end,
        showParent = function(self)
          return self.parent
        end,
        parent = { dithered = false },
      }

      local old_extract = BookInfoManager.extractInBackground
      local old_is_extracting = BookInfoManager.isExtractingInBackground
      local old_nextTick = UIManager.nextTick
      local old_scheduleIn = UIManager.scheduleIn
      local old_setDirty = UIManager.setDirty
      local scheduled_action

      BookInfoManager.extractInBackground = function(self, files)
        return true
      end
      BookInfoManager.isExtractingInBackground = function()
        return true
      end
      UIManager.nextTick = function(self, fn)
        fn()
      end
      UIManager.scheduleIn = function(self, delay, fn)
        scheduled_action = fn
      end
      UIManager.setDirty = function() end

      CoverMenu.updateItems(menu, 1, false)
      assert.is_not_nil(scheduled_action)

      -- Run scheduled polling action
      scheduled_action()
      -- book1 was found and removed, book2 remains
      assert.are.equal(1, #menu.items_to_update)
      assert.are.equal("book2.epub", menu.items_to_update[1].filepath)

      BookInfoManager.extractInBackground = old_extract
      BookInfoManager.isExtractingInBackground = old_is_extracting
      UIManager.nextTick = old_nextTick
      UIManager.scheduleIn = old_scheduleIn
    end)

    it(
      "should handle fork failure when extractInBackground returns false",
      function()
        local menu = {
          cover_info_cache = {},
          dimen = require("ui/geometry"):new({ x = 0, y = 0, w = 600, h = 800 }),
          layout = {},
          item_group = { clear = function() end, free = function() end },
          page_info = { resetLayout = function() end },
          return_button = { resetLayout = function() end },
          content_group = { resetLayout = function() end },
          _recalculateDimen = function() end,
          _updateItemsBuildUI = function(self)
            self.items_to_update = {
              { filepath = "book1.epub", cover_specs = {} },
            }
          end,
          updatePageInfo = function() end,
          showParent = function() end,
        }

        local shown_info
        local old_show = UIManager.show
        UIManager.show = function(self, widget)
          shown_info = widget
        end
        local old_extract = BookInfoManager.extractInBackground
        BookInfoManager.extractInBackground = function()
          return false
        end
        local tick_cb
        local old_nextTick = UIManager.nextTick
        UIManager.nextTick = function(self, fn)
          tick_cb = fn
        end

        CoverMenu.updateItems(menu, 1, false)
        assert.is_function(tick_cb)
        tick_cb()

        assert.is_not_nil(shown_info)
        assert.is_nil(menu.items_update_action)

        UIManager.show = old_show
        BookInfoManager.extractInBackground = old_extract
        UIManager.nextTick = old_nextTick
      end
    )
  end)

  describe("Menu Dialog Extensions", function()
    it(
      "should replace showFileDialog and add ignore cover and metadata buttons",
      function()
        local menu = {
          path = "/books",
          cover_info_cache = {},
          dimen = require("ui/geometry"):new({ x = 0, y = 0, w = 600, h = 800 }),
          layout = {},
          item_group = { clear = function() end, free = function() end },
          page_info = { resetLayout = function() end },
          return_button = { resetLayout = function() end },
          content_group = { resetLayout = function() end },
          _recalculateDimen = function() end,
          _updateItemsBuildUI = function() end,
          updatePageInfo = function() end,
          showParent = function() end,
          updateItems = function() end,
          updateCache = function() end,
          showFileDialog = function(self, item)
            self.file_dialog = {
              title = "Book Dialog",
              title_align = "left",
              buttons = {},
            }
          end,
        }

        local old_nextTick = UIManager.nextTick
        local old_close = UIManager.close
        local old_show = UIManager.show
        local shown_dialog

        UIManager.nextTick = function(self, fn)
          fn()
        end
        UIManager.close = function() end
        UIManager.show = function(self, dialog)
          shown_dialog = dialog
        end

        CoverMenu.updateItems(menu, 1, false)
        assert.is_function(menu.showFileDialog)

        -- Trigger showFileDialog
        menu.book_props = {
          has_cover = true,
          has_meta = true,
          ignore_cover = false,
          ignore_meta = false,
        }
        menu:showFileDialog({ path = "/books/book1.epub" })

        assert.is_not_nil(shown_dialog)
        assert.are.equal(2, #shown_dialog.buttons)
        assert.are.equal("Ignore cover", shown_dialog.buttons[1][1].text)
        assert.are.equal("Ignore metadata", shown_dialog.buttons[1][2].text)
        assert.are.equal(
          "Refresh cached book information",
          shown_dialog.buttons[2][1].text
        )

        UIManager.nextTick = old_nextTick
        UIManager.close = old_close
        UIManager.show = old_show
      end
    )

    it("should extend onHistoryMenuHold and onCollectionsMenuHold", function()
      local menu = {
        cover_info_cache = {},
        onMenuHold_orig = function(self, item)
          self.histfile_dialog = {
            title = "History Dialog",
            title_align = "left",
            buttons = {},
          }
          self.collfile_dialog = {
            title = "Collection Dialog",
            title_align = "left",
            buttons = {},
          }
        end,
        updateItems = function() end,
        updateCache = function() end,
        book_props = {
          has_cover = true,
          has_meta = true,
          ignore_cover = true,
          ignore_meta = true,
        },
      }

      local old_close = UIManager.close
      local old_show = UIManager.show
      local shown_dialog
      UIManager.close = function() end
      UIManager.show = function(self, d)
        shown_dialog = d
      end

      -- History hold
      CoverMenu.onHistoryMenuHold(menu, { file = "/books/book1.epub" })
      assert.is_not_nil(shown_dialog)
      assert.are.equal("Unignore cover", shown_dialog.buttons[1][1].text)
      assert.are.equal("Unignore metadata", shown_dialog.buttons[1][2].text)

      -- Collection hold
      shown_dialog = nil
      CoverMenu.onCollectionsMenuHold(menu, { file = "/books/book1.epub" })
      assert.is_not_nil(shown_dialog)
      assert.are.equal("Unignore cover", shown_dialog.buttons[1][1].text)
      assert.are.equal("Unignore metadata", shown_dialog.buttons[1][2].text)

      UIManager.close = old_close
      UIManager.show = old_show
    end)
  end)

  describe("onClose & tapPlus", function()
    it("should manage onClose cleanup idempotently", function()
      local freed = false
      local menu = {
        cover_info_cache = { ["book.epub"] = {} },
        items_update_action = function() end,
        item_group = {
          free = function()
            freed = true
          end,
        },
      }

      local unscheduled = false
      local old_unsched = UIManager.unschedule
      local old_schedIn = UIManager.scheduleIn
      UIManager.unschedule = function()
        unscheduled = true
      end
      UIManager.scheduleIn = function() end

      local term_called = false
      local old_term = BookInfoManager.terminateBackgroundJobs
      BookInfoManager.terminateBackgroundJobs = function()
        term_called = true
      end

      CoverMenu.onClose(menu)
      assert.is_true(menu._covermenu_onclose_done)
      assert.is_true(term_called)
      assert.is_true(unscheduled)
      assert.is_true(freed)
      assert.is_nil(menu.cover_info_cache)
      assert.is_nil(menu.items_update_action)

      -- Second call is no-op
      term_called = false
      CoverMenu.onClose(menu)
      assert.is_false(term_called)

      BookInfoManager.terminateBackgroundJobs = old_term
      UIManager.unschedule = old_unsched
      UIManager.scheduleIn = old_schedIn
    end)

    it("should extend tapPlus with extract and cache action", function()
      local menu = {
        file_dialog = {
          select_mode = false,
          title = "Plus Dialog",
          title_align = "left",
          buttons = {},
        },
      }

      CoverMenu._FileManager_tapPlus_orig = function(self) end
      local shown_dialog
      local old_show = UIManager.show
      local old_close = UIManager.close
      UIManager.show = function(self, d)
        shown_dialog = d
      end
      UIManager.close = function() end

      CoverMenu.tapPlus(menu)
      assert.is_not_nil(shown_dialog)
      assert.are.equal(2, #shown_dialog.buttons)
      assert.are.equal(
        "Extract and cache book information",
        shown_dialog.buttons[2][1].text
      )

      -- Select mode does not modify
      menu.file_dialog.select_mode = true
      shown_dialog = nil
      CoverMenu.tapPlus(menu)
      assert.is_nil(shown_dialog)

      UIManager.show = old_show
      UIManager.close = old_close
    end)
  end)
end)
