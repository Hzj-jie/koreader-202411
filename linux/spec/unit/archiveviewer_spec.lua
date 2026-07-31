describe("ArchiveViewer plugin", function()
  local ArchiveViewer

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    ArchiveViewer = require("plugins/archiveviewer.koplugin/main")
  end)

  it("should initialize ArchiveViewer plugin class", function()
    assert.is_table(ArchiveViewer)
    local instance = ArchiveViewer:new()
    assert.is_table(instance)
  end)

  it("should check supported file types correctly", function()
    local instance = ArchiveViewer:new()
    assert.is_true(instance:isFileTypeSupported("test.cbz"))
    assert.is_true(instance:isFileTypeSupported("test.epub"))
    assert.is_true(instance:isFileTypeSupported("test.zip"))
    assert.is_true(instance:isFileTypeSupported("path/to/archive.ZIP"))
    assert.is_false(instance:isFileTypeSupported("test.pdf"))
    assert.is_false(instance:isFileTypeSupported("test.txt"))
  end)

  it("should build item tables for root and subfolders", function()
    local instance = ArchiveViewer:new()
    instance.list_table = {
      ["/"] = {
        ["file1.txt"] = "1024",
        ["folder1"] = false,
      },
      ["folder1/"] = {
        ["file2.png"] = "2048",
      },
    }

    local root_items = instance:getItemTable("")
    assert.is_table(root_items)
    assert.are.equal(2, #root_items)

    local folder_items = instance:getItemTable("folder1/")
    assert.is_table(folder_items)
    -- Should include parent folder navigation entry (../)
    assert.are.equal(2, #folder_items)
    assert.is_number(folder_items[1].text:find("%.%./"))
  end)

  it("should handle zip list table parsing gracefully", function()
    local instance = ArchiveViewer:new()
    instance.arc_file = "/tmp/non_existent_archive_test.zip"
    instance.list_table = {}
    instance:getZipListTable()
    assert.is_table(instance.list_table)
  end)
end)
