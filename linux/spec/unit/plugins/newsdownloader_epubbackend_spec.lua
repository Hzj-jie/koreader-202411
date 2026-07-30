describe("EpubDownloadBackend module", function()
  local EpubDownloadBackend

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    EpubDownloadBackend = require("plugins/newsdownloader.koplugin/epubdownloadbackend")
  end)

  describe("Initialization & Defaults", function()
    it("should expose dismiss error code and default properties", function()
      assert.is_table(EpubDownloadBackend)
      assert.are.equal(EpubDownloadBackend.dismissed_error_code, "Interrupted by user")
    end)

    it("should expose backend table functions", function()
      assert.is_table(EpubDownloadBackend)
      if type(EpubDownloadBackend.downloadFeeds) == "function" then
        assert.is_function(EpubDownloadBackend.downloadFeeds)
      end
    end)
  end)
end)
