describe("Readerpaging module", function()
  local sample_pdf = "spec/front/unit/data/sample.pdf"
  local readerui, UIManager, Event, DocumentRegistry, ReaderUI, Screen
  local paging

  setup(function()
    require("commonrequire")
    UIManager = require("ui/uimanager")
    stub(UIManager, "getNthTopWidget")
    UIManager.getNthTopWidget.returns({})
    Event = require("ui/event")
    DocumentRegistry = require("document/documentregistry")
    ReaderUI = require("apps/reader/readerui")
    Screen = require("device").screen
  end)

  teardown(function()
    UIManager.getNthTopWidget:revert()
  end)

  describe("Page mode", function()
    setup(function()
      readerui = ReaderUI:new({
        dimen = Screen:getSize(),
        document = DocumentRegistry:openDocument(sample_pdf),
      })
      paging = readerui.paging
    end)
    teardown(function()
      readerui:onExit()
      readerui:onClose()
    end)

    it("should calculate progress and percent correctly", function()
      paging.view.page_scroll = false
      paging.current_page = 5
      paging.number_of_pages = 10
      assert.equals(5, paging:getLastProgress())
      assert.equals(0.5, paging:getLastPercent())

      paging.current_page = 0
      assert.is_nil(paging:getLastPercent())
      paging.current_page = 1
      paging.number_of_pages = readerui.document.info.number_of_pages
    end)

    it("should set and get page position", function()
      paging.page_positions = {}
      paging:setPagePosition(2, 0.5)
      assert.equals(0.5, paging:getPagePosition(2))
      paging:setPagePosition(2, 0)
      assert.equals(0, paging:getPagePosition(2))
      assert.equals(0, paging:getPagePosition(99))
    end)

    it("should handle percent navigation", function()
      paging:onGotoPage(1)
      paging:onGotoPercent(50)
      assert.equals(
        math.floor(paging.number_of_pages * 0.5),
        paging.current_page
      )

      paging:onGotoPercent(-10)
      assert.equals(1, paging.current_page)

      paging:onGotoPercent(500)
      assert.equals(paging.number_of_pages, paging.current_page)

      paging:onGotoPercentage(0.2)
      assert.equals(
        math.floor(0.2 * paging.number_of_pages),
        paging.current_page
      )

      paging:onGotoPercentage(-0.5)
      assert.equals(1, paging.current_page)

      paging:onGotoPercentage(1.5)
      assert.equals(paging.number_of_pages, paging.current_page)
    end)

    it("should toggle page and bookmark flipping modes", function()
      assert.is_false(paging.page_flipping_mode)
      paging:onTogglePageFlipping()
      assert.is_true(paging.page_flipping_mode)
      paging:onTogglePageFlipping()
      assert.is_false(paging.page_flipping_mode)

      assert.is_false(paging.bookmark_flipping_mode)
      paging:onToggleBookmarkFlipping()
      assert.is_true(paging.bookmark_flipping_mode)
      paging:onToggleBookmarkFlipping()
      assert.is_false(paging.bookmark_flipping_mode)
    end)

    it("should enter and exit skim mode", function()
      paging.skim_backup = nil
      paging:enterSkimMode()
      assert.is_not_nil(paging.skim_backup)
      paging:exitSkimMode()
      assert.is_nil(paging.skim_backup)
    end)

    it("should handle scroll settings updates", function()
      paging:onScrollSettingsUpdated("classic", true, 100)
      assert.equals("classic", paging.scroll_method)

      paging:onScrollSettingsUpdated("turbo", false, 50)
      assert.equals("turbo", paging.scroll_method)
    end)

    it("should update rotation and gamma for scroll page states", function()
      local orig_states = readerui.view.page_states
      readerui.view.page_states = {
        { rotation = 0, gamma = 1.0 },
        { rotation = 0, gamma = 1.0 },
      }
      paging:onUpdateScrollPageRotation(90)
      assert.equals(90, readerui.view.page_states[1].rotation)
      assert.equals(90, readerui.view.page_states[2].rotation)

      paging:onUpdateScrollPageGamma(1.5)
      assert.equals(1.5, readerui.view.page_states[1].gamma)
      assert.equals(1.5, readerui.view.page_states[2].gamma)
      readerui.view.page_states = orig_states
    end)

    it("should handle reflow and redraw events", function()
      assert.is_true(paging:onRedrawCurrentPage())

      local orig_wrap = readerui.view.document.configurable.text_wrap
      paging:onToggleReflow()
      assert.is_not.equals(
        orig_wrap,
        readerui.view.document.configurable.text_wrap
      )
      paging:onToggleReflow()
      assert.equals(orig_wrap, readerui.view.document.configurable.text_wrap)
    end)

    it("should get and restore book location", function()
      paging:onGotoPage(2)
      local loc = paging:getBookLocation()
      assert.is_not_nil(loc)
      assert.is_true(paging:onRestoreBookLocation(loc))
    end)

    it("should handle relative page navigation", function()
      paging:onGotoPage(1)
      paging:onGotoRelativePage(1)
      assert.equals(2, paging.current_page)
      paging:onGotoRelativePage(-1)
      assert.equals(1, paging.current_page)
    end)

    it("should handle chapter navigation when TOC is available", function()
      local orig_toc = readerui.toc
      local orig_link = readerui.link
      readerui.toc = {
        getNextChapter = function(self, page)
          return page + 1
        end,
        getPreviousChapter = function(self, page)
          return page - 1 > 0 and page - 1 or nil
        end,
      }
      readerui.link = {
        addCurrentLocationToStack = function() end,
      }
      paging:onGotoPage(1)
      assert.is_true(paging:onGotoNextChapter())
      assert.equals(2, paging.current_page)

      assert.is_true(paging:onGotoPrevChapter())
      assert.equals(1, paging.current_page)
      readerui.toc = orig_toc
      readerui.link = orig_link
    end)

    it("should handle save and read settings", function()
      local MockConfig = {
        data = {
          page_positions = {},
          last_page = 3,
          flipping_zoom_mode = "fit",
          flipping_scroll_mode = true,
        },
        readTableRef = function(self, key)
          return self.data[key]
        end,
        read = function(self, key)
          return self.data[key]
        end,
        isTrue = function(self, key)
          return self.data[key] == true
        end,
      }
      paging:onReadSettings(MockConfig)
      assert.equals(3, paging.current_page)
      assert.equals("fit", paging.flipping_zoom_mode)
      assert.is_true(paging.flipping_scroll_mode)

      local saved = {}
      local orig_doc_settings = readerui.doc_settings
      readerui.doc_settings = {
        save = function(self, key, val)
          saved[key] = val
        end,
      }
      paging:onSaveSettings()
      readerui.doc_settings = orig_doc_settings
      assert.equals(3, saved["last_page"])
      assert.equals(3 / paging.number_of_pages, saved["percent_finished"])
      assert.equals("fit", saved["flipping_zoom_mode"])
      assert.is_true(saved["flipping_scroll_mode"])
    end)

    it("should handle view recalculate, zoom mode, and page updates", function()
      paging:onZoomModeUpdate("pageheight")
      assert.equals("pageheight", paging.zoom_mode)

      local Geom = require("ui/geometry")
      local v_area = Geom:new({ x = 0, y = 0, w = 100, h = 100 })
      local p_area = Geom:new({ x = 0, y = 0, w = 100, h = 200 })
      paging:onViewRecalculate(v_area, p_area)
      assert.equals(100, paging.visible_area.w)
      assert.equals(200, paging.page_area.h)

      paging:onPageUpdate(4, "page")
      assert.equals(4, paging.current_page)
    end)

    it("should handle gesture release and swipe", function()
      paging._pan_started = true
      paging._pan_has_scrolled = true
      paging._pan_page_states_to_restore = readerui.view.page_states
      assert.is_true(paging:onHandledAsSwipe())
      assert.is_false(paging._pan_started)

      paging._pan_has_scrolled = false
      local ges = { direction = "west" }
      assert.is_true(paging:onSwipe(nil, ges))
    end)

    it("should emit EndOfBook event at the end", function()
      UIManager:quit()
      UIManager:show(readerui)
      local called = false
      UIManager:nextTick(function()
        readerui:handleEvent(Event:new("SetScrollMode", false))
        readerui.zooming:setZoomMode("pageheight")
        paging:onGotoPage(readerui.document:getPageCount())
        readerui.onEndOfBook = function()
          called = true
        end
        paging:onGotoViewRel(1)
        local dialog = UIManager._window_stack[#UIManager._window_stack].widget
        if dialog.name == "end_document" then
          UIManager:close(dialog)
        end
        UIManager:close(readerui)
        -- We haven't torn it down yet
        ReaderUI.instance = readerui
      end)
      UIManager:run()
      assert.is.truthy(called)
      readerui.onEndOfBook = nil
      UIManager:quit()
    end)
  end)

  describe("Scroll mode", function()
    setup(function()
      local purgeDir = require("ffi/util").purgeDir
      local DocSettings = require("docsettings")
      purgeDir(DocSettings:getSidecarDir(sample_pdf))
      os.remove(DocSettings:getHistoryPath(sample_pdf))

      readerui = ReaderUI:new({
        dimen = Screen:getSize(),
        document = DocumentRegistry:openDocument(sample_pdf),
      })
      paging = readerui.paging
    end)
    teardown(function()
      readerui:onExit()
      readerui:onClose()
    end)

    it("should emit EndOfBook event at the end", function()
      UIManager:quit()
      UIManager:show(readerui)
      local called = false
      UIManager:nextTick(function()
        paging.page_positions = {}
        readerui:handleEvent(Event:new("SetScrollMode", true))
        paging:onGotoPage(readerui.document:getPageCount())
        readerui.zooming:setZoomMode("pageheight", true)
        readerui.onEndOfBook = function()
          called = true
        end
        paging:onGotoViewRel(1)
        paging:onGotoViewRel(1)
        local dialog = UIManager._window_stack[#UIManager._window_stack].widget
        if dialog.name == "end_document" then
          UIManager:close(dialog)
        end
        UIManager:close(readerui)
        -- We haven't torn it down yet
        ReaderUI.instance = readerui
      end)
      UIManager:run()
      assert.is.truthy(called)
      readerui.onEndOfBook = nil
      UIManager:quit()
    end)

    it("should scroll backward on the first page without crash", function()
      local sample_djvu = "spec/front/unit/data/djvu3spec.djvu"
      -- Unsafe second // ReaderUI instance!
      ReaderUI.instance = nil
      local tmp_readerui = ReaderUI:new({
        dimen = Screen:getSize(),
        document = DocumentRegistry:openDocument(sample_djvu),
      })
      tmp_readerui.paging:onScrollPanRel(-100)
      tmp_readerui:onExit()
      tmp_readerui:onClose()
      -- Restore the ref to the original ReaderUI instance
      ReaderUI.instance = readerui
    end)

    it("should scroll forward on the last page without crash", function()
      local sample_djvu = "spec/front/unit/data/djvu3spec.djvu"
      -- Unsafe second // ReaderUI instance!
      ReaderUI.instance = nil
      local tmp_readerui = ReaderUI:new({
        dimen = Screen:getSize(),
        document = DocumentRegistry:openDocument(sample_djvu),
      })
      paging = tmp_readerui.paging
      paging:onGotoPage(tmp_readerui.document:getPageCount())
      paging:onScrollPanRel(120)
      paging:onScrollPanRel(-1)
      paging:onScrollPanRel(120)
      tmp_readerui:onExit()
      tmp_readerui:onClose()
      -- Restore the ref to the original ReaderUI instance
      ReaderUI.instance = readerui
    end)
  end)
end)
