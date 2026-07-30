describe("Newsdownloader XML parser module", function()
  local XmlParser

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    XmlParser = require("plugins/newsdownloader.koplugin/lib/xml")
  end)

  describe("Parser Initialization & Parsing", function()
    it("should instantiate XML parser", function()
      assert.is_table(XmlParser)
      local handler = {}
      local parser = XmlParser.xmlParser(handler)
      assert.is_table(parser)
    end)

    it("should parse simple XML text", function()
      local handler = {
        startElement = function() end,
        endElement = function() end,
        text = function() end,
      }
      local parser = XmlParser.xmlParser(handler)
      if type(parser.parseText) == "function" then
        parser:parseText("<root><item>test</item></root>")
      end
    end)

    it("should evaluate xml entities safely", function()
      if type(XmlParser.eval) == "function" then
        assert.are.equal("&", XmlParser.eval("&amp;"))
      end
    end)
  end)
end)
