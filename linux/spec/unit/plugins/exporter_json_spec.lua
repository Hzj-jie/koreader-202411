describe("JSON Exporter target module", function()
  local JsonExporter

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    JsonExporter = require("plugins/exporter.koplugin/target/json")
  end)

  it("should build menu table with settings callbacks", function()
    JsonExporter.isEnabled = function() return true end
    JsonExporter.settings = { bookChecksum = true }
    JsonExporter.saveSettings = function() end

    local menu = JsonExporter:getMenuTable()
    assert.is_table(menu)
    assert.are.equal("Json", menu.text)
    assert.is_table(menu.sub_item_table)
    assert.are.equal(2, #menu.sub_item_table)
  end)

  it("should export single book and multiple books notes to JSON file", function()
    local tmp_file = os.tmpname()
    JsonExporter.getFilePath = function() return tmp_file end
    JsonExporter.settings = { bookChecksum = false }

    local single_notes = {
      {
        title = "Book 1",
        author = "Author 1",
        exported = "2024-05-15",
        file = "book1.epub",
        number_of_pages = 100,
        { { text = "Clipping 1" } },
      },
    }

    assert.is_true(JsonExporter:export(single_notes))

    local f = io.open(tmp_file, "r")
    assert.is_not_nil(f)
    local content = f:read("*a")
    f:close()
    assert.is_true(content:find("Book 1") ~= nil)

    local multi_notes = {
      { title = "Book 1", author = "Author 1", { { text = "Clipping 1" } } },
      { title = "Book 2", author = "Author 2", { { text = "Clipping 2" } } },
    }
    assert.is_true(JsonExporter:export(multi_notes))

    os.remove(tmp_file)
  end)

  it("should format and trigger shareText for single book notes", function()
    JsonExporter.settings = { bookChecksum = false }
    local shared_text = nil
    JsonExporter.shareText = function(self, text)
      shared_text = text
    end

    local booknotes = {
      title = "Shared Book",
      author = "Author",
      { { text = "Shared Clipping" } },
    }

    JsonExporter:share(booknotes)
    assert.is_string(shared_text)
    assert.is_true(shared_text:find("Shared Book") ~= nil)
  end)
end)
