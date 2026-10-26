describe("My Clippings Exporter target module", function()
  local ClippingsExporter
  local ffiUtil

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    ClippingsExporter = require("plugins/exporter.koplugin/target/my_clippings")
    ffiUtil = require("ffi/util")
  end)

  it(
    "should format and export clippings to file with notes and author fallback",
    function()
      local pid = ffiUtil.getpid()
      local tmp_file = string.format("/tmp/test_exporter_clippings_%d.txt", pid)
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
        {
          title = "Anonymous Book",
          author = nil,
          {
            {
              text = "Anonymous Highlight",
              page = 5,
              time = 1715774500,
            },
          },
        },
      }

      assert.is_true(ClippingsExporter:export(notes))

      local f = io.open(tmp_file, "r")
      assert.is_not_nil(f)
      local content = f:read("*a")
      f:close()

      assert.is_truthy(content:find("Test Book %(Test Author%)"))
      assert.is_truthy(content:find("Highlight text"))
      assert.is_truthy(content:find("Personal note"))
      assert.is_truthy(content:find("Anonymous Book %(Unknown%)"))
      assert.is_truthy(content:find("Anonymous Highlight"))
      assert.is_truthy(content:find("=========="))

      os.remove(tmp_file)
    end
  )

  it("should append clippings when exporting repeatedly", function()
    local pid = ffiUtil.getpid()
    local tmp_file =
      string.format("/tmp/test_exporter_clippings_append_%d.txt", pid)
    ClippingsExporter.getFilePath = function()
      return tmp_file
    end

    local note1 = {
      {
        title = "Book 1",
        author = "Author 1",
        { { text = "First text", page = 1, time = 1715774400 } },
      },
    }
    local note2 = {
      {
        title = "Book 2",
        author = "Author 2",
        { { text = "Second text", page = 2, time = 1715774500 } },
      },
    }

    assert.is_true(ClippingsExporter:export(note1))
    assert.is_true(ClippingsExporter:export(note2))

    local f = io.open(tmp_file, "r")
    assert.is_not_nil(f)
    local content = f:read("*a")
    f:close()

    assert.is_truthy(content:find("First text"))
    assert.is_truthy(content:find("Second text"))

    os.remove(tmp_file)
  end)

  it("should return false when target file cannot be opened", function()
    ClippingsExporter.getFilePath = function()
      return "/nonexistent_unwritable_dir/my_clippings.txt"
    end

    local notes = {
      {
        title = "Book",
        author = "Author",
        { { text = "Text", page = 1, time = 1715774400 } },
      },
    }

    assert.is_false(ClippingsExporter:export(notes))
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
    assert.is_truthy(shared_text:find("Shared Book"))
    assert.is_truthy(shared_text:find("Shared Highlight"))
    assert.is_truthy(shared_text:find("=========="))
  end)
end)
