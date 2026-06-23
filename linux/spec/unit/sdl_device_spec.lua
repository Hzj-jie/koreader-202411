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
            instance = static_thirdparty_instance
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
                    getRawSize = function() return {w = mock_fb_sdl.instance.w, h = mock_fb_sdl.instance.h} end,
                    getSize = function() return {w = mock_fb_sdl.instance.w, h = mock_fb_sdl.instance.h} end,
                    screen_size = {w = o.w or 600, h = o.h or 800},
                    getScreenWidth = function() return mock_fb_sdl.instance.w end,
                    getHWNightmode = stub().returns(false),
                    setNightmode = stub(),
                    getRotationMode = stub().returns(0),
                    setRotationMode = stub(),
                    close = stub(),
                }
                return mock_fb_sdl.instance
            end
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
            end
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
            end
        }
        package.loaded["device/sdl/powerd"] = mock_powerd

        mock_event = {
            new = function(self, name, attributes, ges_attributes)
                return {
                    name = name,
                    attributes = attributes,
                    ges_attributes = ges_attributes,
                }
            end
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
            }
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
            os.getenv.invokes(function(key) return nil end)
            local Device = require("device/sdl/device")
            assert.is.same("Emulator", Device.model)
        end)

        it("returns AppImage when APPIMAGE is set", function()
            os.getenv.invokes(function(key)
                if key == "APPIMAGE" then return "/path/to/appimage" end
                return nil
            end)
            local Device = require("device/sdl/device")
            assert.is.same("AppImage", Device.model)
        end)

        it("returns Flatpak when FLATPAK is set", function()
            os.getenv.invokes(function(key)
                if key == "FLATPAK" then return "1" end
                return nil
            end)
            local Device = require("device/sdl/device")
            assert.is.same("Flatpak", Device.model)
        end)

        it("returns UbuntuTouch when UBUNTU_APPLICATION_ISOLATION is set", function()
            os.getenv.invokes(function(key)
                if key == "UBUNTU_APPLICATION_ISOLATION" then return "1" end
                return nil
            end)
            local Device = require("device/sdl/device")
            assert.is.same("UbuntuTouch", Device.model)
        end)
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
                if key == "DISABLE_TOUCH" then return "1" end
                return nil
            end)
            local Device = require("device/sdl/device")
            Device:init()
            assert.is.same(false, Device.isTouchDevice())
            assert.is.same(true, Device.hasSymKey())
        end)

        it("handles EMULATE_READER_FORCE_PORTRAIT", function()
            os.getenv.invokes(function(key)
                if key == "EMULATE_READER_FORCE_PORTRAIT" then return "1" end
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
            os.getenv.invokes(function(key) return nil end)
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
            os.getenv.invokes(function(key) return nil end)
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
                value = { x = 0, y = -1 }
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
                value = { x = 0, y = 1 }
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
                value = "/path/to/dropped_book.epub"
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
                value = "hello"
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
                value = { data1 = 800, data2 = 1000 }
            }

            captured_input_args.handleSdlEv(mock_input.instance, ev_resize)

            assert.spy(mock_fb_sdl.instance.resize).was.called_with(mock_fb_sdl.instance, 800, 1000)
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
                value = { data1 = 150, data2 = 250 }
            }

            captured_input_args.handleSdlEv(mock_input.instance, ev_move)

            assert.is.same(150, Device.window.left)
            assert.is.same(250, Device.window.top)
        end)
    end)
end)
-- luacheck: pop
