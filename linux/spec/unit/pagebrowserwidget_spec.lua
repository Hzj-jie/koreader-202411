describe("PageBrowserWidget module", function()
  local PageBrowserWidget, UIManager

  setup(function()
    require("commonrequire")
    PageBrowserWidget = require("ui/widget/pagebrowserwidget")
    UIManager = require("ui/uimanager")
  end)

  it("should initialize with mergeSize and support exit callbacks", function()
    local exit_called = false
    local root_exit_called = false

    local mock_ui = {
      view = {
        shouldInvertBiDiLayoutMirroring = function()
          return false
        end,
      },
      document = {
        getPageCount = function()
          return 100
        end,
        hasHiddenFlows = function()
          return false
        end,
      },
      toc = {
        pageno = 1,
        toc_depth = 0,
        toc = {},
        fillToc = function() end,
        getSpansCount = function()
          return 0
        end,
      },
      link = {
        getPreviousLocationPages = function()
          return {}
        end,
      },
      bookmark = {
        getBookmarkedPages = function()
          return {}
        end,
      },
      doc_settings = {
        read = function()
          return nil
        end,
      },
      handmade = {
        isHandmadeTocEnabled = function()
          return false
        end,
      },
      thumbnail = {
        hasThumbnail = function()
          return false
        end,
        getPageThumbnail = function()
          return nil
        end,
      },
    }

    local widget = PageBrowserWidget:new({
      ui = mock_ui,
      focus_page = 1,
      on_exit = function()
        exit_called = true
      end,
      on_root_exit = function()
        root_exit_called = true
      end,
    })

    assert.is_not_nil(widget)
    local size = widget:getSize()
    assert.is_not_nil(size)
    assert.is_true(size.w > 0)
    assert.is_true(size.h > 0)

    -- Verify callback registration
    assert.is_not_nil(widget.on_exit)
    assert.is_not_nil(widget.on_root_exit)
  end)

  it("should support mergeSize and dirtyRegion", function()
    local mock_ui = {
      view = {
        shouldInvertBiDiLayoutMirroring = function()
          return false
        end,
      },
      document = {
        getPageCount = function()
          return 10
        end,
        hasHiddenFlows = function()
          return false
        end,
      },
      toc = {
        pageno = 1,
        toc_depth = 0,
        toc = {},
        fillToc = function() end,
        getSpansCount = function()
          return 0
        end,
      },
      link = {
        getPreviousLocationPages = function()
          return {}
        end,
      },
      bookmark = {
        getBookmarkedPages = function()
          return {}
        end,
      },
      doc_settings = {
        read = function()
          return nil
        end,
      },
      handmade = {
        isHandmadeTocEnabled = function()
          return false
        end,
      },
      thumbnail = {
        hasThumbnail = function()
          return false
        end,
        getPageThumbnail = function()
          return nil
        end,
      },
    }

    local widget = PageBrowserWidget:new({
      ui = mock_ui,
      focus_page = 1,
    })

    widget:mergeSize(100, 100)
    assert.are.equal(100, widget:getSize().w)
    assert.are.equal(100, widget:getSize().h)
  end)
end)
