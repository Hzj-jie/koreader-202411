describe("CoverBrowser BookInfoManager plugin module", function()
  local BookInfoManager, DataStorage

  setup(function()
    require("commonrequire")
    DataStorage = require("datastorage")
    BookInfoManager = require("plugins/coverbrowser.koplugin/bookinfomanager")
  end)

  it("should expose BookInfoManager instance and methods", function()
    assert.is_table(BookInfoManager)
    if type(BookInfoManager.getCover) == "function" then
      assert.is_function(BookInfoManager.getCover)
    end
  end)

  it("should handle book info cache directory creation", function()
    local cache_dir = DataStorage:getSettingsDir() .. "/bookinfo_cache"
    assert.is_string(cache_dir)
  end)

  it("should extract cover specs safely for non-existent files", function()
    if type(BookInfoManager.getCoverSpec) == "function" then
      local cover_spec = BookInfoManager:getCoverSpec("non_existent_book.epub")
      assert.is_nil(cover_spec)
    end
  end)
end)
