-- luacheck: ignore 122
describe("Exporter BaseExporter plugin module", function()
  local BaseExporter, DataStorage, Device

  setup(function()
    require("commonrequire")
    BaseExporter = require("plugins/exporter.koplugin/base")
    DataStorage = require("datastorage")
    Device = require("device")
  end)

  before_each(function()
    G_reader_settings:save("exporter", {})
  end)

  describe("Lifecycle and configuration", function()
    it("requires a string name on construction", function()
      assert.has_error(function()
        BaseExporter:new({})
      end, "name is mandatory")
    end)

    it("initializes default attributes and version", function()
      local exporter = BaseExporter:new({ name = "html" })
      assert.are.equal("html", exporter.name)
      assert.are.equal("html", exporter.extension)
      assert.is_false(exporter.is_remote)
      assert.are.equal("1.0.0", exporter.version)
      assert.are.equal("html/1.0.0", exporter:getVersion())
    end)

    it("executes init_callback and saves modified settings", function()
      local callback_called = false
      local exporter = BaseExporter:new({
        name = "custom",
        init_callback = function(_, settings)
          callback_called = true
          settings.api_key = "secret_123"
          return true, settings
        end,
      })

      assert.is_true(callback_called)
      assert.are.equal("secret_123", exporter.settings.api_key)
      assert.is_true(exporter.new_settings)

      local saved = G_reader_settings:readTableRef("exporter")
      assert.are.equal("secret_123", saved.custom.api_key)
    end)

    it("manages enabled state via toggleEnabled and isEnabled", function()
      local exporter = BaseExporter:new({ name = "markdown" })
      assert.is_falsy(exporter:isEnabled())

      exporter:toggleEnabled()
      assert.is_true(exporter:isEnabled())

      exporter:toggleEnabled()
      assert.is_falsy(exporter:isEnabled())
    end)

    it("generates menu table reflecting enabled state", function()
      local exporter = BaseExporter:new({ name = "text" })
      local menu = exporter:getMenuTable()

      assert.are.equal("Text", menu.text)
      assert.is_falsy(menu.checked_func())

      menu.callback()
      assert.is_true(menu.checked_func())
    end)

    it("formats ISO-like timestamp from fixed or current time", function()
      local fixed_time = 1700000000
      local exporter =
        BaseExporter:new({ name = "json", timestamp = fixed_time })
      assert.are.equal(
        os.date("%Y-%m-%d-%H-%M-%S", fixed_time),
        exporter:getTimeStamp()
      )
    end)
  end)

  describe("File path resolution", function()
    it("returns nil for remote exporters", function()
      local exporter = BaseExporter:new({ name = "cloud", is_remote = true })
      assert.is_nil(exporter:getFilePath({}))
    end)

    it("resolves multi-book export path in clipping directory", function()
      local exporter = BaseExporter:new({
        name = "markdown",
        extension = "md",
        timestamp = 1700000000,
      })
      local t = {
        { output_filename = "Book1" },
        { output_filename = "Book2" },
      }
      local path = exporter:getFilePath(t)
      assert.is_string(path)
      assert.is_truthy(path:find("all-books.md", 1, true))
    end)

    it(
      "resolves single-book export path in book folder when clipping_dir_book is enabled",
      function()
        G_reader_settings:save("exporter", { clipping_dir_book = true })
        local exporter = BaseExporter:new({
          name = "text",
          extension = "txt",
          timestamp = 1700000000,
        })
        local t = {
          {
            file = "/sdcard/books/fiction/sample.epub",
            output_filename = "sample",
          },
        }
        local path = exporter:getFilePath(t)
        assert.is_string(path)
        assert.is_truthy(path:match("^/sdcard/books/fiction/"))
        assert.is_truthy(path:match("%-sample%.txt$"))
      end
    )
  end)

  describe("Defect verifications", function()
    it(
      "fails: exposes getFilePath crashing when #t == 1 and output_filename is nil",
      function()
        local exporter = BaseExporter:new({
          name = "notes",
          extension = "txt",
          timestamp = 1700000000,
        })

        -- A single book note table where output_filename was omitted or nil
        local single_book_notes = {
          { file = "/tmp/sample.epub" },
        }

        -- When #t == 1 and t[1].output_filename is nil:
        -- title becomes nil.
        -- string.format("%s-%s.%s", self:getTimeStamp(), title, self.extension)
        -- produces a path with "-nil.txt" instead of falling back to a valid title/bookname
        local path = exporter:getFilePath(single_book_notes)
        assert.is_string(path)
        assert.is_falsy(
          path:find("-nil.", 1, true),
          "File path should not contain '-nil.' when output_filename is nil"
        )
      end
    )
  end)
end)
