describe("Wallabag plugin unit tests", function()
  local Wallabag, UIManager, DataStorage, LuaSettings, NetworkMgr, socketutil, http, filemanagerutil, JSON, lfs
  local mock_ui, wallabag_instance

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    DataStorage = require("datastorage")
    LuaSettings = require("frontend/luasettings")
    NetworkMgr = require("ui/network/manager")
    UIManager = require("ui/uimanager")
    socketutil = require("socketutil")
    http = require("socket.http")
    filemanagerutil = require("apps/filemanager/filemanagerutil")
    JSON = require("json")
    lfs = require("libs/libkoreader-lfs")
    Wallabag = require("plugins/wallabag.koplugin/main")
  end)

  before_each(function()
    mock_ui = {
      menu = { registerToMainMenu = spy.new(function() end) },
    }
    wallabag_instance = Wallabag:new({ ui = mock_ui, path = "plugins/wallabag.koplugin" })
    wallabag_instance.server_url = "https://app.wallabag.it"
    wallabag_instance.client_id = "test_client_id"
    wallabag_instance.client_secret = "test_client_secret"
    wallabag_instance.username = "test_user"
    wallabag_instance.password = "test_pass"
    wallabag_instance.directory = "/downloads/wallabag"
    wallabag_instance.access_token = "test_token"
  end)

  after_each(function()
    if UIManager._window_stack then
      for i = #UIManager._window_stack, 1, -1 do
        local win = UIManager._window_stack[i]
        if win and win.widget then
          UIManager:close(win.widget)
        end
      end
    end
  end)

  describe("Initialization & Settings Dialogs", function()
    it("should initialize default properties and settings", function()
      assert.is_table(wallabag_instance)
      assert.are.equal(wallabag_instance.token_expiry, 0)
      assert.is_true(wallabag_instance.is_delete_finished)
      assert.is_false(wallabag_instance.is_delete_read)
      assert.is_false(wallabag_instance.is_delete_abandoned)
      assert.is_false(wallabag_instance.is_auto_delete)
      assert.are.equal(wallabag_instance.articles_per_sync, 30)
      assert.spy(mock_ui.menu.registerToMainMenu).was_called()
    end)

    it("should open editServerSettings dialog and trigger buttons", function()
      local show_stub = stub(UIManager, "show")
      wallabag_instance:editServerSettings()
      assert.stub(show_stub).was.called(1)
      local dialog = wallabag_instance.settings_dialog
      assert.is_table(dialog)

      -- Info button
      if dialog.buttons and dialog.buttons[1] and dialog.buttons[1][2] then
        dialog.buttons[1][2].callback()
      end

      -- Close button
      if dialog.buttons and dialog.buttons[1] and dialog.buttons[1][1] then
        dialog.buttons[1][1].callback()
      end

      -- Save/Apply button callback
      if dialog.buttons and dialog.buttons[1] and dialog.buttons[1][3] then
        dialog.getFields = function()
          return { "https://my.wallabag.com///", "id123", "sec123", "user123", "pass123" }
        end
        dialog.buttons[1][3].callback()
        assert.are.equal("https://my.wallabag.com", wallabag_instance.server_url)
        assert.are.equal("id123", wallabag_instance.client_id)
        assert.are.equal("sec123", wallabag_instance.client_secret)
        assert.are.equal("user123", wallabag_instance.username)
        assert.are.equal("pass123", wallabag_instance.password)
      end
      show_stub:revert()
    end)

    it("should open editClientSettings dialog and trigger buttons", function()
      local show_stub = stub(UIManager, "show")
      wallabag_instance:editClientSettings()
      assert.stub(show_stub).was.called(1)
      local dialog = wallabag_instance.client_settings_dialog
      assert.is_table(dialog)

      -- Close button
      if dialog.buttons and dialog.buttons[1] and dialog.buttons[1][1] then
        dialog.buttons[1][1].callback()
      end

      if dialog.buttons and dialog.buttons[1] and dialog.buttons[1][2] then
        dialog.getFields = function()
          return { "50" }
        end
        dialog.buttons[1][2].callback()
        assert.are.equal(50, wallabag_instance.articles_per_sync)
      end
      show_stub:revert()
    end)

    it("should open setFilterTag and trigger save callback", function()
      local show_stub = stub(UIManager, "show")
      local mock_menu = { updateItems = stub() }
      wallabag_instance:setFilterTag(mock_menu)
      assert.stub(show_stub).was.called(1)
      local dialog = wallabag_instance.tag_dialog
      assert.is_table(dialog)

      -- Cancel
      dialog.buttons[1][1].callback()

      -- OK
      dialog.getInputText = function() return "readlater" end
      dialog.buttons[1][2].callback()
      assert.are.equal("readlater", wallabag_instance.filter_tag)
      assert.stub(mock_menu.updateItems).was.called(1)

      show_stub:revert()
    end)

    it("should open setTagsDialog and trigger save callback", function()
      local show_stub = stub(UIManager, "show")
      local saved_tags
      wallabag_instance:setTagsDialog(
        { updateItems = function() end },
        "Tags Dialog",
        "Description",
        "tag1, tag2",
        function(tags) saved_tags = tags end
      )
      assert.stub(show_stub).was.called(1)
      local dialog = wallabag_instance.tags_dialog
      assert.is_table(dialog)

      -- Cancel
      dialog.buttons[1][1].callback()

      -- Save
      dialog.getInputText = function() return "news, tech" end
      dialog.buttons[1][2].callback()
      assert.are.equal("news, tech", saved_tags)
      show_stub:revert()
    end)

    it("should handle setDownloadDirectory", function()
      local DownloadMgr = require("ui/downloadmgr")
      local choose_stub = stub(DownloadMgr, "chooseDir")
      local mock_menu = { updateItems = stub() }
      wallabag_instance:setDownloadDirectory(mock_menu)
      assert.stub(choose_stub).was.called(1)
      choose_stub:revert()
    end)
  end)

  describe("API and Authentication Handlers", function()
    it("should callAPI for GET JSON requests and handle responses", function()
      local http_request_stub = stub(http, "request", function(req)
        if req.url and req.url:find("entries.json") then
          local resp = JSON.encode({ _embedded = { items = { { id = 10, title = "T1", tags = {} } } } })
          if req.sink then
            req.sink(resp)
          end
          return 1, 200, { ["content-type"] = "application/json" }, "HTTP/1.1 200 OK"
        end
        return nil, "Connection refused"
      end)

      local res, err = wallabag_instance:callAPI("GET", "/api/entries.json", nil, "", "")
      assert.is_nil(err)
      assert.is_table(res)
      assert.is_table(res._embedded)

      -- Network error
      local net_res, net_err = wallabag_instance:callAPI("GET", "/nonexistent", nil, "", "")
      assert.is_nil(net_res)
      assert.are.equal("network_error", net_err)

      http_request_stub:revert()
    end)

    it("should callAPI for file downloads and handle HTTP errors", function()
      local show_stub = stub(UIManager, "show")
      local http_request_stub = stub(http, "request", function(req)
        if req.url and req.url:find("export.epub") then
          if req.sink then
            req.sink("Fake EPUB Content")
          end
          return 1, 200, { ["content-type"] = "application/epub+zip" }, "HTTP/1.1 200 OK"
        elseif req.url and req.url:find("error404") then
          return 1, 404, { ["content-type"] = "text/plain" }, "HTTP/1.1 404 Not Found"
        else
          local resp = "invalid json{"
          if req.sink then req.sink(resp) end
          return 1, 200, { ["content-type"] = "application/json" }, "HTTP/1.1 200 OK"
        end
      end)

      local tmp_file = "/tmp/test_wallabag_dl_" .. os.time() .. ".epub"
      local ok = wallabag_instance:callAPI("GET", "/api/entries/1/export.epub", nil, "", tmp_file)
      assert.is_true(ok)
      os.remove(tmp_file)

      local err_res, err_type, err_code = wallabag_instance:callAPI("GET", "/error404", nil, "", "")
      assert.is_nil(err_res)
      assert.are.equal("http_error", err_type)
      assert.are.equal(404, err_code)

      -- Invalid json
      local json_res, json_err = wallabag_instance:callAPI("GET", "/invalidjson", nil, "", "")
      assert.is_nil(json_res)
      assert.are.equal("json_error", json_err)

      http_request_stub:revert()
      show_stub:revert()
    end)

    it("should manage bearer token lifecycle and handle unconfigured states", function()
      local show_stub = stub(UIManager, "show")

      -- Unconfigured state
      wallabag_instance.server_url = ""
      local token_ok = wallabag_instance:getBearerToken()
      assert.is_false(token_ok)

      -- Invalid directory
      wallabag_instance.server_url = "https://app.wallabag.it"
      wallabag_instance.directory = "/downloads/wallabag"
      local lfs_attr_stub = stub(lfs, "attributes", function(path, attr)
        if attr == "mode" or attr == nil then return "file" end
        return nil
      end)
      token_ok = wallabag_instance:getBearerToken()
      assert.is_false(token_ok)
      lfs_attr_stub:revert()

      -- Valid directory and cached token
      lfs_attr_stub = stub(lfs, "attributes", function(path, attr)
        if attr == "mode" or attr == nil then return "directory" end
        return nil
      end)
      wallabag_instance.directory = "/downloads/wallabag"
      wallabag_instance.access_token = "valid_cached_token"
      wallabag_instance.token_expiry = os.time() + 1000
      token_ok = wallabag_instance:getBearerToken()
      assert.is_true(token_ok)

      -- Expired token, refresh successfully
      wallabag_instance.directory = "/downloads/wallabag"
      wallabag_instance.token_expiry = 0
      local call_api_stub = stub(wallabag_instance, "callAPI", function(...)
        local args = { ... }
        for _, arg in ipairs(args) do
          if type(arg) == "string" and arg:find("oauth") then
            return { access_token = "new_access_token", expires_in = 3600 }
          end
        end
        return nil
      end)
      token_ok = wallabag_instance:getBearerToken()
      assert.is_true(token_ok)
      assert.are.equal("new_access_token", wallabag_instance.access_token)

      -- Token refresh failure
      call_api_stub:revert()
      call_api_stub = stub(wallabag_instance, "callAPI", function() return nil end)
      wallabag_instance.token_expiry = 0
      token_ok = wallabag_instance:getBearerToken()
      assert.is_false(token_ok)

      call_api_stub:revert()
      lfs_attr_stub:revert()
      show_stub:revert()
    end)
  end)

  describe("Article List and Downloading", function()
    it("should fetch article list with pagination and handle errors", function()
      local show_stub = stub(UIManager, "show")
      wallabag_instance.articles_per_sync = 2
      wallabag_instance.filter_tag = "tech"
      wallabag_instance.ignore_tags = "spam"

      local call_api_stub = stub(wallabag_instance, "callAPI", function(self, method, url)
        if url:find("page=1") then
          return {
            _embedded = {
              items = {
                { id = 1, title = "Article 1", tags = { { label = "tech" } } },
                { id = 2, title = "Article 2", tags = { { label = "spam" } } },
              },
            },
          }
        elseif url:find("page=2") then
          return {
            _embedded = {
              items = {
                { id = 3, title = "Article 3", tags = { { label = "tech" } } },
              },
            },
          }
        end
        return nil, "http_error", 404
      end)

      local list = wallabag_instance:getArticleList()
      assert.is_table(list)
      assert.are.equal(2, #list)
      assert.are.equal(1, list[1].id)
      assert.are.equal(3, list[2].id)

      -- Error during fetch
      call_api_stub:revert()
      call_api_stub = stub(wallabag_instance, "callAPI", function()
        return nil, "server_error"
      end)
      list = wallabag_instance:getArticleList()
      assert.is_nil(list)

      call_api_stub:revert()
      show_stub:revert()
    end)

    it("should download article with existing file date check and original doc option", function()
      local DocumentRegistry = require("document/documentregistry")
      local doc_reg_provider_stub = stub(DocumentRegistry, "hasProvider", function(self, mime)
        if mime == "application/pdf" or (type(mime) == "string" and mime:find("pdf")) then return true end
        return false
      end)
      local doc_reg_mime_stub = stub(DocumentRegistry, "mimeToExt", function(self, mime) return "pdf" end)

      wallabag_instance.download_original_document = true
      wallabag_instance.is_dateparser_available = true
      wallabag_instance.dateparser = {
        parse = function(d) return 1000 end,
      }

      local lfs_attr_stub = stub(lfs, "attributes", function(path)
        if path:find("Existing") then
          return { modification = 2000 }
        end
        return nil
      end)

      local call_api_stub = stub(wallabag_instance, "callAPI", function() return true end)

      -- Existing newer local file -> skipped (2)
      local res = wallabag_instance:download({
        id = 10,
        title = "Existing Article",
        mimetype = "text/html",
        updated_at = "2026-01-01",
      })
      assert.are.equal(2, res)

      -- New PDF article -> downloaded (3)
      res = wallabag_instance:download({
        id = 11,
        title = "PDF Article",
        mimetype = "application/pdf",
        url = "https://example.com/paper.pdf",
      })
      assert.are.equal(3, res)

      -- Failed download -> failed (1)
      call_api_stub:revert()
      call_api_stub = stub(wallabag_instance, "callAPI", function() return false end)
      res = wallabag_instance:download({
        id = 12,
        title = "Failed Article",
        mimetype = "text/html",
      })
      assert.are.equal(1, res)

      call_api_stub:revert()
      lfs_attr_stub:revert()
      doc_reg_mime_stub:revert()
      doc_reg_provider_stub:revert()
    end)
  end)

  describe("Synchronization and Deletion Handlers", function()
    it("should synchronize articles, download queue, and remote deletes", function()
      local show_stub = stub(UIManager, "show")
      local repaint_stub = stub(UIManager, "forceRepaint")
      local token_stub = stub(wallabag_instance, "getBearerToken", function() return true end)
      local add_art_stub = stub(wallabag_instance, "addArticle", function() return true end)
      local proc_local_stub = stub(wallabag_instance, "processLocalFiles", function() return 1 end)
      local proc_remote_stub = stub(wallabag_instance, "processRemoteDeletes", function() return 2 end)
      local dl_stub = stub(wallabag_instance, "download", function() return 3 end) -- downloaded

      local art_list_stub = stub(wallabag_instance, "getArticleList", function()
        return {
          { id = 101, title = "Art 1" },
          { id = 102, title = "Art 2" },
        }
      end)

      wallabag_instance.access_token = "valid_tok"
      wallabag_instance.download_queue = { "https://example.com/queued" }

      wallabag_instance:synchronize()

      assert.stub(add_art_stub).was.called(1)
      assert.stub(proc_local_stub).was.called(1)
      assert.stub(dl_stub).was.called(2)
      assert.stub(proc_remote_stub).was.called(1)

      art_list_stub:revert()
      dl_stub:revert()
      proc_remote_stub:revert()
      proc_local_stub:revert()
      add_art_stub:revert()
      token_stub:revert()
      repaint_stub:revert()
      show_stub:revert()
    end)

    it("should process remote deletes when is_sync_remote_delete is enabled", function()
      local show_stub = stub(UIManager, "show")
      local repaint_stub = stub(UIManager, "forceRepaint")
      wallabag_instance.is_sync_remote_delete = true
      wallabag_instance.directory = "/downloads/wallabag"

      local lfs_dir_stub = stub(lfs, "dir", function(dir)
        local files = { ".", "..", "[w-id_101] Keep.epub", "[w-id_102] Stale.epub" }
        local i = 0
        return function()
          i = i + 1
          return files[i]
        end
      end)

      local del_local_stub = stub(wallabag_instance, "deleteLocalArticle")

      local remote_ids = { ["101"] = true }
      local deleted = wallabag_instance:processRemoteDeletes(remote_ids)
      assert.are.equal(1, deleted)
      assert.stub(del_local_stub).was.called(1)

      del_local_stub:revert()
      lfs_dir_stub:revert()
      repaint_stub:revert()
      show_stub:revert()
    end)

    it("should process local files and remove / archive matching articles", function()
      local show_stub = stub(UIManager, "show")
      local repaint_stub = stub(UIManager, "forceRepaint")
      local token_stub = stub(wallabag_instance, "getBearerToken", function() return true end)

      wallabag_instance.is_delete_finished = true
      wallabag_instance.is_delete_read = true
      wallabag_instance.is_delete_abandoned = true
      wallabag_instance.send_review_as_tags = true

      local DocSettings = require("docsettings")
      local has_sidecar_stub = stub(DocSettings, "hasSidecarFile", function() return true end)
      local doc_settings_open_stub = stub(DocSettings, "open", function(self, path)
        if path:find("Complete") then
          return {
            readTableRef = function(self, key)
              if key == "summary" then return { status = "complete", note = "tag1, tag2" } end
              return {}
            end,
            read = function(self, key)
              if key == "percent_finished" then return 0.5 end
              return nil
            end,
          }
        elseif path:find("Abandoned") then
          return {
            readTableRef = function(self, key)
              if key == "summary" then return { status = "abandoned" } end
              return {}
            end,
            read = function(self, key) return nil end,
          }
        else
          return {
            readTableRef = function(self, key)
              if key == "summary" then return { status = "reading" } end
              return {}
            end,
            read = function(self, key)
              if key == "percent_finished" then return 1 end
              return nil
            end,
          }
        end
      end)

      local lfs_dir_stub = stub(lfs, "dir", function(dir)
        local files = { ".", "..", "[w-id_1] Complete.epub", "[w-id_2] Abandoned.epub", "[w-id_3] Read100.epub" }
        local i = 0
        return function()
          i = i + 1
          return files[i]
        end
      end)

      local remove_art_stub = stub(wallabag_instance, "removeArticle")
      local add_tags_stub = stub(wallabag_instance, "addTags")

      local num_deleted = wallabag_instance:processLocalFiles("manual")
      assert.are.equal(3, num_deleted)
      assert.stub(remove_art_stub).was.called(3)
      assert.stub(add_tags_stub).was.called(3)

      add_tags_stub:revert()
      remove_art_stub:revert()
      lfs_dir_stub:revert()
      doc_settings_open_stub:revert()
      has_sidecar_stub:revert()
      token_stub:revert()
      repaint_stub:revert()
      show_stub:revert()
    end)

    it("should removeArticle with PATCH when archiving and DELETE otherwise", function()
      local token_stub = stub(wallabag_instance, "getBearerToken", function() return true end)
      local call_api_stub = stub(wallabag_instance, "callAPI", function() return true end)
      local del_local_stub = stub(wallabag_instance, "deleteLocalArticle")

      -- DELETE mode
      wallabag_instance.is_archiving_deleted = false
      wallabag_instance:removeArticle("/downloads/wallabag/[w-id_77] MyArt.epub")
      assert.stub(call_api_stub).was.called(1)

      -- ARCHIVE mode
      wallabag_instance.is_archiving_deleted = true
      wallabag_instance:removeArticle("/downloads/wallabag/[w-id_77] MyArt.epub")
      assert.stub(call_api_stub).was.called(2)

      del_local_stub:revert()
      call_api_stub:revert()
      token_stub:revert()
    end)

    it("should addTags and addArticle properly", function()
      local DocSettings = require("docsettings")
      local doc_settings_open_stub = stub(DocSettings, "open", function()
        return {
          readTableRef = function(self, key)
            if key == "summary" then return { note = "review_tag" } end
            return {}
          end,
        }
      end)
      local call_api_stub = stub(wallabag_instance, "callAPI", function() return true end)
      local token_stub = stub(wallabag_instance, "getBearerToken", function() return true end)

      wallabag_instance:addTags("/downloads/wallabag/[w-id_88] Tagged.epub")
      assert.stub(call_api_stub).was.called(1)

      wallabag_instance:addArticle("https://example.com/new_art")
      assert.stub(call_api_stub).was.called(2)

      token_stub:revert()
      call_api_stub:revert()
      doc_settings_open_stub:revert()
    end)

    it("should handle addWallabagArticle and onSynchronizeWallabag online / offline", function()
      local show_stub = stub(UIManager, "show")
      local is_online_stub = stub(NetworkMgr, "isOnline", function() return false end)

      -- Offline -> adds to download queue
      wallabag_instance.download_queue = {}
      wallabag_instance:addWallabagArticle("https://example.com/queued_offline")
      assert.are.equal(1, #wallabag_instance.download_queue)

      -- Online -> adds article directly
      is_online_stub:revert()
      is_online_stub = stub(NetworkMgr, "isOnline", function() return true end)
      local add_stub = stub(wallabag_instance, "addArticle", function() return true end)
      wallabag_instance:addWallabagArticle("https://example.com/online_art")
      assert.stub(add_stub).was.called(1)

      -- onSynchronizeWallabag
      local run_online_stub = stub(NetworkMgr, "runWhenOnline", function(self, cb) cb() end)
      local sync_stub = stub(wallabag_instance, "synchronize")
      local refresh_stub = stub(wallabag_instance, "refreshCurrentDirIfNeeded")

      wallabag_instance:onSynchronizeWallabag()
      assert.stub(sync_stub).was.called(1)
      assert.stub(refresh_stub).was.called(1)

      refresh_stub:revert()
      sync_stub:revert()
      run_online_stub:revert()
      add_stub:revert()
      is_online_stub:revert()
      show_stub:revert()
    end)
  end)

  describe("Menu Structure and Dispatcher", function()
    it("should populate mainMenu and submenus", function()
      local menu_items = {}
      wallabag_instance:addToMainMenu(menu_items)

      assert.is_table(menu_items.wallabag)
      assert.is_table(menu_items.wallabag.sub_item_table)
      assert.is_true(#menu_items.wallabag.sub_item_table >= 3)
    end)

    it("should exercise all sub_item_table items and callbacks", function()
      local show_stub = stub(UIManager, "show")
      local bcast_stub = stub(UIManager, "broadcastEvent")
      local dl_dir_stub = stub(wallabag_instance, "setDownloadDirectory")
      local srv_stub = stub(wallabag_instance, "editServerSettings")
      local cli_stub = stub(wallabag_instance, "editClientSettings")
      local filter_stub = stub(wallabag_instance, "setFilterTag")
      local tags_stub = stub(wallabag_instance, "setTagsDialog")

      local menu_items = {}
      wallabag_instance:addToMainMenu(menu_items)

      local items = menu_items.wallabag.sub_item_table
      -- Retrieve new articles
      items[1].callback()
      assert.stub(bcast_stub).was.called(1)

      -- Delete finished articles remotely
      local run_online_stub = stub(NetworkMgr, "runWhenOnline", function(self, cb) cb() end)
      local proc_stub = stub(wallabag_instance, "processLocalFiles", function() return 5 end)
      assert.is_true(items[2].enabled_func())
      items[2].callback()
      proc_stub:revert()
      run_online_stub:revert()

      -- Go to download folder
      local filemanager_stub = stub(require("apps/filemanager/filemanager"), "showFiles")
      items[3].callback()
      assert.stub(filemanager_stub).was.called(1)
      filemanager_stub:revert()

      -- Settings submenu items
      local settings_items = items[4].sub_item_table
      assert.is_table(settings_items)
      for _, s_item in ipairs(settings_items) do
        if s_item.text_func then
          assert.is_string(s_item.text_func())
        end
        if s_item.checked_func then
          s_item.checked_func()
        end
        if s_item.callback then
          s_item.callback({ updateItems = function() end })
        end
        if s_item.sub_item_table then
          for _, del_item in ipairs(s_item.sub_item_table) do
            if del_item.checked_func then
              del_item.checked_func()
            end
            if del_item.callback then
              del_item.callback()
            end
          end
        end
      end

      -- Info item
      items[5].callback()

      tags_stub:revert()
      filter_stub:revert()
      cli_stub:revert()
      srv_stub:revert()
      dl_dir_stub:revert()
      bcast_stub:revert()
      show_stub:revert()
    end)

    it("should register dispatcher action", function()
      local Dispatcher = require("dispatcher")
      local register_stub = stub(Dispatcher, "registerAction")
      wallabag_instance:onDispatcherRegisterActions()
      assert.stub(register_stub).was.called_with(Dispatcher, "wallabag_download", match.is_table())
      register_stub:revert()
    end)
  end)

  describe("Article Processing and Deletion Handlers", function()
    it("should extract article ID and delete local article safely", function()
      local path = "/downloads/wallabag/[w-id_42] Sample.epub"
      local id = wallabag_instance:getArticleID(path)
      assert.are.equal("42", id)

      local delete_stub = stub(require("apps/filemanager/filemanager"), "deleteFile")
      local lfs_stub = stub(require("libs/libkoreader-lfs"), "attributes", function() return "file" end)
      wallabag_instance:deleteLocalArticle(path)
      assert.stub(delete_stub).was.called()

      lfs_stub:revert()
      delete_stub:revert()
    end)

    it("should filter ignored tags and manage download queue", function()
      wallabag_instance.ignore_tags = "skipme, ignorethis"
      local articles = {
        { id = 1, title = "Article 1", tags = { { label = "keep" } } },
        { id = 2, title = "Article 2", tags = { { label = "skipme" } } },
        { id = 3, title = "Article 3", tags = { { label = "fine" } } },
      }
      local filtered = wallabag_instance:filterIgnoredTags(articles)
      assert.are.equal(2, #filtered)
      assert.are.equal(1, filtered[1].id)
      assert.are.equal(3, filtered[2].id)

      wallabag_instance.download_queue = {}
      wallabag_instance:addToDownloadQueue("https://example.com/article1")
      assert.are.equal(1, #wallabag_instance.download_queue)
      assert.are.equal("https://example.com/article1", wallabag_instance.download_queue[1])
    end)

    it("should handle onCloseDocument safely", function()
      wallabag_instance.remove_finished_from_history = true
      local mock_doc_settings = {
        readTableRef = function() return { status = "complete" } end,
      }
      wallabag_instance.ui.document = { file = "/downloads/wallabag/[w-id_42] Sample.epub" }
      wallabag_instance.ui.doc_settings = mock_doc_settings
      wallabag_instance.ui.paging = { getLastPercent = function() return 1 end }
      wallabag_instance.ui.setLastDirForFileBrowser = function() end

      local remove_stub = stub(require("readhistory"), "removeItemByPath")
      wallabag_instance:onCloseDocument()
      assert.stub(remove_stub).was.called()
      remove_stub:revert()
    end)
  end)
end)
