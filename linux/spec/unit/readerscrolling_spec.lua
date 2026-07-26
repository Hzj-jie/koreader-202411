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
end)
