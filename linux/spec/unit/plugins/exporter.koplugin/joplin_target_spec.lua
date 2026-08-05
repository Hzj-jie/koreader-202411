describe("Joplin Exporter target", function()
  local JoplinExporter, UIManager, http, json

  setup(function()
    require("commonrequire")
    http = require("socket.http")
    json = require("json")
    UIManager = require("ui/uimanager")
    JoplinExporter = require("plugins/exporter.koplugin/target/joplin")
  end)

  before_each(function()
    G_reader_settings:save("exporter", {
      joplin = {
        ip = "192.168.1.50",
        port = 41184,
        token = "secret_token_123",
      },
      markdown = {
        formatting_options = {
          lighten = "italic",
          underscore = "underline_markdownit",
          strikeout = "strikethrough",
          invert = "bold",
        },
        highlight_formatting = true,
      },
    })
    JoplinExporter:loadSettings()
  end)

  after_each(function()
    if type(http.request) == "table" and http.request.revert then
      http.request:revert()
    end
  end)

  describe("initialization and readiness", function()
    it("should have correct properties", function()
      assert.are.equal("joplin", JoplinExporter.name)
      assert.is_true(JoplinExporter.is_remote)
      assert.are.equal("1.1.0", JoplinExporter.version)
      assert.are.equal("KOReader Notes", JoplinExporter.notebook_name)
    end)

    it("should check if ready to export", function()
      assert.is_truthy(JoplinExporter:isReadyToExport())

      JoplinExporter.settings.ip = nil
      JoplinExporter.settings.port = 41184
      JoplinExporter.settings.token = "secret_token_123"
      assert.is_falsy(JoplinExporter:isReadyToExport())

      JoplinExporter.settings.ip = "192.168.1.50"
      JoplinExporter.settings.port = nil
      JoplinExporter.settings.token = "secret_token_123"
      assert.is_falsy(JoplinExporter:isReadyToExport())

      JoplinExporter.settings.ip = "192.168.1.50"
      JoplinExporter.settings.port = 41184
      JoplinExporter.settings.token = nil
      assert.is_falsy(JoplinExporter:isReadyToExport())
    end)
  end)

  describe("notebook and note operations via makeRequest", function()
    it(
      "findNoteByTitle: returns note id when title and notebook match",
      function()
        stub(http, "request", function(req)
          assert.is_not_nil(req.url:find("notes%?token=secret_token_123"))
          assert.is_not_nil(req.url:find("fields=id,title,parent_id"))
          assert.are.equal("GET", req.method)
          local body = json.encode({
            has_more = false,
            items = {
              { id = "note_111", title = "Test Book", parent_id = "nb_999" },
              { id = "note_222", title = "Other Book", parent_id = "nb_999" },
            },
          })
          req.sink(body)
          return 1, 200, {}
        end)

        local note_id = JoplinExporter:findNoteByTitle("Test Book", "nb_999")
        assert.are.equal("note_111", note_id)
      end
    )

    it(
      "findNoteByTitle: handles pagination and returns nil if not found",
      function()
        local calls = 0
        stub(http, "request", function(req)
          calls = calls + 1
          local body
          if calls == 1 then
            assert.is_not_nil(req.url:find("&page=1$"))
            body = json.encode({
              has_more = true,
              items = {
                {
                  id = "note_001",
                  title = "Page 1 Book",
                  parent_id = "nb_999",
                },
              },
            })
          else
            assert.is_not_nil(req.url:find("&page=2$"))
            body = json.encode({
              has_more = false,
              items = {
                {
                  id = "note_002",
                  title = "Page 2 Book",
                  parent_id = "nb_999",
                },
              },
            })
          end
          req.sink(body)
          return 1, 200, {}
        end)

        local note_id = JoplinExporter:findNoteByTitle("Page 2 Book", "nb_999")
        assert.are.equal("note_002", note_id)
        assert.are.equal(2, calls)

        http.request:revert()
        stub(http, "request", function(req)
          req.sink(json.encode({ has_more = false, items = {} }))
          return 1, 200, {}
        end)

        assert.is_nil(JoplinExporter:findNoteByTitle("Nonexistent", "nb_999"))
      end
    )

    it("findNoteByTitle: returns nil on HTTP or Joplin server error", function()
      stub(http, "request", function(req)
        req.sink(json.encode({ error = "Unauthorized token" }))
        return 1, 401, {}
      end)

      assert.is_nil(JoplinExporter:findNoteByTitle("Title", "nb_id"))
    end)

    it("findNotebookByTitle: returns notebook id when title matches", function()
      stub(http, "request", function(req)
        assert.is_not_nil(req.url:find("folders%?token=secret_token_123"))
        assert.is_not_nil(req.url:find("query=title"))
        assert.are.equal("GET", req.method)
        local body = json.encode({
          has_more = false,
          items = {
            { id = "folder_100", title = "KOReader Notes" },
          },
        })
        req.sink(body)
        return 1, 200, {}
      end)

      local folder_id = JoplinExporter:findNotebookByTitle("KOReader Notes")
      assert.are.equal("folder_100", folder_id)
    end)

    it(
      "notebookExist: returns notebook id if found or false if not found",
      function()
        stub(http, "request", function(req)
          local body = json.encode({
            items = {
              { id = "folder_200", title = "KOReader Notes" },
            },
          })
          req.sink(body)
          return 1, 200, {}
        end)

        assert.are.equal(
          "folder_200",
          JoplinExporter:notebookExist("KOReader Notes")
        )

        http.request:revert()
        stub(http, "request", function(req)
          req.sink(json.encode({ items = {} }))
          return 1, 200, {}
        end)

        assert.is_false(JoplinExporter:notebookExist("KOReader Notes"))
      end
    )

    it("createNotebook: posts folder title and created_time", function()
      local req_payload
      stub(http, "request", function(req)
        assert.are.equal("POST", req.method)
        assert.is_not_nil(req.url:find("folders%?token=secret_token_123"))
        if req.source then
          req_payload = req.source()
        end
        req.sink(json.encode({ id = "new_folder_id" }))
        return 1, 200, {}
      end)

      local id = JoplinExporter:createNotebook("New Notebook", 1700000000)
      assert.are.equal("new_folder_id", id)
      assert.is_not_nil(req_payload)
      local data = json.decode(req_payload)
      assert.are.equal("New Notebook", data.title)
      assert.are.equal(1700000000, data.created_time)
    end)

    it("createNote: posts title, body, parent_id, created_time", function()
      local req_payload
      stub(http, "request", function(req)
        assert.are.equal("POST", req.method)
        assert.is_not_nil(req.url:find("notes%?token=secret_token_123"))
        if req.source then
          req_payload = req.source()
        end
        req.sink(json.encode({ id = "new_note_id" }))
        return 1, 200, {}
      end)

      local id = JoplinExporter:createNote(
        "Book Title",
        "Note Markdown Body",
        "folder_id_123",
        1700000000
      )
      assert.are.equal("new_note_id", id)
      local data = json.decode(req_payload)
      assert.are.equal("Book Title", data.title)
      assert.are.equal("Note Markdown Body", data.body)
      assert.are.equal("folder_id_123", data.parent_id)
      assert.are.equal(1700000000, data.created_time)
    end)

    it("updateNote: puts updated body to note endpoint", function()
      local req_payload
      stub(http, "request", function(req)
        assert.are.equal("PUT", req.method)
        assert.is_not_nil(
          req.url:find("notes/note_id_555%?token=secret_token_123")
        )
        if req.source then
          req_payload = req.source()
        end
        req.sink(json.encode({ id = "note_id_555" }))
        return 1, 200, {}
      end)

      local id = JoplinExporter:updateNote("Updated Body Text", "note_id_555")
      assert.are.equal("note_id_555", id)
      local data = json.decode(req_payload)
      assert.are.equal("Updated Body Text", data.body)
    end)
  end)

  describe("getMenuTable", function()
    it("should return valid menu configuration", function()
      local menu = JoplinExporter:getMenuTable()
      assert.is_table(menu)
      assert.are.equal("Joplin", menu.text)
      assert.is_function(menu.checked_func)
      assert.is_table(menu.sub_item_table)
      assert.are.equal(4, #menu.sub_item_table)
    end)

    it("should handle IP and Port input dialog callback", function()
      local shown_dialog
      stub(UIManager, "show", function(self_ui, dialog)
        shown_dialog = dialog
      end)
      stub(UIManager, "close", function(self_ui, dialog) end)

      local menu = JoplinExporter:getMenuTable()
      local ip_port_item = menu.sub_item_table[1]
      ip_port_item.callback()

      assert.is_not_nil(shown_dialog)
      stub(shown_dialog, "getFields", function()
        return { "10.0.0.5", "8080" }
      end)

      -- Trigger OK callback
      local ok_callback = shown_dialog.buttons[1][2].callback
      ok_callback()

      assert.are.equal("10.0.0.5", JoplinExporter.settings.ip)
      assert.are.equal(8080, JoplinExporter.settings.port)

      UIManager.show:revert()
      UIManager.close:revert()
    end)

    it("should handle Token input dialog callback", function()
      local shown_dialog
      stub(UIManager, "show", function(self_ui, dialog)
        shown_dialog = dialog
      end)
      stub(UIManager, "close", function(self_ui, dialog) end)

      local menu = JoplinExporter:getMenuTable()
      local token_item = menu.sub_item_table[2]
      token_item.callback()

      assert.is_not_nil(shown_dialog)
      stub(shown_dialog, "getInputText", function()
        return "new_secret_token"
      end)

      -- Trigger Set Token callback
      local set_token_cb = shown_dialog.buttons[1][2].callback
      set_token_cb()

      assert.are.equal("new_secret_token", JoplinExporter.settings.token)

      UIManager.show:revert()
      UIManager.close:revert()
    end)

    it("should toggle enabled state and show help dialog", function()
      local shown_dialog
      stub(UIManager, "show", function(self_ui, dialog)
        shown_dialog = dialog
      end)

      local menu = JoplinExporter:getMenuTable()
      local toggle_item = menu.sub_item_table[3]
      assert.is_falsy(JoplinExporter.settings.enabled)
      toggle_item.callback()
      assert.is_true(JoplinExporter.settings.enabled)

      local help_item = menu.sub_item_table[4]
      help_item.callback()
      assert.is_not_nil(shown_dialog)

      UIManager.show:revert()
    end)
  end)

  describe("export", function()
    local book_notes

    before_each(function()
      book_notes = {
        {
          title = "Sample Book Title",
          author = "Author Name",
          [1] = {
            [1] = {
              page = 10,
              time = 1715767200,
              datetime = "2024-05-15 10:00:00",
              text = "Highlight text sample",
              drawer = "lighten",
            },
          },
        },
      }
    end)

    it("should return false if settings are not ready", function()
      JoplinExporter.settings.ip = nil
      assert.is_false(JoplinExporter:export(book_notes))
    end)

    it("should return false if ping fails", function()
      stub(http, "request", function(req)
        req.sink("NotJoplin")
        return 1, 200, {}
      end)

      assert.is_false(JoplinExporter:export(book_notes))
    end)

    it(
      "should create notebook if absent and export note via createNote",
      function()
        stub(http, "request", function(req)
          if req.url:find("/ping") then
            req.sink("JoplinClipperServer")
          elseif req.url:find("/folders%?") and req.method == "GET" then
            -- notebookExist returns false
            req.sink(json.encode({ items = {} }))
          elseif req.url:find("/folders%?") and req.method == "POST" then
            -- createNotebook returns new ID
            req.sink(json.encode({ id = "created_notebook_id" }))
          elseif req.url:find("/notes%?") and req.method == "GET" then
            -- findNoteByTitle returns no matching note
            req.sink(json.encode({ has_more = false, items = {} }))
          elseif req.url:find("/notes%?") and req.method == "POST" then
            -- createNote returns note id
            req.sink(json.encode({ id = "created_note_id" }))
          end
          return 1, 200, {}
        end)

        local result = JoplinExporter:export(book_notes)
        assert.is_true(result)
        assert.are.equal(
          "created_notebook_id",
          JoplinExporter.settings.notebook_guid
        )
      end
    )

    it(
      "should reuse existing notebook and update note via updateNote",
      function()
        JoplinExporter.settings.notebook_guid = "existing_guid"

        stub(http, "request", function(req)
          if req.url:find("/ping") then
            req.sink("JoplinClipperServer")
          elseif req.url:find("/folders%?") and req.method == "GET" then
            -- notebookExist returns existing notebook id
            req.sink(json.encode({
              items = { { id = "existing_guid", title = "KOReader Notes" } },
            }))
          elseif req.url:find("/notes%?") and req.method == "GET" then
            -- findNoteByTitle returns existing note id
            req.sink(json.encode({
              has_more = false,
              items = {
                {
                  id = "existing_note_123",
                  title = "Sample Book Title",
                  parent_id = "existing_guid",
                },
              },
            }))
          elseif
            req.url:find("/notes/existing_note_123") and req.method == "PUT"
          then
            -- updateNote returns updated note id
            req.sink(json.encode({ id = "existing_note_123" }))
          end
          return 1, 200, {}
        end)

        local result = JoplinExporter:export(book_notes)
        assert.is_true(result)
      end
    )

    it("should return false if notebook creation fails", function()
      stub(http, "request", function(req)
        if req.url:find("/ping") then
          req.sink("JoplinClipperServer")
        elseif req.url:find("/folders%?") and req.method == "GET" then
          req.sink(json.encode({ items = {} }))
        elseif req.url:find("/folders%?") and req.method == "POST" then
          -- createNotebook fails
          req.sink(json.encode({ error = "Notebook creation failed" }))
        end
        return 1, 200, {}
      end)

      assert.is_false(JoplinExporter:export(book_notes))
    end)
  end)
end)
