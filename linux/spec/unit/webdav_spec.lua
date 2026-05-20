describe("WebDav", function()
  local WebDav
  local mock_webdav_api
  local mock_uimanager
  local mock_document_registry
  local mock_reader_ui
  local mock_confirm_box
  local mock_info_message
  local mock_multi_input_dialog
  local mock_util
  local mock_ffi_util

  setup(function()
    require("commonrequire")
  end)

  before_each(function()
    _G.G_reader_settings = {
      isTrue = function(self, _key)
        return false
      end,
    }

    mock_webdav_api = {
      download_response = 200,
      upload_response = 200,
      create_folder_response = 201,
      listFolder = function(self, _address, _user, _pass, _path, _folder_mode)
        return { "file1", "file2" }
      end,
      downloadFile = function(self, _url, _username, _password, _local_path)
        return self.download_response
      end,
      getJoinedPath = function(self, address, path)
        if address:sub(-1) == "/" or path:sub(1, 1) == "/" then
          return address .. path
        else
          return address .. "/" .. path
        end
      end,
      uploadFile = function(self, _path, _username, _password, _local_path)
        return self.upload_response
      end,
      createFolder = function(self, _url, _username, _password, _folder_name)
        return self.create_folder_response
      end,
      urlEncode = function(str)
        return str -- simple passthrough for tests
      end,
    }
    package.loaded["apps/cloudstorage/webdavapi"] = mock_webdav_api

    mock_uimanager = {
      shown_widgets = {},
      show = function(self, widget)
        table.insert(self.shown_widgets, widget)
      end,
      broadcastEvent = function(self, event)
        self.broadcasted_event = event
      end,
      close = function(self, widget)
        for i, w in ipairs(self.shown_widgets) do
          if w == widget then
            table.remove(self.shown_widgets, i)
            break
          end
        end
      end,
    }
    package.loaded["ui/uimanager"] = mock_uimanager

    mock_document_registry = {
      has_provider = true,
      hasProvider = function(self, _filename)
        return mock_document_registry.has_provider
      end,
    }
    package.loaded["document/documentregistry"] = mock_document_registry

    mock_reader_ui = {
      showReader_called_with = nil,
      showReader = function(self, path)
        self.showReader_called_with = path
      end,
    }
    package.loaded["apps/reader/readerui"] = mock_reader_ui

    mock_confirm_box = {
      new = function(self, args)
        return {
          is_confirm_box = true,
          text = args.text,
          ok_callback = args.ok_callback,
        }
      end,
    }
    package.loaded["ui/widget/confirmbox"] = mock_confirm_box

    mock_info_message = {
      new = function(self, args)
        return {
          is_info_message = true,
          text = args.text,
          timeout = args.timeout,
        }
      end,
    }
    package.loaded["ui/widget/infomessage"] = mock_info_message

    mock_multi_input_dialog = {
      new = function(self, args)
        return {
          is_multi_input_dialog = true,
          args = args,
          onExit = function(self) end,
        }
      end,
    }
    package.loaded["ui/widget/multiinputdialog"] = mock_multi_input_dialog

    mock_util = {
      splitFilePathName = function(path)
        local dir = path:match("^(.*)/") or ""
        local file = path:match("([^/]+)$") or path
        return dir, file
      end,
      urlEncode = function(str)
        return str
      end,
      fixUtf8 = function(str, _replacement)
        return str
      end,
    }
    package.loaded["util"] = mock_util

    package.loaded["ui/bidi"] = {
      dirpath = function(p)
        return p
      end,
      filepath = function(p)
        return p
      end,
      filename = function(p)
        return p
      end,
    }

    mock_ffi_util = {
      template = function(tmpl, ...)
        local args = { ... }
        return tmpl:gsub("%%(%d+)", function(n)
          return tostring(args[tonumber(n)])
        end)
      end,
      basename = function(path)
        return path:match("([^/]+)$") or path
      end,
    }
    package.loaded["ffi/util"] = mock_ffi_util

    package.loaded["gettext"] = function(text)
      return text
    end

    package.loaded["logger"] = {
      dbg = function() end,
    }

    package.loaded["ui/event"] = {
      new = function(self, name, ...)
        return { name = name, ... }
      end,
    }

    WebDav = require("apps/cloudstorage/webdav")
  end)

  after_each(function()
    package.loaded["apps/cloudstorage/webdav"] = nil
    package.loaded["apps/cloudstorage/webdavapi"] = nil
    package.loaded["ui/uimanager"] = nil
    package.loaded["document/documentregistry"] = nil
    package.loaded["apps/reader/readerui"] = nil
    package.loaded["ui/widget/confirmbox"] = nil
    package.loaded["ui/widget/infomessage"] = nil
    package.loaded["ui/widget/multiinputdialog"] = nil
    package.loaded["util"] = nil
    package.loaded["ui/bidi"] = nil
    package.loaded["ffi/util"] = nil
    package.loaded["gettext"] = nil
    package.loaded["logger"] = nil
    package.loaded["ui/event"] = nil
    _G.G_reader_settings = nil
  end)

  describe("run", function()
    it("should call WebDavApi:listFolder", function()
      local res = WebDav:run("http://example.com", "user", "pass", "/path", true)
      assert.are.same({ "file1", "file2" }, res)
    end)
  end)

  describe("downloadFile", function()
    it("should show ConfirmBox on success by default", function()
      local callback_called = false
      local callback_close = function()
        callback_called = true
      end

      WebDav:downloadFile(
        { url = "remote/file.epub" },
        "http://example.com",
        "user",
        "pass",
        "/local/path/file.epub",
        callback_close
      )

      assert.are.equal(1, #mock_uimanager.shown_widgets)
      local widget = mock_uimanager.shown_widgets[1]
      assert.is_true(widget.is_confirm_box)
      assert.are.equal(
        "File saved to:\n/local/path/file.epub\nWould you like to read the downloaded book now?",
        widget.text
      )

      -- Trigger OK
      widget.ok_callback()

      assert.truthy(mock_uimanager.broadcasted_event)
      assert.are.equal("SetupShowReader", mock_uimanager.broadcasted_event.name)
      assert.is_true(callback_called)
      assert.are.equal(
        "/local/path/file.epub",
        mock_reader_ui.showReader_called_with
      )
    end)

    it(
      "should show InfoMessage on success if show_unsupported is true and no provider exists",
      function()
        _G.G_reader_settings.isTrue = function(self, key)
          if key == "show_unsupported" then
            return true
          end
          return false
        end
        mock_document_registry.has_provider = false

        WebDav:downloadFile(
          { url = "remote/file.unsupported" },
          "http://example.com",
          "user",
          "pass",
          "/local/path/file.unsupported",
          nil
        )

        assert.are.equal(1, #mock_uimanager.shown_widgets)
        local widget = mock_uimanager.shown_widgets[1]
        assert.is_true(widget.is_info_message)
        assert.are.equal(
          "File saved to:\n/local/path/file.unsupported",
          widget.text
        )
      end
    )

    it("should show InfoMessage on failure", function()
      mock_webdav_api.download_response = 500

      WebDav:downloadFile(
        { url = "remote/file.epub" },
        "http://example.com",
        "user",
        "pass",
        "/local/path/file.epub",
        nil
      )

      assert.are.equal(1, #mock_uimanager.shown_widgets)
      local widget = mock_uimanager.shown_widgets[1]
      assert.is_true(widget.is_info_message)
      assert.are.equal(
        "Could not save file to:\n/local/path/file.epub",
        widget.text
      )
      assert.are.equal(3, widget.timeout)
    end)
  end)

  describe("uploadFile", function()
    it("should show InfoMessage on success", function()
      local callback_called = false
      local callback_close = function()
        callback_called = true
      end

      WebDav:uploadFile(
        "remote/dir",
        "http://example.com",
        "user",
        "pass",
        "/local/path/file.epub",
        callback_close
      )

      assert.are.equal(1, #mock_uimanager.shown_widgets)
      local widget = mock_uimanager.shown_widgets[1]
      assert.is_true(widget.is_info_message)
      assert.are.equal(
        "File uploaded:\nhttp://example.com",
        widget.text
      )
      assert.is_true(callback_called)
    end)

    it("should show InfoMessage on failure", function()
      mock_webdav_api.upload_response = 500

      WebDav:uploadFile(
        "remote/dir",
        "http://example.com",
        "user",
        "pass",
        "/local/path/file.epub",
        nil
      )

      assert.are.equal(1, #mock_uimanager.shown_widgets)
      local widget = mock_uimanager.shown_widgets[1]
      assert.is_true(widget.is_info_message)
      assert.are.equal(
        "Could not upload file:\nhttp://example.com",
        widget.text
      )
      assert.are.equal(3, widget.timeout)
    end)
  end)

  describe("createFolder", function()
    it("should call callback on success", function()
      local callback_called = false
      local callback_close = function()
        callback_called = true
      end

      WebDav:createFolder(
        "remote/dir",
        "http://example.com/",
        "user",
        "pass",
        "new_folder",
        callback_close
      )

      assert.is_true(callback_called)
      assert.are.equal(0, #mock_uimanager.shown_widgets)
    end)

    it("should show InfoMessage on failure", function()
      mock_webdav_api.create_folder_response = 500

      WebDav:createFolder(
        "remote/dir",
        "http://example.com/",
        "user",
        "pass",
        "new_folder",
        nil
      )

      assert.are.equal(1, #mock_uimanager.shown_widgets)
      local widget = mock_uimanager.shown_widgets[1]
      assert.is_true(widget.is_info_message)
      assert.are.equal(
        "Could not create folder:\nnew_folder",
        widget.text
      )
    end)
  end)

  describe("info", function()
    it("should show InfoMessage with account info", function()
      WebDav:info({ text = "My WebDAV", address = "http://example.com" })

      assert.are.equal(1, #mock_uimanager.shown_widgets)
      local widget = mock_uimanager.shown_widgets[1]
      assert.is_true(widget.is_info_message)
      assert.are.equal(
        "Type: WebDAV\nName: My WebDAV\nAddress: http://example.com",
        widget.text
      )
    end)
  end)
end)
