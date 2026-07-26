describe("ReaderCoptListener module", function()
  local ReaderCoptListener, DocumentRegistry, ReaderUI, Screen

  setup(function()
    require("commonrequire")
    ReaderCoptListener = require("apps/reader/modules/readercoptlistener")
    DocumentRegistry = require("document/documentregistry")
    ReaderUI = require("apps/reader/readerui")
    Screen = require("device").screen
  end)

  it("should instantiate copt listener module", function()
    local sample_epub = "spec/front/unit/data/leaves.epub"
    local doc = DocumentRegistry:openDocument(sample_epub)
    local listener = ReaderCoptListener:new({
      document = doc,
      view = {},
    })

    assert.is_table(listener)
    assert.is_table(listener.additional_header_content)

    doc:close()
  end)

  it("should handle event propagation methods safely", function()
    local sample_epub = "spec/front/unit/data/leaves.epub"
    local doc = DocumentRegistry:openDocument(sample_epub)
    local listener = ReaderCoptListener:new({
      document = doc,
      view = {},
    })

    if type(listener.onSetCreFont) == "function" then
      listener:onSetCreFont("Noto Sans", 100)
    end

    doc:close()
  end)
end)
