describe("XMNote Exporter plugin target", function()
  local XMNoteExporter, http

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    http = require("socket.http")
    XMNoteExporter = require("plugins/exporter.koplugin/target/xmnote")
  end)

  it("should check readiness to export based on IP setting", function()
    local exporter = XMNoteExporter:new({ name = "xmnote" })
    assert.is_false(exporter:isReadyToExport())

    exporter.settings.ip = "192.168.1.100"
    assert.is_true(exporter:isReadyToExport())
  end)

  it("should generate menu table structure", function()
    local exporter = XMNoteExporter:new({ name = "xmnote" })
    local menu = exporter:getMenuTable()
    assert.is_table(menu)
    assert.is_table(menu.sub_item_table)
    assert.are.equal(3, #menu.sub_item_table)
  end)

  it("should format request body correctly", function()
    local exporter = XMNoteExporter:new({ name = "xmnote" })
    local booknotes = {
      title = "Sample Book",
      author = "Sample Author",
      {
        {
          text = "Sample highlight text",
          note = "Sample note",
          chapter = "Chapter 1",
          page = 15,
        },
      },
    }

    local body = exporter:createRequestBody(booknotes)
    assert.is_table(body)
    assert.are.equal("Sample Book", body.title)
    assert.are.equal("Sample Author", body.author)
    assert.is_table(body.entries)
    assert.are.equal(1, #body.entries)
    assert.are.equal("Sample highlight text", body.entries[1].text)
    assert.are.equal(15, body.entries[1].page)
  end)

  it("should post highlights to XMNote API successfully", function()
    local old_request = http.request
    local request_url = nil

    http.request = function(req)
      request_url = req.url
      local sink = req.sink
      sink('{"code":200,"message":"success"}')
      return 1, 200, {}, "200 OK"
    end

    local exporter = XMNoteExporter:new({ name = "xmnote" })
    exporter.settings.ip = "192.168.1.100"

    local booknotes = {
      title = "Sample Book",
      {
        {
          text = "Sample highlight text",
          page = 5,
        },
      },
    }

    local ok = exporter:export({ booknotes })
    assert.is_true(ok)
    assert.are.equal("http://192.168.1.100:8080/send", request_url)

    http.request = old_request
  end)

  it("should handle API error codes gracefully", function()
    local old_request = http.request

    http.request = function(req)
      local sink = req.sink
      sink('{"code":500,"message":"internal error"}')
      return 1, 200, {}, "200 OK"
    end

    local exporter = XMNoteExporter:new({ name = "xmnote" })
    exporter.settings.ip = "192.168.1.100"

    local booknotes = {
      title = "Sample Book",
      {
        {
          text = "Sample highlight text",
          page = 5,
        },
      },
    }

    local ok = exporter:export({ booknotes })
    assert.is_false(ok)

    http.request = old_request
  end)
end)
