local lfs = require("libs/libkoreader-lfs")
local spy = require("luassert.spy")
local stub = require("luassert.stub")

describe("ui_benchmark tool and Kindle KUAL benchmark launcher", function()
  local DataStorage
  local Device
  local UIManager
  local Blitbuffer
  local UIBenchmark
  local tmp_root
  local workspace_dir

  local function readFile(path)
    local f = assert(io.open(path, "rb"))
    local content = f:read("*a")
    f:close()
    return content
  end

  local function writeFile(path, content)
    local f = assert(io.open(path, "wb"))
    assert(f:write(content))
    f:close()
  end

  local function assertMaxLineLen(report, max_len)
    for line in (report .. "\n"):gmatch("(.-)\n") do
      assert.is_true(
        #line <= max_len,
        string.format("line exceeds %d chars (%d): %s", max_len, #line, line)
      )
    end
  end

  setup(function()
    require("commonrequire")
    DataStorage = require("datastorage")
    Device = require("device")
    UIManager = require("ui/uimanager")
    UIManager:init()
    Blitbuffer = require("ffi/blitbuffer")
    UIBenchmark = require("tools/ui_benchmark")
    tmp_root = DataStorage:getTmpDir()
    workspace_dir =
      assert(os.getenv("KO_WORKSPACE_DIR"), "KO_WORKSPACE_DIR must be set")
  end)

  describe("CLI argument parsing and formatting", function()
    it("parses help, run, compare, and show subcommands cleanly", function()
      assert.are.same("help", assert(UIBenchmark.parseArgs({})).mode)
      assert.are.same("help", assert(UIBenchmark.parseArgs({ "-h" })).mode)
      assert.are.same("help", assert(UIBenchmark.parseArgs({ "--help" })).mode)

      local opts = assert(UIBenchmark.parseArgs({ "run" }))
      assert.are.same("run", opts.mode)
      assert.is_nil(opts.out)
      assert.are.same(UIBenchmark.DEFAULT_MAX_SECS, opts.max_secs)

      opts = assert(UIBenchmark.parseArgs({ "run", "bench.lua", "1.5" }))
      assert.are.same({ mode = "run", out = "bench.lua", max_secs = 1.5 }, opts)

      opts = assert(UIBenchmark.parseArgs({ "run", "-", "2.5" }))
      assert.are.same("run", opts.mode)
      assert.is_nil(opts.out)
      assert.are.same(2.5, opts.max_secs)

      opts = assert(
        UIBenchmark.parseArgs({ "compare", "lj.lua", "lua.lua", "report.log" })
      )
      assert.are.same({
        mode = "compare",
        lj_path = "lj.lua",
        lua_path = "lua.lua",
        out = "report.log",
      }, opts)

      opts =
        assert(UIBenchmark.parseArgs({ "compare", "lj.lua", "lua.lua", "-" }))
      assert.are.same("compare", opts.mode)
      assert.is_nil(opts.out)

      opts = assert(UIBenchmark.parseArgs({ "show", "benchmark.log" }))
      assert.are.same({ mode = "show", show_file = "benchmark.log" }, opts)
    end)

    it("rejects invalid CLI commands and arguments cleanly", function()
      local ok, err = UIBenchmark.parseArgs({ "bogus" })
      assert.is_nil(ok)
      assert.truthy(err:find("unknown command", 1, true))

      ok, err = UIBenchmark.parseArgs({ "run", "bench.lua", "0" })
      assert.is_nil(ok)
      assert.truthy(err:find("max_secs", 1, true))

      ok, err = UIBenchmark.parseArgs({ "run", "bench.lua", "1.5", "extra" })
      assert.is_nil(ok)
      assert.truthy(err:find("unexpected extra argument", 1, true))

      ok, err = UIBenchmark.parseArgs({ "compare", "only_one.lua" })
      assert.is_nil(ok)
      assert.truthy(err:find("compare requires", 1, true))

      ok, err = UIBenchmark.parseArgs({
        "compare",
        "lj.lua",
        "lua.lua",
        "out.log",
        "extra",
      })
      assert.is_nil(ok)
      assert.truthy(err:find("unexpected extra argument", 1, true))

      ok, err = UIBenchmark.parseArgs({ "show" })
      assert.is_nil(ok)
      assert.truthy(err:find("show requires", 1, true))

      ok, err = UIBenchmark.parseArgs({ "show", "a.log", "b.log" })
      assert.is_nil(ok)
      assert.truthy(err:find("show requires", 1, true))
    end)

    it("maps Blitbuffer pixel type constants to readable names", function()
      assert.are.same(
        "BB4",
        UIBenchmark.bbTypeName(Blitbuffer.TYPE_BB4, Blitbuffer)
      )
      assert.are.same(
        "BB8",
        UIBenchmark.bbTypeName(Blitbuffer.TYPE_BB8, Blitbuffer)
      )
      assert.are.same(
        "BB8A",
        UIBenchmark.bbTypeName(Blitbuffer.TYPE_BB8A, Blitbuffer)
      )
      assert.are.same(
        "BBRGB16",
        UIBenchmark.bbTypeName(Blitbuffer.TYPE_BBRGB16, Blitbuffer)
      )
      assert.are.same(
        "BBRGB24",
        UIBenchmark.bbTypeName(Blitbuffer.TYPE_BBRGB24, Blitbuffer)
      )
      assert.are.same(
        "BBRGB32",
        UIBenchmark.bbTypeName(Blitbuffer.TYPE_BBRGB32, Blitbuffer)
      )
    end)

    it("bounds measurePhase loops and handles skipped phases", function()
      local time = require("ui/time")
      local fake_fts = 0
      local cleanup_called = 0
      local seen_steps = {}
      local mono_stub = stub(time, "monotonic", function()
        return fake_fts
      end)
      finally(function()
        mono_stub:revert()
      end)

      local phase = UIBenchmark.measurePhase(
        "test_phase",
        "Test phase",
        0.5,
        function(step)
          table.insert(seen_steps, step)
          if step == 0 then
            -- Warm-up time must not be counted in total_ms or ops.
            fake_fts = fake_fts + time.ms(1000)
            return
          end
          fake_fts = fake_fts + time.ms(200)
        end,
        function()
          cleanup_called = cleanup_called + 1
        end
      )
      assert.are.same("OK", phase.status)
      assert.are.same({ 0, 1, 2, 3 }, seen_steps)
      assert.are.same(3, phase.ops)
      assert.are.same(600, phase.total_ms)
      assert.are.same(200, phase.ms_per_op)
      assert.are.same(1, cleanup_called)

      -- Must run at least 1 measured op after warm-up even if single op already exceeds max_secs
      fake_fts = 0
      seen_steps = {}
      local single = UIBenchmark.measurePhase(
        "slow_phase",
        "Slow phase",
        0.05,
        function(step)
          table.insert(seen_steps, step)
          fake_fts = fake_fts + time.ms(500)
        end
      )
      assert.are.same("OK", single.status)
      assert.are.same({ 0, 1 }, seen_steps)
      assert.are.same(1, single.ops)
      assert.are.same(500, single.ms_per_op)

      -- Returning skip during warm-up stops immediately without a second step_fn call
      local skip_calls = 0
      local skip_cleanup = 0
      local skipped = UIBenchmark.measurePhase(
        "skip_phase",
        "Skipped phase",
        1.0,
        function()
          skip_calls = skip_calls + 1
          return "skip", "no writable tmp dir"
        end,
        function()
          skip_cleanup = skip_cleanup + 1
        end
      )
      assert.are.same("SKIPPED", skipped.status)
      assert.are.same(1, skip_calls)
      assert.are.same(1, skip_cleanup)
      assert.are.same(0, skipped.ops)
      assert.is_nil(skipped.ms_per_op)
      assert.are.same("no writable tmp dir", skipped.note)
    end)

    it(
      "round-trips Lua dump results and renders comparison reports <= 50 chars/line",
      function()
        local dump = require("dump")
        local LuaSettings = require("luasettings")
        local util = require("util")
        local lj_run = {
          meta = {
            runtime = "./luajit tools/ui_benchmark.lua",
            lua_version = "Lua 5.1",
            jit_version = "LuaJIT 2.1.0",
            device = "KindleDXG",
            screen = "824x1200",
            paint_target = "200x200",
            bb_type = "BB4",
            bb_bpp = 4,
            cbb = "off",
            status = "OK",
            status_detail = "done",
          },
          phases = {
            {
              id = "cold_startup",
              label = "Cold startup",
              status = "OK",
              ops = 1,
              total_ms = 200,
              ms_per_op = 200,
              note = "",
            },
            {
              id = "menu_layout_paint",
              label = "Menu layout",
              status = "OK",
              ops = 100,
              total_ms = 3000,
              ms_per_op = 30,
              note = "",
            },
            {
              id = "widget_layout_paint",
              label = "Widgets/text",
              status = "OK",
              ops = 80,
              total_ms = 3200,
              ms_per_op = 40,
              note = "",
            },
            {
              id = "blitbuffer_ops",
              label = "Blit x200",
              status = "OK",
              ops = 500,
              total_ms = 2500,
              ms_per_op = 5,
              note = "",
            },
            {
              id = "settings_dump_load",
              label = "Settings x20",
              status = "SKIPPED",
              ops = 0,
              total_ms = 0,
              ms_per_op = nil,
              note = "no writable tmp dir",
            },
            {
              id = "credocument_pages",
              label = "CRe x20",
              status = "OK",
              ops = 10,
              total_ms = 3000,
              ms_per_op = 300,
              note = "",
            },
          },
        }
        local lua_run = {
          meta = {
            runtime = "./lua tools/ui_benchmark.lua",
            lua_version = "Lua 5.5",
            jit_version = "none",
            device = "KindleDXG",
            screen = "824x1200",
            paint_target = "200x200",
            bb_type = "BB4",
            bb_bpp = 4,
            cbb = "off",
            status = "OK",
            status_detail = "done",
          },
          phases = {
            {
              id = "cold_startup",
              label = "Cold startup",
              status = "OK",
              ops = 1,
              total_ms = 500,
              ms_per_op = 500,
              note = "",
            },
            {
              id = "menu_layout_paint",
              label = "Menu layout",
              status = "OK",
              ops = 15,
              total_ms = 3000,
              ms_per_op = 200,
              note = "",
            },
            {
              id = "widget_layout_paint",
              label = "Widgets/text",
              status = "OK",
              ops = 12,
              total_ms = 3000,
              ms_per_op = 250,
              note = "",
            },
            {
              id = "blitbuffer_ops",
              label = "Blit x200",
              status = "OK",
              ops = 4,
              total_ms = 4000,
              ms_per_op = 1000,
              note = "",
            },
            {
              id = "settings_dump_load",
              label = "Settings x20",
              status = "SKIPPED",
              ops = 0,
              total_ms = 0,
              ms_per_op = nil,
              note = "no writable tmp dir",
            },
            {
              id = "credocument_pages",
              label = "CRe x20",
              status = "OK",
              ops = 4,
              total_ms = 3200,
              ms_per_op = 800,
              note = "",
            },
          },
        }

        local lj_path = tmp_root .. "/ui_bench_roundtrip_lj.lua"
        local lua_path = tmp_root .. "/ui_bench_roundtrip_lua.lua"
        local missing_path = tmp_root .. "/ui_bench_roundtrip_missing.lua"
        local err_path = tmp_root .. "/ui_bench_roundtrip_err.lua"
        finally(function()
          os.remove(lj_path)
          os.remove(lua_path)
          os.remove(missing_path)
          os.remove(err_path)
        end)

        assert(util.writeToFile(dump(lj_run), lj_path, true))
        assert(util.writeToFile(dump(lua_run), lua_path, true))
        local decoded_lj, lj_ok = LuaSettings:load(lj_path)
        local decoded_lua, lua_ok = LuaSettings:load(lua_path)
        assert.is_true(lj_ok)
        assert.is_true(lua_ok)
        assert.are.same("KindleDXG", decoded_lj.meta.device)
        assert.are.same("200x200", decoded_lj.meta.paint_target)
        assert.are.same("BB4", decoded_lj.meta.bb_type)
        assert.are.same(4, decoded_lj.meta.bb_bpp)
        assert.are.same("off", decoded_lj.meta.cbb)
        assert.are.same(1000, decoded_lua.phases[4].ms_per_op)

        local report =
          UIBenchmark.formatComparisonReport(decoded_lj, decoded_lua)
        assertMaxLineLen(report, UIBenchmark.REPORT_WIDTH)
        assert.truthy(report:find("Device:  KindleDXG (824x1200)", 1, true))
        assert.truthy(
          report:find("Surface: BB4 4bpp, CBB off, paint 200x200", 1, true)
        )
        assert.truthy(report:find("LuaJIT:  Lua 5.1 / LuaJIT 2.1.0", 1, true))
        assert.truthy(report:find("Lua:     Lua 5.5\n", 1, true))
        assert.is_nil(report:find("Lua:     Lua 5.5 /", 1, true))
        assert.truthy(report:find("Blit x200", 1, true))
        assert.truthy(report:find("Settings x20", 1, true))
        assert.truthy(report:find("CRe x20", 1, true))
        assert.truthy(report:find("200.0x", 1, true))
        assert.truthy(report:find("2.50x", 1, true))
        assert.truthy(report:find("500/4", 1, true))
        assert.truthy(report:find("SKIPPED", 1, true))
        assert.truthy(report:find("no writable tmp dir", 1, true))

        writeFile(
          missing_path,
          'return { meta = { status = "MISSING", status_detail = "./lua not found or not executable" } }\n'
        )
        local missing_lua, missing_ok = LuaSettings:load(missing_path)
        assert.is_true(missing_ok)
        local partial_report =
          UIBenchmark.formatComparisonReport(decoded_lj, missing_lua)
        assertMaxLineLen(partial_report, UIBenchmark.REPORT_WIDTH)
        assert.truthy(partial_report:find("Lua:     missing", 1, true))
        assert.truthy(
          partial_report:find("./lua not found or not executable", 1, true)
        )

        writeFile(
          err_path,
          'return { meta = { status = "ERROR", status_detail = "exit code 42 (see crash.log)" } }\n'
        )
        local err_lua, err_ok = LuaSettings:load(err_path)
        assert.is_true(err_ok)
        local err_report =
          UIBenchmark.formatComparisonReport(decoded_lj, err_lua)
        assertMaxLineLen(err_report, UIBenchmark.REPORT_WIDTH)
        assert.truthy(err_report:find("[ERROR]", 1, true))
        assert.truthy(err_report:find("exit code 42 (see crash.log)", 1, true))
      end
    )
  end)

  describe("runtime workloads and safety invariants", function()
    it(
      "isolates G_reader_settings in memory without mutating real settings.reader.lua",
      function()
        local orig_defaults = _G.G_defaults
        local orig_settings = _G.G_reader_settings
        local orig_named = _G.G_named_settings
        local fake_data_dir =
          string.format("%s/ui_bench_data_%s", tmp_root, tostring(os.time()))
        local fake_tmp_dir =
          string.format("%s/ui_bench_tmp_%s", tmp_root, tostring(os.time()))
        assert(lfs.mkdir(fake_data_dir))
        assert(lfs.mkdir(fake_tmp_dir))
        local real_settings_file = fake_data_dir .. "/settings.reader.lua"
        local sentinel = 'return {\n    ["sentinel_key"] = "preserve_me",\n}\n'
        writeFile(real_settings_file, sentinel)

        local data_dir_stub
        local tmp_dir_stub
        finally(function()
          if data_dir_stub then
            data_dir_stub:revert()
          end
          if tmp_dir_stub then
            tmp_dir_stub:revert()
          end
          -- luacheck: push ignore 122
          _G.G_defaults = orig_defaults
          _G.G_reader_settings = orig_settings
          _G.G_named_settings = orig_named
          -- luacheck: pop
          os.remove(real_settings_file)
          lfs.rmdir(fake_data_dir)
          lfs.rmdir(fake_tmp_dir)
        end)

        data_dir_stub = stub(DataStorage, "getDataDir", function()
          return fake_data_dir
        end)
        tmp_dir_stub = stub(DataStorage, "getTmpDir", function()
          return fake_tmp_dir
        end)

        local LuaDefaults = require("luadefaults")
        local LuaSettings = require("luasettings")
        local util = require("util")

        UIBenchmark.initSandboxSettings(
          DataStorage,
          LuaDefaults,
          LuaSettings,
          util
        )
        assert.are.same(
          "preserve_me",
          _G.G_reader_settings:read("sentinel_key")
        )
        _G.G_reader_settings:save("dev_no_c_blitter", true)
        _G.G_reader_settings:save("closed_rotation_mode", 1)
        _G.G_reader_settings:flush()
        _G.G_reader_settings:close()
        assert.are.same(sentinel, readFile(real_settings_file))
        for entry in lfs.dir(fake_tmp_dir) do
          assert.truthy(
            entry == "." or entry == "..",
            "unexpected sandbox file on disk: " .. entry
          )
        end

        -- Read-only boot path (getTmpDir() == nil)
        tmp_dir_stub:revert()
        tmp_dir_stub = stub(DataStorage, "getTmpDir", function()
          return nil
        end)
        UIBenchmark.initSandboxSettings(
          DataStorage,
          LuaDefaults,
          LuaSettings,
          util
        )
        assert.are.same(
          "preserve_me",
          _G.G_reader_settings:read("sentinel_key")
        )
        _G.G_reader_settings:save("closed_rotation_mode", 2)
        _G.G_reader_settings:flush()
        _G.G_reader_settings:close()
        assert.are.same(sentinel, readFile(real_settings_file))
      end
    )

    it(
      "executes all live offscreen workloads cleanly with bounded iterations",
      function()
        local env = {
          Device = Device,
          UIManager = UIManager,
          DataStorage = DataStorage,
          Blitbuffer = Blitbuffer,
        }
        local info = UIBenchmark.collectDeviceInfo(env)
        assert.is_string(info.device)
        assert.truthy(info.screen:match("^%d+x%d+$"))
        assert.is_nil(info.runtime)
        assert.is_nil(info.width)
        assert.is_nil(info.height)
        assert.is_nil(info.paint_width)
        assert.is_nil(info.paint_height)
        assert.is_nil(info.bb_type_id)
        local pw, ph = UIBenchmark.paintSize(Device.screen)
        assert.is_true(pw > 0 and pw <= UIBenchmark.PAINT_TARGET_MAX)
        assert.is_true(ph > 0 and ph <= UIBenchmark.PAINT_TARGET_MAX)
        assert.are.same(string.format("%dx%d", pw, ph), info.paint_target)
        assert.is_number(info.bb_bpp)
        assert.truthy(info.cbb == "on" or info.cbb == "off")

        local fake_small = {
          getWidth = function()
            return 120
          end,
          getHeight = function()
            return 160
          end,
        }
        local sw_small, sh_small = UIBenchmark.paintSize(fake_small)
        assert.are.same({ 120, 160 }, { sw_small, sh_small })
        local fake_large = {
          getWidth = function()
            return 824
          end,
          getHeight = function()
            return 1200
          end,
        }
        local sw_large, sh_large = UIBenchmark.paintSize(fake_large)
        assert.are.same({ 200, 200 }, { sw_large, sh_large })

        assert.are.same(_VERSION, info.lua_version)
        assert.are.same(
          _VERSION == "Lua 5.1" and jit.version or "none",
          info.jit_version
        )

        local menu_res = UIBenchmark.benchMenuLayoutAndPaint(env, 0.01)
        assert.are.same("OK", menu_res.status)
        assert.are.same("Menu layout", menu_res.label)
        assert.is_true(menu_res.ops >= 1)

        local widget_res = UIBenchmark.benchWidgetLayoutAndPaint(env, 0.01)
        assert.are.same("OK", widget_res.status)
        assert.are.same("Widgets/text", widget_res.label)
        assert.is_true(widget_res.ops >= 1)

        local use_cbb = Blitbuffer:getUseCBB()
        local bb_res = UIBenchmark.benchBlitbufferOps(env, 0.01)
        assert.are.same("OK", bb_res.status)
        assert.are.same(use_cbb and "Blit x200" or "Blit ops", bb_res.label)
        assert.is_true(bb_res.ops >= 1)

        local settings_res = UIBenchmark.benchSettingsDumpLoad(env, 0.01)
        assert.are.same("OK", settings_res.status)
        assert.are.same("Settings x20", settings_res.label)
        assert.is_true(settings_res.ops >= 1)

        local cre_res = UIBenchmark.benchCreDocumentPages(env, 0.01)
        assert.are.same("OK", cre_res.status)
        assert.are.same(use_cbb and "CRe x20" or "CRe pages", cre_res.label)
        assert.is_true(cre_res.ops >= 1)
      end
    )

    it(
      "reads Blitbuffer:getUseCBB() at phase time for Blit ops and CRe pages batching",
      function()
        local cbb_state = true
        local cbb_stub = stub(Blitbuffer, "getUseCBB", function()
          return cbb_state
        end)
        finally(function()
          cbb_stub:revert()
        end)

        local env = {
          Device = Device,
          UIManager = UIManager,
          DataStorage = DataStorage,
          Blitbuffer = Blitbuffer,
        }
        assert.are.same(
          "Blit x200",
          UIBenchmark.benchBlitbufferOps(env, 0.01).label
        )
        assert.are.same(
          "Settings x20",
          UIBenchmark.benchSettingsDumpLoad(env, 0.01).label
        )
        assert.are.same(
          "CRe x20",
          UIBenchmark.benchCreDocumentPages(env, 0.01).label
        )

        cbb_state = false
        assert.are.same(
          "Blit ops",
          UIBenchmark.benchBlitbufferOps(env, 0.01).label
        )
        assert.are.same(
          "Settings x20",
          UIBenchmark.benchSettingsDumpLoad(env, 0.01).label
        )
        assert.are.same(
          "CRe pages",
          UIBenchmark.benchCreDocumentPages(env, 0.01).label
        )
      end
    )

    it(
      "skips Settings IO and CRe pages cleanly when DataStorage:getTmpDir() is nil",
      function()
        local tmp_stub = stub(DataStorage, "getTmpDir", function()
          return nil
        end)
        finally(function()
          tmp_stub:revert()
        end)

        local env = {
          Device = Device,
          UIManager = UIManager,
          DataStorage = DataStorage,
          Blitbuffer = Blitbuffer,
        }
        local settings_res = UIBenchmark.benchSettingsDumpLoad(env, 0.01)
        assert.are.same("SKIPPED", settings_res.status)
        assert.are.same("Settings x20", settings_res.label)
        assert.are.same("no writable tmp dir", settings_res.note)

        local cre_res = UIBenchmark.benchCreDocumentPages(env, 0.01)
        assert.are.same("SKIPPED", cre_res.status)
        assert.are.same(
          Blitbuffer:getUseCBB() and "CRe x20" or "CRe pages",
          cre_res.label
        )
        assert.are.same("no writable tmp dir", cre_res.note)
      end
    )

    it(
      "displays a saved benchmark report via TextViewer and exits cleanly on close",
      function()
        local report_path = tmp_root .. "/ui_benchmark_show_spec.log"
        local sample_report =
          "KOReader Benchmark (Lua vs LuaJIT)\nSample report body\n"
        writeFile(report_path, sample_report)

        local shown_viewer
        local show_stub = stub(UIManager, "show", function(_uimgr, widget)
          shown_viewer = widget
        end)
        local run_stub = stub(UIManager, "run", function()
          if shown_viewer and shown_viewer.close_callback then
            shown_viewer.close_callback()
          end
          return 0
        end)
        local quit_stub = stub(UIManager, "quit")

        finally(function()
          show_stub:revert()
          run_stub:revert()
          quit_stub:revert()
          if shown_viewer then
            shown_viewer:free()
          end
          UIManager:clearRenderStack()
          os.remove(report_path)
        end)

        local ok, rc =
          UIBenchmark.showReportFile(report_path, { UIManager = UIManager })
        assert.is_true(ok)
        assert.are.same(0, rc)
        assert.spy(show_stub).was.called(1)
        local viewer = show_stub.calls[1].vals[2]
        assert.are.same("Benchmark (Lua vs LuaJIT)", viewer.title)
        assert.are.same("code", viewer.text_type)
        assert.are.same(sample_report, viewer.text)
        assert.spy(quit_stub).was.called(1)
      end
    )

    it(
      "uses generic Device exit in run mode, full Device:exit in show, and runs compare",
      function()
        local GenericDevice = require("device/generic/device")
        local LuaSettings = require("luasettings")
        local fake_device = {
          exit = spy.new(function() end),
        }
        local fake_env = {
          Device = fake_device,
          UIManager = UIManager,
          DataStorage = DataStorage,
          Blitbuffer = Blitbuffer,
        }
        local boot_stub = stub(UIBenchmark, "bootstrapEnvironment", function()
          return fake_env
        end)
        local run_stub = stub(UIBenchmark, "runAllBenchmarks", function()
          return {
            meta = {
              runtime = "test",
              lua_version = "Lua 5.1",
              jit_version = "LuaJIT 2.1.0",
              device = "SpecDevice",
              screen = "800x600",
              paint_target = "200x200",
              bb_type = "BB8",
              bb_bpp = 8,
              cbb = "on",
              status = "OK",
              status_detail = "done",
            },
            phases = {},
          }
        end)
        local show_stub = stub(UIBenchmark, "showReportFile", function()
          return true, 0
        end)
        local generic_exit_stub = stub(GenericDevice, "exit")
        local lj_out = tmp_root .. "/ui_bench_main_lj.lua"
        local lua_out = tmp_root .. "/ui_bench_main_lua.lua"
        local missing_out = tmp_root .. "/ui_bench_main_missing.lua"
        local cmp_out = tmp_root .. "/ui_bench_main_cmp.log"

        finally(function()
          boot_stub:revert()
          run_stub:revert()
          show_stub:revert()
          generic_exit_stub:revert()
          os.remove(lj_out)
          os.remove(lua_out)
          os.remove(cmp_out)
        end)

        assert.are.same(0, UIBenchmark.main({ "run", lj_out }))
        assert.spy(generic_exit_stub).was.called_with(fake_device)
        assert.spy(fake_device.exit).was_not_called()
        local saved, load_ok = LuaSettings:load(lj_out)
        assert.is_true(load_ok)
        assert.are.same("SpecDevice", saved.meta.device)

        writeFile(lua_out, readFile(lj_out))
        assert.are.same(
          0,
          UIBenchmark.main({ "compare", lj_out, lua_out, cmp_out })
        )
        local cmp_text = readFile(cmp_out)
        assertMaxLineLen(cmp_text, UIBenchmark.REPORT_WIDTH)
        assert.truthy(cmp_text:find("SpecDevice", 1, true))

        assert.are.same(
          0,
          UIBenchmark.main({ "compare", missing_out, lua_out, cmp_out })
        )
        local err_cmp_text = readFile(cmp_out)
        assertMaxLineLen(err_cmp_text, UIBenchmark.REPORT_WIDTH)
        assert.truthy(err_cmp_text:find("[ERROR]", 1, true))
        assert.truthy(
          err_cmp_text:find("cannot load ui_bench_main_missing.lua", 1, true)
        )

        assert.are.same(0, UIBenchmark.main({ "show", cmp_out }))
        assert.spy(fake_device.exit).was.called_with(fake_device)
        assert.spy(generic_exit_stub).was.called(1)
      end
    )
  end)

  describe(
    "benchmark runner script, KUAL menu.json, and koreader.sh --benchmark integration",
    function()
      local function createStandalonePlatform()
        local sandbox = string.format(
          "%s/run_bench_%d_%d",
          tmp_root,
          os.time(),
          math.floor(os.clock() * 1e6)
        )
        local ko_tools = sandbox .. "/koreader/tools"
        local plat_dir = sandbox .. "/platform"
        local plat_tools = plat_dir .. "/tools"
        local tmp_dir = sandbox .. "/tmp"
        for _, d in ipairs({
          sandbox,
          sandbox .. "/koreader",
          ko_tools,
          plat_dir,
          plat_tools,
          tmp_dir,
        }) do
          assert(lfs.mkdir(d))
        end

        local calls_log = sandbox .. "/calls.log"
        writeFile(
          ko_tools .. "/run_benchmark.sh",
          readFile(workspace_dir .. "/koreader/tools/run_benchmark.sh")
        )
        assert.are.same(
          0,
          os.execute(
            string.format("chmod +x %q", ko_tools .. "/run_benchmark.sh")
          )
        )
        assert.are.same(
          0,
          os.execute(
            string.format(
              "ln -s ../../koreader/tools/run_benchmark.sh %q",
              plat_tools .. "/run_benchmark.sh"
            )
          )
        )
        return sandbox, plat_dir, tmp_dir, calls_log
      end

      local function createSandboxLauncher()
        local sandbox = string.format(
          "%s/ksh_bench_%d_%d",
          tmp_root,
          os.time(),
          math.floor(os.clock() * 1e6)
        )
        local ko_dir = sandbox .. "/ko"
        local ko_tools = ko_dir .. "/tools"
        local vartmp_dir = sandbox .. "/vartmp"
        local stub_bin = sandbox .. "/bin"
        for _, d in ipairs({ sandbox, ko_dir, ko_tools, vartmp_dir, stub_bin }) do
          assert(lfs.mkdir(d))
        end

        local calls_log = sandbox .. "/calls.log"
        -- Rewrite /mnt/us and /var/tmp in a copy so POSIX sh execution hits our sandbox stubs only
        local raw_sh = readFile(workspace_dir .. "/kindle/koreader.sh")
        local test_sh = raw_sh
          :gsub("/mnt/us/koreader([^%.])", ko_dir .. "%1")
          :gsub("/mnt/us/", sandbox .. "/")
          :gsub("/var/tmp", vartmp_dir)
          :gsub("/etc/prettyversion%.txt", sandbox .. "/no_prettyversion")
          :gsub(
            "/var/local/system/userpasswdenabled",
            sandbox .. "/no_passcode"
          )
          :gsub("/etc/init%.d/volumd", sandbox .. "/no_volumd")
          :gsub("/etc/upstart/volumd%.conf", sandbox .. "/no_volumd_upstart")
        writeFile(sandbox .. "/koreader.sh", test_sh)
        writeFile(
          ko_tools .. "/run_benchmark.sh",
          readFile(workspace_dir .. "/koreader/tools/run_benchmark.sh")
        )
        writeFile(ko_dir .. "/fbink", "#!/bin/sh\nexit 0\n")
        writeFile(
          ko_dir .. "/libkohelper.sh",
          string.format(
            "INIT_TYPE='none'\neips_print_bottom_centered() { printf 'EIPS: %%s\\n' \"$1\" >>%q; }\n",
            calls_log
          )
        )
        writeFile(stub_bin .. "/lipc-set-prop", "#!/bin/sh\nexit 0\n")
        writeFile(stub_bin .. "/pidof", "#!/bin/sh\nexit 1\n")
        writeFile(stub_bin .. "/usleep", "#!/bin/sh\nexit 0\n")
        writeFile(stub_bin .. "/nice", "#!/bin/sh\necho 0\n")
        assert.are.same(
          0,
          os.execute(
            string.format(
              "chmod +x %q %q %q %q %q %q %q %q",
              sandbox .. "/koreader.sh",
              ko_tools .. "/run_benchmark.sh",
              ko_dir .. "/fbink",
              ko_dir .. "/libkohelper.sh",
              stub_bin .. "/lipc-set-prop",
              stub_bin .. "/pidof",
              stub_bin .. "/usleep",
              stub_bin .. "/nice"
            )
          )
        )
        return sandbox, ko_dir, stub_bin, calls_log
      end

      it(
        "keeps KUAL menu.json flat and adds Benchmark (Lua vs LuaJIT)",
        function()
          local rapidjson = require("rapidjson")
          local menu = rapidjson.decode(
            readFile(workspace_dir .. "/kindle/extensions/koreader/menu.json")
          )
          assert.are.same(1, #menu.items)
          local koreader_menu = menu.items[1]
          assert.are.same("KOReader", koreader_menu.name)
          assert.are.same(3, #koreader_menu.items)

          assert.are.same("Start KOReader", koreader_menu.items[1].name)
          assert.are.same("--kual", koreader_menu.items[1].params)
          assert.is_false(koreader_menu.items[1].exitmenu)

          assert.are.same("Start KOReader (lua)", koreader_menu.items[2].name)
          assert.are.same("--kual --lua", koreader_menu.items[2].params)
          assert.is_false(koreader_menu.items[2].exitmenu)

          local bench_item = koreader_menu.items[3]
          assert.are.same("Benchmark (Lua vs LuaJIT)", bench_item.name)
          assert.are.same(4, bench_item.priority)
          assert.are.same("/mnt/us/koreader/koreader.sh", bench_item.action)
          assert.are.same("--kual --benchmark", bench_item.params)
          assert.is_false(bench_item.exitmenu)
          assert.is_false(bench_item.status)
          assert.are.same(
            "status Benchmark (Lua vs LuaJIT)",
            bench_item.internal
          )
        end
      )

      it(
        "runs standalone via platform symlinks and handles missing/failing VMs and compare errors",
        function()
          local src_runner = workspace_dir .. "/koreader/tools/run_benchmark.sh"
          assert.are.same(
            0,
            os.execute(
              string.format("sh -n %q && dash -n %q", src_runner, src_runner)
            )
          )
          local raw_runner = readFile(src_runner)
          assert.is_nil(raw_runner:find("eips_print_bottom_centered", 1, true))
          assert.is_nil(raw_runner:find("libkohelper", 1, true))
          assert.is_nil(raw_runner:find("/mnt/us", 1, true))
          assert.is_nil(raw_runner:find("dirname", 1, true))
          assert.is_nil(raw_runner:find("printf", 1, true))
          assert.is_nil(raw_runner:find("trap", 1, true))

          local sandbox, plat_dir, tmp_dir, calls_log =
            createStandalonePlatform()
          finally(function()
            os.execute(string.format("rm -rf %q", sandbox))
          end)

          local real_settings = plat_dir .. "/settings.reader.lua"
          local sentinel =
            'return {\n    ["sentinel_key"] = "preserve_me",\n}\n'
          writeFile(real_settings, sentinel)

          local stub_vm = string.format(
            '#!/bin/sh\nname=$(basename "$0")\n'
              .. "seed=0\n"
              .. 'if [ -n "${XDG_CONFIG_HOME:-}" ] && [ -f "${XDG_CONFIG_HOME}/koreader/settings.reader.lua" ]; then\n'
              .. "  seed=1\n"
              .. "  printf 'write_inside_sandbox' >\"${XDG_CONFIG_HOME}/koreader/settings.reader.lua\"\n"
              .. "fi\n"
              .. 'printf \'BIN=%%s ARGS=%%s\\n\' "$name" "$*" >>%q\n'
              .. 'printf \'ENV=%%s MULTI=%%s XDG=%%s SEED=%%s\\n\' "$name" "${KO_MULTIUSER:-}" "${XDG_CONFIG_HOME:-}" "$seed" >>%q\n'
              .. 'if [ "$2" = "run" ] && [ -n "$3" ]; then printf \'return { meta = { status = "OK" } }\\n\' >"$3"; fi\n'
              .. 'if [ "$2" = "compare" ] && [ -n "$5" ]; then cat "$3" "$4" >"$5"; fi\n'
              .. "exit 0\n",
            calls_log,
            calls_log
          )
          writeFile(plat_dir .. "/luajit", stub_vm)
          writeFile(plat_dir .. "/lua", stub_vm)
          assert.are.same(
            0,
            os.execute(
              string.format(
                "chmod +x %q %q",
                plat_dir .. "/luajit",
                plat_dir .. "/lua"
              )
            )
          )

          -- Invoking via relative symlink from outside plat_dir resolves plat_dir via dirname
          local rc = os.execute(
            string.format(
              "cd %q && TMPDIR=%q %q 1.5 >/dev/null 2>&1",
              sandbox,
              tmp_dir,
              "platform/tools/run_benchmark.sh"
            )
          )
          assert.are.same(0, rc)

          local calls = readFile(calls_log)
          assert.truthy(
            calls:find(
              "BIN=luajit ARGS=tools/ui_benchmark.lua run " .. tmp_dir .. "/",
              1,
              true
            )
          )
          assert.truthy(
            calls:find(
              "BIN=lua ARGS=tools/ui_benchmark.lua run " .. tmp_dir .. "/",
              1,
              true
            )
          )
          assert.truthy(calls:find(" 1.5", 1, true))
          assert.truthy(
            calls:find(
              "BIN=luajit ARGS=tools/ui_benchmark.lua compare ",
              1,
              true
            )
          )
          assert.truthy(calls:find(" benchmark.log", 1, true))
          assert.truthy(
            calls:find(
              "BIN=luajit ARGS=tools/ui_benchmark.lua show benchmark.log",
              1,
              true
            )
          )
          local expected_xdg_prefix = tmp_dir .. "/koreader-bench-data."
          local env_count = 0
          for xdg in calls:gmatch("ENV=%S+ MULTI=1 XDG=(%S+) SEED=1") do
            assert.truthy(
              xdg:sub(1, #expected_xdg_prefix) == expected_xdg_prefix
            )
            env_count = env_count + 1
          end
          assert.are.same(4, env_count)
          assert.are.same(sentinel, readFile(real_settings))
          assert.are.same(
            "file",
            lfs.attributes(plat_dir .. "/benchmark.log", "mode")
          )
          for entry in lfs.dir(tmp_dir) do
            assert.is_nil(entry:find("koreader-bench-", 1, true))
          end

          -- Fallback when ./luajit is missing: ./lua receives MISSING table and displays report
          os.remove(plat_dir .. "/luajit")
          writeFile(calls_log, "")
          local lua_only_rc = os.execute(
            string.format(
              "TMPDIR=%q %q >/dev/null 2>&1",
              tmp_dir,
              plat_dir .. "/tools/run_benchmark.sh"
            )
          )
          assert.are.same(0, lua_only_rc)
          local fallback_calls = readFile(calls_log)
          assert.truthy(
            fallback_calls:find(
              "BIN=lua ARGS=tools/ui_benchmark.lua compare ",
              1,
              true
            )
          )
          assert.truthy(
            fallback_calls:find(
              "BIN=lua ARGS=tools/ui_benchmark.lua show benchmark.log",
              1,
              true
            )
          )
          local fallback_log = readFile(plat_dir .. "/benchmark.log")
          assert.truthy(fallback_log:find('status = "MISSING"', 1, true))
          assert.truthy(
            fallback_log:find("./luajit not found or not executable", 1, true)
          )

          -- Failing Lua VM (42), succeeding LuaJIT: overwrites any partial output and logs exit code 42
          writeFile(calls_log, "")
          writeFile(plat_dir .. "/luajit", stub_vm)
          writeFile(
            plat_dir .. "/lua",
            string.format(
              "#!/bin/sh\nprintf 'BIN=lua ARGS=%%s\\n' \"$*\" >>%q\n"
                .. 'if [ "$2" = "run" ] && [ -n "$3" ]; then printf \'PARTIAL_GARBAGE\\n\' >"$3"; fi\n'
                .. "exit 42\n",
              calls_log
            )
          )
          assert.are.same(
            0,
            os.execute(
              string.format(
                "chmod +x %q %q",
                plat_dir .. "/luajit",
                plat_dir .. "/lua"
              )
            )
          )

          local partial_rc = os.execute(
            string.format(
              "TMPDIR=%q %q >/dev/null 2>&1",
              tmp_dir,
              plat_dir .. "/tools/run_benchmark.sh"
            )
          )
          assert.are.same(0, partial_rc)
          local partial_log = readFile(plat_dir .. "/benchmark.log")
          assert.truthy(partial_log:find("exit code 42", 1, true))
          assert.is_nil(partial_log:find("PARTIAL_GARBAGE", 1, true))
          assert.truthy(
            readFile(calls_log):find(
              "BIN=luajit ARGS=tools/ui_benchmark.lua show benchmark.log",
              1,
              true
            )
          )

          -- Both VMs fail: runner returns non-zero while still writing benchmark.log
          writeFile(calls_log, "")
          writeFile(
            plat_dir .. "/luajit",
            string.format(
              "#!/bin/sh\nprintf 'BIN=luajit ARGS=%%s\\n' \"$*\" >>%q\n"
                .. 'if [ "$2" = "compare" ]; then cat "$3" "$4" >"$5"; exit 0; fi\n'
                .. 'if [ "$2" = "show" ]; then exit 0; fi\n'
                .. "exit 41\n",
              calls_log
            )
          )
          assert.are.same(
            0,
            os.execute(string.format("chmod +x %q", plat_dir .. "/luajit"))
          )
          local both_fail_rc = os.execute(
            string.format(
              "TMPDIR=%q %q >/dev/null 2>&1",
              tmp_dir,
              plat_dir .. "/tools/run_benchmark.sh"
            )
          )
          assert.is_not.same(0, both_fail_rc)
          local both_log = readFile(plat_dir .. "/benchmark.log")
          assert.truthy(both_log:find("exit code 41", 1, true))
          assert.truthy(both_log:find("exit code 42", 1, true))

          -- compare fails (7): runner exits non-zero and must NOT invoke show
          writeFile(calls_log, "")
          writeFile(
            plat_dir .. "/luajit",
            string.format(
              "#!/bin/sh\nprintf 'BIN=luajit ARGS=%%s\\n' \"$*\" >>%q\n"
                .. 'if [ "$2" = "compare" ]; then exit 7; fi\n'
                .. "exit 0\n",
              calls_log
            )
          )
          assert.are.same(
            0,
            os.execute(string.format("chmod +x %q", plat_dir .. "/luajit"))
          )
          local compare_fail_rc = os.execute(
            string.format(
              "TMPDIR=%q %q >/dev/null 2>&1",
              tmp_dir,
              plat_dir .. "/tools/run_benchmark.sh"
            )
          )
          assert.is_not.same(0, compare_fail_rc)
          assert.is_nil(readFile(calls_log):find(" show ", 1, true))
          for entry in lfs.dir(tmp_dir) do
            assert.is_nil(entry:find("koreader-bench-", 1, true))
          end

          -- Failed settings seed cp cleans temp files and sandbox data dir before exiting non-zero (without trap)
          local bad_cp_bin = sandbox .. "/bad_cp_bin"
          assert(lfs.mkdir(bad_cp_bin))
          writeFile(bad_cp_bin .. "/cp", "#!/bin/sh\nexit 1\n")
          assert.are.same(
            0,
            os.execute(string.format("chmod +x %q", bad_cp_bin .. "/cp"))
          )
          local cp_fail_rc = os.execute(
            string.format(
              "PATH=%q:$PATH TMPDIR=%q %q >/dev/null 2>&1",
              bad_cp_bin,
              tmp_dir,
              plat_dir .. "/tools/run_benchmark.sh"
            )
          )
          assert.is_not.same(0, cp_fail_rc)
          for entry in lfs.dir(tmp_dir) do
            assert.is_nil(entry:find("koreader-bench-", 1, true))
          end

          -- Both VMs non-executable: writes error report to benchmark.log and exits non-zero
          assert.are.same(
            0,
            os.execute(
              string.format(
                "chmod -x %q %q",
                plat_dir .. "/luajit",
                plat_dir .. "/lua"
              )
            )
          )
          local none_exec_rc = os.execute(
            string.format(
              "TMPDIR=%q %q >/dev/null 2>&1",
              tmp_dir,
              plat_dir .. "/tools/run_benchmark.sh"
            )
          )
          assert.is_not.same(0, none_exec_rc)
          assert.are.same(
            "KOReader Benchmark Report\n\nError: neither ./luajit nor ./lua is executable.\n",
            readFile(plat_dir .. "/benchmark.log")
          )
        end
      )

      it(
        "runs run_benchmark.sh without dirname or printf even from leading-dash relative paths",
        function()
          local sandbox, _, tmp_dir, calls_log = createStandalonePlatform()
          finally(function()
            os.execute(string.format("rm -rf %q", sandbox))
          end)

          local dash_plat = sandbox .. "/-plat"
          assert(lfs.mkdir(dash_plat))
          assert.are.same(
            0,
            os.execute(
              string.format(
                "ln -s %q %q",
                sandbox .. "/koreader/tools",
                dash_plat .. "/tools"
              )
            )
          )

          local bad_bin = sandbox .. "/bad_bin"
          assert(lfs.mkdir(bad_bin))
          writeFile(
            bad_bin .. "/dirname",
            "#!/bin/sh\necho 'busybox: invalid option --' >&2\nexit 1\n"
          )
          writeFile(
            bad_bin .. "/printf",
            "#!/bin/sh\necho 'printf: not found' >&2\nexit 1\n"
          )

          local stub_vm = string.format(
            '#!/bin/sh\nname=$(basename "$0")\nprintf \'BIN=%%s ARGS=%%s\\n\' "$name" "$*" >>%q\n'
              .. 'if [ "$2" = "run" ] && [ -n "$3" ]; then printf \'return { meta = { status = "OK" } }\\n\' >"$3"; fi\n'
              .. 'if [ "$2" = "compare" ] && [ -n "$5" ]; then cat "$3" "$4" >"$5"; fi\n'
              .. "exit 0\n",
            calls_log
          )
          writeFile(dash_plat .. "/luajit", stub_vm)
          writeFile(dash_plat .. "/lua", stub_vm)
          assert.are.same(
            0,
            os.execute(
              string.format(
                "chmod +x %q %q %q %q",
                bad_bin .. "/dirname",
                bad_bin .. "/printf",
                dash_plat .. "/luajit",
                dash_plat .. "/lua"
              )
            )
          )

          local rc = os.execute(
            string.format(
              "cd %q && PATH=%q:$PATH TMPDIR=%q sh -- %q 1.5 >/dev/null 2>&1",
              sandbox,
              bad_bin,
              tmp_dir,
              "-plat/tools/run_benchmark.sh"
            )
          )
          assert.are.same(0, rc)
          local calls = readFile(calls_log)
          assert.truthy(
            calls:find(
              "BIN=luajit ARGS=tools/ui_benchmark.lua show benchmark.log",
              1,
              true
            )
          )
          assert.are.same(
            "file",
            lfs.attributes(dash_plat .. "/benchmark.log", "mode")
          )
        end
      )

      it(
        "delegates kindle/koreader.sh --kual --benchmark cleanly to tools/run_benchmark.sh",
        function()
          local src_script = workspace_dir .. "/kindle/koreader.sh"
          assert.are.same(
            0,
            os.execute(
              string.format("sh -n %q && dash -n %q", src_script, src_script)
            )
          )

          local sandbox, ko_dir, stub_bin, calls_log = createSandboxLauncher()
          finally(function()
            os.execute(string.format("rm -rf %q", sandbox))
          end)

          local stub_vm = string.format(
            '#!/bin/sh\nname=$(basename "$0")\nprintf \'BIN=%%s ARGS=%%s\\n\' "$name" "$*" >>%q\n'
              .. 'if [ "$2" = "run" ] && [ -n "$3" ]; then printf \'return { meta = { status = "OK" } }\\n\' >"$3"; fi\n'
              .. 'if [ "$2" = "compare" ] && [ -n "$5" ]; then cat "$3" "$4" >"$5"; fi\n'
              .. "exit 0\n",
            calls_log
          )
          writeFile(ko_dir .. "/luajit", stub_vm)
          writeFile(ko_dir .. "/lua", stub_vm)
          assert.are.same(
            0,
            os.execute(
              string.format(
                "chmod +x %q %q",
                ko_dir .. "/luajit",
                ko_dir .. "/lua"
              )
            )
          )
          -- Launching must not rely on +x permission on tools/run_benchmark.sh (e.g. vfat mounts)
          assert.are.same(
            0,
            os.execute(
              string.format("chmod -x %q", ko_dir .. "/tools/run_benchmark.sh")
            )
          )

          local rc = os.execute(
            string.format(
              "PATH=%q:$PATH sh %q --kual --benchmark 1.5 >/dev/null 2>&1",
              stub_bin,
              sandbox .. "/koreader.sh"
            )
          )
          assert.are.same(0, rc)

          local calls = readFile(calls_log)
          assert.truthy(
            calls:find("EIPS: Running Lua vs LuaJIT benchmark", 1, true)
          )
          assert.truthy(
            calls:find("BIN=luajit ARGS=tools/ui_benchmark.lua run ", 1, true)
          )
          assert.truthy(
            calls:find("BIN=lua ARGS=tools/ui_benchmark.lua run ", 1, true)
          )
          assert.truthy(calls:find(" 1.5", 1, true))
          assert.truthy(
            calls:find(
              "BIN=luajit ARGS=tools/ui_benchmark.lua compare ",
              1,
              true
            )
          )
          assert.truthy(calls:find(" benchmark.log", 1, true))
          assert.truthy(
            calls:find(
              "BIN=luajit ARGS=tools/ui_benchmark.lua show benchmark.log",
              1,
              true
            )
          )
          assert.are.same(
            "file",
            lfs.attributes(ko_dir .. "/benchmark.log", "mode")
          )

          -- Non-zero exit from run_benchmark.sh propagates through koreader.sh without invoking show
          writeFile(calls_log, "")
          writeFile(
            ko_dir .. "/luajit",
            string.format(
              "#!/bin/sh\nprintf 'BIN=luajit ARGS=%%s\\n' \"$*\" >>%q\n"
                .. 'if [ "$2" = "compare" ]; then exit 7; fi\n'
                .. "exit 0\n",
              calls_log
            )
          )
          assert.are.same(
            0,
            os.execute(string.format("chmod +x %q", ko_dir .. "/luajit"))
          )
          local fail_rc = os.execute(
            string.format(
              "PATH=%q:$PATH sh %q --kual --benchmark >/dev/null 2>&1",
              stub_bin,
              sandbox .. "/koreader.sh"
            )
          )
          assert.is_not.same(0, fail_rc)
          assert.is_nil(readFile(calls_log):find(" show ", 1, true))

          -- Errors from run_benchmark.sh itself (not only VM invocations) are captured in crash.log and backed up
          for entry in lfs.dir(sandbox) do
            if entry:match("^koreader%.crash%.%d+%.log$") then
              os.remove(sandbox .. "/" .. entry)
            end
          end
          assert.are.same(
            0,
            os.execute(
              string.format(
                "chmod -x %q %q",
                ko_dir .. "/luajit",
                ko_dir .. "/lua"
              )
            )
          )
          local missing_vm_rc = os.execute(
            string.format(
              "PATH=%q:$PATH sh %q --kual --benchmark >/dev/null 2>&1",
              stub_bin,
              sandbox .. "/koreader.sh"
            )
          )
          assert.is_not.same(0, missing_vm_rc)
          local crash_log = readFile(ko_dir .. "/crash.log")
          assert.truthy(
            crash_log:find("Neither ./luajit nor ./lua is executable!", 1, true)
          )
          local backup_contents
          for entry in lfs.dir(sandbox) do
            if entry:match("^koreader%.crash%.%d+%.log$") then
              backup_contents = readFile(sandbox .. "/" .. entry)
            end
          end
          assert.is_not_nil(backup_contents)
          assert.truthy(
            backup_contents:find(
              "Neither ./luajit nor ./lua is executable!",
              1,
              true
            )
          )
        end
      )

      it(
        "handles exit code 90 in kindle, kobo, and linux launchers without forwarding reader args",
        function()
          -- 1. Kindle launcher: reader exits 90 -> EIPS notice + sh ./tools/run_benchmark.sh (no args) -> restarts reader (85) -> exits 0
          local k_sandbox, k_dir, k_stub_bin, k_calls_log =
            createSandboxLauncher()
          finally(function()
            os.execute(string.format("rm -rf %q", k_sandbox))
          end)
          local k_state = k_sandbox .. "/reader_ran"
          writeFile(
            k_dir .. "/luajit",
            string.format(
              '#!/bin/sh\nif [ "$1" = "reader.lua" ]; then shift; printf \'KINDLE_READER ARGS=%%s\\n\' "$*" >>%q; '
                .. "if [ ! -f %q ]; then : >%q; exit 90; fi; exit 0; fi\nexit 1\n",
              k_calls_log,
              k_state,
              k_state
            )
          )
          writeFile(
            k_dir .. "/tools/run_benchmark.sh",
            string.format(
              "#!/bin/sh\nprintf 'KINDLE_BENCH ARGS=%%s\\n' \"$*\" >>%q\nexit 0\n",
              k_calls_log
            )
          )
          assert.are.same(
            0,
            os.execute(
              string.format(
                "chmod +x %q && chmod -x %q",
                k_dir .. "/luajit",
                k_dir .. "/tools/run_benchmark.sh"
              )
            )
          )
          local k_rc = os.execute(
            string.format(
              "PATH=%q:$PATH sh %q --kual /sandbox/book.epub >/dev/null 2>&1",
              k_stub_bin,
              k_sandbox .. "/koreader.sh"
            )
          )
          assert.are.same(0, k_rc)
          local k_calls = readFile(k_calls_log)
          assert.are.same(
            "EIPS: Starting KOReader . . .\n"
              .. "KINDLE_READER ARGS=/sandbox/book.epub\n"
              .. "EIPS: Running Lua vs LuaJIT benchmark . . .\n"
              .. "KINDLE_BENCH ARGS=\n"
              .. "KINDLE_READER ARGS=/sandbox/book.epub\n",
            k_calls
          )

          -- 2. Kobo launcher: defines KO_RC_BENCHMARK=90, runs benchmark, sets RESTART without crash banner
          local raw_kobo = readFile(workspace_dir .. "/kobo/koreader.sh")
          local kobo_script = k_sandbox .. "/kobo_koreader.sh"
          writeFile(kobo_script, raw_kobo)
          assert.are.same(
            0,
            os.execute(
              string.format("sh -n %q && dash -n %q", kobo_script, kobo_script)
            )
          )
          assert.truthy(raw_kobo:find("KO_RC_BENCHMARK=90", 1, true))

          local loop_start = assert(
            raw_kobo:find("# List of supported special return codes", 1, true)
          )
          local loop_end = assert(
            raw_kobo:find(
              "\n# If we requested a reboot/shutdown",
              loop_start,
              true
            )
          )
          local kobo_loop = raw_kobo:sub(loop_start, loop_end - 1)
          local kobo_plat = k_sandbox .. "/kobo_plat"
          assert(lfs.mkdir(kobo_plat))
          assert(lfs.mkdir(kobo_plat .. "/tools"))
          local kobo_calls = kobo_plat .. "/calls.log"
          local kobo_state = kobo_plat .. "/reader_ran"
          writeFile(
            kobo_plat .. "/luajit",
            string.format(
              '#!/bin/sh\nif [ "$1" = "reader.lua" ]; then shift; printf \'KOBO_READER ARGS=%%s\\n\' "$*" >>%q; '
                .. "if [ ! -f %q ]; then : >%q; exit 90; fi; exit 0; fi\nexit 1\n",
              kobo_calls,
              kobo_state,
              kobo_state
            )
          )
          writeFile(
            kobo_plat .. "/fbink",
            string.format(
              "#!/bin/sh\nprintf 'KOBO_FBINK ARGS=%%s\\n' \"$*\" >>%q\nexit 0\n",
              kobo_calls
            )
          )
          writeFile(
            kobo_plat .. "/tools/run_benchmark.sh",
            string.format(
              "#!/bin/sh\nprintf 'KOBO_BENCH ARGS=%%s\\n' \"$*\" >>%q\nexit 0\n",
              kobo_calls
            )
          )
          writeFile(
            kobo_plat .. "/test_loop.sh",
            string.format(
              "#!/bin/sh\ncd %q || exit 1\nLUA_BIN=luajit\nALWAYS_ABORT=false\nCRASH_COUNT=0\nCRASH_TS=0\nCRASH_PREV_TS=0\n"
                .. "ko_update_check() { :; }\n"
                .. "ko_do_fbdepth() { printf 'KOBO_FBDEPTH\\n' >>%q; }\n"
                .. "ko_do_dns() { :; }\n%s\n",
              kobo_plat,
              kobo_calls,
              kobo_loop
            )
          )
          assert.are.same(
            0,
            os.execute(
              string.format(
                "chmod +x %q %q %q",
                kobo_plat .. "/luajit",
                kobo_plat .. "/fbink",
                kobo_plat .. "/test_loop.sh"
              )
            )
          )
          local kobo_rc = os.execute(
            string.format(
              "sh %q /mnt/onboard/book.kepub >/dev/null 2>&1",
              kobo_plat .. "/test_loop.sh"
            )
          )
          assert.are.same(0, kobo_rc)
          local kobo_log = readFile(kobo_calls)
          assert.are.same(
            "KOBO_FBDEPTH\n"
              .. "KOBO_READER ARGS=/mnt/onboard/book.kepub\n"
              .. "KOBO_FBINK ARGS=-q -y -5 -pm Running Lua vs LuaJIT benchmark . . .\n"
              .. "KOBO_BENCH ARGS=\n"
              .. "KOBO_FBDEPTH\n"
              .. "KOBO_READER ARGS=/mnt/onboard/book.kepub\n",
            kobo_log
          )

          -- 3. Linux _run.sh: exit 90 runs sh ./tools/run_benchmark.sh without ARGS and restarts with same LUA
          local src_linux_run = workspace_dir .. "/linux/_run.sh"
          assert.are.same(
            0,
            os.execute(string.format("bash -n %q", src_linux_run))
          )
          local l_plat = k_sandbox .. "/linux_plat"
          local l_home = k_sandbox .. "/linux_home"
          assert(lfs.mkdir(l_plat))
          assert(lfs.mkdir(l_plat .. "/tools"))
          assert(lfs.mkdir(l_home))
          assert(lfs.mkdir(l_home .. "/.config"))
          assert(lfs.mkdir(l_home .. "/.config/koreader"))
          writeFile(l_plat .. "/_run.sh", readFile(src_linux_run))
          local l_calls = l_plat .. "/calls.log"
          local l_state = l_plat .. "/reader_ran"
          writeFile(
            l_plat .. "/luajit",
            string.format(
              '#!/bin/sh\nif [ "$1" = "./reader.lua" ]; then shift; printf \'LINUX_READER ARGS=%%s\\n\' "$*" >>%q; '
                .. "if [ ! -f %q ]; then : >%q; exit 90; fi; exit 0; fi\nexit 1\n",
              l_calls,
              l_state,
              l_state
            )
          )
          writeFile(
            l_plat .. "/tools/run_benchmark.sh",
            string.format(
              "#!/bin/sh\nprintf 'LINUX_BENCH ARGS=%%s\\n' \"$*\" >>%q\nexit 0\n",
              l_calls
            )
          )
          assert.are.same(
            0,
            os.execute(
              string.format(
                "chmod +x %q %q",
                l_plat .. "/luajit",
                l_plat .. "/_run.sh"
              )
            )
          )
          os.execute(
            string.format(
              "cd %q && HOME=%q LUA=./luajit bash ./_run.sh %q >/dev/null 2>&1",
              l_plat,
              l_home,
              "/tmp/book.epub"
            )
          )
          assert.are.same(
            "LINUX_READER ARGS=/tmp/book.epub\n"
              .. "LINUX_BENCH ARGS=\n"
              .. "LINUX_READER ARGS=\n",
            readFile(l_calls)
          )
        end
      )
    end
  )
end)
