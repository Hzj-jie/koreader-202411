describe("BookMapWidget callbacks", function()
    local BookMapWidget, Font, UIManager
    local mock_ui

    setup(function()
        require("commonrequire")
        BookMapWidget = require("ui/widget/bookmapwidget")
        Font = require("ui/font")
        UIManager = require("ui/uimanager")

        mock_ui = {
            view = {
                shouldInvertBiDiLayoutMirroring = function() return false end,
            },
            document = {
                getPageCount = function() return 100 end,
                getPageMap = function() end,
                hasHiddenFlows = function() return false end,
                flows = {},
            },
            toc = {
                pageno = 1,
                toc_depth = 1,
                fillToc = function() end,
                toc_items_per_page_default = 10,
                toc = {},
            },
            bookmark = {
                getBookmarkedPages = function() return {} end,
            },
            doc_settings = {
                isTrue = function() return false end,
                read = function() return nil end,
            },
            handmade = {
                isHandmadeTocEnabled = function() return false end,
            },
            link = {
                getPreviousLocationPages = function() return {} end,
                addCurrentLocationToStack = function() end,
            },
        }
    end)

    it("should trigger on_exit callback when onExit is called", function()
        local exit_called = false
        local bm = BookMapWidget:new({
            ui = mock_ui,
            on_exit = function(close_all)
                exit_called = true
            end,
        })

        -- Stub UIManager.close since we don't need to close windows
        local original_close = UIManager.close
        UIManager.close = function() end

        bm:onExit(true)
        assert.is_true(exit_called)

        UIManager.close = original_close
    end)

    it("should trigger on_update callback when exiting after editable stuff was edited", function()
        local update_called = false
        local bm = BookMapWidget:new({
            ui = mock_ui,
            on_update = function()
                update_called = true
            end,
        })

        -- Stub UIManager.close since we don't need to close windows
        local original_close = UIManager.close
        UIManager.close = function() end

        bm:updateEditableStuff(true)
        bm:onExit(false)
        assert.is_true(update_called)

        UIManager.close = original_close
    end)
end)

describe("BookMapWidget ReaderUI Integration", function()
    local DataStorage, DocumentRegistry, ReaderUI, UIManager, Screen, DocSettings, Util, BookMapWidget, PageBrowserWidget
    local sample_epub

    setup(function()
        require("commonrequire")
        DataStorage = require("datastorage")
        DocSettings = require("docsettings")
        DocumentRegistry = require("document/documentregistry")
        ReaderUI = require("apps/reader/readerui")
        UIManager = require("ui/uimanager")
        Screen = require("device").screen
        Util = require("ffi/util")
        BookMapWidget = require("ui/widget/bookmapwidget")
        PageBrowserWidget = require("ui/widget/pagebrowserwidget")

        sample_epub = "spec/front/unit/data/juliet.epub"
    end)

    it("should allow showing BookMap and transitioning to PageBrowser", function()
        DocSettings:open(sample_epub):purge()
        local readerui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument(sample_epub),
        }
        readerui.status.enabled = false

        -- Initially, the topmost widget on the stack is ReaderUI
        assert.truthy(UIManager:isWindowWidget(readerui))

        -- 1. Show BookMap
        readerui.thumbnail:onShowBookMap()
        -- 1. Show BookMap
        readerui.thumbnail:onShowBookMap()
        local bookmap
        for i = #UIManager._window_stack, 1, -1 do
            local w = UIManager._window_stack[i].widget
            if getmetatable(w) == BookMapWidget then
                bookmap = w
                break
            end
        end
        assert.truthy(bookmap)

        -- Verify it does NOT have on_exit or on_update callbacks because it was opened from ReaderThumbnail
        assert.falsy(bookmap.on_exit)
        assert.falsy(bookmap.on_update)
        assert.truthy(bookmap.on_root_exit)

        -- Mock getVGroupRowAtY and getPageAtX to bypass coordinate calculations
        bookmap.getVGroupRowAtY = function()
            return {
                start_page = 10,
                getPageAtX = function() return 10 end,
            }
        end

        -- Ensure tap to page browser is enabled
        local original_settings_nilOrTrue = G_reader_settings.nilOrTrue
        G_reader_settings.nilOrTrue = function() return true end

        -- Tap to open PageBrowser
        local Geom = require("ui/geometry")
        bookmap:onTap(nil, { pos = Geom:new({ x = 100, y = 100 }) })

        local pagebrowser
        for i = #UIManager._window_stack, 1, -1 do
            local w = UIManager._window_stack[i].widget
            if getmetatable(w) == PageBrowserWidget then
                pagebrowser = w
                break
            end
        end
        assert.truthy(pagebrowser)

        -- Verify it HAS on_exit and on_update callbacks because it was opened from BookMap!
        assert.truthy(pagebrowser.on_exit)
        assert.truthy(pagebrowser.on_update)

        -- 3. Close PageBrowser
        -- We expect PageBrowser to exit and return back to BookMap
        pagebrowser:onExit(false)

        -- BookMap should still be in the stack
        local found_bookmap = false
        for i = #UIManager._window_stack, 1, -1 do
            local w = UIManager._window_stack[i].widget
            if getmetatable(w) == BookMapWidget then
                found_bookmap = true
                break
            end
        end
        assert.is_true(found_bookmap)

        -- Restore settings mock
        G_reader_settings.nilOrTrue = original_settings_nilOrTrue

        -- Clean up
        UIManager:close(bookmap)
        UIManager:close(readerui)
        UIManager:quit()
    end)
end)
