describe("Memos Exporter target module", function()
  local MemosExporter, http, UIManager

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    http = require("socket.http")
    MemosExporter = require("plugins/exporter.koplugin/target/memos")
    UIManager = require("ui/uimanager")
  end)

  local orig_show, orig_close, orig_request
  local shown_widgets, closed_widgets

  before_each(function()
    shown_widgets = {}
    closed_widgets = {}
    orig_show = UIManager.show
    orig_close = UIManager.close
    orig_request = http.request

    UIManager.show = function(_self, w)
      table.insert(shown_widgets, w)
    end
    UIManager.close = function(_self, w)
      table.insert(closed_widgets, w)
    end
  end)

  after_each(function()
    UIManager.show = orig_show
    UIManager.close = orig_close
    http.request = orig_request
  end)

  it("should check readiness based on API and token settings", function()
    MemosExporter.settings = {}
    assert.is_false(MemosExporter:isReadyToExport())

    MemosExporter.settings = { api = "https://memos.example.com/api/v1/memo" }
    assert.is_false(MemosExporter:isReadyToExport())

    MemosExporter.settings = {
      api = "https://memos.example.com/api/v1/memo",
      token = "sample_token",
    }
    assert.is_true(MemosExporter:isReadyToExport())
  end)

  it("should build menu table with configuration callbacks, cancel, and save", function()
    local toggle_called = false
    MemosExporter.isEnabled = function()
      return true
    end
    MemosExporter.toggleEnabled = function()
      toggle_called = true
    end
    MemosExporter.saveSettings = function() end

    local menu = MemosExporter:getMenuTable()
    assert.is_table(menu)
    assert.are.equal("Memos", menu.text)
    assert.is_table(menu.sub_item_table)
    assert.are.equal(3, #menu.sub_item_table)

    -- Item 1: API URL Dialog
    menu.sub_item_table[1].callback()
    assert.are.equal(1, #shown_widgets)
    local api_dialog = shown_widgets[1]
    assert.is_table(api_dialog)

    -- Cancel
    api_dialog.buttons[1][1].callback()
    assert.are.equal(1, #closed_widgets)
    assert.are.equal(api_dialog, closed_widgets[1])

    -- Save API URL
    api_dialog.getInputText = function()
      return "https://newmemos.com/api"
    end
    api_dialog.buttons[1][2].callback()
    assert.are.equal("https://newmemos.com/api", MemosExporter.settings.api)

    -- Item 2: Token Dialog
    menu.sub_item_table[2].callback()
    assert.are.equal(2, #shown_widgets)
    local token_dialog = shown_widgets[2]
    assert.is_table(token_dialog)

    token_dialog.getInputText = function()
      return "new_token"
    end
    token_dialog.buttons[1][2].callback()
    assert.are.equal("new_token", MemosExporter.settings.token)

    -- Item 3: Toggle
    menu.sub_item_table[3].callback()
    assert.is_true(toggle_called)
  end)

  it("should format highlight content, title tags, and execute export flow", function()
    MemosExporter.settings = {
      api = "https://memos.example.com/api/v1/memo",
      token = "sample_token",
    }

    local captured_requests = {}
    http.request = function(req)
      local json = require("json")
      local body = json.decode(req.source())
      table.insert(captured_requests, {
        url = req.url,
        method = req.method,
        headers = req.headers,
        body = body,
      })
      req.sink('{"id": 1}')
      return 1, 200, {}, "200 OK"
    end

    local booknotes = {
      title = "Design Patterns",
      {
        {
          text = "Decorator adds responsibilities dynamically.",
          note = "Very useful pattern",
          page = 175,
        },
      },
    }

    assert.is_true(MemosExporter:export({ booknotes }))
    assert.are.equal(1, #captured_requests)
    local req = captured_requests[1]
    assert.are.equal("https://memos.example.com/api/v1/memo", req.url)
    assert.are.equal("POST", req.method)
    assert.are.equal("Bearer sample_token", req.headers["Authorization"])

    local content = req.body.content
    assert.is_true(string.find(content, "Decorator adds responsibilities dynamically.", 1, true) ~= nil)
    assert.is_true(string.find(content, "Very useful pattern", 1, true) ~= nil)
    assert.is_true(string.find(content, "Design Patterns (page: 175", 1, true) ~= nil)
    assert.is_true(string.find(content, "#Design_Patterns #koreader", 1, true) ~= nil)
  end)

  describe("failing tests for production bugs", function()
    it("should set Content-Length header in makeRequest (fails because Content-Length is omitted)", function()
      MemosExporter.settings = {
        api = "https://memos.example.com/api/v1/memo",
        token = "sample_token",
      }

      local header_content_length = nil
      http.request = function(req)
        header_content_length = req.headers["Content-Length"]
        req.sink('{"id": 1}')
        return 1, 200, {}, "200 OK"
      end

      local booknotes = {
        title = "Test",
        {
          { text = "Text", page = 1 },
        },
      }

      MemosExporter:createHighlights(booknotes)
      -- socket.http needs Content-Length header for POST body
      assert.is_not_nil(header_content_length)
    end)

    it("should return false from createHighlights and export when all HTTP requests fail (fails due to unconditional return true)", function()
      MemosExporter.settings = {
        api = "https://memos.example.com/api/v1/memo",
        token = "sample_token",
      }

      http.request = function(_req)
        return 1, 500, {}, "500 Server Error"
      end

      local booknotes = {
        title = "Failing Export",
        {
          { text = "Will fail", page = 1 },
        },
      }

      local ok = MemosExporter:createHighlights(booknotes)
      assert.is_false(ok)
    end)

    it("should handle bookmark clipping with nil text without crashing (fails concatenating nil clipping.text)", function()
      MemosExporter.settings = {
        api = "https://memos.example.com/api/v1/memo",
        token = "sample_token",
      }

      http.request = function(req)
        req.sink('{"id": 1}')
        return 1, 200, {}, "200 OK"
      end

      -- Bookmark clipping with nil text
      local booknotes_with_bookmark = {
        title = "Bookmark Book",
        {
          { text = nil, note = "Bookmark note", page = 50 },
        },
      }

      assert.has_no.errors(function()
        MemosExporter:createHighlights(booknotes_with_bookmark)
      end)
    end)

    it("should handle multi-chunk ltn12 responses in makeRequest (fails due to json.decode(sink[1]))", function()
      MemosExporter.settings = {
        api = "https://memos.example.com/api/v1/memo",
        token = "sample_token",
      }

      http.request = function(req)
        -- Multi-chunk response
        req.sink('{"id":')
        req.sink('1}')
        return 1, 200, {}, "200 OK"
      end

      local booknotes = {
        title = "Test Book",
        {
          { text = "Highlight", page = 1 },
        },
      }

      assert.has_no.errors(function()
        local ok = MemosExporter:createHighlights(booknotes)
        assert.is_true(ok)
      end)
    end)
  end)
end)
