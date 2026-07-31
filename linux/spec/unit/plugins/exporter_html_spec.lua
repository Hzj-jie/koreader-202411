describe("HTML Exporter target module", function()
  local HtmlExporter

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    HtmlExporter = require("plugins/exporter.koplugin/target/html")
    HtmlExporter.path = "plugins/exporter.koplugin"
  end)

  it("should generate HTML content for single or multiple books", function()
    local booknotes = {
      title = "HTML Book",
      author = "Author Name",
      {
        { chapter = "Chapter 1", text = "HTML Clipping", page = 1, time = 1715774400 },
      },
    }

    local content = HtmlExporter:getRenderedContent({ booknotes })
    assert.is_string(content)
    assert.is_true(content:find("HTML Book") ~= nil)
  end)

  it("should export HTML content to file", function()
    local tmp_file = os.tmpname()
    HtmlExporter.getFilePath = function() return tmp_file end

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
    os.remove(tmp_file)
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
  end)
end)
