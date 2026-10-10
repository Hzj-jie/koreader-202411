-- luacheck: ignore 122
describe("OPDS Parser module", function()
  local OPDSParser

  setup(function()
    require("commonrequire")
    OPDSParser = require("plugins/opds.koplugin/opdsparser")
  end)

  describe("XML and Atom/OPDS Feed Parsing", function()
    it("parses feed metadata, entries, and links", function()
      local xml = [[
        <?xml version="1.0" encoding="utf-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <id>urn:uuid:catalog-1</id>
          <title>Catalog Title</title>
          <updated>2026-10-10T00:00:00Z</updated>
          <link rel="self" href="/opds/root.xml" type="application/atom+xml"/>
          <entry>
            <id>urn:uuid:book-1</id>
            <title>First Book &amp; Stories</title>
            <link rel="http://opds-spec.org/acquisition" href="/books/1.epub" type="application/epub+zip"/>
            <link rel="http://opds-spec.org/image" href="/covers/1.jpg" type="image/jpeg"/>
            <content type="text">A great &lt;b&gt;read&lt;/b&gt;.</content>
          </entry>
        </feed>
      ]]

      local res = OPDSParser:parse(xml)
      assert.is_table(res)
      assert.is_table(res.feed)
      assert.are.equal("urn:uuid:catalog-1", res.feed.id)
      assert.are.equal("Catalog Title", res.feed.title)
      assert.is_table(res.feed.link)
      assert.are.equal("/opds/root.xml", res.feed.link[1].href)

      assert.is_table(res.feed.entry)
      assert.are.equal(1, #res.feed.entry)
      local entry = res.feed.entry[1]
      assert.are.equal("urn:uuid:book-1", entry.id)
      assert.are.equal("First Book & Stories", entry.title)
      assert.is_table(entry.link)
      assert.are.equal(2, #entry.link)
    end)

    it("handles comments, stylesheets, CDATA, and unclosed tags", function()
      local xml = [=[
        <?xml version="1.0" encoding="utf-8"?>
        <?xml-stylesheet href="style.css" type="text/css"?>
        <!-- Catalog header comment -->
        <feed>
          <title><![CDATA[Special <Header> & Notes]]></title>
          <entry>
            <title>Book with <br> break and <hr> line</title>
            <id>book-2</id>
          </entry>
        </feed>
      ]=]

      local res = OPDSParser:parse(xml)
      assert.is_table(res)
      assert.is_table(res.feed)
      assert.are.equal("book-2", res.feed.entry[1].id)
    end)

    it("unescapes standard named and decimal numeric entities", function()
      local xml = [[
        <feed>
          <title>&quot;Quotes&quot; &apos;Apos&apos; &#8212; Dash</title>
        </feed>
      ]]

      local res = OPDSParser:parse(xml)
      assert.is_table(res)
      assert.are.equal("\"Quotes\" 'Apos' — Dash", res.feed.title)
    end)
  end)

  describe("Defect verifications", function()
    it(
      "fails: exposes unescape crashing on hex character entities like &#x2014;",
      function()
        local xml = [[
        <feed>
          <entry>
            <title>War &#x2014; Peace</title>
            <id>book-hex</id>
          </entry>
        </feed>
      ]]

        -- In opdsparser.lua line 22-27:
        -- unescape matches "(&(#?)([%d%a]+);)".
        -- For "&#x2014;", n is "#" and s is "x2014".
        -- tonumber("x2014") returns nil (Lua requires "0x...").
        -- util.unicodeCodepointToUtf8(nil) then throws: attempt to compare nil with number.
        -- The test asserts that OPDSParser:parse parses without crashing and returns the em-dash.
        local ok, res = pcall(function()
          return OPDSParser:parse(xml)
        end)

        assert.is_true(
          ok,
          "OPDSParser:parse should not crash on hex entities &#x...;: "
            .. tostring(res)
        )
        assert.is_table(res)
        assert.are.equal("War — Peace", res.feed.entry[1].title)
      end
    )
  end)
end)
