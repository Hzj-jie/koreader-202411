describe("Newsdownloader XML parser module", function()
  local XmlParser

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    package.path = "plugins/newsdownloader.koplugin/lib/?.lua;" .. package.path
    XmlParser = require("plugins/newsdownloader.koplugin/lib/xml")
  end)

  describe("Parser Initialization & Parsing", function()
    it("should instantiate XML parser", function()
      assert.is_table(XmlParser)
      local handler = {}
      local parser = XmlParser.xmlParser(handler)
      assert.is_table(parser)
    end)
  end)
end)
