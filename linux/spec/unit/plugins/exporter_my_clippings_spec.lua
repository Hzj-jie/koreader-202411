describe("My Clippings Exporter target module", function()
  local ClippingsExporter

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    ClippingsExporter = require("plugins/exporter.koplugin/target/my_clippings")
  end)

  it("should format and export clippings to file", function()
    local tmp_file = os.tmpname()
    ClippingsExporter.getFilePath = function()
      return tmp_file
    end

    local notes = {
      {
        title = "Test Book",
        author = "Test Author",
        {
          {
            text = "Highlight text",
            note = "Personal note",
            page = 12,
            time = 1715774400,
          },
        },
      },
    }

    assert.is_true(ClippingsExporter:export(notes))

    local f = io.open(tmp_file, "r")
    assert.is_not_nil(f)
    local content = f:read("*a")
    f:close()

    assert.is_true(content:find("Test Book") ~= nil)
    assert.is_true(content:find("Highlight text") ~= nil)
    assert.is_true(content:find("Personal note") ~= nil)
    assert.is_true(content:find("==========") ~= nil)

    os.remove(tmp_file)
  end)

  it("should trigger shareText with formatted clippings content", function()
    local shared_text = nil
    ClippingsExporter.shareText = function(self, text)
      shared_text = text
    end

    local booknotes = {
      title = "Shared Book",
      author = "Author",
      {
        {
          text = "Shared Highlight",
          page = 1,
          time = 1715774400,
        },
      },
    }

    ClippingsExporter:share(booknotes)
    assert.is_string(shared_text)
    assert.is_true(shared_text:find("Shared Book") ~= nil)
  end)
end)
