describe("Sudoku plugin", function()
  local Sudoku

  setup(function()
    require("commonrequire")
    Sudoku = require("plugins/sudoku.koplugin/main")
  end)

  it("should initialize Sudoku plugin class", function()
    assert.is_table(Sudoku)
    assert.is_function(Sudoku.new)
  end)

  it("should populate main menu entry", function()
    local sudoku = Sudoku:new({
      ui = {
        menu = {
          registerToMainMenu = function() end,
        },
      },
    })
    local items = {}
    sudoku:addToMainMenu(items)
    assert.is_table(items.sudoku)
  end)
end)
