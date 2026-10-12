describe("ClippingsExporter module", function()
  local ClippingsExporter

  setup(function()
    require("commonrequire")
    ClippingsExporter = require("plugins/exporter.koplugin/target/my_clippings")
  end)

  it("should initialize with correct metadata and txt extension", function()
    assert.are.equal("myClippings", ClippingsExporter.name)
    assert.are.equal("txt", ClippingsExporter.extension)
    assert.are.equal("text/plain", ClippingsExporter.mimetype)
    assert.are.equal("myClippings", ClippingsExporter.all_books_title)
  end)

  it("should export booknotes to file in append mode", function()
    local written_content = {}
    local orig_open = io.open
    local dummy_file = {
      write = function(_, text)
        table.insert(written_content, text)
      end,
      close = function() end,
    }
    io.open = function(path, mode)
      assert.are.equal("a", mode)
      return dummy_file
    end
    finally(function()
      io.open = orig_open
    end)

    local booknotes = {
      title = "Sample Book",
      author = "Jane Doe",
      output_filename = "sample_book",
      {
        { text = "Great passage", page = 12, time = 1600000000 },
      },
    }

    local ok = ClippingsExporter:export({ booknotes })
    assert.is_true(ok)
    assert.is_true(#written_content > 0)
    local full_text = table.concat(written_content)
    assert.is_true(full_text:find("Sample Book") ~= nil)
    assert.is_true(full_text:find("Jane Doe") ~= nil)
    assert.is_true(full_text:find("Great passage") ~= nil)
  end)

  it("shares formatted clipping content across booknotes", function()
    local shared_text = nil
    local orig_share = ClippingsExporter.shareText
    ClippingsExporter.shareText = function(_, text)
      shared_text = text
    end
    finally(function()
      ClippingsExporter.shareText = orig_share
    end)

    local booknotes = {
      title = "Test Novel",
      author = "Famous Author",
      {
        { text = "Memorable quote from book", page = 42, time = 1234567890 },
      },
    }

    ClippingsExporter:share(booknotes)
    assert.is_not_nil(shared_text)
    assert.is_true(shared_text:find("Test Novel") ~= nil)
  end)
end)
