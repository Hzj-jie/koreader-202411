describe("DropBox", function()
  local DropBox
  local mock_dropbox_api
  local mock_uimanager
  local mock_document_registry
  local mock_reader_ui
  local mock_confirm_box
  local mock_info_message
  local mock_multi_input_dialog
  local mock_util

  setup(function()
    require("commonrequire")
  end)

  before_each(function()
    _G.G_reader_settings = {
      isTrue = function(self, _key)
        return false
      end,
    }

    mock_dropbox_api = {
      getAccessToken = function(self, _refresh_token, _app_key_colon_secret)
        return "mock_access_token"
      end,
      listFolder = function(self, _url, _password, _choose_folder_mode)
        return { "folder1", "folder2" }
      end,
      showFiles = function(self, _url, _password)
        return { { text = "file1.epub", size = 100 } }
      end,
      downloadFile = function(self, _url, _password, _path)
        return self.download_code or 200
      end,
      uploadFile = function(self, _url, _password, _file_path)
        return self.upload_code or 200
      end,
      createFolder = function(self, _url, _password, _folder_name)
        return self.create_folder_code or 200
      end,
      fetchInfo = function(self, _token, space)
        if space then
          return { allocation = { allocated = 1000 }, used = 500 }
        else
          return {
            account_type = { [".tag"] = "basic" },
            name = { display_name = "User" },
            email = "user@test.com",
            country = "US",
          }
        end
      end,
    }
    package.loaded["apps/cloudstorage/dropboxapi"] = mock_dropbox_api

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
      getFriendlySize = function(size)
        return size .. " bytes"
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

    package.loaded["ffi/util"] = {
      template = function(tmpl, ...)
        local args = { ... }
        return tmpl:gsub("%%(%d+)", function(n)
          return tostring(args[tonumber(n)])
        end)
      end,
    }

    package.loaded["gettext"] = function(text)
      return text
    end

    package.loaded["ui/event"] = {
      new = function(self, name, ...)
        return { name = name, ... }
      end,
    }

    DropBox = require("apps/cloudstorage/dropbox")
  end)

  after_each(function()
    package.loaded["apps/cloudstorage/dropbox"] = nil
    package.loaded["apps/cloudstorage/dropboxapi"] = nil
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
    package.loaded["ui/event"] = nil
    _G.G_reader_settings = nil
  end)

  describe("getAccessToken", function()
    it("should call DropBoxApi:getAccessToken", function()
      local token = DropBox:getAccessToken("refresh", "key:secret")
      assert.are.equal("mock_access_token", token)
    end)
  end)

  describe("run", function()
    it("should call DropBoxApi:listFolder", function()
      local res = DropBox:run("/url", "pass", true)
      assert.are.same({ "folder1", "folder2" }, res)
    end)
  end)

  describe("showFiles", function()
    it("should call DropBoxApi:showFiles", function()
      local res = DropBox:showFiles("/url", "pass")
      assert.are.same({ { text = "file1.epub", size = 100 } }, res)
    end)
  end)

  describe("downloadFile", function()
    it("should show ConfirmBox on success by default", function()
      mock_dropbox_api.download_code = 200
      local callback_called = false
      local callback_close = function()
        callback_called = true
      end

      DropBox:downloadFile(
        { url = "/remote/path" },
        "pass",
        "/local/path/book.epub",
        callback_close
      )

      assert.are.equal(1, #mock_uimanager.shown_widgets)
      local widget = mock_uimanager.shown_widgets[1]
      assert.is_true(widget.is_confirm_box)
      assert.are.equal(
        "File saved to:\n/local/path/book.epub\nWould you like to read the downloaded book now?",
        widget.text
      )

      -- Trigger OK
      widget.ok_callback()

      assert.truthy(mock_uimanager.broadcasted_event)
      assert.are.equal("SetupShowReader", mock_uimanager.broadcasted_event.name)
      assert.is_true(callback_called)
      assert.are.equal(
        "/local/path/book.epub",
        mock_reader_ui.showReader_called_with
      )
    end)

    it(
      "should show InfoMessage on success if show_unsupported is true and no provider exists",
      function()
        mock_dropbox_api.download_code = 200
        _G.G_reader_settings.isTrue = function(self, key)
          if key == "show_unsupported" then
            return true
          end
          return false
        end
        mock_document_registry.has_provider = false

        DropBox:downloadFile(
          { url = "/remote/path" },
          "pass",
          "/local/path/book.unsupported",
          nil
        )

        assert.are.equal(1, #mock_uimanager.shown_widgets)
        local widget = mock_uimanager.shown_widgets[1]
        assert.is_true(widget.is_info_message)
        assert.are.equal(
          "File saved to:\n/local/path/book.unsupported",
          widget.text
        )
      end
    )

    it("should show InfoMessage on failure", function()
      mock_dropbox_api.download_code = 500

      DropBox:downloadFile(
        { url = "/remote/path" },
        "pass",
        "/local/path/book.epub",
        nil
      )

      assert.are.equal(1, #mock_uimanager.shown_widgets)
      local widget = mock_uimanager.shown_widgets[1]
      assert.is_true(widget.is_info_message)
      assert.are.equal(
        "Could not save file to:\n/local/path/book.epub",
        widget.text
      )
      assert.are.equal(3, widget.timeout)
    end)
  end)

  describe("downloadFileNoUI", function()
    it("should return true on success", function()
      mock_dropbox_api.download_code = 200
      local res =
        DropBox:downloadFileNoUI("/remote/path", "pass", "/local/path")
      assert.is_true(res)
    end)

    it("should return false on failure", function()
      mock_dropbox_api.download_code = 500
      local res =
        DropBox:downloadFileNoUI("/remote/path", "pass", "/local/path")
      assert.is_false(res)
    end)
  end)

  describe("uploadFile", function()
    it("should show InfoMessage on success", function()
      mock_dropbox_api.upload_code = 200
      local callback_called = false
      local callback_close = function()
        callback_called = true
      end

      DropBox:uploadFile(
        "/remote/path",
        "pass",
        "/local/path/book.epub",
        callback_close
      )

      assert.are.equal(1, #mock_uimanager.shown_widgets)
      local widget = mock_uimanager.shown_widgets[1]
      assert.is_true(widget.is_info_message)
      assert.are.equal("File uploaded:\nbook.epub", widget.text)
      assert.is_true(callback_called)
    end)

    it("should show InfoMessage on failure", function()
      mock_dropbox_api.upload_code = 500

      DropBox:uploadFile("/remote/path", "pass", "/local/path/book.epub", nil)

      assert.are.equal(1, #mock_uimanager.shown_widgets)
      local widget = mock_uimanager.shown_widgets[1]
      assert.is_true(widget.is_info_message)
      assert.are.equal("Could not upload file:\nbook.epub", widget.text)
    end)
  end)

  describe("createFolder", function()
    it("should call callback on success", function()
      mock_dropbox_api.create_folder_code = 200
      local callback_called = false
      local callback_close = function()
        callback_called = true
      end

      DropBox:createFolder("/remote/path", "pass", "new_folder", callback_close)

      assert.is_true(callback_called)
      assert.are.equal(0, #mock_uimanager.shown_widgets)
    end)

    it("should show InfoMessage on failure", function()
      mock_dropbox_api.create_folder_code = 500

      DropBox:createFolder("/remote/path", "pass", "new_folder", nil)

      assert.are.equal(1, #mock_uimanager.shown_widgets)
      local widget = mock_uimanager.shown_widgets[1]
      assert.is_true(widget.is_info_message)
      assert.are.equal("Could not create folder:\nnew_folder", widget.text)
    end)
  end)

  describe("info", function()
    it("should show InfoMessage with account info", function()
      DropBox:info("token")

      assert.are.equal(1, #mock_uimanager.shown_widgets)
      local widget = mock_uimanager.shown_widgets[1]
      assert.is_true(widget.is_info_message)
      assert.are.equal(
        "Type: basic\nName: User\nEmail: user@test.com\nCountry: US\nSpace total: 1000 bytes\nSpace used: 500 bytes",
        widget.text
      )
    end)
  end)
end)
