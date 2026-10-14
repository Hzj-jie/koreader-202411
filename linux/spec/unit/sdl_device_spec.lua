-- luacheck: push ignore
require("commonrequire")

describe("device/sdl/device", function()
  local mock_sdl, mock_thirdparty, mock_fb_sdl, mock_input, mock_powerd
  local mock_event, mock_readerui, mock_filemanager
  local captured_input_args
  local static_thirdparty_instance

  setup(function()
    -- Force unload so they reload with our mocks
    package.unload("device/sdl/device")
    package.unload("device/thirdparty")
    package.unload("ffi/framebuffer_SDL2_0")
    package.unload("device/input")
    package.unload("device/sdl/powerd")

    stub(os, "getenv")
    stub(os, "execute")

    mock_sdl = {
      getPowerInfo = stub(),
      startTextInput = stub(),
      stopTextInput = stub(),
      setWindowFullscreen = stub(),
      getBasePath = stub().returns("/fake/base/path"),
    }
    package.loaded["ffi/SDL2_0"] = mock_sdl

    static_thirdparty_instance = {
      checkMethod = stub(),
    }
    mock_thirdparty = {
      new = function(self, o)
        static_thirdparty_instance.dicts = o.dicts
        static_thirdparty_instance.check = o.check
        return static_thirdparty_instance
      end,
      instance = static_thirdparty_instance,
    }
    package.loaded["device/thirdparty"] = mock_thirdparty

    mock_fb_sdl = {
      new = function(self, o)
        mock_fb_sdl.instance = {
          w = o.w or 600,
          h = o.h or 800,
          setWindowIcon = stub().returns(true),
          resize = stub(),
          setViewport = stub(),
          setupDithering = stub(),
          getRawSize = function()
            return { w = mock_fb_sdl.instance.w, h = mock_fb_sdl.instance.h }
          end,
          getSize = function()
            return { w = mock_fb_sdl.instance.w, h = mock_fb_sdl.instance.h }
          end,
          screen_size = { w = o.w or 600, h = o.h or 800 },
          getScreenWidth = function()
            return mock_fb_sdl.instance.w
          end,
          getHWNightmode = stub().returns(false),
          setNightmode = stub(),
          getRotationMode = stub().returns(0),
          setRotationMode = stub(),
          close = stub(),
        }
        return mock_fb_sdl.instance
      end,
    }
    package.loaded["ffi/framebuffer_SDL2_0"] = mock_fb_sdl

    mock_input = {
      new = function(self, o)
        captured_input_args = o
        mock_input.instance = {
          device = o.device,
          event_map = o.event_map,
          handleSdlEv = o.handleSdlEv,
          gameControllerRumble = stub().returns(false),
          registerEventAdjustHook = stub(),
          adjustTouchSwitchAxesAndMirrorX = "adjustTouchSwitchAxesAndMirrorX",
        }
        return mock_input.instance
      end,
    }
    package.loaded["device/input"] = mock_input

    package.loaded["device/sdl/event_map_sdl2"] = {}
    package.loaded["device/sdl/keyboard_layout"] = {}

    mock_powerd = {
      new = function(self, o)
        return {
          device = o.device,
          beforeSuspend = stub(),
          afterResume = stub(),
        }
      end,
    }
    package.loaded["device/sdl/powerd"] = mock_powerd

    mock_event = {
      new = function(self, name, attributes, ges_attributes)
        return {
          name = name,
          attributes = attributes,
          ges_attributes = ges_attributes,
        }
      end,
    }
    package.loaded["ui/event"] = mock_event

    mock_readerui = {
      showReader = stub(),
    }
    package.loaded["apps/reader/readerui"] = mock_readerui

    mock_filemanager = {
      instance = {
        reinit = stub(),
        path = "/fake/fm/path",
        focused_file = "fake_book.epub",
      },
    }
    package.loaded["apps/filemanager/filemanager"] = mock_filemanager
  end)

  teardown(function()
    os.getenv:revert()
    os.execute:revert()
    package.unload("ffi/SDL2_0")
    package.unload("device/thirdparty")
    package.unload("ffi/framebuffer_SDL2_0")
    package.unload("device/input")
    package.unload("device/sdl/event_map_sdl2")
    package.unload("device/sdl/keyboard_layout")
    package.unload("device/sdl/powerd")
    package.unload("ui/event")
    package.unload("apps/reader/readerui")
    package.unload("apps/filemanager/filemanager")
  end)

  before_each(function()
    G_reader_settings:save("sdl_window", {
      width = 600,
      height = 800,
      left = 10,
      top = 20,
    })
    os.getenv:clear()
    os.execute:clear()
    static_thirdparty_instance.checkMethod:clear()
    captured_input_args = nil
  end)

  after_each(function()
    package.unload("device/sdl/device")
  end)

  describe("device probe", function()
    it("returns Emulator when no environment variables are set", function()
      os.getenv.invokes(function(key)
        return nil
      end)
      local Device = require("device/sdl/device")
      assert.is.same("Emulator", Device.model)
    end)

    it("returns AppImage when APPIMAGE is set", function()
      os.getenv.invokes(function(key)
        if key == "APPIMAGE" then
          return "/path/to/appimage"
        end
        return nil
      end)
      local Device = require("device/sdl/device")
      assert.is.same("AppImage", Device.model)
    end)

    it("returns Flatpak when FLATPAK is set", function()
      os.getenv.invokes(function(key)
        if key == "FLATPAK" then
          return "1"
        end
        return nil
      end)
      local Device = require("device/sdl/device")
      assert.is.same("Flatpak", Device.model)
    end)

    it(
      "returns UbuntuTouch when UBUNTU_APPLICATION_ISOLATION is set",
      function()
        os.getenv.invokes(function(key)
          if key == "UBUNTU_APPLICATION_ISOLATION" then
            return "1"
          end
          return nil
        end)
        local Device = require("device/sdl/device")
        assert.is.same("UbuntuTouch", Device.model)
      end
    )
  end)

  describe("init", function()
    it("handles EMULATE_READER_VIEWPORT", function()
      os.getenv.invokes(function(key)
        if key == "EMULATE_READER_VIEWPORT" then
          return "{x=5,y=10,w=200,h=300}"
        end
        return nil
      end)
      local Device = require("device/sdl/device")
      Device:init()
      assert.is.truthy(Device.viewport)
      assert.is.same(5, Device.viewport.x)
      assert.is.same(10, Device.viewport.y)
      assert.is.same(200, Device.viewport.w)
      assert.is.same(300, Device.viewport.h)
      assert.spy(mock_fb_sdl.instance.setViewport).was.called()
    end)

    it("handles DISABLE_TOUCH", function()
      os.getenv.invokes(function(key)
        if key == "DISABLE_TOUCH" then
          return "1"
        end
        return nil
      end)
      local Device = require("device/sdl/device")
      Device:init()
      assert.is.same(false, Device.isTouchDevice())
      assert.is.same(true, Device.hasSymKey())
    end)

    it("handles EMULATE_READER_FORCE_PORTRAIT", function()
      os.getenv.invokes(function(key)
        if key == "EMULATE_READER_FORCE_PORTRAIT" then
          return "1"
        end
        return nil
      end)
      local Device = require("device/sdl/device")
      Device:init()
      assert.is.same(true, Device.isAlwaysPortrait())
      assert.spy(mock_input.instance.registerEventAdjustHook).was.called()
    end)
  end)

  describe("link and dict lookup", function()
    before_each(function()
      os.getenv.invokes(function(key)
        return nil
      end)
    end)

    it("opens link on Linux with xdg-open", function()
      -- simulate Linux
      local old_os = jit.os
      jit.os = "Linux"

      os.execute.invokes(function(cmd)
        if cmd == "command -v xdg-open >/dev/null" then
          return 0
        elseif cmd == "xdg-open 'http://example.com'" then
          return 0
        end
        return 1
      end)

      local Device = require("device/sdl/device")
      assert.is.same(true, Device:canOpenLink())
      assert.is.same(true, Device:openLink("http://example.com"))

      jit.os = old_os
    end)

    it("performs external dict lookup with goldendict command", function()
      local old_os = jit.os
      jit.os = "Linux"

      os.execute.invokes(function(cmd)
        if cmd == "command -v goldendict >/dev/null" then
          return 0
        elseif cmd == "goldendict word &" then
          return 0
        end
        return 1
      end)

      local Device = require("device/sdl/device")
      static_thirdparty_instance.checkMethod.returns(true, "goldendict")

      local callback_called = false
      Device:doExternalDictLookup("word", "goldendict", function()
        callback_called = true
      end)

      assert.spy(static_thirdparty_instance.checkMethod).was.called()
      local call = static_thirdparty_instance.checkMethod.calls[1]
      assert.is.same("dict", call.vals[2])
      assert.is.same("goldendict", call.vals[3])

      assert.spy(os.execute).was.called_with("goldendict word &")
      assert.is.same(true, callback_called)

      jit.os = old_os
    end)
  end)

  describe("input events", function()
    local mock_uimgr

    before_each(function()
      os.getenv.invokes(function(key)
        return nil
      end)
      mock_uimgr = {
        userInput = stub(),
        broadcastEvent = stub(),
        setDirty = stub(),
      }
    end)

    it("handles SDL_MOUSEWHEEL up/down events", function()
      local Device = require("device/sdl/device")
      Device:UIManagerReady(mock_uimgr)
      Device:init()

      assert.is.truthy(captured_input_args)
      assert.is.truthy(captured_input_args.handleSdlEv)

      -- SDL_MOUSEWHEEL event (down: y = -1)
      local ev_down = {
        code = 1027, -- SDL_MOUSEWHEEL
        time = { sec = 123, usec = 456 },
        value = { x = 0, y = -1 },
      }

      captured_input_args.handleSdlEv(mock_input.instance, ev_down)

      assert.spy(mock_uimgr.userInput).was.called(2)
      local first_call = mock_uimgr.userInput.calls[1]
      local second_call = mock_uimgr.userInput.calls[2]

      assert.is.same("Pan", first_call.vals[2].name)
      assert.is.same("north", first_call.vals[2].ges_attributes.direction)
      assert.is.same("Gesture", second_call.vals[2].name)
      assert.is.same("pan_release", second_call.vals[2].attributes.ges)

      mock_uimgr.userInput:clear()

      -- SDL_MOUSEWHEEL event (up: y = 1)
      local ev_up = {
        code = 1027, -- SDL_MOUSEWHEEL
        time = { sec = 123, usec = 456 },
        value = { x = 0, y = 1 },
      }

      captured_input_args.handleSdlEv(mock_input.instance, ev_up)

      assert.spy(mock_uimgr.userInput).was.called(2)
      first_call = mock_uimgr.userInput.calls[1]
      second_call = mock_uimgr.userInput.calls[2]

      assert.is.same("Pan", first_call.vals[2].name)
      assert.is.same("south", first_call.vals[2].ges_attributes.direction)
      assert.is.same("Gesture", second_call.vals[2].name)
      assert.is.same("pan_release", second_call.vals[2].attributes.ges)
    end)

    it("handles SDL_DROPFILE event", function()
      local Device = require("device/sdl/device")
      Device:UIManagerReady(mock_uimgr)
      Device:init()

      local ev_drop = {
        code = 4096, -- SDL_DROPFILE
        value = "/path/to/dropped_book.epub",
      }

      captured_input_args.handleSdlEv(mock_input.instance, ev_drop)

      assert.spy(mock_readerui.showReader).was.called()
      local call = mock_readerui.showReader.calls[1]
      assert.is.same("/path/to/dropped_book.epub", call.vals[2])
    end)

    it("handles SDL_TEXTINPUT event", function()
      local Device = require("device/sdl/device")
      Device:UIManagerReady(mock_uimgr)
      Device:init()

      local ev_text = {
        code = 771, -- SDL_TEXTINPUT
        value = "hello",
      }

      captured_input_args.handleSdlEv(mock_input.instance, ev_text)

      assert.spy(mock_uimgr.userInput).was.called(1)
      local call = mock_uimgr.userInput.calls[1]
      assert.is.same("TextInput", call.vals[2].name)
      assert.is.same("hello", call.vals[2].attributes)
    end)

    it("handles SDL_WINDOWEVENT_RESIZED event", function()
      local Device = require("device/sdl/device")
      Device:UIManagerReady(mock_uimgr)
      Device:init()

      local ev_resize = {
        code = 5, -- SDL_WINDOWEVENT_RESIZED
        value = { data1 = 800, data2 = 1000 },
      }

      captured_input_args.handleSdlEv(mock_input.instance, ev_resize)

      assert
        .spy(mock_fb_sdl.instance.resize).was
        .called_with(mock_fb_sdl.instance, 800, 1000)
      assert.is.same(800, Device.window.width)
      assert.is.same(1000, Device.window.height)

      assert.spy(mock_uimgr.broadcastEvent).was.called(3)
      -- broadcast events are SetDimensions, ScreenResize, RedrawCurrentPage
      local events = {}
      for _, call in ipairs(mock_uimgr.broadcastEvent.calls) do
        table.insert(events, call.vals[2].name)
      end
      assert.is.truthy(table.concat(events, ", "):find("SetDimensions"))
      assert.is.truthy(table.concat(events, ", "):find("ScreenResize"))
      assert.is.truthy(table.concat(events, ", "):find("RedrawCurrentPage"))

      assert.spy(mock_filemanager.instance.reinit).was.called()
      assert.spy(mock_uimgr.setDirty).was.called_with(mock_uimgr, "all", "ui")
    end)

    it("handles SDL_WINDOWEVENT_MOVED event", function()
      local Device = require("device/sdl/device")
      Device:UIManagerReady(mock_uimgr)
      Device:init()

      local ev_move = {
        code = 4, -- SDL_WINDOWEVENT_MOVED
        value = { data1 = 150, data2 = 250 },
      }

      captured_input_args.handleSdlEv(mock_input.instance, ev_move)

      assert.is.same(150, Device.window.left)
      assert.is.same(250, Device.window.top)
    end)
  end)
end)

describe("SDL device", function()
  local SDL = require("ffi/SDL2_0")
  local SDLDevice = require("device/sdl/device")
  local orig_execute = os.execute
  local orig_set_fullscreen = SDL.setWindowFullscreen
  local fullscreen_mode_set = nil

  before_each(function()
    fullscreen_mode_set = nil
    SDL.setWindowFullscreen = function(mode)
      fullscreen_mode_set = mode
      return true
    end
  end)

  after_each(function()
    os.execute = orig_execute
    SDL.setWindowFullscreen = orig_set_fullscreen
  end)

  describe("properties and capabilities", function()
    it("reports correct capabilities for Emulator", function()
      assert.is_true(SDLDevice:isSDL())
      assert.is_true(SDLDevice:isEmulator())
      assert.is_true(SDLDevice:hasColorScreen())
      assert.is_true(SDLDevice:hasEinkScreen())
      assert.is_false(SDLDevice:isDefaultFullscreen())
      assert.is_true(SDLDevice:supportsScreensaver())
    end)

    it(
      "manages page press pressure and feedback settings on Emulator",
      function()
        SDLDevice:setPagePressPressure(1)
        assert.are.equal(1, SDLDevice:pagePressPressure())

        SDLDevice:setPagePressFeedback(2)
        assert.are.equal(2, SDLDevice:pagePressFeedback())

        assert.has_error(function()
          SDLDevice:setPagePressPressure(5)
        end)
        assert.has_error(function()
          SDLDevice:setPagePressFeedback(5)
        end)
      end
    )
  end)

  describe("setDateTime", function()
    local executed_cmds = {}

    before_each(function()
      executed_cmds = {}
      os.execute = function(cmd)
        table.insert(executed_cmds, cmd)
        return 0
      end
    end)

    it("executes date and hwclock for complete date and time", function()
      local res = SDLDevice:setDateTime(2026, 10, 10, 16, 20, 0)
      assert.is_true(res)
      assert.are.equal("date -s '2026-10-10 16:20:0'", executed_cmds[1])
      assert.are.equal("hwclock -u -w", executed_cmds[2])
    end)

    it("executes date time-only when date parts omitted", function()
      local res = SDLDevice:setDateTime(nil, nil, nil, 8, 30, 0)
      assert.is_true(res)
      assert.are.equal("date -s '8:30'", executed_cmds[1])
      assert.are.equal("hwclock -u -w", executed_cmds[2])
    end)

    it("returns true without executing when hour or min is nil", function()
      local res = SDLDevice:setDateTime(2026, 10, 10, nil, 30, 0)
      assert.is_true(res)
      assert.are.equal(0, #executed_cmds)
    end)
  end)

  describe("toggleFullscreen", function()
    it("toggles fullscreen mode on standard desktop SDL device", function()
      local dev = SDLDevice:extend({
        fullscreen = nil,
      })
      dev:toggleFullscreen()
      assert.is_true(dev.fullscreen)
      assert.is_true(fullscreen_mode_set)

      dev:toggleFullscreen()
      assert.is_false(dev.fullscreen)
    end)
  end)

  describe("openLink", function()
    it("should escape single quotes in link", function()
      -- Link arguments containing single quotes must be properly escaped
      local executed_cmd = nil
      os.execute = function(cmd)
        executed_cmd = cmd
        return 0
      end

      local dev = SDLDevice:extend({
        canOpenLink = function()
          return true, "xdg-open"
        end,
      })

      dev:openLink("https://example.com/path?q=don't")
      assert.is_not_nil(executed_cmd)
      -- If properly escaped, the command should not contain an unescaped single quote
      -- that breaks the shell string. For example, `'https://example.com/path?q=don'\''t'`
      assert.is_nil(
        executed_cmd:match("xdg%-open 'https://example%.com/path%?q=don't'"),
        "single quotes in link should be escaped before passing to shell: "
          .. tostring(executed_cmd)
      )
    end)
  end)
end)

-- luacheck: pop
