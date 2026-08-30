describe("ReaderScrolling module", function()
  local ReaderScrolling, DocumentRegistry, ReaderUI, Screen

  setup(function()
    require("commonrequire")
    ReaderScrolling = require("apps/reader/modules/readerscrolling")
    DocumentRegistry = require("document/documentregistry")
    ReaderUI = require("apps/reader/readerui")
    Screen = require("device").screen
  end)

  it("should initialize scrolling module", function()
    local sample_pdf = "spec/front/unit/data/sample.pdf"
    local readerui = ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(sample_pdf),
    })

    local scrolling = readerui.scrolling
    assert.is_table(scrolling)

    readerui:onExit()
    readerui:onClose()
  end)

  it("should handle dispatcher registration and main menu items", function()
    local scrolling = ReaderScrolling:new({
      ui = {
        menu = {
          registerToMainMenu = function() end,
        },
        view = { view_mode = "scroll" },
      },
    })

    local menu_items = {}
    if type(scrolling.addToMainMenu) == "function" then
      scrolling:addToMainMenu(menu_items)
      assert.is_table(menu_items.scrolling)
    end

    if type(scrolling.onDispatcherRegisterActions) == "function" then
      scrolling:onDispatcherRegisterActions()
    end
  end)

  it(
    "should calculate default scroll activation delay and handle settings",
    function()
      local mock_doc_settings = {
        read = function()
          return nil
        end,
        nilOrTrue = function()
          return true
        end,
        save = function() end,
      }
      local scrolling = ReaderScrolling:new({
        ui = {
          menu = { registerToMainMenu = function() end },
          doc_settings = mock_doc_settings,
        },
      })

      if type(scrolling.getDefaultScrollActivationDelay_ms) == "function" then
        local delay = scrolling:getDefaultScrollActivationDelay_ms()
        assert.is_number(delay)
      end

      if type(scrolling.onReadSettings) == "function" then
        scrolling:onReadSettings(mock_doc_settings)
      end
    end
  )

  local function createReaderUI()
    local sample_pdf = "spec/front/unit/data/sample.pdf"
    return ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(sample_pdf),
    })
  end

  it("should populate main menu items and execute settings callbacks", function()
    local readerui = createReaderUI()
    local scrolling = readerui.scrolling
    assert.truthy(scrolling)

    local menu_items = {}
    scrolling:addToMainMenu(menu_items)
    assert.truthy(menu_items.scrolling)
    if menu_items.scrolling.enabled_func then
      readerui.view.page_scroll = false
      readerui.view.view_mode = "scroll"
      assert.is_true(menu_items.scrolling.enabled_func())
      readerui.view.page_scroll = false
      readerui.view.view_mode = "page"
      assert.is_false(menu_items.scrolling.enabled_func())
    end

    local mock_menu = { updateItems = function() end }
    for _, item in ipairs(menu_items.scrolling.sub_item_table) do
      if item.text_func then item:text_func() end
      if item.enabled_func then item:enabled_func() end
      if item.checked_func then item:checked_func() end
      if item.callback then
        item.callback(mock_menu)
        local UIManager = require("ui/uimanager")
        local top = UIManager:getTopmostVisibleWidget()
        if top and top.callback then
          top.callback({ value = 300 })
        end
        if top then
          UIManager:close(top)
        end
      end
    end

    readerui:onExit()
    readerui:onClose()
  end)

  it("should apply scroll methods and toggle inertial scroll setting", function()
    local readerui = createReaderUI()
    local scrolling = readerui.scrolling

    scrolling.scroll_method = scrolling.SCROLL_METHOD_TURBO
    scrolling:applyScrollSettings()
    assert.is.same(scrolling.SCROLL_METHOD_TURBO, scrolling.scroll_method)

    scrolling.scroll_method = scrolling.SCROLL_METHOD_ON_RELEASE
    scrolling:applyScrollSettings()
    assert.is.same(
      scrolling.SCROLL_METHOD_ON_RELEASE,
      scrolling.scroll_method
    )

    scrolling.scroll_method = scrolling.SCROLL_METHOD_CLASSIC
    scrolling.inertial_scroll = true
    scrolling:applyScrollSettings()
    assert.is.same(scrolling.SCROLL_METHOD_CLASSIC, scrolling.scroll_method)
    assert.is_true(scrolling._inertial_scroll_enabled)

    scrolling:onReaderReady()

    readerui:onExit()
    readerui:onClose()
  end)

  it("should handle manual scroll accounting and inertial scroll simulation", function()
    local readerui = createReaderUI()
    local scrolling = readerui.scrolling

    local scroll_called = false
    local done_called = false
    scrolling:setInertialScrollCallbacks(function()
      scroll_called = true
      return true
    end, function()
      done_called = true
    end)

    local time = require("ui/time")
    local now = time.monotonic()
    scrolling:accountManualScroll(50, now)
    scrolling:accountManualScroll(100, now + time.ms(20))
    assert.is_boolean(scrolling:startInertialScroll())

    if scrolling._inertial_scroll_action then
      scrolling._inertial_scroll_action()
      if scrolling._just_reschedule then
        scrolling._inertial_scroll_action()
      end
      scrolling._velocity = 5
      scrolling._inertial_scroll_action()
    end

    scrolling:cancelInertialScroll()
    assert.is_boolean(scrolling:cancelledByTouch() or false)
    scrolling:setInertialScrollCallbacks(nil, nil)

    readerui:onExit()
    readerui:onClose()
  end)

  it("should setup touch zones and handle cancel by touch", function()
    local readerui = createReaderUI()
    local scrolling = readerui.scrolling

    scrolling._cancelled_by_touch = true
    scrolling:setupTouchZones()

    readerui:onExit()
    readerui:onClose()
  end)
end)
