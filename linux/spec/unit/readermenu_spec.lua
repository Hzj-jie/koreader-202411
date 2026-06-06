describe("ReaderMenu integration", function()
    local DocumentRegistry, ReaderUI, DocSettings, UIManager, Screen, purgeDir

    setup(function()
        require("commonrequire")
        package.unloadAll()
        local Device = require("device")
        Device.powerd.isChargingHW = function() return false end
        Device.powerd.getCapacityHW = function() return 0 end
        require("document/canvascontext"):init(Device)
        DocumentRegistry = require("document/documentregistry")
        DocSettings = require("docsettings")
        ReaderUI = require("apps/reader/readerui")
        UIManager = require("ui/uimanager")
        Screen = require("device").screen
        purgeDir = require("ffi/util").purgeDir
    end)

    before_each(function()
        UIManager._window_stack = {}
    end)

    after_each(function()
        if ReaderUI and ReaderUI.instance then
            ReaderUI.instance:onClose()
        end
        UIManager._window_stack = {}
    end)

    it("should trigger TouchMenu when tapping the top part of the screen", function()
        local sample_pdf = "spec/front/unit/data/2col.pdf"
        purgeDir(DocSettings:getSidecarDir(sample_pdf))
        os.remove(DocSettings:getHistoryPath(sample_pdf))

        local readerui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument(sample_pdf),
        }

        -- Close any initial loading info/notifications
        while #UIManager._window_stack > 1 do
            UIManager:close(UIManager._window_stack[#UIManager._window_stack].widget)
        end

        assert.is.same(1, #UIManager._window_stack)
        assert.is.same(readerui, UIManager._window_stack[1].widget)

        print("UIManager._input_gestures_disabled:", UIManager._input_gestures_disabled)
        print("readerui touch zones count:", #readerui._ordered_touch_zones)

        -- Simulate tapping at the top of the screen (e.g. x = width / 2, y = 10)
        local Event = require("ui/event")
        local Geom = require("ui/geometry")
        local tap_event = Event:new("Gesture", {
            ges = "tap",
            pos = Geom:new({ x = Screen:getWidth() / 2, y = 10 }),
            time = require("ui/time").monotonic(),
        }):asUserInput()

        UIManager:userInput(tap_event)

        assert.is.same(3, #UIManager._window_stack)

        local menu_container = UIManager._window_stack[3].widget
        local touch_menu = menu_container[1]
        assert.is_not_nil(touch_menu)

        readerui:onExit()
        readerui:onClose()
    end)

    it("should trigger TouchMenu when swiping down from the top part of the screen", function()
        local sample_pdf = "spec/front/unit/data/2col.pdf"
        purgeDir(DocSettings:getSidecarDir(sample_pdf))
        os.remove(DocSettings:getHistoryPath(sample_pdf))

        local readerui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument(sample_pdf),
        }

        -- Close any initial loading info/notifications
        while #UIManager._window_stack > 1 do
            UIManager:close(UIManager._window_stack[#UIManager._window_stack].widget)
        end

        assert.is.same(1, #UIManager._window_stack)

        -- Simulate swiping down (direction = south) starting near the top of the screen
        local Event = require("ui/event")
        local Geom = require("ui/geometry")
        local swipe_event = Event:new("Gesture", {
            ges = "swipe",
            direction = "south",
            pos = Geom:new({ x = Screen:getWidth() / 2, y = 10 }),
            time = require("ui/time").monotonic(),
            distance = 0,
        }):asUserInput()

        UIManager:userInput(swipe_event)

        assert.is.same(3, #UIManager._window_stack)

        local menu_container = UIManager._window_stack[3].widget
        local touch_menu = menu_container[1]
        assert.is_not_nil(touch_menu)

        readerui:onExit()
        readerui:onClose()
    end)
end)
