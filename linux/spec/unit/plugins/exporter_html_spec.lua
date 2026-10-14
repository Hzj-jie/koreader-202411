describe("HTML Exporter target module", function()
  local HtmlExporter
  local ffiUtil

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    HtmlExporter = require("plugins/exporter.koplugin/target/html")
    HtmlExporter.path = "plugins/exporter.koplugin"
    ffiUtil = require("ffi/util")
  end)

  it("should generate HTML content for single or multiple books", function()
    local booknotes = {
      title = "HTML Book",
      author = "Author Name",
      {
        {
          chapter = "Chapter 1",
          text = "HTML Clipping 1",
          page = 1,
          time = 1715774400,
        },
      },
      {
        {
          chapter = "Chapter 1",
          text = "HTML Clipping 2",
          page = 2,
          time = 1715774500,
        },
      },
    }

    local content = HtmlExporter:getRenderedContent({ booknotes })
    assert.is_string(content)
    assert.is_truthy(content:find("HTML Book"))
    assert.is_truthy(content:find("Chapter 1"))
    assert.is_truthy(content:find("HTML Clipping 1"))
    assert.is_truthy(content:find("HTML Clipping 2"))
  end)

  it("should group clippings by chapter transitions", function()
    local booknotes = {
      title = "Multi Chapter Book",
      author = "Author Name",
      {
        {
          chapter = "Chapter 1",
          text = "C1 text",
          page = 1,
          time = 1715774400,
        },
      },
      {
        {
          chapter = "Chapter 2",
          text = "C2 text",
          page = 10,
          time = 1715774500,
        },
      },
    }

    local content = HtmlExporter:getRenderedContent({ booknotes })
    assert.is_string(content)
    assert.is_truthy(content:find("Chapter 1"))
    assert.is_truthy(content:find("Chapter 2"))
    assert.is_truthy(content:find("C1 text"))
    assert.is_truthy(content:find("C2 text"))
  end)

  it(
    "should set document title to All Books when exporting multiple books",
    function()
      local book1 = {
        title = "Book One",
        author = "Author A",
        { { chapter = "Ch 1", text = "Text 1", page = 1, time = 1715774400 } },
      }
      local book2 = {
        title = "Book Two",
        author = "Author B",
        { { chapter = "Ch 1", text = "Text 2", page = 2, time = 1715774400 } },
      }

      local content = HtmlExporter:getRenderedContent({ book1, book2 })
      assert.is_string(content)
      assert.is_truthy(content:find("All Books"))
    end
  )

  it("should export HTML content to file", function()
    local pid = ffiUtil.getpid()
    local tmp_file = string.format("/tmp/test_exporter_html_%d.html", pid)
    HtmlExporter.getFilePath = function()
      return tmp_file
    end

    local notes = {
      {
        title = "Exported HTML Book",
        author = "Author Name",
        {
          { chapter = "Ch 1", text = "Text", page = 5, time = 1715774400 },
        },
      },
    }

    assert.is_true(HtmlExporter:export(notes))

    local f = io.open(tmp_file, "r")
    assert.is_not_nil(f)
    local text = f:read("*a")
    f:close()

    assert.is_true(#text > 0)
    assert.is_truthy(text:find("Exported HTML Book"))
    os.remove(tmp_file)
  end)

  it("should return false when target file cannot be opened", function()
    HtmlExporter.getFilePath = function()
      return "/nonexistent_dir_cannot_write/file.html"
    end

    local notes = {
      {
        title = "Failed Book",
        author = "Author",
        { { chapter = "Ch 1", text = "Text", page = 1, time = 1715774400 } },
      },
    }

    assert.is_false(HtmlExporter:export(notes))
  end)

  it("should trigger shareText with rendered HTML", function()
    local shared_text = nil
    HtmlExporter.shareText = function(self, text)
      shared_text = text
    end

    local booknotes = {
      title = "Shared HTML Book",
      author = "Author Name",
      {
        { chapter = "Ch 1", text = "Text", page = 5, time = 1715774400 },
      },
    }

    HtmlExporter:share(booknotes)
    assert.is_string(shared_text)
    assert.is_true(#shared_text > 0)
    assert.is_truthy(shared_text:find("Shared HTML Book"))
  end)
end)
