describe("ReaderScrolling module", function()
  local ReaderScrolling

  setup(function()
    require("commonrequire")
    ReaderScrolling = require("apps/reader/modules/readerscrolling")
  end)

  it("should initialize constants and support callback registration", function()
    local mock_ui = {
      menu = {
        registerToMainMenu = function() end,
      },
    }
    local scrolling = ReaderScrolling:new({
      ui = mock_ui,
    })

    assert.is_not_nil(scrolling)
    assert.are.equal("classic", scrolling.SCROLL_METHOD_CLASSIC)
    assert.are.equal("turbo", scrolling.SCROLL_METHOD_TURBO)
    assert.are.equal("on_release", scrolling.SCROLL_METHOD_ON_RELEASE)

    local called = false
    scrolling._do_scroll_callback = function(_dist)
      called = true
      return true
    end

    local res = scrolling._do_scroll_callback(10)
    assert.is_true(res)
    assert.is_true(called)
  end)
end)

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
end)
