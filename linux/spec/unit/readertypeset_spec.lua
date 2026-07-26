describe("ReaderTypeset module", function()
  local ReaderTypeset

  setup(function()
    require("commonrequire")
    ReaderTypeset = require("apps/reader/modules/readertypeset")
  end)

  it("should initialize and register to main menu via self.ui.menu", function()
    local register_called = false
    local mock_ui = {
      menu = {
        registerToMainMenu = function(_self_module, _target)
          register_called = true
        end,
      },
      document = {
        is_fb2 = false,
      },
    }

    local typeset = ReaderTypeset:new({
      ui = mock_ui,
    })

    assert.is_not_nil(typeset)
    assert.is_true(register_called)
  end)
end)

describe("ReaderTypeset module", function()
  local ReaderTypeset, DocumentRegistry, ReaderUI, Screen

  setup(function()
    require("commonrequire")
    ReaderTypeset = require("apps/reader/modules/readertypeset")
    DocumentRegistry = require("document/documentregistry")
    ReaderUI = require("apps/reader/readerui")
    Screen = require("device").screen
  end)

  it("should initialize typeset module and handle settings", function()
    local sample_epub = "spec/front/unit/data/leaves.epub"
    local readerui = ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(sample_epub),
    })

    local typeset = readerui.typeset
    assert.is_table(typeset)

    local menu_items = {}
    typeset:addToMainMenu(menu_items)
    assert.is_table(menu_items.set_render_style)

    readerui:onExit()
    readerui:onClose()
  end)
end)
