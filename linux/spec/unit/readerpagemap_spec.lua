describe("ReaderPageMap module", function()
  local ReaderPageMap, DocumentRegistry, ReaderUI, Screen

  setup(function()
    require("commonrequire")
    ReaderPageMap = require("apps/reader/modules/readerpagemap")
    DocumentRegistry = require("document/documentregistry")
    ReaderUI = require("apps/reader/readerui")
    Screen = require("device").screen
  end)

  it("should initialize pagemap module", function()
    local sample_epub = "spec/front/unit/data/leaves.epub"
    local readerui = ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(sample_epub),
    })

    local pagemap = readerui.pagemap
    assert.is_table(pagemap)
    assert.is_function(pagemap.resetLayout)

    pagemap:resetLayout()

    readerui:onExit()
    readerui:onClose()
  end)

  describe("Menu & Dispatcher Integration", function()
    it("should register dispatcher actions", function()
      local mock_ui = {
        menu = {
          registerToMainMenu = function() end,
        },
      }
      local pagemap = ReaderPageMap:new({
        ui = mock_ui,
      })
      if type(pagemap.onDispatcherRegisterActions) == "function" then
        pagemap:onDispatcherRegisterActions()
      end
    end)
  end)
end)
