describe("SyncService", function()
  local SyncService
  local mock_network_mgr
  local mock_dropbox_api
  local mock_webdav_api
  local mock_ffiutil
  local mock_os
  local mock_uimanager
  local original_os_remove
  local gettext_called_with

  setup(function()
    require("commonrequire")
  end)

  before_each(function()
    gettext_called_with = {}
    mock_os = {
      removed_files = {},
    }
    original_os_remove = os.remove
    -- luacheck: ignore 122
    os.remove = function(path)
      table.insert(mock_os.removed_files, path)
      return true
    end

    -- Mock dependencies
    package.loaded["datastorage"] = {
      getSettingsDir = function()
        return "/tmp"
      end,
    }
    package.loaded["ui/font"] = {
      getFace = function()
        return "mock_face"
      end,
    }
    package.loaded["ui/widget/infomessage"] = {
      new = function(self, args)
        return args
      end,
    }
    package.loaded["luasettings"] = {
      open = function(_, _path)
        return {
          readTableRef = function(_, _key)
            return {}
          end,
        }
      end,
    }

    -- Simple Mock Widget / Menu
    local Widget = {
      extend = function(self, props)
        local class = {}
        for k, v in pairs(props or {}) do
          class[k] = v
        end
        class.init = function(self) end
        return class
      end,
    }
    package.loaded["ui/widget/menu"] = Widget

    mock_network_mgr = {
      runWhenOnline_called = false,
      runWhenConnected_called = false,
      runWhenOnline = function(self, cb)
        self.runWhenOnline_called = true
        self.cb = cb
      end,
      runWhenConnected = function(self, cb)
        self.runWhenConnected_called = true
        self.cb = cb
      end,
    }
    package.loaded["ui/network/manager"] = mock_network_mgr

    package.loaded["ui/widget/notification"] = {
      new = function(self, args)
        return args
      end,
    }

    package.loaded["device"] = {
      screen = {
        getWidth = function()
          return 800
        end,
        getHeight = function()
          return 600
        end,
      },
    }

    mock_uimanager = {
      shown_widget = nil,
      show = function(self, widget)
        self.shown_widget = widget
      end,
    }
    package.loaded["ui/uimanager"] = mock_uimanager

    mock_ffiutil = {
      basename_called_with = nil,
      basename = function(path)
        mock_ffiutil.basename_called_with = path
        return path:match("^.+/(.+)$") or path
      end,
      copyFile_called = false,
      copyFile = function(src, dest)
        mock_ffiutil.copyFile_called = true
        mock_ffiutil.copy_src = src
        mock_ffiutil.copy_dest = dest
      end,
    }
    package.loaded["ffi/util"] = mock_ffiutil

    local mock_util = {
      stringStartsWith = function(str, prefix)
        return str:sub(1, #prefix) == prefix
      end,
      stringEndsWith = function(str, suffix)
        return suffix == "" or str:sub(-#suffix) == suffix
      end,
      urlDecode = function(str)
        return str
      end,
    }
    package.loaded["util"] = mock_util

    package.loaded["gettext"] = function(text)
      table.insert(gettext_called_with, text)
      return text
    end

    mock_dropbox_api = {
      downloadFile_called = false,
      downloadFile = function(self, path, token, dest)
        self.downloadFile_called = true
        self.download_path = path
        self.download_token = token
        self.download_dest = dest
        local code = self.download_code or 200
        -- If we have a list of codes, use them one by one
        if type(self.download_code_list) == "table" then
          code = table.remove(self.download_code_list, 1) or 200
        end
        return code, self.download_etag or "etag123"
      end,
      uploadFile_called = false,
      uploadFile = function(self, url_base, token, path, etag, _autorename)
        self.uploadFile_called = true
        self.upload_url_base = url_base
        self.upload_token = token
        self.upload_path = path
        self.upload_etag = etag
        local code = self.upload_code or 200
        if type(self.upload_code_list) == "table" then
          code = table.remove(self.upload_code_list, 1) or 200
        end
        return code
      end,
      getAccessToken = function(self, password, _address)
        return "token_" .. password
      end,
    }
    package.loaded["apps/cloudstorage/dropboxapi"] = mock_dropbox_api

    mock_webdav_api = {
      downloadFile_called = false,
      downloadFile = function(self, path, username, password, dest)
        self.downloadFile_called = true
        self.download_path = path
        self.download_username = username
        self.download_password = password
        self.download_dest = dest
        local code = self.download_code or 200
        if type(self.download_code_list) == "table" then
          code = table.remove(self.download_code_list, 1) or 200
        end
        return code, self.download_etag or "etag123"
      end,
      uploadFile_called = false,
      uploadFile = function(self, path, username, password, src, etag)
        self.uploadFile_called = true
        self.upload_path = path
        self.upload_username = username
        self.upload_password = password
        self.upload_src = src
        self.upload_etag = etag
        local code = self.upload_code or 200
        if type(self.upload_code_list) == "table" then
          code = table.remove(self.upload_code_list, 1) or 200
        end
        return code
      end,
      getJoinedPath = function(self, p1, p2)
        if p1:sub(-1) == "/" then
          p1 = p1:sub(1, -2)
        end
        if p2:sub(1, 1) == "/" then
          p2 = p2:sub(2)
        end
        return p1 .. "/" .. p2
      end,
    }
    package.loaded["apps/cloudstorage/webdavapi"] = mock_webdav_api

    package.loaded["logger"] = {
      err = function() end,
    }

    package.loaded["apps/cloudstorage/syncservice"] = nil
    SyncService = require("apps/cloudstorage/syncservice")
  end)

  after_each(function()
    -- luacheck: ignore 122
    os.remove = original_os_remove
    package.loaded["apps/cloudstorage/syncservice"] = nil
    package.loaded["datastorage"] = nil
    package.loaded["ui/font"] = nil
    package.loaded["ui/widget/infomessage"] = nil
    package.loaded["luasettings"] = nil
    package.loaded["ui/widget/menu"] = nil
    package.loaded["ui/network/manager"] = nil
    package.loaded["ui/widget/notification"] = nil
    package.loaded["device"] = nil
    package.loaded["ui/uimanager"] = nil
    package.loaded["ffi/util"] = nil
    package.loaded["util"] = nil
    package.loaded["gettext"] = nil
    package.loaded["apps/cloudstorage/dropboxapi"] = nil
    package.loaded["apps/cloudstorage/webdavapi"] = nil
    package.loaded["logger"] = nil
  end)

  describe("getReadablePath", function()
    it("should format Dropbox path correctly", function()
      local server = {
        type = "dropbox",
        url = "myfolder",
      }
      assert.are.equal("/myfolder/", SyncService.getReadablePath(server))

      server.url = "/myfolder"
      assert.are.equal("/myfolder/", SyncService.getReadablePath(server))

      server.url = "myfolder/"
      assert.are.equal("/myfolder/", SyncService.getReadablePath(server))
    end)

    it("should format WebDAV path correctly", function()
      local server = {
        type = "webdav",
        address = "http://example.com",
        url = "myfolder",
      }
      assert.are.equal(
        "http://example.com/myfolder/",
        SyncService.getReadablePath(server)
      )

      server.address = "http://example.com/"
      server.url = "/myfolder"
      assert.are.equal(
        "http://example.com/myfolder/",
        SyncService.getReadablePath(server)
      )

      server.address = "http://example.com/"
      server.url = "myfolder/"
      assert.are.equal(
        "http://example.com/myfolder/",
        SyncService.getReadablePath(server)
      )
    end)
  end)

  describe("removeLastSyncDB", function()
    it("should remove the sync DB file", function()
      SyncService.removeLastSyncDB("/path/to/file")
      assert.are.equal(1, #mock_os.removed_files)
      assert.are.equal("/path/to/file.sync", mock_os.removed_files[1])
    end)
  end)

  describe("sync", function()
    it("should assert if wrong server type", function()
      local server = {
        type = "unknown",
      }
      local cb_called = false
      SyncService.sync(server, "/path/to/file", function()
        cb_called = true
      end, true)

      -- Since it is unknown type, it runs on connected (WebDAV is default if not dropbox)
      -- Wait, if server.type ~= "dropbox" and server.type ~= "webdav"
      -- But SyncService.sync has:
      -- if server.type == "dropbox" then NetworkMgr:runWhenOnline(exec) else NetworkMgr:runWhenConnected(exec) end
      -- So "unknown" will run NetworkMgr:runWhenConnected(exec)
      assert.is_true(mock_network_mgr.runWhenConnected_called)

      -- Trigger exec
      mock_network_mgr.cb()

      assert.is_false(cb_called)
      assert.is_nil(mock_uimanager.shown_widget) -- silent = true
    end)

    it("should show wrong server type error if not silent", function()
      local server = {
        type = "unknown",
      }
      SyncService.sync(server, "/path/to/file", function() end, false)
      mock_network_mgr.cb()

      assert.truthy(mock_uimanager.shown_widget)
      assert.are.equal("Wrong server type.", mock_uimanager.shown_widget.text)
    end)

    describe("Dropbox flow", function()
      local server
      before_each(function()
        server = {
          type = "dropbox",
          url = "/books",
          password = "mypasstoken",
          address = "", -- no address means no getAccessToken override
        }
      end)

      it("should download, callback, upload, and copy on success", function()
        local cb_called = false
        local cb_args = {}
        local sync_cb = function(file, cached, income)
          cb_called = true
          cb_args = { file, cached, income }
          return true
        end

        SyncService.sync(server, "/path/to/book.epub", sync_cb, true)

        assert.is_true(mock_network_mgr.runWhenOnline_called)
        assert.is_false(mock_network_mgr.runWhenConnected_called)

        -- Execute
        mock_network_mgr.cb()

        assert.is_true(mock_dropbox_api.downloadFile_called)
        assert.are.equal("/books/book.epub", mock_dropbox_api.download_path)
        assert.are.equal("mypasstoken", mock_dropbox_api.download_token)
        assert.are.equal(
          "/path/to/book.epub.temp",
          mock_dropbox_api.download_dest
        )

        assert.is_true(cb_called)
        assert.are.equal("/path/to/book.epub", cb_args[1])
        assert.are.equal("/path/to/book.epub.sync", cb_args[2])
        assert.are.equal("/path/to/book.epub.temp", cb_args[3])

        assert.is_true(mock_dropbox_api.uploadFile_called)
        assert.are.equal("/books", mock_dropbox_api.upload_url_base)
        assert.are.equal("mypasstoken", mock_dropbox_api.upload_token)
        assert.are.equal("/path/to/book.epub", mock_dropbox_api.upload_path)
        assert.are.equal("etag123", mock_dropbox_api.upload_etag)

        -- Cleanups
        -- Temporaries are removed (income_file_path twice: once inside retry loop start, and once at the end)
        -- Wait, the loop removes it at start: `os.remove(income_file_path)`.
        -- And at the end: `os.remove(income_file_path)` again.
        -- Also `os.remove(cached_file_path)` before copy.
        local expected_removed = {
          "/path/to/book.epub.temp", -- start of loop
          "/path/to/book.epub.temp", -- end of function
          "/path/to/book.epub.sync", -- before copying to cached
        }
        assert.are.equal(#expected_removed, #mock_os.removed_files)
        for i, path in ipairs(expected_removed) do
          assert.are.equal(path, mock_os.removed_files[i])
        end

        assert.is_true(mock_ffiutil.copyFile_called)
        assert.are.equal("/path/to/book.epub", mock_ffiutil.copy_src)
        assert.are.equal("/path/to/book.epub.sync", mock_ffiutil.copy_dest)
      end)

      it("should not upload if download fails", function()
        mock_dropbox_api.download_code = 500
        local cb_called = false

        SyncService.sync(server, "/path/to/book.epub", function()
          cb_called = true
          return true
        end, true)
        mock_network_mgr.cb()

        assert.is_true(mock_dropbox_api.downloadFile_called)
        assert.is_false(cb_called)
        assert.is_false(mock_dropbox_api.uploadFile_called)
        assert.is_false(mock_ffiutil.copyFile_called)
      end)

      it("should not upload if callback returns false", function()
        local cb_called = false
        SyncService.sync(server, "/path/to/book.epub", function()
          cb_called = true
          return false
        end, true)
        mock_network_mgr.cb()

        assert.is_true(mock_dropbox_api.downloadFile_called)
        assert.is_true(cb_called)
        assert.is_false(mock_dropbox_api.uploadFile_called)
        assert.is_false(mock_ffiutil.copyFile_called)
      end)

      it(
        "should retry on 412 (etag conflict) and succeed on second attempt",
        function()
          -- First download returns 200
          -- First upload returns 412
          -- Second download returns 200
          -- Second upload returns 200
          mock_dropbox_api.upload_code_list = { 412, 200 }

          local cb_count = 0
          local sync_cb = function()
            cb_count = cb_count + 1
            return true
          end

          local original_download = mock_dropbox_api.downloadFile
          local download_count = 0
          mock_dropbox_api.downloadFile = function(self, ...)
            download_count = download_count + 1
            return original_download(self, ...)
          end

          local original_upload = mock_dropbox_api.uploadFile
          local upload_count = 0
          mock_dropbox_api.uploadFile = function(self, ...)
            upload_count = upload_count + 1
            return original_upload(self, ...)
          end

          SyncService.sync(server, "/path/to/book.epub", sync_cb, true)
          mock_network_mgr.cb()

          assert.are.equal(2, download_count)
          assert.are.equal(2, cb_count)
          assert.are.equal(2, upload_count)
          assert.is_true(mock_ffiutil.copyFile_called)
        end
      )
    end)

    describe("WebDAV flow", function()
      local server
      before_each(function()
        server = {
          type = "webdav",
          address = "http://mywebdav.com",
          url = "/books",
          username = "davuser",
          password = "davpassword",
        }
      end)

      it("should download, callback, upload, and copy on success", function()
        local cb_called = false
        local cb_args = {}
        local sync_cb = function(file, cached, income)
          cb_called = true
          cb_args = { file, cached, income }
          return true
        end

        SyncService.sync(server, "/path/to/book.epub", sync_cb, true)

        assert.is_false(mock_network_mgr.runWhenOnline_called)
        assert.is_true(mock_network_mgr.runWhenConnected_called)

        -- Execute
        mock_network_mgr.cb()

        assert.is_true(mock_webdav_api.downloadFile_called)
        -- Joined path: http://mywebdav.com + /books + book.epub -> http://mywebdav.com/books/book.epub
        assert.are.equal(
          "http://mywebdav.com/books/book.epub",
          mock_webdav_api.download_path
        )
        assert.are.equal("davuser", mock_webdav_api.download_username)
        assert.are.equal("davpassword", mock_webdav_api.download_password)
        assert.are.equal(
          "/path/to/book.epub.temp",
          mock_webdav_api.download_dest
        )

        assert.is_true(cb_called)
        assert.are.equal("/path/to/book.epub", cb_args[1])
        assert.are.equal("/path/to/book.epub.sync", cb_args[2])
        assert.are.equal("/path/to/book.epub.temp", cb_args[3])

        assert.is_true(mock_webdav_api.uploadFile_called)
        assert.are.equal(
          "http://mywebdav.com/books/book.epub",
          mock_webdav_api.upload_path
        )
        assert.are.equal("davuser", mock_webdav_api.upload_username)
        assert.are.equal("davpassword", mock_webdav_api.upload_password)
        assert.are.equal("/path/to/book.epub", mock_webdav_api.upload_src)
        assert.are.equal("etag123", mock_webdav_api.upload_etag)

        assert.is_true(mock_ffiutil.copyFile_called)
      end)
    end)
  end)
end)
