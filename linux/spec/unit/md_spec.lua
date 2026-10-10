describe("Markdown parser module (md.lua)", function()
  local MD

  setup(function()
    require("commonrequire")
    MD = require("apps/filemanager/lib/md")
  end)

  describe("API entry points and input types", function()
    it("should support renderString, renderTable, renderLineIterator, and callable MD table", function()
      local input_str = "# Heading\nParagraph text"
      local res1 = MD.renderString(input_str)
      assert.is_string(res1)
      assert.is_truthy(res1:find("<h1>Heading</h1>"))
      assert.is_truthy(res1:find("<p>Paragraph text</p>"))

      local lines = { "# Heading", "Paragraph text" }
      local res2 = MD.renderTable(lines)
      assert.is_string(res2)
      assert.is_truthy(res2:find("<h1>Heading</h1>"))

      local idx = 0
      local iterator = function()
        idx = idx + 1
        return lines[idx]
      end
      local res3 = MD.renderLineIterator(iterator)
      assert.is_string(res3)
      assert.is_truthy(res3:find("<h1>Heading</h1>"))

      local res4 = MD(input_str)
      assert.are.equal(res1, res4)

      local res5 = MD.render(input_str)
      assert.are.equal(res1, res5)
    end)

    it("should return nil and error message for invalid input types", function()
      local res, err = MD.render(12345)
      assert.is_nil(res)
      assert.is_truthy(err:find("Source must be a string, table, or function"))

      local res_bool, err_bool = MD.render(true)
      assert.is_nil(res_bool)
      assert.is_truthy(err_bool:find("Source must be a string, table, or function"))
    end)
  end)

  describe("Headings", function()
    it("should parse ATX style headers level 1 to 6", function()
      local headers = {
        "# Header 1",
        "## Header 2",
        "### Header 3",
        "#### Header 4",
        "##### Header 5",
        "###### Header 6",
      }
      for level, text in ipairs(headers) do
        local html = MD(text)
        local tag = "h" .. level
        assert.is_truthy(html:find("<" .. tag .. ">Header " .. level .. "</" .. tag .. ">"))
      end
    end)

    it("should parse Setext style headers", function()
      local setext_h1 = MD("Main Title\n==========")
      assert.is_truthy(setext_h1:find("<h1>Main Title</h1>"))

      local setext_h2 = MD("Sub Title\n---------")
      assert.is_truthy(setext_h2:find("<h2>Sub Title</h2>"))
    end)
  end)

  describe("Inline formatting", function()
    it("should parse bold, italic, code, and strike-through", function()
      local html_bold_star = MD("This is **bold** text.")
      assert.is_truthy(html_bold_star:find("<strong>bold</strong>"))

      local html_bold_under = MD("This is __bold__ text.")
      assert.is_truthy(html_bold_under:find("<strong>bold</strong>"))

      local html_italic_star = MD("This is *italic* text.")
      assert.is_truthy(html_italic_star:find("<em>italic</em>"))

      local html_italic_under = MD("This is _italic_ text.")
      assert.is_truthy(html_italic_under:find("<em>italic</em>"))

      local html_code = MD("This is `inline code`.")
      assert.is_truthy(html_code:find("<code>inline code</code>"))

      local html_strike = MD("This is ~~struck~~ text.")
      assert.is_truthy(html_strike:find("<strike>struck</strike>"))
    end)
  end)

  describe("Links and Images", function()
    it("should parse inline links and images", function()
      local html_link = MD("Visit [KOReader](https://koreader.rocks) now!")
      assert.is_truthy(html_link:find('<a href="https://koreader.rocks">KOReader</a>'))

      local html_img = MD("Logo: ![Alt Text](https://koreader.rocks/logo.png)")
      assert.is_truthy(html_img:find('<img alt="Alt Text" src="https://koreader.rocks/logo.png">'))
    end)

    it("should parse reference-style links and images", function()
      local md_ref = "[KOReader]\n\n[koreader]: https://koreader.rocks"
      local html_ref = MD(md_ref)
      assert.is_truthy(html_ref:find('<a href="https://koreader.rocks">KOReader</a>'))

      local md_ref_img = "![KOReader]\n\n[koreader]: https://koreader.rocks/icon.png"
      local html_ref_img = MD(md_ref_img)
      assert.is_truthy(html_ref_img:find('<img alt="KOReader" src="https://koreader.rocks/icon.png">'))
    end)
  end)

  describe("Block elements", function()
    it("should parse blockquotes", function()
      local html_bq = MD("> Quotation line 1\n> Quotation line 2")
      assert.is_truthy(html_bq:find("<blockquote>"))
      assert.is_truthy(html_bq:find("Quotation line 1"))
      assert.is_truthy(html_bq:find("</blockquote>"))
    end)

    it("should parse horizontal rules", function()
      local html_hr1 = MD("---")
      assert.is_truthy(html_hr1:find("<hr>"))

      local html_hr2 = MD("***")
      assert.is_truthy(html_hr2:find("<hr>"))

      local html_hr3 = MD("___")
      assert.is_truthy(html_hr3:find("<hr>"))
    end)

    it("should parse unordered and ordered lists", function()
      local ulist = "* First\n* Second\n* Third"
      local html_u = MD(ulist)
      assert.is_truthy(html_u:find("<ul>"))
      assert.is_truthy(html_u:find("<li>First</li>"))
      assert.is_truthy(html_u:find("<li>Second</li>"))
      assert.is_truthy(html_u:find("<li>Third</li>"))
      assert.is_truthy(html_u:find("</ul>"))

      local olist = "1. Item one\n2. Item two"
      local html_o = MD(olist)
      assert.is_truthy(html_o:find("<ol>"))
      assert.is_truthy(html_o:find("<li>Item one</li>"))
      assert.is_truthy(html_o:find("<li>Item two</li>"))
      assert.is_truthy(html_o:find("</ol>"))
    end)

    it("should parse fenced code blocks with and without language", function()
      local code_block = "```lua\nlocal a = 10\nlocal b = 20\n```"
      local html_code = MD(code_block)
      assert.is_truthy(html_code:find("<pre><code class=\"language%-lua\">"))
      assert.is_truthy(html_code:find("local a = 10"))
      assert.is_truthy(html_code:find("</code></pre>"))

      local plain_code = "```\nhello plain world\n```"
      local html_plain = MD(plain_code)
      assert.is_truthy(html_plain:find("<pre><code>"))
      assert.is_truthy(html_plain:find("hello plain world"))
      assert.is_truthy(html_plain:find("</code></pre>"))
    end)

    it("should ignore comment lines", function()
      local html = MD("<> this is a comment\nActual text")
      assert.is_falsy(html:find("this is a comment"))
      assert.is_truthy(html:find("<p>Actual text</p>"))
    end)
  end)

  describe("Rendering options", function()
    it("should wrap output with wrapper tag and attributes", function()
      local res = MD("# Title", {
        tag = "article",
        attributes = { id = "main-doc", class = "content" },
      })
      assert.is_truthy(res:find("^<article"))
      assert.is_truthy(res:find('id="main%-doc"'))
      assert.is_truthy(res:find('class="content"'))
      assert.is_truthy(res:find("</article>$"))
    end)

    it("should inject head and tail hooks", function()
      local res = MD("Simple text", {
        prependHead = "<!-- start -->",
        insertHead = "<header>Top</header>",
        insertTail = "<footer>Bottom</footer>",
        appendTail = "<!-- end -->",
      })
      assert.is_truthy(res:find("^<!%-%- start %-%->"))
      assert.is_truthy(res:find("<header>Top</header>"))
      assert.is_truthy(res:find("<footer>Bottom</footer>"))
      assert.is_truthy(res:find("<!%-%- end %-%->$"))
    end)
  end)
end)
