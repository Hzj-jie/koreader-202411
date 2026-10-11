-- luacheck: ignore 122
local http = require("socket.http")

describe("ReadwiseExporter module", function()
  local ReadwiseExporter

  setup(function()
    require("commonrequire")
    ReadwiseExporter = require("plugins/exporter.koplugin/target/readwise")
  end)

  it("should validate readiness based on token configuration", function()
    ReadwiseExporter.settings = {}
    assert.is_false(ReadwiseExporter:isReadyToExport())

    ReadwiseExporter.settings = { token = "test-token" }
    assert.is_true(ReadwiseExporter:isReadyToExport())
  end)

  it("handles nil book author without crashing on gsub", function()
    local orig_request = http.request
    http.request = function(req)
      if req.sink then
        req.sink('{"id": 1}', 10)
      end
      return 1, 200, {}, "OK"
    end
    finally(function()
      http.request = orig_request
    end)

    ReadwiseExporter.settings = { token = "valid-token" }

    local booknotes = {
      title = "Anonymous Article",
      author = nil,
      {
        { text = "Fascinating excerpt", page = 1, time = 1700000000 },
      },
    }

    assert.has_no.errors(function()
      ReadwiseExporter:createHighlights(booknotes)
    end)
  end)

  it("decodes multi-chunk JSON responses from makeRequest", function()
    local orig_request = http.request
    http.request = function(req)
      if req.sink then
        req.sink('{"status":')
        req.sink('"ok"}')
      end
      return 1, 200, {}, "OK"
    end
    finally(function()
      http.request = orig_request
    end)

    ReadwiseExporter.settings = { token = "valid-token" }

    local booknotes = {
      title = "A Book",
      author = "An Author",
      {
        { text = "A quote", page = 1, time = 1700000000 },
      },
    }

    -- Exposes defect: makeRequest decodes json.decode(sink[1]) instead of
    -- json.decode(table.concat(sink)), failing on chunked responses.
    local ok = ReadwiseExporter:createHighlights(booknotes)
    assert.is_true(ok)
  end)
end)
