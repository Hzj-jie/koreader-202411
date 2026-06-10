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

    it("should switch tabs on swipe left & right on ReaderMenu", function()
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

        local initial_tab = touch_menu.cur_tab
        assert.is_not_nil(initial_tab)
        local page_num = touch_menu.page_num

        -- Swipe left (west) page_num times to go to the next tab
        for i = 1, page_num do
            local center_x = touch_menu.dimen.x + touch_menu.dimen.w / 2
            local center_y = touch_menu.dimen.y + touch_menu.dimen.h / 2
            local swipe_left_event = Event:new("Gesture", {
                ges = "swipe",
                direction = "west",
                pos = Geom:new({ x = center_x, y = center_y }),
                time = require("ui/time").monotonic() + i * 1000,
            }):asUserInput()
            UIManager:userInput(swipe_left_event)
        end

        assert.is.same(3, #UIManager._window_stack)

        local next_tab = touch_menu.cur_tab

        -- Swipe right (east) once to go back to the previous tab (since page reset to 1 on tab switch)
        local center_x = touch_menu.dimen.x + touch_menu.dimen.w / 2
        local center_y = touch_menu.dimen.y + touch_menu.dimen.h / 2
        local swipe_right_event = Event:new("Gesture", {
            ges = "swipe",
            direction = "east",
            pos = Geom:new({ x = center_x, y = center_y }),
            time = require("ui/time").monotonic(),
        }):asUserInput()
        UIManager:userInput(swipe_right_event)

        assert.is.same(3, #UIManager._window_stack)

        local final_tab = touch_menu.cur_tab

        assert.is_not.same(initial_tab, next_tab)
        assert.is.same(initial_tab, final_tab)

        readerui:onExit()
        readerui:onClose()
    end)

    it("should not spawn a new TouchMenu layer when swiping south on top-level TouchMenu", function()
        local sample_pdf = "spec/front/unit/data/2col.pdf"
        purgeDir(DocSettings:getSidecarDir(sample_pdf))
        os.remove(DocSettings:getHistoryPath(sample_pdf))

        local readerui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument(sample_pdf),
        }

        while #UIManager._window_stack > 1 do
            UIManager:close(UIManager._window_stack[#UIManager._window_stack].widget)
        end

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

        local old_activate_menu = G_named_settings.activate_menu
        G_named_settings.activate_menu = function() return "swipe" end
        readerui.menu.activation_menu = "swipe" -- Update the cached value in the readerui menu module

        local center_x = touch_menu.dimen.x + touch_menu.dimen.w / 2
        local center_y = 50 -- Inside DTAP_ZONE_MENU (0 to 100) and inside TouchMenu (0 to 607)
        local swipe_south_event = Event:new("Gesture", {
            ges = "swipe",
            direction = "south",
            pos = Geom:new({ x = center_x, y = center_y }),
            time = require("ui/time").monotonic(),
        }):asUserInput()
        UIManager:userInput(swipe_south_event)

        -- Check that stack size did not grow (it should stay 3, or close the menu to <= 2)
        assert.is_true(#UIManager._window_stack <= 3)

        G_named_settings.activate_menu = old_activate_menu
        readerui:onExit()
        readerui:onClose()
    end)

    it("should close TouchMenu on swipe north", function()
        local sample_pdf = "spec/front/unit/data/2col.pdf"
        purgeDir(DocSettings:getSidecarDir(sample_pdf))
        os.remove(DocSettings:getHistoryPath(sample_pdf))

        local readerui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument(sample_pdf),
        }

        while #UIManager._window_stack > 1 do
            UIManager:close(UIManager._window_stack[#UIManager._window_stack].widget)
        end

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

        -- Swipe north on TouchMenu
        local center_x = touch_menu.dimen.x + touch_menu.dimen.w / 2
        local center_y = touch_menu.dimen.y + touch_menu.dimen.h / 2
        local swipe_north_event = Event:new("Gesture", {
            ges = "swipe",
            direction = "north",
            pos = Geom:new({ x = center_x, y = center_y }),
            time = require("ui/time").monotonic(),
        }):asUserInput()
        UIManager:userInput(swipe_north_event)

        -- We assert 2, because bottom menu (ConfigDialog) is expected to stay open.
        assert.is.same(2, #UIManager._window_stack)

        readerui:onExit()
        readerui:onClose()
    end)

    it("should close TouchMenu on tapping up button", function()
        local sample_pdf = "spec/front/unit/data/2col.pdf"
        purgeDir(DocSettings:getSidecarDir(sample_pdf))
        os.remove(DocSettings:getHistoryPath(sample_pdf))

        local readerui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument(sample_pdf),
        }

        while #UIManager._window_stack > 1 do
            UIManager:close(UIManager._window_stack[#UIManager._window_stack].widget)
        end

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

        -- Force repaint to ensure positions are calculated
        UIManager:forceRepaint()

        -- Find up button
        local up_button = touch_menu.footer[1][1]
        assert.is_not_nil(up_button)

        -- Simulate tap on up button
        local pos = up_button.dimen
        local tap_up_event = Event:new("Gesture", {
            ges = "tap",
            pos = Geom:new({ x = pos.x + pos.w / 2, y = pos.y + pos.h / 2 }),
            time = require("ui/time").monotonic(),
        }):asUserInput()
        UIManager:userInput(tap_up_event)

        -- Menu should be closed, but bottom menu (ConfigDialog) is expected to stay open
        assert.is.same(2, #UIManager._window_stack)

        readerui:onExit()
        readerui:onClose()
    end)

    it("should cycle through multiple tabs on successive swipe west gestures", function()
        local sample_pdf = "spec/front/unit/data/2col.pdf"
        purgeDir(DocSettings:getSidecarDir(sample_pdf))
        os.remove(DocSettings:getHistoryPath(sample_pdf))

        local readerui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument(sample_pdf),
        }

        while #UIManager._window_stack > 1 do
            UIManager:close(UIManager._window_stack[#UIManager._window_stack].widget)
        end

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

        local tabs_visited = {}
        local initial_tab = touch_menu.cur_tab
        tabs_visited[initial_tab] = true

        local current_tab = initial_tab
        -- We try to switch tab 3 times and expect to see 3 different tabs
        for step = 1, 3 do
            local limit = 10
            local count = 0
            local prev_tab = current_tab
            while touch_menu.cur_tab == prev_tab and count < limit do
                local center_x = touch_menu.dimen.x + touch_menu.dimen.w / 2
                local center_y = touch_menu.dimen.y + touch_menu.dimen.h / 2
                local swipe_left_event = Event:new("Gesture", {
                    ges = "swipe",
                    direction = "west",
                    pos = Geom:new({ x = center_x, y = center_y }),
                    time = require("ui/time").monotonic() + (step * 10 + count) * 1000,
                }):asUserInput()
                UIManager:userInput(swipe_left_event)
                count = count + 1
            end
            current_tab = touch_menu.cur_tab
            assert.is_not.same(prev_tab, current_tab)
            assert.is.same(3, #UIManager._window_stack)
            tabs_visited[current_tab] = true
        end

        local visited_count = 0
        for _ in pairs(tabs_visited) do
            visited_count = visited_count + 1
        end
        assert.is_true(visited_count > 1)

        readerui:onExit()
        readerui:onClose()
    end)

    it("should not crash when reloading and swiping menu", function()
        local Event = require("ui/event")
        local Geom = require("ui/geometry")
        local sample_pdf = "spec/front/unit/data/2col.pdf"
        purgeDir(DocSettings:getSidecarDir(sample_pdf))
        os.remove(DocSettings:getHistoryPath(sample_pdf))

        local readerui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument(sample_pdf),
        }

        -- Open TouchMenu (tap top)
        local tap_event = Event:new("Gesture", {
            ges = "tap",
            pos = Geom:new({ x = Screen:getWidth() / 2, y = 10 }),
            time = require("ui/time").monotonic(),
        }):asUserInput()
        UIManager:userInput(tap_event)

        assert.is.same(3, #UIManager._window_stack)

        -- Reload document
        readerui:onReload()
        readerui = ReaderUI.instance

        -- Swipe west
        local swipe_event = Event:new("Gesture", {
            ges = "swipe",
            direction = "west",
            distance = 100,
            pos = Geom:new({ x = Screen:getWidth() / 2, y = Screen:getHeight() / 2 }),
            time = require("ui/time").monotonic() + 1000,
        }):asUserInput()

        UIManager:userInput(swipe_event)

        if readerui then
            readerui:onExit()
            readerui:onClose()
        end
    end)

    it("should not leak menu when switching documents repeatedly", function()
        local Event = require("ui/event")
        local Geom = require("ui/geometry")
        local CenterContainer = require("ui/widget/container/centercontainer")
        local ReadHistory = require("readhistory")

        -- Clear history
        ReadHistory.hist = {}
        ReadHistory:_flush()

        local file1 = "spec/front/unit/data/2col.pdf"
        local file2 = "spec/front/unit/data/paper.pdf"

        purgeDir(DocSettings:getSidecarDir(file1))
        os.remove(DocSettings:getHistoryPath(file1))
        purgeDir(DocSettings:getSidecarDir(file2))
        os.remove(DocSettings:getHistoryPath(file2))

        -- 1. Open file1
        local readerui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument(file1),
        }

        -- 2. Open file2 (file1 goes to history)
        ReaderUI:showReader(file2)
        readerui = ReaderUI.instance

        -- 3. Open menu in file2 reader (tap top)
        local tap_event = Event:new("Gesture", {
            ges = "tap",
            pos = Geom:new({ x = Screen:getWidth() / 2, y = 10 }),
            time = require("ui/time").monotonic(),
        }):asUserInput()
        UIManager:userInput(tap_event)

        -- Check stack: ReaderUI, ConfigDialog, menu_container
        local center_containers = 0
        for i = 1, #UIManager._window_stack do
            if getmetatable(UIManager._window_stack[i].widget) == CenterContainer then
                center_containers = center_containers + 1
            end
        end
        assert.is_true(center_containers == 1)

        -- 4. Go to previous file (file1)
        readerui:onOpenLastDoc()
        readerui = ReaderUI.instance

        -- Check stack: should NOT have stale menu_container
        center_containers = 0
        for i = 1, #UIManager._window_stack do
            if getmetatable(UIManager._window_stack[i].widget) == CenterContainer then
                center_containers = center_containers + 1
            end
        end
        assert.is_true(center_containers == 0)

        -- 5. Open menu in file1 reader
        tap_event.time = require("ui/time").monotonic() + 1000
        UIManager:userInput(tap_event)

        center_containers = 0
        for i = 1, #UIManager._window_stack do
            if getmetatable(UIManager._window_stack[i].widget) == CenterContainer then
                center_containers = center_containers + 1
            end
        end
        assert.is_true(center_containers == 1)

        -- 6. Go to previous file (file2)
        readerui:onOpenLastDoc()
        readerui = ReaderUI.instance

        -- Check stack: should NOT have stale menu
        center_containers = 0
        for i = 1, #UIManager._window_stack do
            if getmetatable(UIManager._window_stack[i].widget) == CenterContainer then
                center_containers = center_containers + 1
            end
        end
        assert.is_true(center_containers == 0)

        -- Cleanup
        if readerui then
            readerui:onExit()
            readerui:onClose()
        end
    end)

    it("should not leak menu when panning south on top while menu is open", function()
        local Event = require("ui/event")
        local sample_pdf = "spec/front/unit/data/2col.pdf"
        purgeDir(DocSettings:getSidecarDir(sample_pdf))
        os.remove(DocSettings:getHistoryPath(sample_pdf))

        local readerui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument(sample_pdf),
        }
        local Geom = require("ui/geometry")
        local CenterContainer = require("ui/widget/container/centercontainer")

        -- Open menu (tap top)
        local tap_event = Event:new("Gesture", {
            ges = "tap",
            pos = Geom:new({ x = Screen:getWidth() / 2, y = 10 }),
            time = require("ui/time").monotonic(),
        }):asUserInput()
        UIManager:userInput(tap_event)

        assert.is.same(3, #UIManager._window_stack)

        -- Pan south (in trigger zone)
        local pan_event = Event:new("Gesture", {
            ges = "pan",
            direction = "south",
            pos = Geom:new({ x = Screen:getWidth() / 2, y = 10 }),
            time = require("ui/time").monotonic() + 1000,
        }):asUserInput()
        UIManager:userInput(pan_event)

        -- Check for duplicate menu_container
        local center_containers = 0
        for i = 1, #UIManager._window_stack do
            local w = UIManager._window_stack[i].widget
            local class = getmetatable(w)
            if class == CenterContainer then
                center_containers = center_containers + 1
            end
        end
        assert.is_true(center_containers < 2)

        if readerui then
            readerui:onExit()
            readerui:onClose()
        end
    end)

    it("should not trigger TouchMenu assertion under normal conditions", function()
        local sample_pdf = "spec/front/unit/data/2col.pdf"
        local readerui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument(sample_pdf),
        }

        -- Show menu once
        assert.has_no.errors(function()
            readerui.menu:_showMenu()
        end)

        -- Close it
        readerui.menu:onCloseReaderMenu()

        -- Show it again
        assert.has_no.errors(function()
            readerui.menu:_showMenu()
        end)

        if readerui then
            readerui:onExit()
            readerui:onClose()
        end
    end)

    it("should trigger TouchMenu assertion when showing multiple instances", function()
        local sample_pdf = "spec/front/unit/data/2col.pdf"
        local readerui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument(sample_pdf),
        }

        -- Show menu once
        readerui.menu:_showMenu()

        -- Show menu twice (without closing first) should assert
        assert.has.errors(function()
            readerui.menu:_showMenu()
        end, "Multiple TouchMenu instances detected!")

        if readerui then
            readerui:onExit()
            readerui:onClose()
        end
    end)
end)
