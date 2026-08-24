describe("Readerview module", function()
  local DocumentRegistry, Blitbuffer, ReaderUI, UIManager, Event, Screen, DocSettings

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))
    DocumentRegistry = require("document/documentregistry")
    Blitbuffer = require("ffi/blitbuffer")
    ReaderUI = require("apps/reader/readerui")
    UIManager = require("ui/uimanager")
    Event = require("ui/event")
    Screen = require("device").screen
    DocSettings = require("docsettings")
  end)

  before_each(function()
    DocSettings:open("spec/front/unit/data/leaves.epub"):purge()
    DocSettings:open("spec/front/unit/data/2col.pdf"):purge()
  end)

  after_each(function()
    if ReaderUI.instance then
      ReaderUI.instance:onClose()
    end
  end)

  it("should stop hinting on document close event", function()
    local sample_epub = "spec/front/unit/data/leaves.epub"
    local readerui = ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(sample_epub),
    })
    for i = #UIManager._task_queue, 1, -1 do
      local task = UIManager._task_queue[i]
      if task.action == readerui.view.emitHintPageEvent then
        error("UIManager's task queue should be empty.")
      end
    end

    local bb = Blitbuffer.new(1000, 1000)
    readerui.view:drawSinglePage(bb, 0, 0)

    local found = false
    for i = #UIManager._task_queue, 1, -1 do
      local task = UIManager._task_queue[i]
      if task.action == readerui.view.emitHintPageEvent then
        found = true
      end
    end
    assert.is.truthy(found)

    readerui:broadcastEvent(Event:new("Close"))

    for i = #UIManager._task_queue, 1, -1 do
      local task = UIManager._task_queue[i]
      if task.action == readerui.view.emitHintPageEvent then
        error("UIManager's task queue should be empty.")
      end
    end

    if readerui.document then
      readerui:onExit()
    end
  end)

  it("should return and restore view context in page mode", function()
    -- we don't want a footer for this test
    G_reader_settings:save("reader_footer_mode", 0)
    local sample_pdf = "spec/front/unit/data/2col.pdf"
    local readerui = ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(sample_pdf),
    })
    readerui:handleEvent(Event:new("SetScrollMode", false))
    readerui.zooming:setZoomMode("page")
    local view = readerui.view
    local ctx = view:getViewContext()
    local zoom = ctx[1].zoom
    ctx[1].zoom = nil
    local saved_ctx = {
      {
        page = 1,
        pos = 0,
        gamma = 1,
        offset = {
          x = 17,
          y = 0,
          h = 0,
          w = 0,
        },
        rotation = 0,
      },
      -- visible_area
      {
        x = 0,
        y = 0,
        h = 800,
        w = 566,
      },
      -- page_area
      {
        x = 0,
        y = 0,
        h = 800,
        w = 566,
      },
    }
    assert.are.same(saved_ctx, ctx)
    assert.is.near(0.95024316487116200491, zoom, 0.0001)

    assert.is.same(view.state.page, 1)
    assert.is.same(view.visible_area.x, 0)
    assert.is.same(view.visible_area.y, 0)
    saved_ctx[1].page = 2
    saved_ctx[1].zoom = zoom
    saved_ctx[2].y = 10
    view:restoreViewContext(saved_ctx)
    assert.is.same(view.state.page, 2)
    assert.is.same(view.visible_area.x, 0)
    assert.is.same(view.visible_area.y, 10)
    G_reader_settings:delete("reader_footer_mode")
    readerui:onExit()
    readerui:onClose()
  end)

  it("should return and restore view context in scroll mode", function()
    -- we don't want a footer for this test
    G_reader_settings:save("reader_footer_mode", 0)
    local sample_pdf = "spec/front/unit/data/2col.pdf"
    local readerui = ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(sample_pdf),
    })
    readerui:handleEvent(Event:new("SetScrollMode", true))
    readerui:handleEvent(Event:new("SetZoomMode", "page"))
    readerui.zooming:setZoomMode("page")
    local view = readerui.view
    local ctx = view:getViewContext()
    local zoom = ctx[1].zoom
    ctx[1].zoom = nil
    local saved_ctx = {
      {
        gamma = 1,
        offset = { x = 17, y = 0 },
        page = 1,
        page_area = {
          h = 800,
          w = 566,
          x = 0,
          y = 0,
        },
        rotation = 0,
        visible_area = {
          h = 800,
          w = 566,
          x = 0,
          y = 0,
        },
      },
    }

    assert.are.same(saved_ctx, ctx)
    assert.is.near(0.95024316487116200491, zoom, 0.0001)

    assert.is.same(view.state.page, 1)
    assert.is.same(view.visible_area.x, 0)
    assert.is.same(view.visible_area.y, 0)
    saved_ctx[1].page = 2
    saved_ctx[1].zoom = zoom
    saved_ctx[1].visible_area.y = 10
    view:restoreViewContext(saved_ctx)
    assert.is.same(#view.page_states, 1)
    assert.is.same(view.page_states[1].page, 2)
    assert.is.same(view.page_states[1].visible_area.x, 0)
    assert.is.same(view.page_states[1].visible_area.y, 10)
    G_reader_settings:delete("reader_footer_mode")
    readerui:onExit()
    readerui:onClose()
  end)

  describe("ReaderView Panning, Coordinates & Events", function()
    local sample_pdf = "spec/front/unit/data/2col.pdf"
    local readerui, view, Geom

    before_each(function()
      Geom = require("ui/geometry")
      readerui = ReaderUI:new({
        dimen = Screen:getSize(),
        document = DocumentRegistry:openDocument(sample_pdf),
      })
      view = readerui.view
    end)

    after_each(function()
      if readerui then
        readerui:onExit()
        readerui:onClose()
      end
    end)

    it("should handle Panning operations and zoom center", function()
      view:PanningStart(100, 100)
      assert.is_not_nil(view.panning_visible_area)

      view:PanningUpdate(15, -25)
      view:PanningStop()
      assert.is_nil(view.panning_visible_area)

      view:SetZoomCenter(200, 300)
      assert.is_not_nil(view.visible_area)
    end)

    it("should transform coordinates between screen and page", function()
      local screen_pos = Geom:new({ x = 100, y = 100 })
      local page_pos = view:screenToPageTransform(screen_pos)
      assert.is_not_nil(page_pos)

      local page_rect = Geom:new({ x = 10, y = 10, w = 100, h = 50 })
      local screen_rect = view:pageToScreenTransform(1, page_rect)
      assert.is_not_nil(screen_rect)

      local page_area = view:getScreenPageArea(1)
      assert.is_not_nil(page_area)
      assert.is_number(page_area.w)
      assert.is_number(page_area.h)

      local computed_area = view:getPageArea(1, 1.0, 0)
      assert.is_not_nil(computed_area)
    end)

    it("should handle updates and view state events", function()
      view:onPageUpdate(2)
      assert.are.equal(2, view.state.page)

      view:onPosUpdate(50)
      view:onZoomUpdate(1.1)
      assert.is_near(1.1, view.state.zoom, 0.001)

      view:onRotationUpdate(90)
      assert.are.equal(90, view.state.rotation)

      local orig_swipe = G_reader_settings:isTrue("swipe_animations")
      view:onTogglePageChangeAnimation()
      assert.are_not.equal(
        orig_swipe,
        G_reader_settings:isTrue("swipe_animations")
      )
      view:onTogglePageChangeAnimation()

      view:onSetFullScreen(true)
      assert.is_false(view.footer_visible)
      view:onSetFullScreen(false)
      assert.is_true(view.footer_visible)

      view:onReaderFooterVisibilityChange()
      view:onSetDimensions(Screen:getSize())
    end)

    it("should draw view and page components without error", function()
      local bb = Blitbuffer.new(800, 600)
      view:paintTo(bb, 0, 0)
      view:drawPageBackground(bb, 0, 0)
      view:drawPageSurround(bb, 0, 0)

      view.highlight = {
        indicator = Geom:new({ x = 50, y = 50, w = 20, h = 20 }),
        temp = {
          [1] = { Geom:new({ x = 10, y = 10, w = 40, h = 20 }) },
        },
      }
      view:drawHighlightIndicator(bb, 0, 0)
      view:drawTempHighlight(bb, 0, 0)
      view:drawSavedHighlight(bb, 0, 0)
    end)
  end)
end)
