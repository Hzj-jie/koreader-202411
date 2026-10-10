describe("Flomo Exporter plugin target", function()
  local FlomoExporter, http, UIManager

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    http = require("socket.http")
    UIManager = require("ui/uimanager")
    FlomoExporter = require("plugins/exporter.koplugin/target/flomo")
  end)

  before_each(function()
    UIManager.setDirty = function() end
  end)

  it("should check readiness to export based on API URL setting", function()
    local exporter = FlomoExporter:new({ name = "flomo" })
    assert.is_false(exporter:isReadyToExport())

    exporter.settings.api = "https://flomoapp.com/api/v1/memo/test/"
    assert.is_true(exporter:isReadyToExport())
  end)

  it(
    "should generate menu table structure and handle dialog callbacks",
    function()
      local exporter = FlomoExporter:new({ name = "flomo" })
      exporter.settings.api = "https://flomoapp.com/api/v1/memo/test/"
      local menu = exporter:getMenuTable()
      assert.is_table(menu)
      assert.is_table(menu.sub_item_table)
      assert.are.equal(2, #menu.sub_item_table)

      -- Toggle enabled callback
      assert.is_falsy(exporter:isEnabled())
      menu.sub_item_table[2].callback()
      assert.is_true(exporter:isEnabled())

      -- Set API URL dialog callback
      local shown_dialog = nil
      local old_show = UIManager.show
      local old_close = UIManager.close
      UIManager.show = function(self_u, w)
        shown_dialog = w
      end
      UIManager.close = function() end

      menu.sub_item_table[1].callback()
      assert.is_not_nil(shown_dialog)
      shown_dialog.getInputText = function()
        return "https://flomoapp.com/api/v1/memo/newurl/"
      end
      -- Trigger "Set API URL" button callback
      shown_dialog.buttons[1][2].callback()
      assert.are.equal(
        "https://flomoapp.com/api/v1/memo/newurl/",
        exporter.settings.api
      )

      UIManager.show = old_show
      UIManager.close = old_close
    end
  )

  it(
    "should format and post highlights with valid single-chunk response",
    function()
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
    end
  )

  it(
    "should include Content-Length header in HTTP POST request [exposes production bug in makeRequest()]",
    function()
      local old_request = http.request
      local captured_headers = nil

      http.request = function(req)
        captured_headers = req.headers
        req.sink('{"code":0,"message":"success"}')
        return 1, 200, {}, "200 OK"
      end

      local exporter = FlomoExporter:new({ name = "flomo" })
      exporter.settings.api = "https://flomoapp.com/api/v1/memo/test/"

      local booknotes = {
        title = "Test Book",
        { { text = "Sample quote", page = 1 } },
      }

      exporter:export({ booknotes })

      -- Production bug: makeRequest() only sets Content-Type, omitting Content-Length
      assert.is_table(captured_headers)
      assert.is_not_nil(captured_headers["Content-Length"])

      http.request = old_request
    end
  )

  it(
    "should handle multi-chunk HTTP responses in makeRequest [exposes production bug in makeRequest()]",
    function()
      local old_request = http.request

      http.request = function(req)
        local sink = req.sink
        -- Response body split across multiple chunks
        sink('{"code":0,')
        sink('"message":"success"}')
        return 1, 200, {}, "200 OK"
      end

      local exporter = FlomoExporter:new({ name = "flomo" })
      exporter.settings.api = "https://flomoapp.com/api/v1/memo/test/"

      local booknotes = {
        title = "Test Book",
        { { text = "Sample quote", page = 1 } },
      }

      -- Production bug: makeRequest decodes sink[1] instead of table.concat(sink),
      -- causing unhandled JSON decode error on multi-chunk responses
      local ok = pcall(function()
        return exporter:export({ booknotes })
      end)
      assert.is_true(ok)

      http.request = old_request
    end
  )

  it(
    "should export bookmark notes when clipping text is nil [exposes production bug in FlomoExporter:createHighlights()]",
    function()
      local old_request = http.request
      http.request = function(req)
        req.sink('{"code":0,"message":"success"}')
        return 1, 200, {}, "200 OK"
      end

      local exporter = FlomoExporter:new({ name = "flomo" })
      exporter.settings.api = "https://flomoapp.com/api/v1/memo/test/"

      -- Bookmark clipping with note but nil text
      local booknotes = {
        title = "Test Book",
        {
          {
            text = nil,
            note = "Bookmark comment note",
            page = 10,
          },
        },
      }

      -- Production bug: concatenates clipping.text without nil check, crashing with nil concatenation
      local ok = pcall(function()
        return exporter:export({ booknotes })
      end)
      assert.is_true(ok)

      http.request = old_request
    end
  )

  it(
    "should return false when highlight export fails due to HTTP error [exposes production bug in FlomoExporter:createHighlights()]",
    function()
      local old_request = http.request

      http.request = function()
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

      -- Production bug: createHighlights unconditionally returns true even when all requests fail
      local ok = exporter:export({ booknotes })
      assert.is_false(ok)

      http.request = old_request
    end
  )
end)
