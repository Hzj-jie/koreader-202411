local ffiUtil = require("ffi/util")
local lfs = require("libs/libkoreader-lfs")

describe("Solitaire Stats module", function()
  local Stats
  local tmp_stats_path

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    Stats = require("plugins/solitaire.koplugin/stats")
  end)

  before_each(function()
    tmp_stats_path = lfs.currentdir() .. "/test_solitaire_stats_" .. ffiUtil.getpid() .. "_" .. os.time() .. ".lua"
  end)

  after_each(function()
    if tmp_stats_path then
      os.remove(tmp_stats_path)
    end
  end)

  it("should instantiate Stats with default values", function()
    local s = Stats:new()
    assert.is_table(s)
    assert.are.equal(0, s.games_played)
    assert.are.equal(0, s.games_won)
    assert.are.equal(0, s.games_lost)
    assert.are.equal(0, s.total_score)
    assert.are.equal(0, s.best_score)
    assert.are.equal(0, s.total_moves)
    assert.are.equal(0, s.fewest_moves)
    assert.are.equal(0, s.total_time)
    assert.are.equal(0, s.best_time)
    assert.are.equal(0, s.current_win_streak)
    assert.are.equal(0, s.longest_win_streak)
    assert.are.equal(0, s.current_lose_streak)
    assert.are.same({}, s.leaderboard)
  end)

  it("should record wins and update streaks/leaderboard across Draw-1 and Draw-3", function()
    local s = Stats:new()
    s.stats_path = tmp_stats_path

    s:recordWin(500, 45, 120, 1)
    assert.are.equal(1, s.games_played)
    assert.are.equal(1, s.games_won)
    assert.are.equal(1, s.draw1_games_played)
    assert.are.equal(1, s.draw1_games_won)
    assert.are.equal(0, s.draw3_games_played)
    assert.are.equal(500, s.best_score)
    assert.are.equal(45, s.fewest_moves)
    assert.are.equal(120, s.best_time)
    assert.are.equal(1, s.current_win_streak)
    assert.are.equal(1, s.longest_win_streak)
    assert.are.equal(0, s.current_lose_streak)

    s:recordWin(600, 40, 100, 3)
    assert.are.equal(2, s.games_played)
    assert.are.equal(2, s.games_won)
    assert.are.equal(1, s.draw3_games_played)
    assert.are.equal(1, s.draw3_games_won)
    assert.are.equal(600, s.best_score)
    assert.are.equal(40, s.fewest_moves)
    assert.are.equal(100, s.best_time)
    assert.are.equal(2, s.current_win_streak)
    assert.are.equal(2, s.longest_win_streak)
    assert.are.equal(2, #s.leaderboard)
    assert.are.equal(600, s.leaderboard[1].score)
    assert.are.equal(500, s.leaderboard[2].score)
  end)

  it("should record losses and reset win streak while tracking lose streak", function()
    local s = Stats:new()
    s.stats_path = tmp_stats_path

    s:recordWin(500, 45, 120, 1)
    s:recordWin(550, 42, 110, 1)
    assert.are.equal(2, s.current_win_streak)
    assert.are.equal(2, s.longest_win_streak)

    s:recordLoss(3)
    assert.are.equal(3, s.games_played)
    assert.are.equal(2, s.games_won)
    assert.are.equal(1, s.games_lost)
    assert.are.equal(1, s.draw3_games_played)
    assert.are.equal(0, s.draw3_games_won)
    assert.are.equal(0, s.current_win_streak)
    assert.are.equal(2, s.longest_win_streak)
    assert.are.equal(1, s.current_lose_streak)

    s:recordLoss(1)
    assert.are.equal(2, s.current_lose_streak)
  end)

  it("should sort leaderboard by score descending and cap at max_leaderboard", function()
    local s = Stats:new()
    s.stats_path = tmp_stats_path

    for score = 100, 1200, 100 do
      s:addToLeaderboard(score, 50, 100, 1)
    end

    assert.are.equal(10, #s.leaderboard)
    assert.are.equal(1200, s.leaderboard[1].score)
    assert.are.equal(300, s.leaderboard[10].score)

    -- Insert intermediate score
    s:addToLeaderboard(850, 48, 95, 3)
    assert.are.equal(10, #s.leaderboard)
    assert.are.equal(1200, s.leaderboard[1].score)
    assert.are.equal(850, s.leaderboard[5].score)
    assert.are.equal(400, s.leaderboard[10].score)
  end)

  it("should calculate averages and format time correctly", function()
    local s = Stats:new()
    s.stats_path = tmp_stats_path

    assert.are.equal(0, s:getWinPercentage())
    assert.are.equal(0, s:getAverageScore())
    assert.are.equal(0, s:getAverageMoves())
    assert.are.equal(0, s:getAverageTime())
    assert.are.equal("--:--", s:formatTime(nil))
    assert.are.equal("--:--", s:formatTime(0))
    assert.are.equal("0:05", s:formatTime(5))
    assert.are.equal("1:00", s:formatTime(60))
    assert.are.equal("2:05", s:formatTime(125))

    s:recordWin(500, 50, 100, 1)
    s:recordWin(300, 30, 200, 3)

    assert.are.equal(100, s:getWinPercentage())
    assert.are.equal(400, s:getAverageScore())
    assert.are.equal(40, s:getAverageMoves())
    assert.are.equal(150, s:getAverageTime())
  end)

  it("should format statistics text with all sections and draw modes", function()
    local s = Stats:new()
    s.stats_path = tmp_stats_path

    -- Unplayed state
    local empty_text = s:getStatsText()
    assert.is_string(empty_text)
    assert.is_not_nil(empty_text:find("Games Played:    0", 1, true))
    assert.is_not_nil(empty_text:find("Fewest Moves:    --", 1, true))
    assert.is_nil(empty_text:find("── By Draw Mode ──", 1, true))

    -- Played state with wins and losses in both modes
    s:recordWin(500, 50, 100, 1)
    s:recordLoss(3)

    local text = s:getStatsText()
    assert.is_not_nil(text:find("Games Played:    2", 1, true))
    assert.is_not_nil(text:find("Games Won:       1", 1, true))
    assert.is_not_nil(text:find("Games Lost:      1", 1, true))
    assert.is_not_nil(text:find("Win Rate:        50%", 1, true))
    assert.is_not_nil(text:find("Best Score:      500", 1, true))
    assert.is_not_nil(text:find("Fewest Moves:    50", 1, true))
    assert.is_not_nil(text:find("── By Draw Mode ──", 1, true))
    assert.is_not_nil(text:find("Draw-1:  1/1 (100%)", 1, true))
    assert.is_not_nil(text:find("Draw-3:  0/1 (0%)", 1, true))
  end)

  it("should format leaderboard text when empty vs populated", function()
    local s = Stats:new()
    s.stats_path = tmp_stats_path

    assert.are.equal("No games won yet!\n\nWin a game to see your scores here.", s:getLeaderboardText())

    s:recordWin(750, 35, 90, 3)
    local board_text = s:getLeaderboardText()
    assert.is_not_nil(board_text:find("══════ BEST SCORES ══════", 1, true))
    assert.is_not_nil(board_text:find("#1  Score: 750  Moves: 35  Time: 1:30  D3", 1, true))
  end)

  it("should persist stats to LuaSettings and reload correctly", function()
    local s1 = Stats:new()
    s1.stats_path = tmp_stats_path
    s1:recordWin(450, 38, 115, 1)

    -- Reload in fresh instance
    local s2 = Stats:new()
    s2.stats_path = tmp_stats_path
    s2:load()

    assert.are.equal(1, s2.games_played)
    assert.are.equal(1, s2.games_won)
    assert.are.equal(450, s2.best_score)
    assert.are.equal(38, s2.fewest_moves)
    assert.are.equal(115, s2.best_time)
    assert.are.equal(1, #s2.leaderboard)

    -- Reset
    s2:reset()
    assert.are.equal(0, s2.games_played)

    local s3 = Stats:new()
    s3.stats_path = tmp_stats_path
    s3:load()
    assert.are.equal(0, s3.games_played)
  end)
end)
