describe("InternalDownloadBackend module", function()
  local InternalDownloadBackend

  setup(function()
    require("commonrequire")
    InternalDownloadBackend =
      require("plugins/newsdownloader.koplugin/internaldownloadbackend")
  end)

  it("should expose InternalDownloadBackend table", function()
    assert.is_table(InternalDownloadBackend)
    assert.is_function(InternalDownloadBackend.getResponseAsString)
  end)
end)
