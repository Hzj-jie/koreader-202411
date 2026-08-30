describe("Memos Exporter target module", function()
  local MemosExporter, http

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    http = require("socket.http")
    MemosExporter = require("plugins/exporter.koplugin/target/memos")
  end)

  it("should check readiness based on API and token settings", function()
    MemosExporter.settings = {}
    assert.is_false(MemosExporter:isReadyToExport())

    MemosExporter.settings = {
      api = "https://memos.example.com/api/v1/memo",
      token = "sample_token",
    }
    assert.is_true(MemosExporter:isReadyToExport())
  end)

  it("should build menu table with configuration callbacks", function()
    MemosExporter.isEnabled = function()
      return true
    end
    local menu = MemosExporter:getMenuTable()

    assert.is_table(menu)
    assert.are.equal("Memos", menu.text)
    assert.is_table(menu.sub_item_table)
    assert.are.equal(3, #menu.sub_item_table)
  end)

  it("should create highlights and handle HTTP response", function()
    MemosExporter.settings = {
      api = "https://memos.example.com/api/v1/memo",
      token = "sample_token",
    }

    local old_request = http.request
    http.request = function(req)
      req.sink('{"id":1}')
      return 1, 200, {}, "200 OK"
    end

    local booknotes = {
      title = "Test Book",
      {
        { text = "Sample clipping text", note = "My note", page = 5 },
      },
    }

    local res = MemosExporter:createHighlights(booknotes)
    assert.is_true(res)

    http.request = old_request
  end)

  it("should execute export flow for book notes", function()
    MemosExporter.settings = {
      api = "https://memos.example.com/api/v1/memo",
      token = "sample_token",
    }

    local old_request = http.request
    http.request = function(req)
      req.sink('{"id":1}')
      return 1, 200, {}, "200 OK"
    end

    local notes = {
      {
        title = "Test Book",
        {
          { text = "Sample clipping", page = 1 },
        },
      },
    }

    assert.is_true(MemosExporter:export(notes))

    http.request = old_request
  end)
end)
