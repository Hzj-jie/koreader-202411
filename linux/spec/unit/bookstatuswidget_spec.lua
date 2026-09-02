describe("BookStatusWidget widget module", function()
  local BookStatusWidget, Device, DocSettings, FileManagerBookInfo, Geom, RenderImage, UIManager

  setup(function()
    require("commonrequire")
    DocSettings = require("docsettings")
    stub(DocSettings, "findCustomCoverFile")
    BookStatusWidget = require("ui/widget/bookstatuswidget")
    Device = require("device")
    FileManagerBookInfo = require("apps/filemanager/filemanagerbookinfo")
    Geom = require("ui/geometry")
    RenderImage = require("ui/renderimage")
    UIManager = require("ui/uimanager")
  end)

  teardown(function()
    if DocSettings.findCustomCoverFile.revert then
      DocSettings.findCustomCoverFile:revert()
    end
  end)

  local function createMockUI(summary_data, page_count, current_page)
    local summary = summary_data or { rating = 4, status = "reading", note = "Great book" }
    local flushed = false
    local mock_ui = {
      document = {
        getProps = function()
          return { title = "Test Title", authors = "Test Author" }
        end,
        getPageCount = function()
          return page_count or 100
        end,
        getCoverPageImage = function()
          return nil
        end,
      },
      doc_props = {
        display_title = "Test Title",
        authors = "Test Author",
        language = "en",
      },
      doc_settings = {
        data = { doc_path = "/tmp/test.epub" },
        save = function() end,
        flush = function()
          flushed = true
        end,
        readSetting = function()
          return nil
        end,
        readTableRef = function(self, key)
          if key == "summary" then
            return summary
          end
          return nil
        end,
      },
      getCurrentPage = function()
        return current_page or 10
      end,
    }
    return mock_ui, function() return flushed end
  end

  it("should initialize BookStatusWidget in portrait mode with touch events", function()
    local mock_ui = createMockUI()
    local widget = BookStatusWidget:new({
      ui = mock_ui,
    })
    assert.is_table(widget)
    assert.is_table(widget.summary)
    assert.are.equal(4, widget.summary.rating)
    assert.are.equal(100, widget.total_pages)
    assert.is_true(widget.dithered)
    assert.is_not_nil(widget.star)
    assert.is_not_nil(widget.ges_events.Swipe)
    assert.is_not_nil(widget.ges_events.MultiSwipe)
    assert.is_not_nil(widget[1])
  end)

  it("should initialize BookStatusWidget in landscape mode and readonly mode", function()
    local mock_ui = createMockUI()
    local old_getMode = Device.screen.getScreenMode
    Device.screen.getScreenMode = function() return "landscape" end

    local widget = BookStatusWidget:new({
      ui = mock_ui,
      readonly = true,
    })
    assert.is_table(widget)
    assert.is_true(widget.readonly)
    assert.is_not_nil(widget.star)
    assert.is_false(widget.star.enabled)
    assert.is_true(widget.star.readonly)

    Device.screen.getScreenMode = old_getMode
  end)

  it("should handle cover image thumbnail scaling when cover image is available", function()
    local mock_ui = createMockUI()
    local mock_bb = {
      getWidth = function() return 500 end,
      getHeight = function() return 800 end,
    }
    local scaled_bb = {
      getWidth = function() return 132 end,
      getHeight = function() return 184 end,
    }
    local old_getCover = FileManagerBookInfo.getCoverImage
    local old_scale = RenderImage.scaleBlitBuffer
    FileManagerBookInfo.getCoverImage = function() return mock_bb end
    RenderImage.scaleBlitBuffer = function() return scaled_bb end

    local widget = BookStatusWidget:new({
      ui = mock_ui,
    })
    assert.is_table(widget)

    FileManagerBookInfo.getCoverImage = old_getCover
    RenderImage.scaleBlitBuffer = old_scale
  end)

  it("should handle statistics getters with default empty stats", function()
    local mock_ui = createMockUI()
    local widget = BookStatusWidget:new({
      ui = mock_ui,
    })
    assert.is_table(widget:getStats())
    assert.are.equal("N/A", widget:getStatDays())
    assert.are.equal("N/A", widget:getStatHours())
    assert.are.equal("N/A", widget:getStatReadPages())
  end)

  it("should handle rating interaction and setStar", function()
    local mock_ui = createMockUI({ rating = 2, status = "reading" })
    local widget = BookStatusWidget:new({
      ui = mock_ui,
    })

    assert.are.equal(2, widget.summary.rating)
    assert.are.equal(5, #widget.layout[1])

    -- Click star 5
    local star5 = widget.layout[1][5]
    star5.callback()
    assert.are.equal(5, widget.summary.rating)
    assert.is_true(widget.updated)

    -- Test setStar(nil)
    widget:setStar(nil)
    assert.are.equal(5, #widget.layout[1])
  end)

  it("should handle onChangeBookStatus and onConfigChoose", function()
    local mock_ui = createMockUI()
    local widget = BookStatusWidget:new({
      ui = mock_ui,
    })

    local tick_cb = nil
    local old_tick = UIManager.tickAfterNext
    UIManager.tickAfterNext = function(self, cb)
      tick_cb = cb
    end

    widget:onConfigChoose(nil, nil, nil, { "reading", "abandoned", "complete" }, 3)
    assert.is_function(tick_cb)

    local dirty_called = false
    local old_setDirty = UIManager.setDirty
    UIManager.setDirty = function(self, widget_target, mode)
      dirty_called = true
    end

    tick_cb()
    assert.are.equal("complete", widget.summary.status)
    assert.is_not_nil(widget.summary.modified)
    assert.is_true(widget.updated)
    assert.is_true(dirty_called)

    UIManager.tickAfterNext = old_tick
    UIManager.setDirty = old_setDirty
  end)

  it("should handle onSwipe gestures", function()
    local mock_ui = createMockUI()
    local widget = BookStatusWidget:new({
      ui = mock_ui,
    })

    -- Directions east, west, north should return false
    assert.is_false(widget:onSwipe(nil, { direction = "east" }))
    assert.is_false(widget:onSwipe(nil, { direction = "west" }))
    assert.is_false(widget:onSwipe(nil, { direction = "north" }))

    -- Diagonal swipe should trigger full refresh and return false
    local dirty_mode = nil
    local old_setDirty = UIManager.setDirty
    UIManager.setDirty = function(self, target, mode)
      dirty_mode = mode
    end
    assert.is_false(widget:onSwipe(nil, { direction = "northeast" }))
    assert.are.equal("full", dirty_mode)
    UIManager.setDirty = old_setDirty

    -- Swipe south should trigger onExit
    local closed_widget = nil
    local old_close = UIManager.close
    UIManager.close = function(self, w)
      closed_widget = w
    end
    assert.is_true(widget:onSwipe(nil, { direction = "south" }))
    assert.are.equal(widget, closed_widget)
    UIManager.close = old_close
  end)

  it("should handle onMultiSwipe", function()
    local mock_ui = createMockUI()
    local widget = BookStatusWidget:new({
      ui = mock_ui,
    })

    local closed_widget = nil
    local old_close = UIManager.close
    UIManager.close = function(self, w)
      closed_widget = w
    end

    assert.is_true(widget:onMultiSwipe(nil, {}))
    assert.are.equal(widget, closed_widget)
    UIManager.close = old_close
  end)

  it("should handle onExit and flush settings when updated", function()
    local mock_ui, is_flushed = createMockUI()
    local widget = BookStatusWidget:new({
      ui = mock_ui,
    })

    local closed_widget, closed_mode
    local old_close = UIManager.close
    UIManager.close = function(self, w, mode)
      closed_widget = w
      closed_mode = mode
    end

    widget.updated = true
    local res = widget:onExit()
    assert.is_true(res)
    assert.is_true(is_flushed())
    assert.are.equal(widget, closed_widget)
    assert.are.equal("flashpartial", closed_mode)

    UIManager.close = old_close
  end)

  it("should handle onSwitchFocus and review InputDialog callbacks", function()
    local mock_ui = createMockUI({ rating = 3, status = "reading", note = "Old note" })
    local widget = BookStatusWidget:new({
      ui = mock_ui,
    })

    local shown_widget = nil
    widget.showWidget = function(self, w)
      shown_widget = w
    end

    widget:onSwitchFocus()
    assert.is_not_nil(widget.note_dialog)
    assert.are.equal(widget.note_dialog, shown_widget)

    local buttons = widget.note_dialog.buttons[1]
    local cancel_btn = buttons[1]
    local save_btn = buttons[2]

    local closed_widget = nil
    local old_close = UIManager.close
    UIManager.close = function(self, w)
      closed_widget = w
    end

    -- Test cancel button
    cancel_btn.callback()
    assert.are.equal(widget.note_dialog, closed_widget)

    -- Test save button
    widget.note_dialog.getInputText = function() return "Updated review note" end
    save_btn.callback()
    assert.are.equal("Updated review note", widget.summary.note)
    assert.are.equal("Updated review note", widget.input_note:getText())
    assert.is_true(widget.updated)

    UIManager.close = old_close
  end)
end)
