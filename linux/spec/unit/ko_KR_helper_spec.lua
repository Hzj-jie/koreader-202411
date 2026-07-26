describe("Korean IME helper module (ko_KR_helper.lua)", function()
  local KoHelper

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    KoHelper = require("ui/data/keyboardlayouts/ko_KR_helper")
  end)

  describe("Initialization & Classes", function()
    it("should expose UIHandler and HgFSM classes", function()
      assert.is_table(KoHelper)
      assert.is_table(KoHelper.UIHandler)
      assert.is_table(KoHelper.HgFSM)
    end)
  end)
end)
