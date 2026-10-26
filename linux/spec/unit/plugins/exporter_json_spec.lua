describe("JSON Exporter target module", function()
  local JsonExporter
  local ffiUtil
  local md5

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    JsonExporter = require("plugins/exporter.koplugin/target/json")
    ffiUtil = require("ffi/util")
    md5 = require("ffi/MD5")
  end)

  it("should build menu table with settings callbacks and toggles", function()
    local enabled = true
    local saved = false
    JsonExporter.isEnabled = function()
      return enabled
    end
    JsonExporter.toggleEnabled = function()
      enabled = not enabled
    end
    JsonExporter.settings = { bookChecksum = true }
    JsonExporter.saveSettings = function()
      saved = true
    end

    local menu = JsonExporter:getMenuTable()
    assert.is_table(menu)
    assert.are.equal("Json", menu.text)
    assert.is_true(menu.checked_func())

    assert.is_table(menu.sub_item_table)
    assert.are.equal(2, #menu.sub_item_table)

    -- Test toggle enabled callback
    local item_export = menu.sub_item_table[1]
    assert.is_true(item_export.checked_func())
    item_export.callback()
    assert.is_false(enabled)

    -- Test toggle checksum callback
    local item_checksum = menu.sub_item_table[2]
    assert.is_true(item_checksum.checked_func())
    item_checksum.callback()
    assert.is_false(JsonExporter.settings.bookChecksum)
    assert.is_true(saved)
  end)

  it("should export single book with book checksum when enabled", function()
    local pid = ffiUtil.getpid()
    local tmp_file = string.format("/tmp/test_exporter_json_chk_%d.json", pid)
    JsonExporter.getFilePath = function()
      return tmp_file
    end
    JsonExporter.settings = { bookChecksum = true }
    local old_sum = md5.sumFile
    md5.sumFile = function()
      return "0123456789abcdef0123456789abcdef"
    end

    local single_notes = {
      {
        title = "Checksum Book",
        author = "Author A",
        exported = "2024-05-15",
        file = "/books/book.epub",
        number_of_pages = 250,
        { { text = "Clipping with checksum" } },
      },
    }

    assert.is_true(JsonExporter:export(single_notes))

    local f = io.open(tmp_file, "r")
    assert.is_not_nil(f)
    local content = f:read("*a")
    f:close()

    assert.is_truthy(content:find("Checksum Book"))
    assert.is_truthy(content:find("0123456789abcdef0123456789abcdef"))

    md5.sumFile = old_sum
    os.remove(tmp_file)
  end)

  it(
    "should export multiple books notes to JSON documents structure",
    function()
      local pid = ffiUtil.getpid()
      local tmp_file =
        string.format("/tmp/test_exporter_json_multi_%d.json", pid)
      JsonExporter.getFilePath = function()
        return tmp_file
      end
      JsonExporter.settings = { bookChecksum = false }

      local multi_notes = {
        {
          title = "Book 1",
          author = "Author 1",
          exported = "2024-05-15",
          file = "book1.epub",
          number_of_pages = 100,
          { { text = "Clipping 1" } },
        },
        {
          title = "Book 2",
          author = "Author 2",
          exported = "2024-05-16",
          file = "book2.epub",
          number_of_pages = 200,
          { { text = "Clipping 2" } },
        },
      }

      assert.is_true(JsonExporter:export(multi_notes))

      local f = io.open(tmp_file, "r")
      assert.is_not_nil(f)
      local content = f:read("*a")
      f:close()

      assert.is_truthy(content:find("Book 1"))
      assert.is_truthy(content:find("Book 2"))
      assert.is_truthy(content:find("documents"))

      os.remove(tmp_file)
    end
  )

  it("should return false when target file cannot be opened", function()
    JsonExporter.getFilePath = function()
      return "/nonexistent_unwritable_dir/file.json"
    end
    JsonExporter.settings = { bookChecksum = false }

    local notes = {
      { title = "Book 1", author = "Author 1", { { text = "Clipping 1" } } },
    }
    assert.is_false(JsonExporter:export(notes))
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
    assert.is_truthy(shared_text:find("Shared Book"))
    assert.is_truthy(shared_text:find("Shared Clipping"))
  end)
end)
