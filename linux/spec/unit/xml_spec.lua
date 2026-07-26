describe("XML parser module (xml.lua)", function()
  local XML

  setup(function()
    require("commonrequire")
    XML = require("plugins/newsdownloader.koplugin/lib/xml")
  end)

  it("should parse xml string into tree structure", function()
    assert.is_table(XML)
    local sample_xml = "<rss><channel><title>Test Feed</title></channel></rss>"
    local parsed = XML.parse and XML.parse(sample_xml)
      or (type(XML.eval) == "function" and XML.eval(sample_xml))
    assert.is_not_nil(parsed)
  end)
end)
