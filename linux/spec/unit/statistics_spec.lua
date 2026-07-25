describe("Statistics plugin", function()
  local ReaderStatistics

  setup(function()
    require("commonrequire")
    ReaderStatistics = require("plugins/statistics.koplugin/main")
  end)

  it("should initialize ReaderStatistics class", function()
    assert.is_table(ReaderStatistics)
    assert.is_function(ReaderStatistics.new)
  end)

  it("should instantiate ReaderStatistics with ui mockup", function()
    local stats = ReaderStatistics:new({
      ui = {
        menu = {
          registerToMainMenu = function() end,
        },
      },
    })
    assert.is_table(stats)
  end)
end)
