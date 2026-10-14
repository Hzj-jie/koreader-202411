local stub = require("luassert.stub")

describe("ViewHTML module", function()
  local ViewHTML, UIManager, Device

  setup(function()
    require("commonrequire")
    ViewHTML = require("ui/viewhtml")
    UIManager = require("ui/uimanager")
    Device = require("device")
  end)

  before_each(function()
    stub(UIManager, "show")
    stub(UIManager, "close")
  end)

  after_each(function()
    UIManager.show:revert()
    UIManager.close:revert()
  end)

  it("should expose ViewHtml methods and views", function()
    assert.is_table(ViewHTML)
    assert.is_table(ViewHTML.VIEWS)
    assert.is_function(ViewHTML.viewSelectionHTML)
    assert.are.equal(4, #ViewHTML.VIEWS)
    assert.are.equal("Switch to standard view", ViewHTML.VIEWS[1][1])
    assert.are.equal(0xE830, ViewHTML.VIEWS[1][2])
    assert.is_false(ViewHTML.VIEWS[1][3])

    assert.are.equal("Switch to debug view", ViewHTML.VIEWS[2][1])
    assert.are.equal(0xEB5A, ViewHTML.VIEWS[2][2])
    assert.is_true(ViewHTML.VIEWS[2][3])

    assert.are.equal("Switch to rendering debug view", ViewHTML.VIEWS[3][1])
    assert.are.equal(0xEF5A, ViewHTML.VIEWS[3][2])
    assert.is_true(ViewHTML.VIEWS[3][3])

    assert.are.equal("Switch to unicode debug view", ViewHTML.VIEWS[4][1])
    assert.are.equal(0xEB5E, ViewHTML.VIEWS[4][2])
    assert.is_true(ViewHTML.VIEWS[4][3])
  end)

  it(
    "should handle viewSelectionHTML with missing pos0 or pos1 gracefully",
    function()
      local document = {}
      assert.is_nil(ViewHTML:viewSelectionHTML(document, nil))
      assert.is_nil(ViewHTML:viewSelectionHTML(document, {}))
      assert.is_nil(ViewHTML:viewSelectionHTML(document, { pos0 = {} }))
      assert.is_nil(ViewHTML:viewSelectionHTML(document, { pos1 = {} }))
    end
  )

  it("should show InfoMessage when document fails to return HTML", function()
    local document = {
      getHTMLFromXPointers = function()
        return nil
      end,
    }
    local selected_text = {
      pos0 = { x = 0, y = 0 },
      pos1 = { x = 10, y = 10 },
    }

    ViewHTML:viewSelectionHTML(document, selected_text)
    assert.stub(UIManager.show).was_called(1)
    local widget = UIManager.show.calls[1].refs[2]
    assert.is_not_nil(widget)
    assert.are.equal("Failed getting HTML for selection", widget.text)
  end)

  it(
    "should open TextViewer dialog for valid selection html (Standard View)",
    function()
      local document = {
        getHTMLFromXPointers = function(_self, _pos0, _pos1, flags, _bool)
          assert.are.equal(0xE830, flags)
          return "<p>Test XML</p>", nil, nil
        end,
      }
      local selected_text = {
        pos0 = { x = 0, y = 0 },
        pos1 = { x = 10, y = 10 },
        text = "Test XML",
      }

      ViewHTML:viewSelectionHTML(document, selected_text)
      assert.stub(UIManager.show).was_called(1)
      local widget = UIManager.show.calls[1].refs[2]
      assert.is_not_nil(widget)
      assert.are.equal("Selection HTML", widget.title)
      assert.are.equal("<p>Test XML</p>", widget.text)
      assert.are.equal("code", widget.text_type)
      assert.is_true(widget.add_default_buttons)
      assert.are.equal("Switch to debug view", widget.buttons_table[1][1].text)
    end
  )

  it(
    "should switch to next view when next view button callback is clicked",
    function()
      local called_flags = {}
      local document = {
        getHTMLFromXPointers = function(_self, _pos0, _pos1, flags, _bool)
          table.insert(called_flags, flags)
          return "<p>Test XML</p>", nil, nil
        end,
      }
      local selected_text = {
        pos0 = { x = 0, y = 0 },
        pos1 = { x = 10, y = 10 },
      }

      ViewHTML:viewSelectionHTML(document, selected_text)
      assert.are.equal(1, #called_flags)
      assert.are.equal(0xE830, called_flags[1])

      local textviewer = UIManager.show.calls[1].refs[2]
      local switch_button = textviewer.buttons_table[1][1]

      switch_button.callback()

      assert.stub(UIManager.close).was_called(1)
      assert.are.equal(textviewer, UIManager.close.calls[1].refs[2])
      assert.stub(UIManager.show).was_called(2)
      assert.are.equal(2, #called_flags)
      assert.are.equal(0xEB5A, called_flags[2])

      local new_textviewer = UIManager.show.calls[2].refs[2]
      assert.are.equal(
        "Switch to rendering debug view",
        new_textviewer.buttons_table[1][1].text
      )
    end
  )

  it("should format html in debug view (massage_html)", function()
    local document = {
      getHTMLFromXPointers = function()
        return "<p>No\u{00A0}break soft\u{00AD}hyphen</p><stylesheet>body { color: red; }</stylesheet>",
          nil,
          nil
      end,
    }
    local selected_text = {
      pos0 = { x = 0, y = 0 },
      pos1 = { x = 10, y = 10 },
    }

    ViewHTML:_viewSelectionHTML(document, selected_text, 2, true, false)

    local textviewer = UIManager.show.calls[1].refs[2]
    -- \u{00A0} replaced by open box \u{2423}, \u{00AD} replaced by dot operator \u{22C5}
    assert.truthy(textviewer.text:find("\u{2423}"))
    assert.truthy(textviewer.text:find("\u{22C5}"))
    assert.truthy(textviewer.text:find("color: red"))
  end)

  it(
    "should hide stylesheet content when hide_stylesheet_elem_content is true",
    function()
      local document = {
        getHTMLFromXPointers = function()
          return "<p>Test</p><stylesheet>body { color: red; }</stylesheet>",
            nil,
            nil
        end,
      }
      local selected_text = {
        pos0 = { x = 0, y = 0 },
        pos1 = { x = 10, y = 10 },
      }

      ViewHTML:_viewSelectionHTML(document, selected_text, 1, true, true)

      local textviewer = UIManager.show.calls[1].refs[2]
      assert.truthy(textviewer.text:find("<stylesheet>%[%...%]</stylesheet>"))
    end
  )

  it(
    "should add buttons for CSS files and handle opening/prettifying CSS",
    function()
      local document = {
        getHTMLFromXPointers = function()
          return "<p>Test</p>", { "style.css" }, nil
        end,
        getDocumentFileContent = function(_self, filename)
          if filename == "style.css" then
            return "div { margin: 0; }"
          end
          return nil
        end,
      }
      local selected_text = {
        pos0 = { x = 0, y = 0 },
        pos1 = { x = 10, y = 10 },
      }

      ViewHTML:viewSelectionHTML(document, selected_text)

      local textviewer = UIManager.show.calls[1].refs[2]
      local css_button = textviewer.buttons_table[1][1]
      assert.truthy(css_button.text:find("style.css"))

      -- Click CSS button
      css_button.callback()

      assert.stub(UIManager.show).was_called(2)
      local cssviewer = UIManager.show.calls[2].refs[2]
      assert.are.equal("style.css", cssviewer.title)
      assert.are.equal("div { margin: 0; }", cssviewer.text)
      assert.are.equal("code", cssviewer.text_type)

      -- Click Prettify button inside CSS viewer
      local prettify_button = cssviewer.buttons_table[1][1]
      assert.are.equal("Prettify", prettify_button.text)
      assert.is_true(prettify_button.enabled)

      prettify_button.callback()

      assert.stub(UIManager.close).was_called(1)
      assert.are.equal(cssviewer, UIManager.close.calls[1].refs[2])
      assert.stub(UIManager.show).was_called(3)
      local prettified_viewer = UIManager.show.calls[3].refs[2]
      assert.are.equal("style.css", prettified_viewer.title)
      assert.truthy(prettified_viewer.text:find("margin: 0"))
    end
  )

  it("should handle failed CSS file retrieval", function()
    local document = {
      getHTMLFromXPointers = function()
        return "<p>Test</p>", { "missing.css" }, nil
      end,
      getDocumentFileContent = function()
        return nil
      end,
    }
    local selected_text = {
      pos0 = { x = 0, y = 0 },
      pos1 = { x = 10, y = 10 },
    }

    ViewHTML:viewSelectionHTML(document, selected_text)

    local textviewer = UIManager.show.calls[1].refs[2]
    local css_button = textviewer.buttons_table[1][1]
    css_button.callback()

    local cssviewer = UIManager.show.calls[2].refs[2]
    assert.are.equal("missing.css", cssviewer.title)
    assert.are.equal("Failed getting CSS content", cssviewer.text)
    assert.is_false(cssviewer.buttons_table[1][1].enabled)
  end)

  it("should toggle CSS files buttons on hold_callback", function()
    local document = {
      getHTMLFromXPointers = function()
        return "<p>Test</p>", { "style.css" }, nil
      end,
    }
    local selected_text = {
      pos0 = { x = 0, y = 0 },
      pos1 = { x = 10, y = 10 },
    }

    ViewHTML:viewSelectionHTML(document, selected_text)
    local textviewer = UIManager.show.calls[1].refs[2]

    -- Hold button callback
    textviewer.default_hold_callback()

    assert.stub(UIManager.close).was_called(1)
    assert.are.equal(textviewer, UIManager.close.calls[1].refs[2])
    assert.stub(UIManager.show).was_called(2)
    local new_viewer = UIManager.show.calls[2].refs[2]
    assert.are.equal(
      "Switch to debug view",
      new_viewer.buttons_table[1][1].text
    )
  end)

  it(
    "should copy selection to clipboard on text_selection_callback when no css_selectors_offsets",
    function()
      local set_clipboard_stub = stub(Device.input, "setClipboardText")

      local document = {
        getHTMLFromXPointers = function()
          return "<p>Test</p>", nil, nil
        end,
      }
      local selected_text = {
        pos0 = { x = 0, y = 0 },
        pos1 = { x = 10, y = 10 },
      }

      ViewHTML:viewSelectionHTML(document, selected_text)
      local textviewer = UIManager.show.calls[1].refs[2]

      textviewer.text_selection_callback(
        "Selected text snippet",
        0,
        1,
        10,
        function(idx)
          return idx
        end
      )

      assert.stub(set_clipboard_stub).was_called_with("Selected text snippet")
      assert.stub(UIManager.show).was_called(2)
      local notification = UIManager.show.calls[2].refs[2]
      assert.are.equal("Selection copied to clipboard.", notification.text)

      set_clipboard_stub:revert()
    end
  )

  it(
    "should handle long-press with css_selectors_offsets and propose CSS selectors",
    function()
      local clipboard_text = ""
      local original_set = Device.input.setClipboardText
      local original_get = Device.input.getClipboardText
      Device.input.setClipboardText = function(txt)
        clipboard_text = txt
      end
      Device.input.getClipboardText = function()
        return clipboard_text
      end

      local sample_tsv = table.concat({
        "0\t2\t33\tbody",
        "9\t3\t449\tDocFragment\t[StyleSheet=stylesheet.css]\t[id=_doc_fragment_52]\t[lang=fr-FR]",
        "168\t4\t481\tbody\t[type=bodymatter]\t[lang=fr-FR]",
        "251\t5\t545\tsection\t.chap\t[type=chapter]\t[role=doc-chapter]",
        "321\t6\t561\tdiv",
        "349\t7\t577\tp\t.justif1\t.no-indent\t[type=main]",
      }, "\n")

      local document = {
        getHTMLFromXPointers = function()
          return "<p>Test</p>", nil, sample_tsv
        end,
        getStylesheetsMatchingRulesets = function(
          _self,
          node_dataindex,
          _with_main
        )
          return {
            "/* ruleset for node " .. tostring(node_dataindex) .. " */",
            "p.justif1 { color: black; }",
          }
        end,
      }
      local selected_text = {
        pos0 = { x = 0, y = 0 },
        pos1 = { x = 10, y = 10 },
      }

      ViewHTML:viewSelectionHTML(document, selected_text)
      local textviewer = UIManager.show.calls[1].refs[2]

      -- Long press at idx 350
      textviewer.text_selection_callback("p text", 0, 1, 10, function(_idx)
        return 350
      end)

      assert.stub(UIManager.show).was_called(2)
      local button_dialog = UIManager.show.calls[2].refs[2]
      assert.are.equal("Copy to clipboard:", button_dialog.title)

      -- Check proposed selector buttons
      local button_rows = button_dialog.buttons
      assert.truthy(#button_rows > 0)

      -- Test clicking first copy selector button
      local sel_button = button_rows[1][1]
      sel_button.callback()
      assert.are.equal(sel_button.text, clipboard_text)
      local notif = UIManager.show.calls[3].refs[2]
      assert.are.equal("Selector copied to clipboard.", notif.text)

      -- Test holding copy selector button
      sel_button.hold_callback()
      assert.are.equal(
        sel_button.text .. "\n" .. sel_button.text,
        clipboard_text
      )

      -- Test Show matched stylesheet rules (element only)
      local elem_rules_row = button_rows[#button_rows - 1]
      local elem_rules_btn = elem_rules_row[1]
      assert.truthy(elem_rules_btn.text:find("element only"))

      elem_rules_btn.callback()
      assert.stub(UIManager.show).was_called(5)
      local rules_viewer = UIManager.show.calls[5].refs[2]
      assert.truthy(rules_viewer.title:find("element only"))
      assert.truthy(rules_viewer.text:find("p.justif1"))

      -- Test Prettify in matching rulesets viewer
      local prettify_rules_btn = rules_viewer.buttons_table[1][1]
      prettify_rules_btn.callback()
      assert.stub(UIManager.close).was_called(1)
      assert.are.equal(rules_viewer, UIManager.close.calls[1].refs[2])

      -- Test Show matched stylesheet rules (all ancestors)
      local anc_rules_row = button_rows[#button_rows]
      local anc_rules_btn = anc_rules_row[1]
      assert.truthy(anc_rules_btn.text:find("all ancestors"))

      anc_rules_btn.callback()
      local anc_rules_viewer =
        UIManager.show.calls[#UIManager.show.calls].refs[2]
      assert.truthy(anc_rules_viewer.title:find("all ancestors"))

      Device.input.setClipboardText = original_set
      Device.input.getClipboardText = original_get
    end
  )

  it(
    "should trigger stylesheet_elem_callback when long pressing on stylesheet element",
    function()
      local sample_tsv = table.concat({
        "0\t2\t33\tbody",
        "90\t4\t465\tstylesheet\t[href=OPS/]",
      }, "\n")

      local document = {
        getHTMLFromXPointers = function()
          return "<p>Test</p><stylesheet>body {}</stylesheet>", nil, sample_tsv
        end,
      }
      local selected_text = {
        pos0 = { x = 0, y = 0 },
        pos1 = { x = 10, y = 10 },
      }

      ViewHTML:viewSelectionHTML(document, selected_text)
      local textviewer = UIManager.show.calls[1].refs[2]

      -- Long press at idx 91 (on stylesheet element)
      textviewer.text_selection_callback(
        "stylesheet text",
        0,
        1,
        10,
        function(_idx)
          return 91
        end
      )

      assert.stub(UIManager.close).was_called(1)
      assert.are.equal(textviewer, UIManager.close.calls[1].refs[2])
      assert.stub(UIManager.show).was_called(2)
      local new_viewer = UIManager.show.calls[2].refs[2]
      assert.truthy(new_viewer.text:find("<stylesheet>%[%...%]</stylesheet>"))
    end
  )
end)
