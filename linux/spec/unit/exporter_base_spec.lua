describe("BaseExporter module", function()
  local BaseExporter

  setup(function()
    require("commonrequire")
    BaseExporter = require("plugins/exporter.koplugin/base")
  end)

  it("should enforce mandatory name and initialize default fields", function()
    assert.has_error(function()
      BaseExporter:new({})
    end, "name is mandatory")

    local exporter = BaseExporter:new({ name = "customexporter" })
    assert.is_table(exporter)
    assert.are.equal("customexporter", exporter.name)
    assert.are.equal("customexporter", exporter.extension)
    assert.is_false(exporter.is_remote)
    assert.are.equal("1.0.0", exporter.version)
    assert.are.equal("customexporter/1.0.0", exporter:getVersion())
    assert.is_string(exporter:getTimeStamp())
  end)

  it(
    "should compute local file paths for single and multiple booknotes",
    function()
      local exporter =
        BaseExporter:new({ name = "myexport", extension = "txt" })
      local note1 = { file = "/books/book1.epub", output_filename = "book1" }
      local note2 = { file = "/books/book2.epub", output_filename = "book2" }

      local single_path = exporter:getFilePath({ note1 })
      assert.is_string(single_path)
      assert.is_true(single_path:find("book1.txt$") ~= nil)

      local multi_path = exporter:getFilePath({ note1, note2 })
      assert.is_string(multi_path)
      assert.is_true(multi_path:find("all%-books.txt$") ~= nil)

      local remote_exporter =
        BaseExporter:new({ name = "remotesvc", is_remote = true })
      assert.is_nil(remote_exporter:getFilePath({ note1 }))
    end
  )

  it("should toggle enabled state when ready to export", function()
    local exporter = BaseExporter:new({ name = "toggleexporter" })
    exporter.settings = { enabled = false }
    assert.is_false(exporter:isEnabled())

    exporter:toggleEnabled()
    assert.is_true(exporter:isEnabled())

    exporter:toggleEnabled()
    assert.is_false(exporter:isEnabled())
  end)

  it("saves exporter settings into reader settings table", function()
    local exporter = BaseExporter:new({ name = "testexporter" })
    exporter.settings.enabled = true
    exporter:saveSettings()

    local plugin_settings = G_reader_settings:readTableRef("exporter")
    assert.is_true(plugin_settings.testexporter.enabled)
    assert.is_true(exporter.new_settings)
  end)
end)
