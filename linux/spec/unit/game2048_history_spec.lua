describe("Game2048 History module", function()
  local History

  setup(function()
    require("commonrequire")
    History = require("plugins/game2048.koplugin/modules/history")
  end)

  it("should initialize History instance", function()
    local history = History:new()
    assert.is_table(history)
  end)
end)
