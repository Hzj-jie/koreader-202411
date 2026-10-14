describe("ReadwiseExporter plugin target module", function()
  local ReadwiseExporter, http, UIManager

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    http = require("socket.http")
    ReadwiseExporter = require("plugins/exporter.koplugin/target/readwise")
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

  it("should check ready to export state based on authorization token", function()
    local exp = setmetatable({ settings = {} }, { __index = ReadwiseExporter })
    assert.is_false(exp:isReadyToExport())

    exp.settings.token = ""
    -- Token is set
    exp.settings.token = "test_auth_token"
    assert.is_true(exp:isReadyToExport())
  end)

  it("should generate menu table and handle token input and toggle", function()
    local toggle_called = false
    local exp = setmetatable(
      { settings = { token = "token123" } },
      { __index = ReadwiseExporter }
    )
    exp.isEnabled = function()
      return true
    end
    exp.toggleEnabled = function()
      toggle_called = true
    end
    exp.saveSettings = function() end

    local menu = exp:getMenuTable()
    assert.is_table(menu)
    assert.are.equal("Readwise", menu.text)
    assert.is_table(menu.sub_item_table)
    assert.are.equal(2, #menu.sub_item_table)

    -- Item 1: Token InputDialog
    menu.sub_item_table[1].callback()
    assert.are.equal(1, #shown_widgets)
    local dialog = shown_widgets[1]
    assert.is_table(dialog)

    -- Cancel
    dialog.buttons[1][1].callback()
    assert.are.equal(1, #closed_widgets)
    assert.are.equal(dialog, closed_widgets[1])

    -- Save new token
    dialog.getInputText = function()
      return "new_secret_token"
    end
    dialog.buttons[1][2].callback()
    assert.are.equal("new_secret_token", exp.settings.token)

    -- Item 2: Toggle
    menu.sub_item_table[2].callback()
    assert.is_true(toggle_called)
  end)

  it("should format highlights with author normalization and payload fields", function()
    local exp = setmetatable(
      { settings = { token = "test_token" } },
      { __index = ReadwiseExporter }
    )

    local sent_requests = {}
    http.request = function(req)
      local json = require("json")
      -- Read source
      local body = req.source()
      table.insert(sent_requests, {
        url = req.url,
        method = req.method,
        headers = req.headers,
        body = json.decode(body),
      })
      req.sink([[{"status": "ok"}]])
      return 1, 200, {}, "200 OK"
    end

    -- Case 1: Multi-line author is normalized with comma
    local booknotes1 = {
      title = "Book A",
      author = "Author One\nAuthor Two",
      {
        {
          text = "First clipping",
          note = "Important note",
          page = 10,
          time = 1600000000,
        },
      },
    }

    assert.is_true(exp:export({ booknotes1 }))
    assert.are.equal(1, #sent_requests)
    local h1 = sent_requests[1].body.highlights[1]
    assert.are.equal("First clipping", h1.text)
    assert.are.equal("Book A", h1.title)
    assert.are.equal("Author One, Author Two", h1.author)
    assert.are.equal("koreader", h1.source_type)
    assert.are.equal("books", h1.category)
    assert.are.equal("Important note", h1.note)
    assert.are.equal(10, h1.location)
    assert.are.equal("2020-09-13T12:26:40Z", h1.highlighted_at)

    -- Case 2: Empty author becomes nil
    local booknotes2 = {
      title = "Book B",
      author = "",
      {
        { text = "Second clipping", page = 20, time = 1600000000 },
      },
    }
    assert.is_true(exp:export({ booknotes2 }))
    assert.are.equal(2, #sent_requests)
    local h2 = sent_requests[2].body.highlights[1]
    assert.is_nil(h2.author)

    -- Case 3: HTTP non-200 returns false
    http.request = function(_req)
      return 1, 500, {}, "500 Internal Server Error"
    end
    assert.is_false(exp:export({ booknotes1 }))
  end)

  describe("failing tests for production bugs", function()
    it("should handle booknotes with nil author without crashing (fails at line 115 indexing nil author)", function()
      local exp = setmetatable(
        { settings = { token = "test_token" } },
        { __index = ReadwiseExporter }
      )

      http.request = function(req)
        req.sink([[{"status": "ok"}]])
        return 1, 200, {}, "200 OK"
      end

      -- Book notes with author = nil
      local booknotes_no_author = {
        title = "Anonymous Manuscript",
        author = nil,
        {
          { text = "Excerpt without author", page = 5, time = 1600000000 },
        },
      }

      assert.has_no.errors(function()
        local ok = exp:export({ booknotes_no_author })
        assert.is_true(ok)
      end)
    end)

    it("should handle multi-chunk ltn12 HTTP responses in makeRequest (fails due to json.decode(sink[1]))", function()
      local exp = setmetatable(
        { settings = { token = "test_token" } },
        { __index = ReadwiseExporter }
      )

      http.request = function(req)
        -- Response arrived in two chunks
        req.sink([[{"status":]])
        req.sink([["ok"}]])
        return 1, 200, {}, "200 OK"
      end

      local booknotes = {
        title = "Test Book",
        author = "Author",
        {
          { text = "Highlight", page = 1, time = 1600000000 },
        },
      }

      assert.has_no.errors(function()
        local ok = exp:export({ booknotes })
        assert.is_true(ok)
      end)
    end)
  end)
end)
