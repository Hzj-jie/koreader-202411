describe("Solitaire Stats module", function()
  local Stats

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    Stats = require("plugins/solitaire.koplugin/stats")
  end)

  it("should instantiate Stats with default values", function()
    local s = Stats:new()
    assert.is_table(s)
    assert.are.equal(0, s.games_played)
    assert.are.equal(0, s.games_won)
  end)

  it("should record wins and update streaks/leaderboard", function()
    local s = Stats:new()
    s.stats_path = os.tmpname()

    s:recordWin(500, 45, 120, 1)
    assert.are.equal(1, s.games_played)
    assert.are.equal(1, s.games_won)
    assert.are.equal(500, s.best_score)
    assert.are.equal(45, s.fewest_moves)
    assert.are.equal(120, s.best_time)
    assert.are.equal(1, s.current_win_streak)

    s:recordWin(600, 40, 100, 3)
    assert.are.equal(2, s.games_played)
    assert.are.equal(2, s.games_won)
    assert.are.equal(600, s.best_score)
    assert.are.equal(40, s.fewest_moves)
    assert.are.equal(2, s.current_win_streak)
    assert.are.equal(2, #s.leaderboard)

    os.remove(s.stats_path)
  end)

  it("should record losses and reset win streak", function()
    local s = Stats:new()
    s.stats_path = os.tmpname()

    s:recordWin(500, 45, 120, 1)
    assert.are.equal(1, s.current_win_streak)

    s:recordLoss(1)
    assert.are.equal(2, s.games_played)
    assert.are.equal(1, s.games_won)
    assert.are.equal(1, s.games_lost)
    assert.are.equal(0, s.current_win_streak)
    assert.are.equal(1, s.current_lose_streak)

    os.remove(s.stats_path)
  end)

  it("should calculate averages and format statistics text", function()
    local s = Stats:new()
    s.stats_path = os.tmpname()

    assert.are.equal(0, s:getWinPercentage())
    assert.are.equal("--:--", s:formatTime(0))
    assert.are.equal("2:05", s:formatTime(125))

    s:recordWin(500, 50, 100, 1)
    s:recordWin(300, 30, 200, 3)

    assert.are.equal(100, s:getWinPercentage())
    assert.are.equal(400, s:getAverageScore())
    assert.are.equal(40, s:getAverageMoves())
    assert.are.equal(150, s:getAverageTime())

    local stats_text = s:getStatsText()
    assert.is_string(stats_text)
    assert.is_true(stats_text:find("Games Played:    2") ~= nil)

    local board_text = s:getLeaderboardText()
    assert.is_string(board_text)
    assert.is_true(board_text:find("#1  Score: 500") ~= nil)

    s:reset()
    assert.are.equal(0, s.games_played)

    os.remove(s.stats_path)
  end)
end)
