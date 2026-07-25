describe("DownloadMgr module", function()
  local DownloadMgr

  setup(function()
    require("commonrequire")
    DownloadMgr = require("ui/downloadmgr")
  end)

  it("should initialize DownloadMgr instance", function()
    local mgr = DownloadMgr:new()
    assert.is_table(mgr)
  end)
end)
