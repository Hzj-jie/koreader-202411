--[[--
UI-mimicking benchmark comparing LuaJIT vs Lua 5.5 performance across startup,
widgets, framebuffer Blitbuffer ops, settings serialization, and CreDocument page turns.

Note: Keep all user-visible text in this file free of `gettext(...)` wrappers so
`update-po.sh` (which scans `koreader/tools/*.lua`) does not add benchmark strings
to translation catalogs, and stay strictly within the common Lua 5.1/5.5 subset.
]]

local UIBenchmark = {}

UIBenchmark.DEFAULT_MAX_SECS = 3.0
UIBenchmark.PAINT_TARGET_MAX = 200
UIBenchmark.REPORT_WIDTH = 50

UIBenchmark.PHASES = {
  { id = "cold_startup", label = "Cold startup" },
  { id = "menu_layout_paint", label = "Menu layout" },
  { id = "widget_layout_paint", label = "Widgets/text" },
  { id = "blitbuffer_ops", label = "Blit ops" },
  { id = "settings_dump_load", label = "Settings IO" },
  { id = "credocument_pages", label = "CRe pages" },
}

local function formatMs(ms)
  if ms == nil then
    return "-"
  end
  return string.format(ms >= 1000 and "%.1f" or "%.2f", ms)
end

local function formatRatio(lua_ms, luajit_ms)
  if not lua_ms or not luajit_ms or luajit_ms <= 0 then
    return "-"
  end
  local ratio = lua_ms / luajit_ms
  return string.format(ratio >= 100 and "%.1fx" or "%.2fx", ratio)
end

local function formatCount(n)
  if not n then
    return "-"
  end
  return n >= 1000000 and string.format("%.1fM", n / 1e6) or tostring(n)
end

local function formatRuntimeSummary(meta)
  local lua_ver = meta.lua_version or "?"
  if meta.jit_version and meta.jit_version ~= "" and meta.jit_version ~= "none" then
    return lua_ver .. " / " .. meta.jit_version
  end
  return lua_ver
end

function UIBenchmark.usageText()
  return table.concat({
    "Usage:",
    "  ./luajit tools/ui_benchmark.lua run [out.lua|-] [max_secs]",
    "  ./luajit tools/ui_benchmark.lua compare <lj.lua> <lua.lua> [out.log|-]",
    "  ./luajit tools/ui_benchmark.lua show <report_file>",
  }, "\n")
end

function UIBenchmark.parseArgs(args)
  local cmd = args[1]
  if not cmd or cmd == "-h" or cmd == "--help" then
    return { mode = "help" }
  end
  if cmd == "run" then
    local out = args[2] ~= "-" and args[2] or nil
    local max_secs = UIBenchmark.DEFAULT_MAX_SECS
    if args[3] ~= nil then
      max_secs = tonumber(args[3])
      if not max_secs or max_secs <= 0 then
        return nil, "max_secs must be a positive number"
      end
    end
    if args[4] ~= nil then
      return nil, "unexpected extra argument: " .. tostring(args[4])
    end
    return { mode = "run", out = out, max_secs = max_secs }
  elseif cmd == "compare" then
    if not args[2] or not args[3] then
      return nil, "compare requires <lj.lua> <lua.lua>"
    end
    if args[5] ~= nil then
      return nil, "unexpected extra argument: " .. tostring(args[5])
    end
    local out = args[4] ~= "-" and args[4] or nil
    return { mode = "compare", lj_path = args[2], lua_path = args[3], out = out }
  elseif cmd == "show" then
    if not args[2] or args[3] ~= nil then
      return nil, "show requires <report_file>"
    end
    return { mode = "show", show_file = args[2] }
  end
  return nil, "unknown command: " .. tostring(cmd)
end

function UIBenchmark.bbTypeName(bb_type, blitbuffer_mod)
  local names = {
    [blitbuffer_mod.TYPE_BB4] = "BB4",
    [blitbuffer_mod.TYPE_BB8] = "BB8",
    [blitbuffer_mod.TYPE_BB8A] = "BB8A",
    [blitbuffer_mod.TYPE_BBRGB16] = "BBRGB16",
    [blitbuffer_mod.TYPE_BBRGB24] = "BBRGB24",
    [blitbuffer_mod.TYPE_BBRGB32] = "BBRGB32",
  }
  return names[bb_type] or ("UNKNOWN(" .. tostring(bb_type) .. ")")
end

function UIBenchmark.initSandboxSettings(DataStorage, LuaDefaults, LuaSettings, util)
  if G_defaults == nil then
    G_defaults = LuaDefaults:open()
  end
  local real_path = DataStorage:getDataDir() .. "/settings.reader.lua"
  local loaded = LuaSettings:load(real_path)
  local copied = util.tableDeepCopy(loaded)
  G_reader_settings = LuaSettings:extend({
    data = copied,
    flush = function() end,
    close = function() end,
  })
  G_named_settings = require("named_settings")
end

function UIBenchmark.bootstrapEnvironment(start_clock)
  require("setupkoenv")
  local time = require("ui/time")
  local setup_cpu_ms = start_clock and math.max(0, (os.clock() - start_clock) * 1000) or 0
  local mono_t0 = time.monotonic()
  local DataStorage = require("datastorage")

  UIBenchmark.initSandboxSettings(DataStorage, require("luadefaults"), require("luasettings"), require("util"))

  local dbg = require("dbg")
  if G_reader_settings:isTrue("debug") then
    dbg:turnOn()
    if G_reader_settings:isTrue("debug_verbose") then
      dbg:setVerbose(true)
    end
  elseif not G_defaults:isTrue("DEV_MODE") then
    local logger = require("logger")
    logger:setLevel(logger.levels.err)
  end

  local is_cbb_enabled = G_reader_settings:nilOrFalse("dev_no_c_blitter")
  if not is_cbb_enabled then
    jit.opt.start("loopunroll=45")
  end

  local lang_locale = os.getenv("KO_RTL") and "ar" or G_reader_settings:read("language")
  if lang_locale then
    require("gettext").changeLang(lang_locale)
  end

  local Blitbuffer = require("ffi/blitbuffer")
  Blitbuffer:setUseCBB(is_cbb_enabled)
  is_cbb_enabled = Blitbuffer:enableCBB(G_reader_settings:nilOrFalse("dev_no_c_blitter"))
  G_reader_settings:save("dev_no_c_blitter", not is_cbb_enabled)

  local Device = require("device")
  require("document/canvascontext"):init(Device)
  require("ui/bidi").setup(lang_locale)

  local fontmap = G_reader_settings:readTable("fontmap")
  if fontmap ~= nil then
    local Font = require("ui/font")
    for k, v in pairs(fontmap) do
      Font.fontmap[k] = v
    end
  end

  local UIManager = require("ui/uimanager")
  UIManager:init()
  require("pluginloader"):loadPlugins()

  return {
    cold_startup_ms = setup_cpu_ms + time.to_ms(time.monotonic() - mono_t0),
    Device = Device,
    UIManager = UIManager,
    DataStorage = DataStorage,
    Blitbuffer = Blitbuffer,
  }
end

function UIBenchmark.paintSize(screen)
  return math.min(UIBenchmark.PAINT_TARGET_MAX, screen:getWidth()),
    math.min(UIBenchmark.PAINT_TARGET_MAX, screen:getHeight())
end

function UIBenchmark.collectDeviceInfo(env)
  local Device = env.Device
  local Blitbuffer = env.Blitbuffer
  local Screen = Device.screen
  local bb_type = Screen.bb:getType()
  local pw, ph = UIBenchmark.paintSize(Screen)
  return {
    device = Device.model or "Unknown",
    screen = string.format("%dx%d", Screen:getWidth(), Screen:getHeight()),
    paint_target = string.format("%dx%d", pw, ph),
    bb_type = UIBenchmark.bbTypeName(bb_type, Blitbuffer),
    bb_bpp = Blitbuffer.TYPE_TO_BPP[bb_type] or 0,
    cbb = Blitbuffer:getUseCBB() and "on" or "off",
    lua_version = _VERSION,
    jit_version = (_VERSION == "Lua 5.1" and jit.version) and jit.version or "none",
  }
end

function UIBenchmark.measurePhase(id, label, max_secs, step_fn, cleanup_fn)
  local time = require("ui/time")
  local function finish(status, ops, total_ms, note)
    if cleanup_fn then
      cleanup_fn()
    end
    collectgarbage("collect")
    return {
      id = id,
      label = label,
      status = status,
      ops = ops,
      total_ms = total_ms,
      ms_per_op = (status == "OK" and ops > 0) and (total_ms / ops) or nil,
      note = note,
    }
  end

  -- One warm-up iteration before starting the timer avoids cold icon/font/JIT skew.
  local warm_res, warm_note = step_fn(0)
  if warm_res == "skip" then
    return finish("SKIPPED", 0, 0, warm_note or "skipped")
  end

  local ops = 0
  local start = time.monotonic()
  local deadline_s = max_secs or UIBenchmark.DEFAULT_MAX_SECS

  while true do
    local res, res_note = step_fn(ops + 1)
    if res == "skip" then
      return finish("SKIPPED", 0, 0, res_note or "skipped")
    end
    ops = ops + 1
    if time.to_s(time.monotonic() - start) >= deadline_s then
      break
    end
  end

  return finish("OK", ops, time.to_ms(time.monotonic() - start), "")
end

function UIBenchmark.benchMenuLayoutAndPaint(env, max_secs)
  local Menu = require("ui/widget/menu")
  local Blitbuffer = env.Blitbuffer
  local Screen = env.Device.screen
  local UIManager = env.UIManager
  local sw, sh = Screen:getWidth(), Screen:getHeight()
  local pw, ph = UIBenchmark.paintSize(Screen)
  local offscreen = Blitbuffer.new(pw, ph, Screen.bb:getType())

  local items = {}
  for i = 1, 100 do
    items[i] = {
      text = string.format("Benchmark Book Entry %03d - Sample Author Name", i),
      mandatory = string.format("%d KB", i * 17),
      callback = function() end,
    }
  end

  return UIBenchmark.measurePhase("menu_layout_paint", "Menu layout", max_secs, function()
    local menu = Menu:new({ title = "Benchmark Menu", item_table = items, width = sw, height = sh })
    menu:onNextPage()
    menu:paintTo(offscreen, 0, 0)
    menu:free()
    UIManager:clearRenderStack()
  end, function()
    UIManager:clearRenderStack()
    offscreen:free()
  end)
end

function UIBenchmark.benchWidgetLayoutAndPaint(env, max_secs)
  local TouchMenu = require("ui/widget/touchmenu")
  local InfoMessage = require("ui/widget/infomessage")
  local ButtonTable = require("ui/widget/buttontable")
  local TextBoxWidget = require("ui/widget/textboxwidget")
  local Screen = env.Device.screen
  local UIManager = env.UIManager
  local sw = Screen:getWidth()
  local pw, ph = UIBenchmark.paintSize(Screen)
  local offscreen = env.Blitbuffer.new(pw, ph, Screen.bb:getType())
  local info_face = require("ui/font"):getFace("infofont")

  local tab_items = {}
  for t, icon in ipairs({ "appbar.settings", "appbar.typeset" }) do
    local tab = { icon = icon }
    for idx = 1, 8 do
      tab[idx] = {
        text = string.format("Option Tab %d Item %d", t, idx),
        checked_func = function()
          return idx % 2 == 1
        end,
        enabled_func = function()
          return true
        end,
        separator = idx == 4,
        callback = function() end,
      }
    end
    tab_items[t] = tab
  end

  local sample_text = "KOReader UI widget layout benchmark measuring text shaping, line wrapping, "
    .. "button table construction, touch menu tab switching, and screen bitmap compositing."
  local box_width = math.floor(sw * 0.8)

  return UIBenchmark.measurePhase("widget_layout_paint", "Widgets/text", max_secs, function()
    local tm = TouchMenu:new({ tab_item_table = tab_items, width = sw })
    tm:switchMenuTab(2)
    tm:paintTo(offscreen, 0, 0)

    local tb = TextBoxWidget:new({ face = info_face, text = sample_text, width = box_width })
    tb:paintTo(offscreen, 0, 0)

    local info = InfoMessage:new({ text = sample_text })
    info:paintTo(offscreen, 0, 0)

    local bt = ButtonTable:new({
      width = box_width,
      buttons = {
        {
          { text = "Cancel", callback = function() end },
          { text = "Details", callback = function() end },
          { text = "OK", callback = function() end },
        },
        {
          { text = "Previous", callback = function() end },
          { text = "Refresh", callback = function() end },
          { text = "Next", callback = function() end },
        },
      },
    })
    bt:paintTo(offscreen, 0, 0)

    tb:free(true)
    info:free()
    bt:free()
    tm:free()
    UIManager:clearRenderStack()
  end, function()
    UIManager:clearRenderStack()
    offscreen:free()
  end)
end

function UIBenchmark.benchBlitbufferOps(env, max_secs)
  local Blitbuffer = env.Blitbuffer
  local Screen = env.Device.screen
  local pw, ph = UIBenchmark.paintSize(Screen)
  local fb_type = Screen.bb:getType()
  local dst_bb = Blitbuffer.new(pw, ph, fb_type)
  local src_bb = Blitbuffer.new(pw, ph, fb_type)
  local batch = Blitbuffer:getUseCBB() and 200 or 1

  src_bb:paintRect(0, 0, pw, ph, Blitbuffer.COLOR_WHITE)
  src_bb:paintRect(
    math.floor(pw * 0.1),
    math.floor(ph * 0.1),
    math.max(1, math.floor(pw * 0.8)),
    math.max(1, math.floor(ph * 0.8)),
    Blitbuffer.COLOR_GRAY_8
  )

  return UIBenchmark.measurePhase(
    "blitbuffer_ops",
    batch > 1 and ("Blit x" .. batch) or "Blit ops",
    max_secs,
    function()
    for _ = 1, batch do
      dst_bb:paintRect(0, 0, pw, ph, Blitbuffer.COLOR_WHITE)
      dst_bb:blitFrom(src_bb, 0, 0, 0, 0, pw, ph)
      dst_bb:invertRect(0, 0, pw, ph)
    end
  end, function()
    dst_bb:free()
    src_bb:free()
  end)
end

function UIBenchmark.benchSettingsDumpLoad(env, max_secs)
  local batch = 20
  local label = "Settings x" .. batch
  local tmp_dir = env.DataStorage:getTmpDir()
  if not tmp_dir then
    return UIBenchmark.measurePhase("settings_dump_load", label, max_secs, function()
      return "skip", "no writable tmp dir"
    end)
  end

  local LuaSettings = require("luasettings")
  local util = require("util")
  local sample = {
    font_size = 22,
    copt_line_spacing = 115,
    dev_no_c_blitter = false,
    night_mode = false,
    lastfile = "/mnt/us/documents/benchmark_sample.epub",
    bookmarks = {},
    menu_favorites = { "toc", "bookmarks", "night_mode", "frontlight", "wifi" },
    reader_config = { justified = true, hyphenation = true, render_dpi = 300, embedded_css = true },
  }
  for i = 1, 10 do
    sample.bookmarks[i] = {
      page = string.format("/body/DocFragment[1]/body/p[%d]/text().0", i),
      pos0 = i * 1024,
      notes = "Benchmark sample highlight note #" .. tostring(i),
    }
  end

  local tmp_path = string.format("%s/koreader_ui_benchmark_io_%d_%d.lua", tmp_dir, os.time(), math.floor(os.clock() * 1e6))
  return UIBenchmark.measurePhase("settings_dump_load", label, max_secs, function()
    for _ = 1, batch do
      local writer = LuaSettings:open(tmp_path)
      writer:reset(util.tableDeepCopy(sample))
      writer:flush()
      local loaded = LuaSettings:load(tmp_path)
      assert(loaded and loaded.reader_config and loaded.reader_config.render_dpi == 300)
    end
  end, function()
    os.remove(tmp_path)
    os.remove(tmp_path .. ".old")
    os.remove(tmp_path .. ".temp")
  end)
end

function UIBenchmark.buildSampleHtml()
  local chunks = { "<!DOCTYPE html><html><head><meta charset=\"utf-8\"></head><body>" }
  local para = "<p>The quick brown fox jumps over the lazy dog while e-ink displays render crisp typography, hyphenation rules, and pagination metrics.</p>"
  for ch = 1, 10 do
    table.insert(chunks, string.format("<h1>Chapter %d</h1>", ch))
    for _ = 1, 8 do
      table.insert(chunks, para)
    end
  end
  table.insert(chunks, "</body></html>")
  return table.concat(chunks, "\n") .. "\n"
end

function UIBenchmark.benchCreDocumentPages(env, max_secs)
  local batch = env.Blitbuffer:getUseCBB() and 20 or 1
  local label = batch > 1 and ("CRe x" .. batch) or "CRe pages"
  local tmp_dir = env.DataStorage:getTmpDir()
  if not tmp_dir then
    return UIBenchmark.measurePhase("credocument_pages", label, max_secs, function()
      return "skip", "no writable tmp dir"
    end)
  end

  local Screen = env.Device.screen
  local sw, sh = Screen:getWidth(), Screen:getHeight()
  local pw, ph = UIBenchmark.paintSize(Screen)
  local offscreen = env.Blitbuffer.new(pw, ph, Screen.bb:getType())
  local page_rect = require("ui/geometry"):new({ x = 0, y = 0, w = pw, h = ph })
  local tmp_html = string.format("%s/koreader_ui_benchmark_book_%d_%d.html", tmp_dir, os.time(), math.floor(os.clock() * 1e6))
  local ok, write_err = require("util").writeToFile(UIBenchmark.buildSampleHtml(), tmp_html)
  assert(ok, "failed to write temp HTML benchmark file: " .. tostring(write_err))

  -- Open and render the document once outside the loop so ops measure page turns/drawing.
  local doc = require("document/documentregistry"):openDocument(tmp_html)
  assert(doc, "DocumentRegistry failed to open temp benchmark HTML")
  doc:setViewDimen({ w = sw, h = sh })
  doc:render()
  local pages = math.max(1, doc:getPageCount())
  local op_idx = 0

  return UIBenchmark.measurePhase("credocument_pages", label, max_secs, function()
    for _ = 1, batch do
      op_idx = op_idx + 1
      doc:drawCurrentViewByPage(offscreen, 0, 0, page_rect, ((op_idx - 1) % pages) + 1)
    end
  end, function()
    doc:close()
    offscreen:free()
    os.remove(tmp_html)
  end)
end

function UIBenchmark.runAllBenchmarks(env, max_secs)
  local meta = UIBenchmark.collectDeviceInfo(env)
  meta.status = "OK"
  meta.status_detail = "done"

  return {
    meta = meta,
    phases = {
      {
        id = "cold_startup",
        label = "Cold startup",
        status = "OK",
        ops = 1,
        total_ms = env.cold_startup_ms,
        ms_per_op = env.cold_startup_ms,
      },
      UIBenchmark.benchMenuLayoutAndPaint(env, max_secs),
      UIBenchmark.benchWidgetLayoutAndPaint(env, max_secs),
      UIBenchmark.benchBlitbufferOps(env, max_secs),
      UIBenchmark.benchSettingsDumpLoad(env, max_secs),
      UIBenchmark.benchCreDocumentPages(env, max_secs),
    },
  }
end

local function indexPhases(run)
  local map = {}
  for _, p in ipairs(run.phases or {}) do
    map[p.id] = p
  end
  return map
end

local function formatVmCell(meta, phase)
  if meta.status == "MISSING" then
    return "MISSING", "-"
  end
  if phase and phase.status == "OK" then
    return formatMs(phase.ms_per_op), formatCount(phase.ops or 0)
  elseif phase then
    return phase.status, "-"
  elseif meta.status ~= "OK" then
    return "ERR", "-"
  end
  return "-", "-"
end

local function describeRuntime(meta)
  if meta.status == "MISSING" then
    return "missing"
  end
  local desc = formatRuntimeSummary(meta)
  if meta.status ~= "OK" then
    desc = desc .. " [" .. tostring(meta.status or "ERR") .. "]"
  end
  return desc
end

function UIBenchmark.formatComparisonReport(lj_run, lua_run)
  local lj_meta = lj_run.meta
  local lua_meta = lua_run.meta
  local hw = lj_meta.device and lj_meta or lua_meta
  local sep = string.rep("-", UIBenchmark.REPORT_WIDTH)

  local lines = {
    "KOReader Benchmark (Lua vs LuaJIT)",
    string.format("Device:  %s (%s)", hw.device or "Unknown", hw.screen or "?"),
    string.format(
      "Surface: %s %sbpp, CBB %s, paint %s",
      hw.bb_type or "?",
      tostring(hw.bb_bpp or "?"),
      hw.cbb or "?",
      hw.paint_target or "?"
    ),
    "LuaJIT:  " .. describeRuntime(lj_meta),
    "Lua:     " .. describeRuntime(lua_meta),
    "",
    string.format("%-12s %7s %7s %7s %13s", "Workload", "LJ(ms)", "Lua(ms)", "Ratio", "Ops(LJ/L)"),
    sep,
  }

  local notes = {}
  if lj_meta.status ~= "OK" and lj_meta.status_detail and lj_meta.status_detail ~= "" then
    table.insert(notes, "  * LJ: " .. lj_meta.status_detail)
  end
  if lua_meta.status ~= "OK" and lua_meta.status_detail and lua_meta.status_detail ~= "" then
    table.insert(notes, "  * Lua: " .. lua_meta.status_detail)
  end

  local lj_map = indexPhases(lj_run)
  local lua_map = indexPhases(lua_run)
  for _, def in ipairs(UIBenchmark.PHASES) do
    local p_lj = lj_map[def.id]
    local p_lua = lua_map[def.id]
    local row_label = (p_lj and p_lj.label) or (p_lua and p_lua.label) or def.label
    local lj_ms_str, lj_ops_str = formatVmCell(lj_meta, p_lj)
    local lua_ms_str, lua_ops_str = formatVmCell(lua_meta, p_lua)
    local ratio_str = "-"
    if p_lj and p_lua and p_lj.status == "OK" and p_lua.status == "OK" then
      ratio_str = formatRatio(p_lua.ms_per_op, p_lj.ms_per_op)
    end
    table.insert(
      lines,
      string.format("%-12s %7s %7s %7s %13s", row_label, lj_ms_str, lua_ms_str, ratio_str, lj_ops_str .. "/" .. lua_ops_str)
    )
    if p_lj and p_lj.status ~= "OK" and p_lj.note ~= "" then
      table.insert(notes, string.format("  * %s (LJ): %s", row_label, p_lj.note))
    end
    if p_lua and p_lua.status ~= "OK" and p_lua.note ~= "" then
      table.insert(notes, string.format("  * %s (Lua): %s", row_label, p_lua.note))
    end
  end

  table.insert(lines, sep)
  if #notes > 0 then
    table.insert(lines, "Notes:")
    for _, n in ipairs(notes) do
      table.insert(lines, n)
    end
  end
  return table.concat(lines, "\n") .. "\n"
end

function UIBenchmark.showReportFile(report_path, env)
  local content, err = require("util").readFromFile(report_path, "rb")
  if not content then
    return false, "failed to read report file " .. tostring(report_path) .. ": " .. tostring(err)
  end
  local UIManager = env.UIManager
  local viewer = require("ui/widget/textviewer"):new({
    title = "Benchmark (Lua vs LuaJIT)",
    text = content,
    text_type = "code",
    close_callback = function()
      UIManager:quit()
    end,
  })
  UIManager:show(viewer)
  local exit_code = UIManager:run()
  return exit_code == 0 or exit_code == nil, exit_code
end

local function emitOutput(out_path, text, lua_dofile_ready)
  if out_path then
    local ok, err = require("util").writeToFile(text, out_path, lua_dofile_ready)
    if not ok then
      io.stderr:write("Failed to write ", out_path, ": ", tostring(err), "\n")
      return false
    end
  else
    io.write(lua_dofile_ready and ("return " .. text .. "\n") or text)
  end
  return true
end

local function loadBenchmarkRun(path)
  local run, ok = require("luasettings"):load(path)
  if ok then
    return run
  end
  local name = path:match("[^/]+$") or path
  local detail = "cannot load " .. name
  if #detail > 40 then
    detail = detail:sub(1, 37) .. "..."
  end
  return { meta = { status = "ERROR", status_detail = detail } }
end

function UIBenchmark.main(cli_args, start_clock)
  local opts, parse_err = UIBenchmark.parseArgs(cli_args or {})
  if not opts then
    io.stderr:write("Error: ", parse_err, "\n", UIBenchmark.usageText(), "\n")
    return 1
  end
  if opts.mode == "help" then
    io.write(UIBenchmark.usageText(), "\n")
    return 0
  end
  if opts.mode == "compare" then
    require("setupkoenv")
    local lj_run = loadBenchmarkRun(opts.lj_path)
    local lua_run = loadBenchmarkRun(opts.lua_path)
    return emitOutput(opts.out, UIBenchmark.formatComparisonReport(lj_run, lua_run)) and 0 or 1
  end

  local env = UIBenchmark.bootstrapEnvironment(start_clock)
  local exit_code = 0

  if opts.mode == "show" then
    local ok, viewer_rc = UIBenchmark.showReportFile(opts.show_file, env)
    if not ok then
      if type(viewer_rc) == "string" then
        io.stderr:write(viewer_rc, "\n")
        exit_code = 1
      else
        exit_code = type(viewer_rc) == "number" and viewer_rc or 1
      end
    end
    env.Device:exit()
  else
    local run = UIBenchmark.runAllBenchmarks(env, opts.max_secs)
    if not emitOutput(opts.out, require("dump")(run), true) then
      exit_code = 1
    end
    require("device/generic/device").exit(env.Device)
  end

  return exit_code
end

if debug.getinfo(3) == nil then
  local start_clock = os.clock()
  os.exit(UIBenchmark.main(arg or { ... }, start_clock), true)
end

return UIBenchmark
