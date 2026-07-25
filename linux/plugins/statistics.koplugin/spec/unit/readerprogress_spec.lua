describe("ReaderProgress module", function()
  local Device, Screen, UIManager, ReaderProgress

  setup(function()
    require("commonrequire")
    package.loaded["plugins/statistics.koplugin/readerprogress"] = nil
    ReaderProgress = require("plugins/statistics.koplugin/readerprogress")
  end)

  before_each(function()
    Device = require("device")
    Screen = Device.screen
    UIManager = require("ui/uimanager")

    stub(Device, "hasKeys")
    stub(Device, "isTouchDevice")
    stub(UIManager, "close")
    stub(UIManager, "scheduleRefresh")

    Device.hasKeys.returns(true)
    Device.isTouchDevice.returns(true)
  end)

  after_each(function()
    Device.hasKeys:revert()
    Device.isTouchDevice:revert()
    UIManager.close:revert()
    UIManager.scheduleRefresh:revert()
  end)

  local function createSampleProgress(opts)
    opts = opts or {}
    local sample_dates = opts.dates or {
      { 20, 2400, "2026-07-25" },
      { 30, 3600, "2026-07-24" },
      { 15, 1800, "2026-07-23" },
      { 0, 0, "2026-07-22" },
      { 25, 3000, "2026-07-21" },
      { 40, 4800, "2026-07-20" },
      { 10, 1200, "2026-07-19" },
    }
    return ReaderProgress:new({
      current_pages = opts.current_pages or 15,
      today_pages = opts.today_pages or 45,
      current_duration = opts.current_duration or 1800,
      today_duration = opts.today_duration or 5400,
      dates = sample_dates,
      readonly = opts.readonly or false,
    })
  end

  it("should initialize ReaderProgress instance with string numbers and dimensions", function()
    local progress = createSampleProgress()
    assert.is_table(progress)
    assert.are.equal("15", progress.current_pages)
    assert.are.equal("45", progress.today_pages)
    assert.is_table(progress.dimen)
    assert.are.equal(Screen:getWidth(), progress.dimen.w)
    assert.are.equal(Screen:getHeight(), progress.dimen.h)
  end)

  it("should set stats_span correctly based on screen orientation", function()
    stub(Screen, "getWidth")
    stub(Screen, "getHeight")

    -- Portrait mode: width < height -> stats_span = 20
    Screen.getWidth.returns(600)
    Screen.getHeight.returns(800)
    local portrait = createSampleProgress()
    assert.are.equal(20, portrait.stats_span)

    -- Landscape mode: width > height -> stats_span = 8
    Screen.getWidth.returns(800)
    Screen.getHeight.returns(600)
    local landscape = createSampleProgress()
    assert.are.equal(8, landscape.stats_span)

    Screen.getWidth:revert()
    Screen.getHeight:revert()
  end)

  it("should calculate total stats correctly via getTotalStats", function()
    local progress = createSampleProgress()
    local total_time, total_pages = progress:getTotalStats(7)
    assert.are.equal(16800, total_time)
    assert.are.equal(140, total_pages)

    local partial_time, partial_pages = progress:getTotalStats(3)
    assert.are.equal(7800, partial_time)
    assert.are.equal(65, partial_pages)

    local zero_time, zero_pages = progress:getTotalStats(0)
    assert.are.equal(0, zero_time)
    assert.are.equal(0, zero_pages)
  end)

  it("should generate summary week widget and averages", function()
    local progress = createSampleProgress()
    local summary_week = progress:genSummaryWeek(Screen:getWidth())
    assert.is_table(summary_week)
  end)

  it("should generate summary day widget", function()
    local progress = createSampleProgress()
    local summary_day = progress:genSummaryDay(Screen:getWidth())
    assert.is_table(summary_day)
  end)

  it("should generate week stats widget", function()
    local progress = createSampleProgress()
    local week_stats = progress:genWeekStats(7)
    assert.is_table(week_stats)
  end)

  it("should generate single and double headers", function()
    local progress = createSampleProgress()
    local single_header = progress:genSingleHeader("Test Header")
    assert.is_table(single_header)

    local double_header = progress:genDoubleHeader("Left", "Right")
    assert.is_table(double_header)
  end)

  it("should generate status content with title bar and callback", function()
    local progress_rw = createSampleProgress({ readonly = false })
    local content_rw = progress_rw:getStatusContent(Screen:getWidth())
    assert.is_table(content_rw)

    local progress_ro = createSampleProgress({ readonly = true })
    local content_ro = progress_ro:getStatusContent(Screen:getWidth())
    assert.is_table(content_ro)
  end)

  it("should handle gesture swipe events correctly", function()
    local progress = createSampleProgress()

    -- Swipe south should trigger onExit and return true
    local res_south = progress:onSwipe(nil, { direction = "south" })
    assert.is_true(res_south)
    assert.stub(UIManager.close).was_called_with(match.ref(UIManager), match.ref(progress))

    -- Swipe east/west/north should return false without scheduleRefresh
    local res_east = progress:onSwipe(nil, { direction = "east" })
    assert.is_false(res_east)

    local res_north = progress:onSwipe(nil, { direction = "north" })
    assert.is_false(res_north)

    -- Diagonal swipe should schedule refresh and return false
    local res_diag = progress:onSwipe(nil, { direction = "south_east" })
    assert.is_false(res_diag)
    assert.stub(UIManager.scheduleRefresh).was_called_with(match.ref(UIManager), "full")
  end)

  it("should exit on close and handle key or multiswipe events", function()
    local progress = createSampleProgress()

    local res_exit = progress:onExit()
    assert.is_true(res_exit)
    assert.stub(UIManager.close).was_called_with(match.ref(UIManager), match.ref(progress))

    UIManager.close:clear()

    local res_key = progress:onAnyKeyPressed()
    assert.is_true(res_key)
    assert.stub(UIManager.close).was_called_with(match.ref(UIManager), match.ref(progress))

    UIManager.close:clear()

    local res_mswipe = progress:onMultiSwipe()
    assert.is_true(res_mswipe)
    assert.stub(UIManager.close).was_called_with(match.ref(UIManager), match.ref(progress))
  end)
end)
