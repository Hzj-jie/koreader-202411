describe("CloudStorage", function()
  local CloudStorage
  local mock_menu
  local mock_luasettings
  local mock_settings_obj
  local mock_dropbox
  local mock_ftp
  local mock_webdav
  local mock_uimanager
  local mock_network_mgr
  local mock_lfs
  local mock_ffi_util
  local mock_document_registry
  local mock_reader_ui
  local mock_button_dialog
  local mock_confirm_box
  local mock_info_message
  local mock_input_dialog

  setup(function()
    require("commonrequire")
  end)

  before_each(function()
    _G.G_reader_settings = {
      isTrue = function(self, _key)
        return false
      end,
    }
    _G.G_named_settings = {
      lastdir = function()
        return "/default/download/dir"
      end,
    }

    mock_settings_obj = {
      cs_servers = {},
      download_dir = nil,
      readTableRef = function(self, key)
        if key == "cs_servers" then
          return self.cs_servers
        end
        return {}
      end,
      read = function(self, key)
        if key == "download_dir" then
          return self.download_dir
        end
        return nil
      end,
      save = function(self, key, val)
        if key == "cs_servers" then
          self.cs_servers = val
        elseif key == "download_dir" then
          self.download_dir = val
        end
      end,
      flush = function(self)
        self.flushed = true
      end,
    }

    mock_luasettings = {
      open = function(self, _path)
        return mock_settings_obj
      end,
    }
    package.loaded["luasettings"] = mock_luasettings

    package.loaded["datastorage"] = {
      getSettingsDir = function()
        return "/settings"
      end,
    }

    mock_menu = {
      extend = function(self, obj)
        obj = obj or {}
        setmetatable(obj, { __index = self })
        return obj
      end,
      new = function(self, obj)
        obj = obj or {}
        setmetatable(obj, { __index = self })
        obj:init()
        return obj
      end,
      init = function(self)
        self.paths = {}
      end,
      switchItemTable = function(self, url, tbl)
        self.switched_url = url
        self.switched_tbl = tbl
      end,
      setTitleBarLeftIcon = function(self, icon)
        self.left_icon = icon
      end,
      onExit = function(self)
        self.on_exit_called = true
      end,
    }
    package.loaded["ui/widget/menu"] = mock_menu

    mock_dropbox = {
      get_token_response = "mock_token",
      run_response = { "db_file1", "db_file2" },
      show_files_response = {},
      getAccessToken = function(self, _pass, _address)
        return self.get_token_response
      end,
      run = function(self, _url, _pass, _choose_folder_mode)
        return self.run_response
      end,
      downloadFile = function(self, _item, _pass, _path, callback_close)
        self.download_called = true
        if callback_close then
          callback_close()
        end
      end,
      showFiles = function(self, _folder, _pass)
        return self.show_files_response
      end,
      downloadFileNoUI = function(self, _url, _pass, _path)
        return true
      end,
      uploadFile = function(self, _url, _pass, _path, callback_close)
        self.upload_called = true
        if callback_close then
          callback_close()
        end
      end,
      createFolder = function(self, _url, _pass, _name, callback_close)
        self.create_folder_called = true
        if callback_close then
          callback_close()
        end
      end,
      info = function(self, _pass)
        self.info_called = true
      end,
    }
    package.loaded["apps/cloudstorage/dropbox"] = mock_dropbox

    mock_ftp = {
      run_response = { "ftp_file1", "ftp_file2" },
      run = function(self, _address, _user, _pass, _url)
        return self.run_response
      end,
      downloadFile = function(self, _item, _address, _user, _pass, _path, callback_close)
        self.download_called = true
        if callback_close then
          callback_close()
        end
      end,
      info = function(self, _item)
        self.info_called = true
      end,
      config = function(self, _item, callback)
        self.config_callback = callback
      end,
    }
    package.loaded["apps/cloudstorage/ftp"] = mock_ftp

    mock_webdav = {
      run_response = { "wd_file1", "wd_file2" },
      run = function(self, _address, _user, _pass, _path, _folder_mode)
        return self.run_response
      end,
      downloadFile = function(self, _item, _address, _user, _pass, _path, callback_close)
        self.download_called = true
        if callback_close then
          callback_close()
        end
      end,
      uploadFile = function(self, _url, _address, _user, _pass, _path, callback_close)
        self.upload_called = true
        if callback_close then
          callback_close()
        end
      end,
      createFolder = function(self, _url, _address, _user, _pass, _name, callback_close)
        self.create_folder_called = true
        if callback_close then
          callback_close()
        end
      end,
      info = function(self, _item)
        self.info_called = true
      end,
      config = function(self, _item, callback)
        self.config_callback = callback
      end,
    }
    package.loaded["apps/cloudstorage/webdav"] = mock_webdav

    mock_uimanager = {
      shown_widgets = {},
      scheduled_funcs = {},
      show = function(self, widget)
        table.insert(self.shown_widgets, widget)
      end,
      close = function(self, widget)
        for i, w in ipairs(self.shown_widgets) do
          if w == widget then
            table.remove(self.shown_widgets, i)
            break
          end
        end
      end,
      scheduleIn = function(self, _delay, func)
        table.insert(self.scheduled_funcs, func)
      end,
      nextTick = function(self, func)
        func()
      end,
      tickAfterNext = function(self, func)
        func()
      end,
    }
    package.loaded["ui/uimanager"] = mock_uimanager

    mock_network_mgr = {
      runWhenOnline = function(self, cb)
        cb()
      end,
      runWhenConnected = function(self, cb)
        cb()
      end,
    }
    package.loaded["ui/network/manager"] = mock_network_mgr

    mock_lfs = {
      files = {},
      dirs = {},
      attributes = function(path, request)
        if mock_lfs.files[path] then
          if request == "size" then
            return mock_lfs.files[path].size or 0
          end
          return mock_lfs.files[path]
        end
        return nil
      end,
      dir = function(path)
        local files = mock_lfs.dirs[path] or {}
        local i = 0
        return function()
          i = i + 1
          local f = files[i]
          if f then
            return f
          end
        end
      end,
    }
    package.loaded["libs/libkoreader-lfs"] = mock_lfs

    mock_ffi_util = {
      template = function(tmpl, ...)
        local args = { ... }
        return tmpl:gsub("%%(%d+)", function(n)
          return tostring(args[tonumber(n)])
        end)
      end,
      orderedPairs = function(t)
        local keys = { "dropbox", "ftp", "webdav" }
        local i = 0
        return function()
          i = i + 1
          local k = keys[i]
          if k then
            return k, t[k]
          end
        end
      end,
    }
    package.loaded["ffi/util"] = mock_ffi_util

    mock_document_registry = {
      has_provider = true,
      hasProvider = function(self, _filename)
        return mock_document_registry.has_provider
      end,
    }
    package.loaded["document/documentregistry"] = mock_document_registry

    mock_reader_ui = {
      showReader = function(self, _path) end,
    }
    package.loaded["apps/reader/readerui"] = mock_reader_ui

    mock_button_dialog = {
      new = function(self, args)
        return {
          is_button_dialog = true,
          title = args.title,
          buttons = args.buttons,
          setTitle = function(s, t)
            s.title = t
          end,
        }
      end,
    }
    package.loaded["ui/widget/buttondialog"] = mock_button_dialog

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

    mock_input_dialog = {
      new = function(self, args)
        return {
          is_input_dialog = true,
          title = args.title,
          input = args.input,
          buttons = args.buttons,
          getInputText = function(s)
            return s.input_text or ""
          end,
          getInputValue = function(s)
            return s.input_value or ""
          end,
          addWidget = function(s, w)
            s.widget = w
          end,
        }
      end,
    }
    package.loaded["ui/widget/inputdialog"] = mock_input_dialog

    package.loaded["ui/widget/pathchooser"] = {
      new = function(self, args)
        return {
          is_path_chooser = true,
          onConfirm = args.onConfirm,
        }
      end,
    }

    package.loaded["ui/widget/checkbutton"] = {
      new = function(self, args)
        return {
          is_check_button = true,
          text = args.text,
          checked = args.checked,
        }
      end,
    }

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

    local mock_gettext = setmetatable({
      ngettext = function(singular, plural, n)
        return n == 1 and singular or plural
      end,
    }, {
      __call = function(_, text)
        return text
      end,
    })
    package.loaded["gettext"] = mock_gettext

    package.loaded["logger"] = {
      dbg = function() end,
      err = function() end,
    }

    CloudStorage = require("apps/cloudstorage/cloudstorage")
  end)

  after_each(function()
    package.loaded["apps/cloudstorage/cloudstorage"] = nil
    package.loaded["luasettings"] = nil
    package.loaded["datastorage"] = nil
    package.loaded["ui/widget/menu"] = nil
    package.loaded["apps/cloudstorage/dropbox"] = nil
    package.loaded["apps/cloudstorage/ftp"] = nil
    package.loaded["apps/cloudstorage/webdav"] = nil
    package.loaded["ui/uimanager"] = nil
    package.loaded["ui/network/manager"] = nil
    package.loaded["libs/libkoreader-lfs"] = nil
    package.loaded["ffi/util"] = nil
    package.loaded["document/documentregistry"] = nil
    package.loaded["apps/reader/readerui"] = nil
    package.loaded["ui/widget/buttondialog"] = nil
    package.loaded["ui/widget/confirmbox"] = nil
    package.loaded["ui/widget/infomessage"] = nil
    package.loaded["ui/widget/inputdialog"] = nil
    package.loaded["ui/widget/pathchooser"] = nil
    package.loaded["ui/widget/checkbutton"] = nil
    package.loaded["ui/bidi"] = nil
    package.loaded["gettext"] = nil
    package.loaded["logger"] = nil
    _G.G_reader_settings = nil
    _G.G_named_settings = nil
  end)

  describe("init", function()
    it("should load settings and generate empty item table if no servers added", function()
      mock_settings_obj.cs_servers = {}
      local cs = CloudStorage:new()
      assert.are.same({}, cs.item_table)
    end)

    it("should generate item table with added servers", function()
      mock_settings_obj.cs_servers = {
        {
          name = "My FTP",
          type = "ftp",
          address = "ftp://example.com",
          username = "user",
          password = "pass",
          url = "/ftp_url",
        },
      }
      local cs = CloudStorage:new()
      assert.are.equal(1, #cs.item_table)
      local item = cs.item_table[1]
      assert.are.equal("My FTP", item.text)
      assert.are.equal("FTP", item.mandatory)
      assert.are.equal("ftp://example.com", item.address)
      assert.are.equal("user", item.username)
      assert.are.equal("pass", item.password)
      assert.are.equal("ftp", item.type)
      assert.are.equal("/ftp_url", item.url)
    end)
  end)

  describe("selectCloudType", function()
    it("should show ButtonDialog with cloud types", function()
      local cs = CloudStorage:new()
      cs:selectCloudType()

      assert.are.equal(1, #mock_uimanager.shown_widgets)
      local dialog = mock_uimanager.shown_widgets[1]
      assert.is_true(dialog.is_button_dialog)
      assert.are.equal("Add new cloud storage", dialog.title)
      assert.are.equal(3, #dialog.buttons)
      assert.are.equal("Dropbox", dialog.buttons[1][1].text)
      assert.are.equal("FTP", dialog.buttons[2][1].text)
      assert.are.equal("WebDAV", dialog.buttons[3][1].text)
    end)
  end)

  describe("openCloudServer", function()
    it("should open FTP server and switch item table", function()
      local cs = CloudStorage:new()
      cs.type = "ftp"
      cs.address = "ftp://example.com"
      cs.username = "user"
      cs.password = "pass"

      local success = cs:openCloudServer("/ftp_url")
      assert.is_true(success)
      assert.are.equal("/ftp_url", cs.switched_url)
      assert.are.same({ "ftp_file1", "ftp_file2" }, cs.switched_tbl)
    end)

    it("should open WebDAV server and switch item table", function()
      local cs = CloudStorage:new()
      cs.type = "webdav"
      cs.address = "http://example.com"
      cs.username = "user"
      cs.password = "pass"

      local success = cs:openCloudServer("/wd_url")
      assert.is_true(success)
      assert.are.equal("/wd_url", cs.switched_url)
      assert.are.same({ "wd_file1", "wd_file2" }, cs.switched_tbl)
    end)

    it("should open Dropbox server and switch item table", function()
      local cs = CloudStorage:new()
      cs.type = "dropbox"
      cs.password = "pass"

      local success = cs:openCloudServer("/db_url")
      assert.is_true(success)
      assert.are.equal("/db_url", cs.switched_url)
      assert.are.same({ "db_file1", "db_file2" }, cs.switched_tbl)
    end)

    it("should show InfoMessage on failure to fetch list", function()
      mock_ftp.run_response = nil
      local cs = CloudStorage:new()
      cs.type = "ftp"
      cs.address = "ftp://example.com"
      cs.username = "user"
      cs.password = "pass"

      local success = cs:openCloudServer("/ftp_url")
      assert.is_false(success)
      assert.are.equal(1, #mock_uimanager.shown_widgets)
      local widget = mock_uimanager.shown_widgets[1]
      assert.is_true(widget.is_info_message)
      assert.are.equal(
        "Cannot fetch list of folder contents\nPlease check your configuration or network connection.",
        widget.text
      )
    end)
  end)

  describe("downloadFile", function()
    it("should show download dialog and trigger FTP download", function()
      local cs = CloudStorage:new()
      cs.type = "ftp"
      cs.address = "ftp://example.com"
      cs.username = "user"
      cs.password = "pass"

      mock_lfs.files["/default/download/dir/file.epub"] = nil

      cs:downloadFile({ text = "file.epub", url = "/remote/file.epub" })

      assert.are.equal(1, #mock_uimanager.shown_widgets)
      local dialog = mock_uimanager.shown_widgets[1]
      assert.is_true(dialog.is_button_dialog)

      local download_btn
      for _, row in ipairs(dialog.buttons) do
        for _, btn in ipairs(row) do
          if btn.text == "Download" then
            download_btn = btn
            break
          end
        end
      end
      assert.truthy(download_btn)

      download_btn.callback()

      assert.are.equal(1, #mock_uimanager.shown_widgets)
      local info = mock_uimanager.shown_widgets[1]
      assert.is_true(info.is_info_message)
      assert.are.equal("Downloading. This might take a moment.", info.text)

      assert.are.equal(1, #mock_uimanager.scheduled_funcs)
      mock_uimanager.scheduled_funcs[1]()

      assert.is_true(mock_ftp.download_called)
    end)

    it("should show ConfirmBox if file already exists", function()
      local cs = CloudStorage:new()
      cs.type = "ftp"
      cs.address = "ftp://example.com"
      cs.username = "user"
      cs.password = "pass"

      mock_lfs.files["/default/download/dir/file.epub"] = { mode = "file", size = 100 }

      cs:downloadFile({ text = "file.epub", url = "/remote/file.epub" })

      local dialog = mock_uimanager.shown_widgets[1]
      local download_btn
      for _, row in ipairs(dialog.buttons) do
        for _, btn in ipairs(row) do
          if btn.text == "Download" then
            download_btn = btn
            break
          end
        end
      end
      download_btn.callback()

      assert.are.equal(1, #mock_uimanager.shown_widgets)
      local confirm = mock_uimanager.shown_widgets[1]
      assert.is_true(confirm.is_confirm_box)
      assert.are.equal("File already exists. Would you like to overwrite it?", confirm.text)

      confirm.ok_callback()

      assert.are.equal(1, #mock_uimanager.scheduled_funcs)
      mock_uimanager.scheduled_funcs[1]()

      assert.is_true(mock_ftp.download_called)
    end)
  end)
end)
