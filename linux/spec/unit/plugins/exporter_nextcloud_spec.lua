describe("Nextcloud Exporter target module", function()
  local NextcloudExporter, http, UIManager

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    http = require("socket.http")
    NextcloudExporter = require("plugins/exporter.koplugin/target/nextcloud")
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

  it("should check readiness based on host, username, and password", function()
    NextcloudExporter.settings = {}
    assert.is_falsy(NextcloudExporter:isReadyToExport())

    NextcloudExporter.settings = { host = "https://example.com" }
    assert.is_falsy(NextcloudExporter:isReadyToExport())

    NextcloudExporter.settings = { host = "https://example.com", username = "user" }
    assert.is_falsy(NextcloudExporter:isReadyToExport())

    NextcloudExporter.settings = {
      host = "https://nextcloud.example.com",
      username = "user1",
      password = "secretpassword",
    }
    assert.is_truthy(NextcloudExporter:isReadyToExport())
  end)

  it("should build menu table with configuration callbacks, cancel, and save", function()
    local toggle_called = false
    NextcloudExporter.isEnabled = function()
      return true
    end
    NextcloudExporter.toggleEnabled = function()
      toggle_called = true
    end
    NextcloudExporter.saveSettings = function() end

    local menu = NextcloudExporter:getMenuTable()
    assert.is_table(menu)
    assert.are.equal("Nextcloud Notes", menu.text)
    assert.is_table(menu.sub_item_table)
    assert.are.equal(3, #menu.sub_item_table)

    -- Item 1: MultiInputDialog setup
    menu.sub_item_table[1].callback()
    assert.are.equal(1, #shown_widgets)
    local dialog = shown_widgets[1]
    assert.is_table(dialog)

    -- Cancel button
    dialog.buttons[1][1].callback()
    assert.are.equal(1, #closed_widgets)
    assert.are.equal(dialog, closed_widgets[1])

    -- OK button (save non-empty fields)
    dialog.getFields = function()
      return { "https://newhost.com", "", "newpass" }
    end
    dialog.buttons[1][2].callback()
    assert.are.equal("https://newhost.com", NextcloudExporter.settings.host)
    assert.are.equal("user1", NextcloudExporter.settings.username) -- preserved empty field
    assert.are.equal("newpass", NextcloudExporter.settings.password)

    -- Item 2: Toggle
    menu.sub_item_table[2].callback()
    assert.is_true(toggle_called)

    -- Item 3: Help message
    menu.sub_item_table[3].callback()
    assert.are.equal(2, #shown_widgets)
    assert.is_true(string.find(shown_widgets[2].text, "Nextcloud-notes", 1, true) ~= nil)
  end)

  it("should handle export when not ready or when HTTP fails", function()
    NextcloudExporter.settings = {}
    assert.is_false(NextcloudExporter:export({}))

    NextcloudExporter.settings = {
      host = "https://nextcloud.example.com",
      username = "user1",
      password = "secretpassword",
    }
    G_reader_settings:save("exporter", {
      markdown = {
        formatting_options = { light = 1 },
        highlight_formatting = false,
      },
    })

    -- HTTP GET failure
    http.request = function(_req)
      return nil, "Connection refused"
    end
    assert.is_false(NextcloudExporter:export({}))

    -- HTTP POST failure
    http.request = function(req)
      if req.method == "GET" then
        req.sink("[]")
        return 1, 200, {}, "200 OK"
      else
        return nil, "Server error"
      end
    end
    local test_notes = {
      {
        title = "Book A",
        author = "Author A",
        { { text = "Sample", page = 1, time = 1000, chapter = "1" } },
      },
    }
    assert.is_false(NextcloudExporter:export(test_notes))
  end)

  it("should export via POST when note does not exist and via PUT when note exists", function()
    NextcloudExporter.settings = {
      host = "https://nextcloud.example.com",
      username = "user1",
      password = "secretpassword",
    }
    G_reader_settings:save("exporter", {
      markdown = {
        formatting_options = { light = 1 },
        highlight_formatting = false,
      },
    })

    local requests = {}
    http.request = function(req)
      table.insert(requests, { method = req.method, url = req.url })
      if req.method == "GET" then
        req.sink('[{"id": 99, "title": "Author - Existing Book"}]')
      else
        req.sink('{"id": 100}')
      end
      return 1, 200, {}, "200 OK"
    end

    local notes = {
      {
        title = "New Book",
        author = "Author",
        { { text = "Note 1", page = 1, time = 1000 } },
      },
      {
        title = "Existing Book",
        author = "Author",
        { { text = "Note 2", page = 2, time = 2000 } },
      },
    }

    assert.is_true(NextcloudExporter:export(notes))
    assert.are.equal(3, #requests)
    assert.are.equal("GET", requests[1].method)
    assert.are.equal("POST", requests[2].method)
    assert.are.equal("https://nextcloud.example.com/index.php/apps/notes/api/v1/notes", requests[2].url)
    assert.are.equal("PUT", requests[3].method)
    assert.are.equal("https://nextcloud.example.com/index.php/apps/notes/api/v1/notes/99", requests[3].url)
  end)

  describe("failing tests for production bugs", function()
    it("should handle multi-chunk ltn12 HTTP responses in makeRequest (fails due to json.decode(sink[1]))", function()
      NextcloudExporter.settings = {
        host = "https://nextcloud.example.com",
        username = "user1",
        password = "secretpassword",
      }
      G_reader_settings:save("exporter", {
        markdown = {
          formatting_options = { light = 1 },
          highlight_formatting = false,
        },
      })

      local put_called = false
      http.request = function(req)
        if req.method == "GET" then
          -- Simulate response arriving in two chunks
          req.sink('[{"id": 42, ')
          req.sink('"title": "Author - My Book"}]')
        elseif req.method == "PUT" then
          put_called = true
          req.sink('{"id": 42}')
        end
        return 1, 200, {}, "200 OK"
      end

      local notes = {
        {
          title = "My Book",
          author = "Author",
          { { text = "Note", page = 1, time = 1000 } },
        },
      }

      -- Must concatenate sink chunks to decode JSON and execute PUT /notes/42
      assert.has_no.errors(function()
        local ok = NextcloudExporter:export(notes)
        assert.is_true(ok)
      end)
      assert.is_true(put_called)
    end)

    it("should export safely when markdown subtable is nil in exporter settings (fails with attempt to index local markdown_settings nil)", function()
      NextcloudExporter.settings = {
        host = "https://nextcloud.example.com",
        username = "user1",
        password = "secretpassword",
      }
      -- Exporter settings without markdown subtable
      G_reader_settings:save("exporter", {})

      http.request = function(req)
        if req.method == "GET" then
          req.sink("[]")
        else
          req.sink('{"id": 1}')
        end
        return 1, 200, {}, "200 OK"
      end

      local notes = {
        {
          title = "Book Without Markdown Settings",
          author = "Author",
          { { text = "Note", page = 1, time = 1000 } },
        },
      }

      assert.has_no.errors(function()
        NextcloudExporter:export(notes)
      end)
    end)
  end)
end)
