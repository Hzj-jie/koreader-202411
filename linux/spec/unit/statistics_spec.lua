describe("Statistics plugin", function()
  local ReaderStatistics, G_reader_settings

  setup(function()
    require("commonrequire")
    G_reader_settings = require("luasettings"):open("reader")
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
    assert.is_table(stats.settings)
    assert.is_true(stats.settings.is_enabled)
  end)

  it("should reset volatile stats", function()
    local stats = ReaderStatistics:new({
      ui = {
        menu = {
          registerToMainMenu = function() end,
        },
      },
    })
    stats:resetVolatileStats()
    assert.is_same(0, stats.mem_read_time)
    assert.is_same(0, stats.mem_read_pages)
  end)
end)
