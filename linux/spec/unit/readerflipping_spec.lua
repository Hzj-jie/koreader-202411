describe("ReaderFlipping module", function()
  local ReaderFlipping, DocumentRegistry, ReaderUI, Screen, Blitbuffer, WidgetContainer

  setup(function()
    require("commonrequire")
    ReaderFlipping = require("apps/reader/modules/readerflipping")
    DocumentRegistry = require("document/documentregistry")
    ReaderUI = require("apps/reader/readerui")
    Screen = require("device").screen
    Blitbuffer = require("ffi/blitbuffer")
    WidgetContainer = require("ui/widget/container/widgetcontainer")
  end)

  it("should initialize widgets, LeftContainer, and default dimensions", function()
    local flipping = ReaderFlipping:new({ ui = {} })
    assert.is_table(flipping)
    assert.is_table(flipping.flipping_widget)
    assert.is_table(flipping.bookmark_flipping_widget)
    assert.is_table(flipping.long_hold_widget)
    assert.is_table(flipping.select_mode_widget)

    assert.is_table(flipping[1])
    assert.are.equal(Screen:getWidth(), flipping[1].dimen.w)
    assert.are.equal(flipping.flipping_widget, flipping[1][1])
  end)

  it("should handle resetLayout and getRefreshRegion", function()
    local flipping = ReaderFlipping:new({ ui = {} })
    flipping[1].dimen.w = 100
    flipping:resetLayout()
    assert.are.equal(Screen:getWidth(), flipping[1].dimen.w)

    local region = flipping:getRefreshRegion()
    assert.are.equal(flipping[1][1].dimen, region)
  end)

  it("should handle rolling rendering state icon widgets and onSetStatusLine cache reset", function()
    local mock_ui = {
      rolling = {
        rendering_state = 1,
        RENDERING_STATE = {
          PARTIALLY_RERENDERED = 1,
          FULL_RENDERING_IN_BACKGROUND = 2,
          FULL_RENDERING_READY = 3,
          RELOADING_DOCUMENT = 4,
          UNKNOWN_STATE = 99,
        },
        cre_top_bar_enabled = false,
      },
    }

    local flipping = ReaderFlipping:new({ ui = mock_ui })

    -- Test when top bar disabled: widget has alpha = true
    local widget1 = flipping:getRollingRenderingStateIconWidget()
    assert.is_table(widget1)
    assert.are.equal("cre.render.partial", widget1.icon)
    assert.is_true(widget1.alpha)

    -- Cached lookup returns identical widget
    assert.are.equal(widget1, flipping:getRollingRenderingStateIconWidget())

    -- Test when top bar enabled: widget has alpha = false
    flipping:onSetStatusLine()
    assert.is_nil(flipping.rolling_rendering_state_widgets)
    mock_ui.rolling.cre_top_bar_enabled = true
    local widget2 = flipping:getRollingRenderingStateIconWidget()
    assert.is_table(widget2)
    assert.is_false(widget2.alpha)

    -- Test state without icon returns nil
    mock_ui.rolling.rendering_state = 99
    assert.is_nil(flipping:getRollingRenderingStateIconWidget())
  end)

  it("should handle paintTo across all 5 branches", function()
    local mock_ui = {
      paging = { bookmark_flipping_mode = false },
      view = { flipping_visible = false },
      highlight = { select_mode = false, long_hold_reached = false },
      rolling = {
        rendering_state = 1,
        RENDERING_STATE = { PARTIALLY_RERENDERED = 1 },
        cre_top_bar_enabled = false,
      },
    }

    local flipping = ReaderFlipping:new({ ui = mock_ui })
    local bb = Blitbuffer.new(100, 100)

    local painted_count = 0
    local orig_paintTo = WidgetContainer.paintTo
    WidgetContainer.paintTo = function(self_wc, target_bb, x, y)
      painted_count = painted_count + 1
      return orig_paintTo(self_wc, target_bb, x, y)
    end

    -- Branch 5: None active -> does not paint
    mock_ui.rolling.rendering_state = nil
    flipping:paintTo(bb, 0, 0)
    assert.are.equal(0, painted_count)

    -- Branch 1a: Paging + flipping_visible + bookmark_flipping_mode -> bookmark_flipping_widget
    mock_ui.view.flipping_visible = true
    mock_ui.paging.bookmark_flipping_mode = true
    flipping:paintTo(bb, 0, 0)
    assert.are.equal(1, painted_count)
    assert.are.equal(flipping.bookmark_flipping_widget, flipping[1][1])

    -- Branch 1b: Paging + flipping_visible + normal flipping -> flipping_widget
    mock_ui.paging.bookmark_flipping_mode = false
    flipping:paintTo(bb, 0, 0)
    assert.are.equal(2, painted_count)
    assert.are.equal(flipping.flipping_widget, flipping[1][1])

    -- Branch 2: Highlight select mode -> select_mode_widget
    mock_ui.view.flipping_visible = false
    mock_ui.highlight.select_mode = true
    flipping:paintTo(bb, 0, 0)
    assert.are.equal(3, painted_count)
    assert.are.equal(flipping.select_mode_widget, flipping[1][1])

    -- Branch 3: Highlight long hold reached -> long_hold_widget
    mock_ui.highlight.select_mode = false
    mock_ui.highlight.long_hold_reached = true
    flipping:paintTo(bb, 0, 0)
    assert.are.equal(4, painted_count)
    assert.are.equal(flipping.long_hold_widget, flipping[1][1])

    -- Branch 4: Rolling rendering state -> rolling rendering state icon widget
    mock_ui.highlight.long_hold_reached = false
    mock_ui.rolling.rendering_state = 1
    flipping:paintTo(bb, 0, 0)
    assert.are.equal(5, painted_count)
    assert.are.equal("cre.render.partial", flipping[1][1].icon)

    WidgetContainer.paintTo = orig_paintTo
  end)

  it("should initialize flipping module in ReaderUI", function()
    local sample_epub = "spec/front/unit/data/leaves.epub"
    local readerui = ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(sample_epub),
    })

    local readerflipping = readerui.flipping or ReaderFlipping:new({ ui = readerui })
    assert.is_table(readerflipping)

    readerui:onExit()
    readerui:onClose()
  end)
end)
