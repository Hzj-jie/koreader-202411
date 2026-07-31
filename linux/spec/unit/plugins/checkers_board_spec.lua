describe("Checkers Board module", function()
  local CheckersBoard

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    CheckersBoard = require("plugins/checkers.koplugin/board")
  end)

  it("should expose CheckersBoard class table", function()
    assert.is_table(CheckersBoard)
  end)
end)
