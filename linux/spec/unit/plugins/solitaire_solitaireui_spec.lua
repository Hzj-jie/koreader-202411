describe("SolitaireUI plugin module", function()
  local SolitaireUI

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    SolitaireUI = require("plugins/solitaire.koplugin/solitaireui")
  end)

  it("should instantiate SolitaireUI container", function()
    local inst = SolitaireUI:new({
      settings_path = os.tmpname(),
      save_path = os.tmpname(),
    })
    assert.is_table(inst)
    assert.is_table(inst.game)
    assert.is_table(inst.stats)

    os.remove(inst.settings_path)
    os.remove(inst.save_path)
  end)

  it("should load and save draw mode settings", function()
    local tmp_settings = os.tmpname()
    local inst = SolitaireUI:new({
      settings_path = tmp_settings,
      save_path = os.tmpname(),
    })

    inst.draw_mode_pref = 3
    inst:saveSettings()

    inst:loadSettings()
    assert.are.equal(3, inst.draw_mode_pref)

    os.remove(tmp_settings)
    os.remove(inst.save_path)
  end)

  it("should save, load, and delete game state", function()
    local tmp_save = os.tmpname()
    local inst = SolitaireUI:new({
      settings_path = os.tmpname(),
      save_path = tmp_save,
    })

    inst:saveGame()
    local loaded = inst:loadGame()
    assert.is_boolean(loaded)

    inst:deleteSave()

    os.remove(inst.settings_path)
  end)

  it("should handle new game and undo move operations", function()
    local inst = SolitaireUI:new({
      settings_path = os.tmpname(),
      save_path = os.tmpname(),
    })

    inst:newGame()
    assert.is_table(inst.game)

    inst:undoMove()

    os.remove(inst.settings_path)
    os.remove(inst.save_path)
  end)
end)
