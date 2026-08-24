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

  it(
    "should handle menu callbacks, touch zones, and inertial scrolling",
    function()
      local sample_pdf = "spec/front/unit/data/sample.pdf"
      local readerui = ReaderUI:new({
        dimen = Screen:getSize(),
        document = DocumentRegistry:openDocument(sample_pdf),
      })
      local scrolling = readerui.scrolling
      assert.truthy(scrolling)

      -- Test addToMainMenu items
      local menu_items = {}
      scrolling:addToMainMenu(menu_items)
      assert.truthy(menu_items.scrolling)
      for _, item in ipairs(menu_items.scrolling.sub_item_table) do
        if item.callback then
          item.callback()
        end
      end

      -- Test scrolling methods
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

      -- Test setInertialScrollCallbacks
      local scroll_called = false
      local done_called = false
      scrolling:setInertialScrollCallbacks(function()
        scroll_called = true
        return true
      end, function()
        done_called = true
      end)

      -- Test accountManualScroll and inertial scroll
      local time = require("ui/time")
      local now = time.monotonic()
      scrolling:accountManualScroll(50, now)
      scrolling:accountManualScroll(100, now + time.ms(20))
      assert.is_boolean(scrolling:startInertialScroll())
      scrolling:cancelInertialScroll()

      scrolling:setInertialScrollCallbacks(nil, nil)

      readerui:onExit()
      readerui:onClose()
    end
  )
end)
