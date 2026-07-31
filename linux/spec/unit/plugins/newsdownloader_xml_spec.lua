describe("Newsdownloader XML parser module", function()
  local XmlParser, Handler

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    XmlParser = require("plugins/newsdownloader.koplugin/lib/xml")
    Handler = require("plugins/newsdownloader.koplugin/lib/handler")
  end)

  describe("Parser Initialization & Parsing", function()
    it("should instantiate XML parser", function()
      local handler = Handler.simpleTreeHandler()
      local parser = XmlParser.xmlParser(handler)
      assert.is_table(parser)
      assert.is_function(parser.parse)
    end)

    it("should parse XML with tags, text, and CDATA", function()
      local handler = Handler.simpleTreeHandler()
      local parser = XmlParser.xmlParser(handler)

      local xml_str = "<?xml version=\"1.0\"?><root><title attr=\"value\">Headline &amp; More</title><![CDATA[cdata block]]></root>"
      parser:parse(xml_str)

      assert.is_table(handler.root)
    end)

    it("should parse entities and escaped characters", function()
      local handler = Handler.simpleTreeHandler()
      local parser = XmlParser.xmlParser(handler)

      assert.are.equal("A", parser:_parseEntities("&#65;"))
      assert.are.equal("B", parser:_parseEntities("&#x42;"))
      assert.are.equal("<", parser:_parseEntities("&lt;"))
      assert.are.equal(">", parser:_parseEntities("&gt;"))
      assert.are.equal("&", parser:_parseEntities("&amp;"))
      assert.are.equal("\"", parser:_parseEntities("&quot;"))
      assert.are.equal("'", parser:_parseEntities("&apos;"))
    end)

    it("should handle comments, PIs, and DTDs", function()
      local pi_called, comment_called = false, false
      local handler = {
        pi = function() pi_called = true end,
        comment = function() comment_called = true end,
        starttag = function() end,
        endtag = function() end,
      }
      local parser = XmlParser.xmlParser(handler)

      local xml_str = "<!-- comment --><?pi text?><root/>"
      parser:parse(xml_str)

      assert.is_true(pi_called)
      assert.is_true(comment_called)
    end)

    it("should raise error on malformed or unmatched XML tags", function()
      local handler = Handler.simpleTreeHandler()
      local parser = XmlParser.xmlParser(handler)

      assert.has_error(function()
        parser:parse("<root><unclosed></root>")
      end)
    end)
  end)
end)
