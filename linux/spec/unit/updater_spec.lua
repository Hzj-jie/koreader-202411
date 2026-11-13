describe("Updater module", function()
  local Updater
  local Device, FfiUtil, NetworkMgr, UIManager, Util
  local http, lfs, socketutil, gettext, T
  local orig_currentdir, temp_root, install_dir

  local function writeFile(path, content)
    local f = assert(io.open(path, "w"))
    f:write(content)
    f:close()
  end

  local function exists(path)
    return lfs.attributes(path) ~= nil
  end

  setup(function()
    require("commonrequire")
    Device = require("device")
    FfiUtil = require("ffi/util")
    NetworkMgr = require("ui/network/manager")
    UIManager = require("ui/uimanager")
    Util = require("util")
    http = require("socket.http")
    lfs = require("libs/libkoreader-lfs")
    socketutil = require("socketutil")
    gettext = require("gettext")
    T = FfiUtil.template
    orig_currentdir = lfs.currentdir
  end)

  before_each(function()
    temp_root = "/tmp/koreader_updater_spec_" .. tostring(FfiUtil.getpid())
    FfiUtil.purgeDir(temp_root)
    assert(lfs.mkdir(temp_root))
    install_dir = temp_root .. "/koreader"
    assert(lfs.mkdir(install_dir))
    lfs.currentdir = function()
      return install_dir
    end
    package.loaded["ui/updater"] = nil
    Updater = require("ui/updater")
  end)

  after_each(function()
    lfs.currentdir = orig_currentdir
    if temp_root then
      FfiUtil.purgeDir(temp_root)
    end
    socketutil:reset_timeout()
  end)

  describe("getPackageName", function()
    it("parses pw2, legacy, and kobo packages from ./ko_update.sh", function()
      for _, pkg in ipairs({ "pw2", "legacy", "kobo" }) do
        writeFile(
          install_dir .. "/ko_update.sh",
          "#!/bin/sh\nPACKAGE=\"" .. pkg .. "\"\necho ok\n"
        )
        assert.are.equal(pkg, Updater:getPackageName())
      end
    end)

    it("returns nil when ./ko_update.sh is missing or lacks PACKAGE", function()
      assert.is_nil(Updater:getPackageName())
      writeFile(install_dir .. "/ko_update.sh", "#!/bin/sh\necho no package\n")
      assert.is_nil(Updater:getPackageName())
    end)
  end)

  describe("update workflow", function()
    local stubs
    local shown_widgets
    local mock_online
    local mock_free_bytes
    local mock_http_fn
    local mock_unpack_ok, mock_unpack_err

    local function captureShown(widget)
      table.insert(shown_widgets, widget)
    end

    before_each(function()
      stubs = {}
      shown_widgets = {}
      mock_online = true
      mock_free_bytes = 512 * 1024 * 1024
      mock_unpack_ok = true
      mock_unpack_err = nil
      mock_http_fn = function(req)
        req.sink("tarball-bytes")
        req.sink(nil)
        return 1, 200, {}
      end

      writeFile(install_dir .. "/ko_update.sh", '#!/bin/sh\nPACKAGE="pw2"\n')

      table.insert(
        stubs,
        stub(Util, "isMonkeyTest", function()
          return false
        end)
      )
      table.insert(stubs, stub(NetworkMgr, "runWhenOnline"))
      table.insert(
        stubs,
        stub(NetworkMgr, "runWhenConnected", function(_, cb)
          cb()
        end)
      )
      table.insert(
        stubs,
        stub(NetworkMgr, "isOnline", function()
          return mock_online
        end)
      )
      table.insert(
        stubs,
        stub(UIManager, "show", function(_, widget)
          captureShown(widget)
        end)
      )
      table.insert(stubs, stub(UIManager, "close"))
      table.insert(
        stubs,
        stub(UIManager, "nextTick", function(_, cb)
          cb()
        end)
      )
      table.insert(
        stubs,
        stub(FfiUtil, "df", function()
          return 1024 * 1024 * 1024, mock_free_bytes
        end)
      )
      table.insert(stubs, stub(socketutil, "set_timeout"))
      table.insert(stubs, stub(socketutil, "reset_timeout"))
      table.insert(
        stubs,
        stub(http, "request", function(req)
          return mock_http_fn(req)
        end)
      )
      table.insert(
        stubs,
        stub(Device, "unpackArchive", function(_, archive, extract_to)
          if not mock_unpack_ok then
            return false, mock_unpack_err
          end
          assert.is_true(exists(archive))
          writeFile(extract_to .. "/ko_update.sh", '#!/bin/sh\nPACKAGE="pw2"\n')
          return true
        end)
      )
      table.insert(stubs, stub(Device, "install"))
    end)

    after_each(function()
      for i = #stubs, 1, -1 do
        stubs[i]:revert()
      end
    end)

    it("does nothing during monkey tests", function()
      stubs[1]:revert()
      stubs[1] = stub(Util, "isMonkeyTest", function()
        return true
      end)

      Updater:update()
      assert.stub(NetworkMgr.runWhenConnected).was_not_called()
      assert.are.equal(0, #shown_widgets)
    end)

    it("shows unsupported message when ko_update.sh is missing", function()
      os.remove(install_dir .. "/ko_update.sh")

      Updater:update()
      assert.stub(NetworkMgr.runWhenConnected).was_not_called()
      assert.are.equal(1, #shown_widgets)
      assert.are.equal(
        gettext("Update is not supported on this device."),
        shown_widgets[1].text
      )
    end)

    it(
      "uses runWhenConnected and shows confirmation without offline warning when online",
      function()
        mock_online = true
        Updater:update()

        assert.stub(NetworkMgr.runWhenOnline).was_not_called()
        assert.stub(NetworkMgr.runWhenConnected).was_called(1)
        assert.are.equal(1, #shown_widgets)
        local confirm = shown_widgets[1]
        assert.are.equal(
          gettext.pgettext("Application update | Button", "Update"),
          confirm.ok_text
        )
        assert.are.equal(
          T(gettext("Download and install the latest update (%1)?"), "pw2"),
          confirm.text
        )
      end
    )

    it(
      "warns about offline network state inside confirmation when offline",
      function()
        mock_online = false
        Updater:update()

        assert.stub(NetworkMgr.runWhenConnected).was_called(1)
        assert.are.equal(1, #shown_widgets)
        local confirm = shown_widgets[1]
        assert.are.equal(
          gettext(
            "Network connection is offline or unstable. The update download may fail."
          )
            .. "\n\n"
            .. T(
              gettext("Download and install the latest update (%1)?"),
              "pw2"
            ),
          confirm.text
        )
      end
    )

    it(
      "aborts before download when free disk space is insufficient",
      function()
        mock_free_bytes = 64 * 1024 * 1024
        Updater:update()
        shown_widgets[1].ok_callback()

        assert.stub(http.request).was_not_called()
        assert.stub(Device.unpackArchive).was_not_called()
        assert.stub(Device.install).was_not_called()
        assert.are.equal(2, #shown_widgets)
        assert.are.equal(
          gettext("Not enough free space to download and unpack the update."),
          shown_widgets[2].text
        )
        assert.is_false(exists(install_dir .. ".update.tar.gz.part"))
        assert.is_false(exists(install_dir .. ".update.tar.gz"))
      end
    )

    it(
      "cleans up partial archive and reports error on HTTP failure",
      function()
        mock_http_fn = function(req)
          req.sink("partial")
          return nil, "timeout"
        end

        Updater:update()
        shown_widgets[1].ok_callback()

        assert.stub(socketutil.reset_timeout).was_called(1)
        assert.stub(UIManager.close).was_called(1)
        assert.stub(Device.unpackArchive).was_not_called()
        assert.stub(Device.install).was_not_called()
        assert.is_false(exists(install_dir .. ".update.tar.gz.part"))
        assert.is_false(exists(install_dir .. ".update.tar.gz"))
        assert.are.equal(
          T(gettext("Failed to download update:\n%1"), "timeout"),
          shown_widgets[#shown_widgets].text
        )
      end
    )

    it("rejects insecure HTTPS to HTTP downgrade redirects", function()
      mock_http_fn = function(req)
        req.sink("redirected")
        req.sink(nil)
        return 1, 302, { location = "http://insecure.example/pw2.tar.gz" }
      end

      Updater:update()
      shown_widgets[1].ok_callback()

      assert.stub(socketutil.reset_timeout).was_called(1)
      assert.stub(Device.unpackArchive).was_not_called()
      assert.is_false(exists(install_dir .. ".update.tar.gz.part"))
      assert.is_false(exists(install_dir .. ".update.tar.gz"))
      assert.are.equal(
        T(gettext("Failed to download update:\n%1"), "302"),
        shown_widgets[#shown_widgets].text
      )
    end)

    it("cleans up on non-200 HTTP responses", function()
      mock_http_fn = function(req)
        req.sink("not found")
        req.sink(nil)
        return 1, 404, {}
      end

      Updater:update()
      shown_widgets[1].ok_callback()

      assert.stub(Device.unpackArchive).was_not_called()
      assert.is_false(exists(install_dir .. ".update.tar.gz.part"))
      assert.is_false(exists(install_dir .. ".update.tar.gz"))
      assert.are.equal(
        T(gettext("Failed to download update:\n%1"), 404),
        shown_widgets[#shown_widgets].text
      )
    end)

    it(
      "cleans up downloaded archive and temp directory when unpack fails",
      function()
        mock_unpack_ok = false
        mock_unpack_err = "corrupt archive"

        Updater:update()
        shown_widgets[1].ok_callback()

        assert.stub(Device.unpackArchive).was_called(1)
        assert.stub(Device.install).was_not_called()
        assert.is_false(exists(install_dir .. ".update.tar.gz"))
        assert.is_false(exists(install_dir .. ".update.tmp"))
        assert.is_false(exists(install_dir .. ".update"))
        assert.are.equal(
          T(gettext("Failed to unpack update:\n%1"), "corrupt archive"),
          shown_widgets[#shown_widgets].text
        )
      end
    )

    it(
      "stages update cleanly into sibling .update and calls Device:install on success",
      function()
        -- Pre-populate stale update artifacts to verify pre-run cleanup
        writeFile(install_dir .. ".update.tar.gz.part", "stale")
        assert(lfs.mkdir(install_dir .. ".update"))
        writeFile(install_dir .. ".update/stale_file", "old")

        local captured_req
        mock_http_fn = function(req)
          captured_req = req
          req.sink("valid-archive")
          req.sink(nil)
          return 1, 200, {}
        end

        Updater:update()
        shown_widgets[1].ok_callback()

        assert.is_table(captured_req)
        assert.are.equal(
          "https://github.com/Hzj-jie/koreader-202411/releases/latest/download/pw2.tar.gz",
          captured_req.url
        )
        assert.are.equal("identity", captured_req.headers["Accept-Encoding"])
        assert
          .stub(socketutil.set_timeout)
          .was_called_with(socketutil, socketutil.FILE_BLOCK_TIMEOUT, -1)
        assert.stub(socketutil.reset_timeout).was_called(1)
        assert.stub(Device.unpackArchive).was_called_with(
          Device,
          install_dir .. ".update.tar.gz",
          install_dir .. ".update.tmp"
        )
        assert.stub(Device.install).was_called(1)
        assert.is_false(exists(install_dir .. ".update.tar.gz.part"))
        assert.is_false(exists(install_dir .. ".update.tar.gz"))
        assert.is_false(exists(install_dir .. ".update.tmp"))
        assert.is_false(exists(install_dir .. ".update/stale_file"))
        assert.is_true(exists(install_dir .. ".update/ko_update.sh"))
      end
    )
  end)
end)
