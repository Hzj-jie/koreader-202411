describe("Coverbrowser MosaicMenu module", function()
  local MosaicMenu

  setup(function()
    require("commonrequire")
    MosaicMenu = require("plugins/coverbrowser.koplugin/mosaicmenu")
  end)

  it("should initialize MosaicMenu module", function()
    assert.is_table(MosaicMenu)
  end)
end)
