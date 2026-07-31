describe("Flomo Exporter plugin target", function()
  local FlomoExporter, http

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    http = require("socket.http")
    FlomoExporter = require("plugins/exporter.koplugin/target/flomo")
  end)

  it("should check readiness to export based on API URL setting", function()
    local exporter = FlomoExporter:new({ name = "flomo" })
    assert.is_false(exporter:isReadyToExport())

    exporter.settings.api = "https://flomoapp.com/api/v1/memo/test/"
    assert.is_true(exporter:isReadyToExport())
  end)

  it("should generate menu table structure", function()
    local exporter = FlomoExporter:new({ name = "flomo" })
    local menu = exporter:getMenuTable()
    assert.is_table(menu)
    assert.is_table(menu.sub_item_table)
    assert.are.equal(2, #menu.sub_item_table)
  end)

  it("should format and post highlights to Flomo API", function()
    local old_request = http.request
    local posted_data = nil

    http.request = function(req)
      local sink = req.sink
      posted_data = req.source()
      sink('{"code":0,"message":"success"}')
      return 1, 200, {}, "200 OK"
    end

    local exporter = FlomoExporter:new({ name = "flomo" })
    exporter.settings.api = "https://flomoapp.com/api/v1/memo/test/"

    local booknotes = {
      title = "Test Book Title",
      {
        {
          text = "Selected highlight quote",
          note = "User comment note",
          page = 42,
        },
      },
    }

    local ok = exporter:export({ booknotes })
    assert.is_true(ok)
    assert.is_string(posted_data)
    assert.is_number(posted_data:find("Selected highlight quote"))
    assert.is_number(posted_data:find("User comment note"))
    assert.is_number(posted_data:find("#Test Book Title"))

    http.request = old_request
  end)

  it("should handle HTTP errors during highlight export gracefully", function()
    local old_request = http.request

    http.request = function(req)
      return 1, 500, {}, "500 Internal Error"
    end

    local exporter = FlomoExporter:new({ name = "flomo" })
    exporter.settings.api = "https://flomoapp.com/api/v1/memo/test/"

    local booknotes = {
      title = "Test Book Title",
      {
        {
          text = "Selected highlight quote",
          page = 1,
        },
      },
    }

    local ok = exporter:export({ booknotes })
    assert.is_true(ok)

    http.request = old_request
  end)
end)
