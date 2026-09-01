describe("DownloadMgr module", function()
  local DownloadMgr
  local UIManager
  local lfs = require("libs/libkoreader-lfs")

  setup(function()
    require("commonrequire")
    DownloadMgr = require("ui/downloadmgr")
    UIManager = require("ui/uimanager")
    lfs.mkdir("/tmp/test_dir")
  end)

  teardown(function()
    lfs.rmdir("/tmp/test_dir")
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

    mgr:chooseDir("/tmp/test_dir")
    assert.truthy(shown_widget)
    assert.are.equal("/tmp/test_dir", shown_widget.path)

    shown_widget.onConfirm("/tmp/chosen_dir")
    assert.are.equal("/tmp/chosen_dir", confirmed_path)

    UIManager.show = orig_show
  end)

  it("should handle chooseDir with settings download_dir and fallback", function()
    local shown_widget = nil
    local orig_show = UIManager.show
    UIManager.show = function(self, widget)
      shown_widget = widget
    end

    G_reader_settings:save("download_dir", "/tmp/test_dir")
    local mgr = DownloadMgr:new()
    mgr:chooseDir()
    assert.truthy(shown_widget)
    assert.are.equal("/tmp", shown_widget.path)

    local orig_lastdir = G_named_settings.lastdir
    G_reader_settings:save("download_dir", nil)
    G_named_settings.lastdir = function() return "/tmp/test_dir" end
    mgr:chooseDir()
    assert.truthy(shown_widget)
    assert.are.equal("/tmp/test_dir", shown_widget.path)

    G_named_settings.lastdir = orig_lastdir
    UIManager.show = orig_show
  end)

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
end)
