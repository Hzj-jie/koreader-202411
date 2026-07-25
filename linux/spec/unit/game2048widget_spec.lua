describe("Game2048Widget widget", function()
  local Game2048Widget

  setup(function()
    require("commonrequire")
    Game2048Widget =
      require("plugins/game2048.koplugin/ui/widget/game2048widget")
  end)

  it("should initialize Game2048Widget", function()
    local widget = Game2048Widget:new({
      width = 400,
      height = 400,
    })

    assert.is_table(widget)
  end)
end)
