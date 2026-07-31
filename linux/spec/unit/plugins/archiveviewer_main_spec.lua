describe("ArchiveViewer main plugin module", function()
  local ArchiveViewer, DocumentRegistry

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    DocumentRegistry = require("document/documentregistry")
    ArchiveViewer = require("plugins/archiveviewer.koplugin/main")
  end)

  it("should initialize ArchiveViewer plugin and register aux provider", function()
    local instance = ArchiveViewer:new()
    assert.is_table(instance)
    assert.are.equal("archiveviewer", instance.name)
  end)

  it("should check supported file types", function()
    local instance = ArchiveViewer:new()
    assert.truthy(instance:isFileTypeSupported("test.cbz"))
    assert.truthy(instance:isFileTypeSupported("test.epub"))
    assert.truthy(instance:isFileTypeSupported("test.zip"))
    assert.falsy(instance:isFileTypeSupported("test.txt"))
  end)
end)
