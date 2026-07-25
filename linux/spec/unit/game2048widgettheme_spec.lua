describe("Game2048WidgetTheme module", function()
  local Game2048WidgetTheme

  setup(function()
    require("commonrequire")
    Game2048WidgetTheme =
      require("plugins/game2048.koplugin/ui/theme/game2048widgettheme")
  end)

  it("should expose Game2048WidgetTheme table", function()
    assert.is_table(Game2048WidgetTheme)
  end)
end)
