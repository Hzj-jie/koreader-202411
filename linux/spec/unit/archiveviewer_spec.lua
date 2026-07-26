describe("ArchiveViewer plugin", function()
  local ArchiveViewer

  setup(function()
    require("commonrequire")
    ArchiveViewer = require("plugins/archiveviewer.koplugin/main")
  end)

  it("should initialize ArchiveViewer plugin class", function()
    assert.is_table(ArchiveViewer)
  end)
end)
