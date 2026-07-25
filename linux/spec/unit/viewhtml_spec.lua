describe("ViewHTML module", function()
  local ViewHTML, UIManager

  setup(function()
    require("commonrequire")
    ViewHTML = require("ui/viewhtml")
    UIManager = require("ui/uimanager")
  end)

  it("should expose ViewHtml methods and views", function()
    assert.is_table(ViewHTML)
    assert.is_table(ViewHTML.VIEWS)
    assert.is_function(ViewHTML.viewSelectionHTML)
  end)

  it("should handle viewSelectionHTML with missing pos0 or pos1 gracefully", function()
    local document = {}
    assert.is_nil(ViewHTML:viewSelectionHTML(document, nil))
    assert.is_nil(ViewHTML:viewSelectionHTML(document, {}))
    assert.is_nil(ViewHTML:viewSelectionHTML(document, { pos0 = {} }))
  end)

  it("should open TextViewer dialog for valid selection html", function()
    local document = {
      getHTMLFromXPointers = function()
        return "<p>Test XML</p>"
      end,
      getCssFilesContent = function()
        return "p { color: red; }"
      end,
    }
    local selected_text = {
      pos0 = { x = 0, y = 0 },
      pos1 = { x = 10, y = 10 },
      text = "Test XML",
    }

    local show_spy = spy.on(UIManager, "show")
    ViewHTML:viewSelectionHTML(document, selected_text)
    assert.spy(show_spy).was_called()
    show_spy:revert()
  end)
end)
