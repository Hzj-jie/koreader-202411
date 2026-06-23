describe("Ftp", function()
  local Ftp
  local mock_ftp_api
  local mock_uimanager
  local mock_document_registry
  local mock_reader_ui
  local mock_confirm_box
  local mock_info_message
  local mock_multi_input_dialog
  local mock_util
  local original_io_open
  local mock_io

  setup(function()
    require("commonrequire")
  end)

  before_each(function()
    _G.G_reader_settings = {
      isTrue = function(self, _key)
        return false
      end,
    }

    mock_io = {
      open_fail = false,
    }
    original_io_open = io.open
    -- luacheck: ignore 122
    io.open = function(_path, _mode)
      if mock_io.open_fail then
        return nil, "mocked open failure"
      end
      return {
        write = function(self, _data)
          return true
        end,
        close = function(self)
          return true
        end,
      }
    end

    mock_ftp_api = {
      ftp_get_response = "226 Transfer complete",
      generateUrl = function(self, address, user, pass)
        return "ftp://"
          .. user
          .. ":"
          .. pass
          .. "@"
          .. address:gsub("^ftp://", "")
      end,
      listFolder = function(self, _url, _path)
        return { "file1", "file2" }
      end,
      ftpGet = function(self, _url, _command, _sink)
        return self.ftp_get_response
      end,
    }
    package.loaded["apps/cloudstorage/ftpapi"] = mock_ftp_api

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
        return str -- simple passthrough for tests
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

    package.loaded["logger"] = {
      dbg = function() end,
    }

    package.loaded["ltn12"] = {
      sink = {
        file = function(_file)
          return "mock_sink"
        end,
      },
    }

    package.loaded["ui/event"] = {
      new = function(self, name, ...)
        return { name = name, ... }
      end,
    }

    Ftp = require("apps/cloudstorage/ftp")
  end)

  after_each(function()
    -- luacheck: ignore 122
    io.open = original_io_open
    package.loaded["apps/cloudstorage/ftp"] = nil
    package.loaded["apps/cloudstorage/ftpapi"] = nil
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
    package.loaded["ltn12"] = nil
    package.loaded["ui/event"] = nil
    _G.G_reader_settings = nil
  end)

  describe("run", function()
    it("should call FtpApi:listFolder with generated URL", function()
      local res = Ftp:run("ftp://example.com", "user", "pass", "/path")
      assert.are.same({ "file1", "file2" }, res)
    end)
  end)

  describe("downloadFile", function()
    it("should show InfoMessage if local file cannot be opened", function()
      mock_io.open_fail = true

      Ftp:downloadFile(
        { url = "/remote/file.epub" },
        "ftp://example.com",
        "user",
        "pass",
        "/local/path/file.epub",
        nil
      )

      assert.are.equal(1, #mock_uimanager.shown_widgets)
      local widget = mock_uimanager.shown_widgets[1]
      assert.is_true(widget.is_info_message)
      assert.are.equal(
        "Could not save file to /local/path/file.epub:\nmocked open failure",
        widget.text
      )
    end)

    it("should show ConfirmBox on success by default", function()
      local callback_called = false
      local callback_close = function()
        callback_called = true
      end

      Ftp:downloadFile(
        { url = "/remote/file.epub" },
        "ftp://example.com",
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

        Ftp:downloadFile(
          { url = "/remote/file.unsupported" },
          "ftp://example.com",
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

    it("should show InfoMessage on failure from ftpGet", function()
      mock_ftp_api.ftp_get_response = nil

      Ftp:downloadFile(
        { url = "/remote/file.epub" },
        "ftp://example.com",
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

  describe("info", function()
    it("should show InfoMessage with account info", function()
      Ftp:info({ text = "My FTP", address = "ftp://example.com" })

      assert.are.equal(1, #mock_uimanager.shown_widgets)
      local widget = mock_uimanager.shown_widgets[1]
      assert.is_true(widget.is_info_message)
      assert.are.equal(
        "Type: FTP\nName: My FTP\nAddress: ftp://example.com",
        widget.text
      )
    end)
  end)
end)
