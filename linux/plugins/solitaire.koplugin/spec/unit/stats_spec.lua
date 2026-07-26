describe("Solitaire Stats module", function()
  local Stats

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    Stats = require("plugins/solitaire.koplugin/stats")
  end)

  describe("Initialization & Defaults", function()
    it("should instantiate Stats with default values", function()
      local s = Stats:new()
      assert.is_table(s)
      assert.are.equal(0, s.games_played)
      assert.are.equal(0, s.games_won)
    end)

    it("should update stats when games finish", function()
      local s = Stats:new()
      if type(s.onGameFinish) == "function" then
        s:onGameFinish(true)
        assert.are.equal(1, s.games_played)
        assert.are.equal(1, s.games_won)

        s:onGameFinish(false)
        assert.are.equal(2, s.games_played)
        assert.are.equal(1, s.games_won)
      end
    end)
  end)
end)
