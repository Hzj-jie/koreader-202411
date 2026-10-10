describe("ReaderGoto module", function()
  local ReaderGoto, DocumentRegistry, ReaderUI, Screen, UIManager

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    ReaderGoto = require("apps/reader/modules/readergoto")
    DocumentRegistry = require("document/documentregistry")
    ReaderUI = require("apps/reader/readerui")
    Screen = require("device").screen
    UIManager = require("ui/uimanager")
  end)

  local sample_epub = "spec/front/unit/data/leaves.epub"

  it("should initialize goto page module and register to main menu", function()
    local readerui = ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(sample_epub),
    })

    local readergoto = ReaderGoto:new({ ui = readerui, document = readerui.document })
    assert.is_table(readergoto)

    local menu_items = {}
    readergoto:addToMainMenu(menu_items)
    assert.is_table(menu_items.go_to)
    assert.are.equal("Go to page", menu_items.go_to.text)
    assert.is_table(menu_items.skim_to)
    assert.are.equal("Skim document", menu_items.skim_to.text)

    readerui:onExit()
    readerui:onClose()
  end)

  it("should handle navigation to beginning, end, and random page", function()
    local readerui = ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(sample_epub),
    })

    local rgoto = ReaderGoto:new({ ui = readerui, document = readerui.document })
    assert.is_true(rgoto:onGoToBeginning())
    assert.is_true(rgoto:onGoToEnd())
    assert.is_true(rgoto:onGoToRandomPage())

    -- When document has only 1 page, onGoToRandomPage returns true immediately
    local orig_getPageCount = readerui.document.getPageCount
    readerui.document.getPageCount = function()
      return 1
    end
    assert.is_true(rgoto:onGoToRandomPage())
    readerui.document.getPageCount = orig_getPageCount

    readerui:onExit()
    readerui:onClose()
  end)

  it("should handle goto dialog and percent/page jumps", function()
    local readerui = ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(sample_epub),
    })

    local rgoto = ReaderGoto:new({ ui = readerui, document = readerui.document })
    rgoto:onShowGotoDialog()
    assert.is_table(rgoto.goto_dialog)

    rgoto.goto_dialog.getInputValue = function()
      return 50
    end
    rgoto.goto_dialog.getInputText = function()
      return "3"
    end

    rgoto:gotoPercent()
    rgoto:gotoPage()

    readerui:onExit()
    readerui:onClose()
  end)

  it("should handle relative page jumps (+ and -)", function()
    local readerui = ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(sample_epub),
    })

    local rgoto = ReaderGoto:new({ ui = readerui, document = readerui.document })
    local broadcasted_events = {}
    local orig_broadcast = UIManager.broadcastEvent
    UIManager.broadcastEvent = function(_self, ev)
      table.insert(broadcasted_events, ev)
    end

    rgoto:onShowGotoDialog()
    rgoto.goto_dialog.getInputText = function()
      return "+5"
    end
    rgoto:gotoPage()

    assert.are.equal(1, #broadcasted_events)
    assert.are.equal("onGotoRelativePage", broadcasted_events[1].handler)
    assert.are.equal(5, broadcasted_events[1].args[1])

    rgoto:onShowGotoDialog()
    rgoto.goto_dialog.getInputText = function()
      return "-2"
    end
    rgoto:gotoPage()

    assert.are.equal(2, #broadcasted_events)
    assert.are.equal("onGotoRelativePage", broadcasted_events[2].handler)
    assert.are.equal(-2, broadcasted_events[2].args[1])

    UIManager.broadcastEvent = orig_broadcast
    readerui:onExit()
    readerui:onClose()
  end)

  it("should handle pagemap page labels and hidden flows", function()
    local readerui = ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(sample_epub),
    })

    local rgoto = ReaderGoto:new({ ui = readerui, document = readerui.document })

    -- Mock pagemap with page labels
    readerui.pagemap = {
      wantsPageLabels = function()
        return true
      end,
      getCurrentPageLabel = function()
        return "iv"
      end,
      getFirstPageLabel = function()
        return "i"
      end,
      getLastPageLabel = function()
        return "xx"
      end,
      getRenderedPageNumber = function(_self, label)
        if label == "10" then
          return 15
        end
        return nil
      end,
    }

    -- Test onShowGotoDialog with pagemap labels
    rgoto:onShowGotoDialog()
    assert.is_true(string.find(rgoto.goto_dialog.input_hint, "@iv %(i %- xx%)") ~= nil)

    local broadcasted_events = {}
    local orig_broadcast = UIManager.broadcastEvent
    UIManager.broadcastEvent = function(_self, ev)
      table.insert(broadcasted_events, ev)
    end

    -- Valid label lookup with numeric string
    rgoto.goto_dialog.getInputText = function()
      return "10"
    end
    rgoto:gotoPage()
    assert.are.equal(1, #broadcasted_events)
    assert.are.equal("onGotoPage", broadcasted_events[1].handler)
    assert.are.equal(15, broadcasted_events[1].args[1])

    -- Unmatched label lookup returns early without closing
    rgoto:onShowGotoDialog()
    local dialog_ref = rgoto.goto_dialog
    rgoto.goto_dialog.getInputText = function()
      return "20"
    end
    rgoto:gotoPage()
    assert.are.equal(1, #broadcasted_events)
    assert.are.equal(dialog_ref, rgoto.goto_dialog)
    rgoto:close()

    -- Test hidden flows syntax [x]y
    readerui.pagemap = nil
    local orig_hasHiddenFlows = readerui.document.hasHiddenFlows
    local orig_flows = readerui.document.flows
    local orig_getTotalPagesInFlow = readerui.document.getTotalPagesInFlow
    local orig_getNextPage = readerui.document.getNextPage
    local orig_getFirstPageInFlow = readerui.document.getFirstPageInFlow

    readerui.document.hasHiddenFlows = function()
      return true
    end
    readerui.document.flows = { [0] = {}, [1] = {} }
    readerui.document.getTotalPagesInFlow = function(_self, flow)
      return (flow == 0 or flow == 1) and 10 or 0
    end
    readerui.document.getNextPage = function(_self, page)
      return page + 1
    end
    readerui.document.getFirstPageInFlow = function(_self, flow)
      return flow == 1 and 25 or 1
    end

    -- Flow 0 syntax: [2]
    rgoto:onShowGotoDialog()
    assert.is_string(rgoto.goto_dialog.description)
    rgoto.goto_dialog.getInputText = function()
      return "[2]"
    end
    rgoto:gotoPage()
    assert.are.equal(2, #broadcasted_events)
    assert.are.equal("onGotoPage", broadcasted_events[2].handler)
    assert.are.equal(2, broadcasted_events[2].args[1])

    -- Flow 1 syntax: [3]1 -> page 25 + 3 - 1 = 27
    rgoto:onShowGotoDialog()
    rgoto.goto_dialog.getInputText = function()
      return "[3]1"
    end
    rgoto:gotoPage()
    assert.are.equal(3, #broadcasted_events)
    assert.are.equal("onGotoPage", broadcasted_events[3].handler)
    assert.are.equal(27, broadcasted_events[3].args[1])

    -- Flow out of bounds syntax: [99]1 -> returns without broadcasting
    rgoto:onShowGotoDialog()
    rgoto.goto_dialog.getInputText = function()
      return "[99]1"
    end
    rgoto:gotoPage()
    assert.are.equal(3, #broadcasted_events)
    rgoto:close()

    readerui.document.hasHiddenFlows = orig_hasHiddenFlows
    readerui.document.flows = orig_flows
    readerui.document.getTotalPagesInFlow = orig_getTotalPagesInFlow
    readerui.document.getNextPage = orig_getNextPage
    readerui.document.getFirstPageInFlow = orig_getFirstPageInFlow

    UIManager.broadcastEvent = orig_broadcast
    readerui:onExit()
    readerui:onClose()
  end)
end)
