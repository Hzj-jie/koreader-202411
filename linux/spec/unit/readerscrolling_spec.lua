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
