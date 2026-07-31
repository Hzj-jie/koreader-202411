describe("CoverMenu plugin base module", function()
  local CoverMenu

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    CoverMenu = require("plugins/coverbrowser.koplugin/covermenu")
  end)

  it("should update cover info cache entries", function()
    local obj = {
      cover_info_cache = {},
    }

    CoverMenu.updateCache(obj, "test.epub", "reading", true, 100)
    assert.is_table(obj.cover_info_cache["test.epub"])

    CoverMenu.updateCache(obj, "test.epub", "finished", false)
    assert.are.equal("finished", obj.cover_info_cache["test.epub"][3])

    CoverMenu.updateCache(obj, "test.epub", nil, false)
    assert.is_nil(obj.cover_info_cache["test.epub"])
  end)
end)
