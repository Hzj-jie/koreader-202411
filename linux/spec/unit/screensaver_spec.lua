local stub = require("luassert.stub")

describe("Screensaver module", function()
  local Screensaver, Device, Screen, UIManager, DocSettings, DocumentRegistry

  setup(function()
    require("commonrequire")
    package.unloadAll()
    local dev = require("device")
    require("document/canvascontext"):init(dev)

    Screensaver = require("ui/screensaver")
    Device = require("device")
    Screen = require("device").screen
    UIManager = require("ui/uimanager")
    DocSettings = require("docsettings")
    DocumentRegistry = require("document/documentregistry")
  end)

  it("should calculate average time for pages", function()
    local old_getAvg = Screensaver.getAvgTimePerPage
    Screensaver.getAvgTimePerPage = function() return 60 end

    local sec = Screensaver:_calcAverageTimeForPages(5)
    assert.is_not_nil(sec)
    assert.is_string(sec)

    Screensaver.getAvgTimePerPage = function() return nil end
    assert.are_equal("N/A", Screensaver:_calcAverageTimeForPages(5))

    Screensaver.getAvgTimePerPage = old_getAvg
  end)

  it("should expand special tokens with ReaderUI instance and hidden flows", function()
    local ReaderUI = require("apps/reader/readerui")
    local mock_doc = {
      hasHiddenFlows = function() return true end,
      getPageNumberInFlow = function() return 10 end,
      getTotalPagesInFlow = function() return 50 end,
      getPageFlow = function() return 1 end,
    }
    local mock_ui = {
      document = mock_doc,
      view = { state = { page = 10 } },
      toc = { getChapterPagesLeft = function() return 5 end },
      doc_props = {
        display_title = "My Test Book",
        authors = "Test Author",
        series = "Test Series",
        series_index = 2,
      },
    }

    ReaderUI.instance = mock_ui
    G_reader_settings:save("lastfile", "/fake/book.epub")

    local template = "%T by %A (%S) page %c of %t (%p%%), ch_left: %h, doc_left: %H"
    local res = Screensaver:expandSpecial(template, "fallback")
    assert.is_true(res:find("My Test Book") ~= nil)
    assert.is_true(res:find("Test Series #2") ~= nil)

    -- Test non-hidden flows
    mock_doc.hasHiddenFlows = function() return false end
    mock_doc.getPageCount = function() return 100 end
    mock_doc.getTotalPagesLeft = function() return 20 end
    local res2 = Screensaver:expandSpecial(template, "fallback")
    assert.is_true(res2:find("My Test Book") ~= nil)

    ReaderUI.instance = nil
    G_reader_settings:save("lastfile", nil)
  end)

  it("should handle setup with document_cover, bookstatus, and cover exclusions", function()
    local ReaderUI = require("apps/reader/readerui")
    local mock_ui = {
      doc_settings = {
        isTrue = function(_, key) return key == "exclude_screensaver" end,
        nilOrFalse = function(_, key) return false end,
      },
    }
    ReaderUI.instance = mock_ui

    -- Cover excluded -> falls back to random_image
    G_reader_settings:save("screensaver_type", "cover")
    G_reader_settings:save("lastfile", "/fake/book.epub")
    Screensaver:setup()
    assert.are_equal("random_image", Screensaver.screensaver_type)

    -- Bookstatus excluded -> falls back to random_image
    G_reader_settings:save("screensaver_type", "bookstatus")
    Screensaver:setup()
    assert.are_equal("random_image", Screensaver.screensaver_type)

    -- Disable excluded -> falls back to random_image
    G_reader_settings:save("screensaver_type", "disable")
    Screensaver:setup()
    assert.are_equal("random_image", Screensaver.screensaver_type)

    -- Document cover
    G_reader_settings:save("screensaver_type", "document_cover")
    G_reader_settings:save("screensaver_document_cover", "/fake/cover.jpg")
    mock_ui.doc_settings.isTrue = function() return false end
    Screensaver:setup()
    assert.are_equal("random_image", Screensaver.screensaver_type)

    ReaderUI.instance = nil
    G_reader_settings:save("screensaver_type", nil)
    G_reader_settings:save("lastfile", nil)
    G_reader_settings:save("screensaver_document_cover", nil)
  end)

  it("should handle show with gesture lock, landscape rotation switch, and overlay messages", function()
    local orig_show = UIManager.show
    local orig_close = UIManager.close
    local shown_widgets = {}
    UIManager.show = function(_, w) table.insert(shown_widgets, w) end
    UIManager.close = function(_, w) end

    -- Set touch device and gesture delay
    local orig_isTouch = Device.isTouchDevice
    local orig_hasEink = Device.hasEinkScreen
    Device.isTouchDevice = function() return true end
    Device.hasEinkScreen = function() return true end

    G_reader_settings:save("screensaver_delay", "gesture")
    G_reader_settings:save("screensaver_type", "random_image")
    G_reader_settings:save("screensaver_img_background", "black")
    G_reader_settings:makeTrue("screensaver_show_message")

    -- Landscape orientation switch to upright
    Screen:setRotationMode(Screen.DEVICE_ROTATED_CLOCKWISE) -- 1 (odd -> landscape)
    Screensaver:setup("reboot", "System Rebooting...")
    Screensaver:show()

    assert.is_not_nil(Screensaver.screensaver_widget)
    assert.is_not_nil(Screensaver.screensaver_lock_widget)
    assert.are_equal(Screen.DEVICE_ROTATED_UPRIGHT, Screen:getRotationMode())

    -- Close in gesture mode
    Screensaver:close()

    Screensaver:cleanup()
    assert.is_nil(Screensaver.screensaver_widget)

    Device.isTouchDevice = orig_isTouch
    Device.hasEinkScreen = orig_hasEink
    G_reader_settings:save("screensaver_delay", nil)
    G_reader_settings:save("screensaver_type", nil)
    UIManager.show = orig_show
    UIManager.close = orig_close
  end)

  it("should handle SVG and image auto-rotation in screensaver", function()
    local orig_show = UIManager.show
    UIManager.show = function(_, w) end

    G_reader_settings:save("screensaver_type", "random_image")
    G_reader_settings:makeTrue("screensaver_rotate_auto_for_best_fit")
    Screensaver:setup()

    -- Test with SVG file path
    Screensaver.image_file = "spec/front/unit/data/sample.svg"
    Screensaver:show()
    assert.is_not_nil(Screensaver.screensaver_widget)
    Screensaver:cleanup()

    G_reader_settings:save("screensaver_type", nil)
    G_reader_settings:save("screensaver_rotate_auto_for_best_fit", nil)
    UIManager.show = orig_show
  end)

  it("should test isExcluded and dialog setters", function()
    local orig_show = UIManager.show
    local shown = nil
    UIManager.show = function(_, w) shown = w end

    Screensaver:chooseFile()
    assert.is_not_nil(shown)

    Screensaver:chooseFolder()
    assert.is_not_nil(shown)

    Screensaver:setMessage()
    assert.is_not_nil(shown)

    assert.is_boolean(Screensaver:isExcluded())

    UIManager.show = orig_show
  end)
end)
