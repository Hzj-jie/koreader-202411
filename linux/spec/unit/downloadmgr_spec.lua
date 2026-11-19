describe("DownloadMgr module", function()
  local DownloadMgr
  local UIManager
  local ffiutil
  local lfs = require("libs/libkoreader-lfs")
  local temp_dir

  setup(function()
    require("commonrequire")
    DownloadMgr = require("ui/downloadmgr")
    UIManager = require("ui/uimanager")
    ffiutil = require("ffi/util")
    local tmp = os.tmpname()
    os.remove(tmp)
    temp_dir = tmp .. "_downloadmgr"
    lfs.mkdir(temp_dir)
  end)

  teardown(function()
    ffiutil.purgeDir(temp_dir)
  end)

  it("should initialize DownloadMgr instance", function()
    local mgr = DownloadMgr:new()
    assert.is_table(mgr)
  end)

  it("should handle chooseDir with explicit directory", function()
    local shown_widget = nil
    local orig_show = UIManager.show
    UIManager.show = function(self, widget)
      shown_widget = widget
    end

    local confirmed_path = nil
    local mgr = DownloadMgr:new({
      onConfirm = function(p)
        confirmed_path = p
      end,
    })

    mgr:chooseDir(temp_dir)
    assert.truthy(shown_widget)
    assert.are.equal(temp_dir, shown_widget.path)

    local chosen_dir = temp_dir .. "/chosen_dir"
    shown_widget.onConfirm(chosen_dir)
    assert.are.equal(chosen_dir, confirmed_path)

    UIManager.show = orig_show
  end)

  it(
    "should handle chooseDir with settings download_dir and fallback",
    function()
      local shown_widget = nil
      local orig_show = UIManager.show
      UIManager.show = function(self, widget)
        shown_widget = widget
      end

      G_reader_settings:save("download_dir", temp_dir)
      local mgr = DownloadMgr:new()
      mgr:chooseDir()
      assert.truthy(shown_widget)
      assert.are.equal(temp_dir, shown_widget.path)

      local orig_lastdir = G_named_settings.lastdir
      G_reader_settings:save("download_dir", nil)
      G_named_settings.lastdir = function()
        return temp_dir
      end
      mgr:chooseDir()
      assert.truthy(shown_widget)
      assert.are.equal(temp_dir, shown_widget.path)

      G_named_settings.lastdir = orig_lastdir
      UIManager.show = orig_show
    end
  )

  it("should handle chooseCloudDir", function()
    local shown_widget = nil
    local orig_show = UIManager.show
    UIManager.show = function(self, widget)
      shown_widget = widget
    end

    local CloudStorage = require("apps/cloudstorage/cloudstorage")
    local orig_init = CloudStorage.init
    CloudStorage.init = function(self) end

    local confirmed_path = nil
    local mgr = DownloadMgr:new({
      item = { name = "cloud_item" },
      onConfirm = function(p)
        confirmed_path = p
      end,
    })

    mgr:chooseCloudDir()
    assert.truthy(shown_widget)
    shown_widget.onConfirm("/cloud/path")
    assert.are.equal("/cloud/path", confirmed_path)

    CloudStorage.init = orig_init
    UIManager.show = orig_show
  end)

  it("should pass require_writable=true to PathChooser in chooseDir", function()
    local shown_widget = nil
    local orig_show = UIManager.show
    UIManager.show = function(_, widget)
      shown_widget = widget
    end

    local mgr = DownloadMgr:new()
    mgr:chooseDir(temp_dir)
    assert.truthy(shown_widget)
    assert.is_true(shown_widget.require_writable)

    UIManager.show = orig_show
  end)

  it("should pre-flight checkDownloadDir and notify when read-only", function()
    local util = require("util")
    local orig_isDirRW = util.isDirRW
    local shown_notifications = {}
    local orig_show = UIManager.show
    UIManager.show = function(_, widget)
      table.insert(shown_notifications, widget)
    end

    local rw_dir = temp_dir .. "/rw_dir"
    local ro_dir = temp_dir .. "/ro_dir"
    util.isDirRW = function(dir)
      return dir == rw_dir
    end

    assert.is_true(DownloadMgr.checkDownloadDir(rw_dir))
    assert.are.equal(0, #shown_notifications)

    assert.is_false(DownloadMgr.checkDownloadDir(ro_dir))
    assert.are.equal(1, #shown_notifications)
    assert.is_not_nil(shown_notifications[1].text:find("read%-only"))

    util.isDirRW = orig_isDirRW
    UIManager.show = orig_show
  end)

  it(
    "should fallback to G_reader_settings download_dir when no directory is provided",
    function()
      local util = require("util")
      local orig_isDirRW = util.isDirRW

      util.isDirRW = function(dir)
        return dir == "/custom/download_path"
      end

      G_reader_settings:save("download_dir", "/custom/download_path")
      assert.is_true(DownloadMgr.checkDownloadDir())

      G_reader_settings:save("download_dir", "/custom/ro_path")
      assert.is_false(DownloadMgr.checkDownloadDir())

      G_reader_settings:delete("download_dir")
      util.isDirRW = orig_isDirRW
    end
  )

  it(
    "should fallback to G_named_settings.lastdir when download_dir setting is nil",
    function()
      local util = require("util")
      local orig_isDirRW = util.isDirRW
      local orig_lastdir = G_named_settings.lastdir

      G_reader_settings:delete("download_dir")
      G_named_settings.lastdir = function()
        return "/custom/last_dir"
      end

      util.isDirRW = function(dir)
        return dir == "/custom/last_dir"
      end

      assert.is_true(DownloadMgr.checkDownloadDir())

      G_named_settings.lastdir = orig_lastdir
      util.isDirRW = orig_isDirRW
    end
  )
end)
