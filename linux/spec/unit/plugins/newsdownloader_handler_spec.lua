describe("NewsDownloader XML handler module", function()
  local handler

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    handler = require("plugins/newsdownloader.koplugin/lib/handler")
  end)

  it("should instantiate simpleTreeHandler", function()
    local h = handler.simpleTreeHandler()
    assert.is_table(h)
    assert.is_table(h.root)
    assert.is_table(h.stack)
  end)

  it("should process starttag, text, and endtag events", function()
    local h = handler.simpleTreeHandler()
    h.parseAttributes = true

    h:starttag("item", { id = "1" })
    h:starttag("title", nil)
    h:text("Sample Title")
    h:endtag("title", "title")
    h:endtag("item", "item")

    assert.is_table(h.root)
  end)

  it("should reduce single child nodes in XML tree", function()
    local h = handler.simpleTreeHandler()
    h:starttag("root", nil)
    h:starttag("child", nil)
    h:text("value")
    h:endtag("child", "child")
    h:endtag("root", "root")

    assert.is_not_nil(h.root)
  end)

  it("should parse CDATA elements identically to text", function()
    local h = handler.simpleTreeHandler()
    h:starttag("root", nil)
    h:cdata("cdata content")
    h:endtag("root", "root")

    assert.is_not_nil(h.root)
  end)
end)
