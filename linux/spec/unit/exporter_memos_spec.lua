-- luacheck: ignore 122
local http = require("socket.http")
local json = require("json")

describe("MemosExporter module", function()
  local MemosExporter

  setup(function()
    require("commonrequire")
    MemosExporter = require("plugins/exporter.koplugin/target/memos")
  end)

  it(
    "should validate readiness based on api and token configuration",
    function()
      MemosExporter.settings = {}
      assert.is_false(MemosExporter:isReadyToExport())

      MemosExporter.settings = { api = "http://localhost:5230/api/v1/memo" }
      assert.is_false(MemosExporter:isReadyToExport())

      MemosExporter.settings = {
        api = "http://localhost:5230/api/v1/memo",
        token = "test-token",
      }
      assert.is_true(MemosExporter:isReadyToExport())
    end
  )

  it(
    "returns false from createHighlights when highlight exports fail",
    function()
      local orig_request = http.request
      http.request = function()
        return nil, "connection refused"
      end
      finally(function()
        http.request = orig_request
      end)

      MemosExporter.settings = {
        api = "http://localhost:5230/api/v1/memo",
        token = "test-token",
      }

      local booknotes = {
        title = "Test Book",
        {
          { text = "Highlight 1", page = 10 },
          { text = "Highlight 2", page = 15 },
        },
      }

      local ok = MemosExporter:createHighlights(booknotes)
      assert.is_false(ok)
    end
  )

  it(
    "includes Content-Length header in makeRequest for JSON payloads",
    function()
      local captured_req = nil
      local orig_request = http.request
      http.request = function(req)
        captured_req = req
        if req.sink then
          req.sink('{"id": 1}', 10)
        end
        return 1, 200, { ["content-type"] = "application/json" }, "OK"
      end
      finally(function()
        http.request = orig_request
      end)

      MemosExporter.settings = {
        api = "http://localhost:5230/api/v1/memo",
        token = "test-token",
      }

      local booknotes = {
        title = "Test Book",
        {
          { text = "Highlight 1", page = 10 },
        },
      }

      MemosExporter:createHighlights(booknotes)
      assert.is_not_nil(captured_req)
      assert.is_not_nil(captured_req.headers["Content-Length"])
    end
  )

  it("formats page numbers with matching ASCII parentheses", function()
    local captured_content = nil
    local orig_request = http.request
    http.request = function(req)
      local chunks = {}
      while true do
        local chunk = req.source()
        if not chunk then
          break
        end
        table.insert(chunks, chunk)
      end
      local body = table.concat(chunks)
      local data = json.decode(body)
      captured_content = data.content
      if req.sink then
        req.sink('{"id": 1}', 10)
      end
      return 1, 200, {}, "OK"
    end
    finally(function()
      http.request = orig_request
    end)

    MemosExporter.settings = {
      api = "http://localhost:5230/api/v1/memo",
      token = "test-token",
    }

    local booknotes = {
      title = "Test Book",
      {
        { text = "Highlight 1", page = 42 },
      },
    }

    MemosExporter:createHighlights(booknotes)
    assert.is_string(captured_content)
    assert.is_true(captured_content:find("%(page: 42%)") ~= nil)
  end)

  it("decodes multi-chunk JSON responses in makeRequest", function()
    local orig_request = http.request
    http.request = function(req)
      if req.sink then
        req.sink('{"status":')
        req.sink('"success"}')
      end
      return 1, 200, {}, "OK"
    end
    finally(function()
      http.request = orig_request
    end)

    MemosExporter.settings = {
      api = "http://localhost:5230/api/v1/memo",
      token = "test-token",
    }

    local booknotes = {
      title = "Test Book",
      {
        { text = "Highlight 1", page = 1 },
      },
    }

    local ok = MemosExporter:createHighlights(booknotes)
    assert.is_true(ok)
  end)
end)
