describe("EpubDownloadBackend module", function()
  local EpubDownloadBackend

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    package.path = "plugins/newsdownloader.koplugin/?.lua;" .. package.path
    EpubDownloadBackend = require("plugins/newsdownloader.koplugin/epubdownloadbackend")
  end)

  describe("Initialization & Defaults", function()
    it("should expose dismiss error code and default properties", function()
      assert.is_table(EpubDownloadBackend)
      assert.are.equal(EpubDownloadBackend.dismissed_error_code, "Interrupted by user")
    end)
  end)
end)
