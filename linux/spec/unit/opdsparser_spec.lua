describe("OPDSParser", function()
  local OPDSParser

  setup(function()
    require("commonrequire")
    OPDSParser = require("plugins/opds.koplugin/opdsparser")
  end)

  it("should parse basic OPDS feed with feed metadata and entries", function()
    local xml = [[<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <id>urn:feed:1</id>
  <title>Test Catalog</title>
  <updated>2026-10-10T00:00:00Z</updated>
  <link rel="self" href="/opds" type="application/atom+xml" />
  <entry>
    <id>urn:book:1</id>
    <title>First Book</title>
    <link rel="http://opds-spec.org/acquisition" href="/book1.epub" type="application/epub+zip" />
  </entry>
  <entry>
    <id>urn:book:2</id>
    <title>Second Book</title>
    <link rel="http://opds-spec.org/acquisition" href="/book2.epub" type="application/epub+zip" />
  </entry>
</feed>]]

    local parsed = OPDSParser:parse(xml)
    assert.is_table(parsed)
    local feed = parsed.feed
    assert.is_table(feed)
    assert.are.equal("Test Catalog", feed.title)
    assert.are.equal("urn:feed:1", feed.id)
    assert.is_table(feed.link)
    assert.are.equal("/opds", feed.link[1].href)

    assert.is_table(feed.entry)
    assert.are.equal(2, #feed.entry)
    assert.are.equal("First Book", feed.entry[1].title)
    assert.are.equal("/book1.epub", feed.entry[1].link[1].href)
    assert.are.equal("Second Book", feed.entry[2].title)
    assert.are.equal("/book2.epub", feed.entry[2].link[1].href)
  end)

  it("should unescape standard XML entities and unicode codepoints", function()
    local xml = [[<feed xmlns="http://www.w3.org/2005/Atom">
  <title>Fish &amp; Chips &lt;Edition &gt; &quot;Special&apos;</title>
  <entry>
    <title>Em&#8212;Dash &amp; Euro &#8364;</title>
  </entry>
</feed>]]

    local parsed = OPDSParser:parse(xml)
    assert.is_table(parsed)
    local feed = parsed.feed
    assert.is_table(feed)
    assert.are.equal("Fish & Chips <Edition > \"Special'", feed.title)
    assert.is_table(feed.entry)
    assert.is_truthy(feed.entry[1].title:find("Em—Dash & Euro €"))
  end)

  it("should handle CDATA sections by extracting content and unescaping", function()
    local xml = [==[<feed xmlns="http://www.w3.org/2005/Atom">
  <title><![CDATA[Catalog with <Special> & "Chars"]]></title>
  <entry>
    <summary><![CDATA[Some summary with & and <tags>]]></summary>
  </entry>
</feed>]==]

    local parsed = OPDSParser:parse(xml)
    assert.is_table(parsed)
    local feed = parsed.feed
    assert.is_table(feed)
    assert.are.equal("Catalog with <Special> & \"Chars\"", feed.title)
    assert.are.equal("Some summary with & and <tags>", feed.entry[1].summary)
  end)

  it("should mangle HTML/XHTML content tags into text node", function()
    local xml = [[<feed xmlns="http://www.w3.org/2005/Atom">
  <title>Feed</title>
  <entry>
    <title>Book 1</title>
    <content type="text/html"><p>Paragraph 1</p><br><p>Paragraph 2</p></content>
  </entry>
</feed>]]

    local parsed = OPDSParser:parse(xml)
    assert.is_table(parsed)
    local feed = parsed.feed
    assert.is_table(feed)
    assert.is_table(feed.entry)
    assert.is_string(feed.entry[1].content)
    assert.is_truthy(feed.entry[1].content:find("Paragraph 1"))
    assert.is_truthy(feed.entry[1].content:find("Paragraph 2"))
  end)

  it("should strip xml-stylesheet, comments, and fix self-closing tags and br/hr", function()
    local xml = [[<?xml version="1.0" encoding="utf-8"?>
<?xml-stylesheet type="text/xsl" href="/opds.xsl"?>
<!-- This is an XML comment that luxl does not like -->
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>Commented Feed</title>
  <entry>
    <title>Entry 1</title>
    <content>Line 1<br>Line 2<hr>End</content>
  </entry>
</feed>]]

    local parsed = OPDSParser:parse(xml)
    assert.is_table(parsed)
    local feed = parsed.feed
    assert.is_table(feed)
    assert.are.equal("Commented Feed", feed.title)
    assert.is_table(feed.entry)
    assert.are.equal("Entry 1", feed.entry[1].title)
  end)
end)
