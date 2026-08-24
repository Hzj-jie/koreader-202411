describe("Readerfooter module", function()
  local DocumentRegistry, ReaderUI, ReaderFooter, DocSettings, UIManager
  local purgeDir, Screen, copyFile
  local footer_sample_pdf, footer_sample_epub, footer_sample_txt
  local tapFooterMenu

  local original_os_date = os.date

  local function is_am()
    -- Technically only an issue for 1 digit results from %-H, e.g., anything below 10:00 AM
    return tonumber(os.date("%H")) < 10
  end

  local function get_isolated_file(original_path, test_id)
    local docsettings_dir = DocSettings.getSidecarStorage("dir")
    require("util").makePath(docsettings_dir)
    local ext = original_path:match("%.([^.]+)$")
    local name = original_path:match("([^/]+)%.[^.]+$")
    local isolated_path = docsettings_dir
      .. "/"
      .. name
      .. "_"
      .. test_id
      .. "."
      .. ext
    copyFile(original_path, isolated_path)
    return isolated_path
  end

  local function cleanup_isolated_file(isolated_path)
    purgeDir(DocSettings:getSidecarDir(isolated_path))
    os.remove(DocSettings:getHistoryPath(isolated_path))
    os.remove(isolated_path)
  end

  setup(function()
    -- Mock os.time and os.date to return a fixed 09:00 AM time
    -- to ensure 100% deterministic clock widths regardless of host time/timezone!
    os.time = function()
      return 1700000000
    end
    os.date = function(format, time)
      local t = time or 1700000000
      if format == "%H" then
        return "09"
      elseif format == "%p" then
        return "AM"
      elseif
        format:find("%%%-I")
        or format:find("%%_I")
        or format:find("%%I")
      then
        local res =
          format:gsub("%%%-I", "9"):gsub("%%_I", " 9"):gsub("%%I", "09")
        res = res:gsub("%%M", "00")
        res = res:gsub("%%p", "AM")
        return res
      elseif
        format:find("%%%-H")
        or format:find("%%_H")
        or format:find("%%H")
      then
        local res =
          format:gsub("%%%-H", "9"):gsub("%%_H", " 9"):gsub("%%H", "09")
        res = res:gsub("%%M", "00")
        return res
      end
      return original_os_date(format, t)
    end
    require("commonrequire")
    package.unloadAll()
    local Device = require("device")
    -- Override powerd for running tests on devices with batteries.
    Device.powerd.isChargingHW = function()
      return false
    end
    Device.powerd.getCapacityHW = function()
      return 0
    end
    require("document/canvascontext"):init(Device)
    DocumentRegistry = require("document/documentregistry")
    DocSettings = require("docsettings")
    ReaderUI = require("apps/reader/readerui")
    ReaderFooter = require("apps/reader/modules/readerfooter")
    UIManager = require("ui/uimanager")
    copyFile = require("ffi/util").copyFile
    purgeDir = require("ffi/util").purgeDir
    Screen = require("device").screen

    local DataStorage = require("datastorage")
    footer_sample_pdf = DataStorage:getDataDir() .. "/readerfooter_2col.pdf"
    footer_sample_epub = DataStorage:getDataDir() .. "/readerfooter_juliet.epub"
    footer_sample_txt = DataStorage:getDataDir() .. "/readerfooter_sample.txt"
    copyFile("spec/front/unit/data/2col.pdf", footer_sample_pdf)
    copyFile("spec/front/unit/data/juliet.epub", footer_sample_epub)
    copyFile("spec/front/unit/data/sample.txt", footer_sample_txt)

    function tapFooterMenu(menu_items, menu_title)
      local status_bar = menu_items.status_bar

      if status_bar then
        for _, subitem in ipairs(status_bar.sub_item_table) do
          if subitem.text_func and subitem.text_func() == menu_title then
            subitem.callback()
            return
          end
          if subitem.text == menu_title then
            subitem.callback()
            return
          end
          if subitem.sub_item_table then
            local status_bar_sub_item = subitem.sub_item_table
            for _, sub_subitem in ipairs(status_bar_sub_item) do
              if
                sub_subitem.text_func
                and sub_subitem.text_func() == menu_title
              then
                sub_subitem.callback()
                return
              end
              if sub_subitem.text == menu_title then
                sub_subitem.callback()
                return
              end
            end
          end
        end
        error('Menu item not found: "' .. menu_title .. '"!')
      end
      error('Menu item not found: "Status bar"!')
    end
  end)

  teardown(function()
    -- Clean up global settings we played with
    G_reader_settings:delete("reader_footer_mode")
    G_reader_settings:delete("footer")
    G_reader_settings:flush()

    if footer_sample_pdf then
      purgeDir(DocSettings:getSidecarDir(footer_sample_pdf))
      os.remove(DocSettings:getHistoryPath(footer_sample_pdf))
      os.remove(footer_sample_pdf)
    end
    if footer_sample_epub then
      purgeDir(DocSettings:getSidecarDir(footer_sample_epub))
      os.remove(DocSettings:getHistoryPath(footer_sample_epub))
      os.remove(footer_sample_epub)
    end
    if footer_sample_txt then
      purgeDir(DocSettings:getSidecarDir(footer_sample_txt))
      os.remove(DocSettings:getHistoryPath(footer_sample_txt))
      os.remove(footer_sample_txt)
    end
  end)

  before_each(function()
    local settings = {}
    for k, v in pairs(ReaderFooter.default_settings) do
      settings[k] = v
    end
    -- Enforce Battery, the real default is dynamic (Device:hasBattery())
    settings.battery = true
    G_reader_settings:save("footer", settings)

    -- NOTE: Forcefully disable the statistics plugin, as lj-sqlite3 is horribly broken under Busted,
    --       causing it to erratically fail to load, affecting the results of this test...
    G_reader_settings:save("plugins_disabled", {
      statistics = true,
    })
    UIManager:run()
  end)

  after_each(function()
    if ReaderUI and ReaderUI.instance then
      local doc_path = ReaderUI.instance.document
        and ReaderUI.instance.document.file
      if ReaderUI.instance.document then
        ReaderUI.instance:onExit()
      else
        ReaderUI.instance:onClose()
      end
      if doc_path then
        DocSettings:open(doc_path):purge()
        os.remove(DocSettings:getHistoryPath(doc_path))
      end
    end
  end)

  it("should setup footer as visible in all_at_once mode", function()
    G_reader_settings:save("reader_footer_mode", 1)
    local settings = G_reader_settings:read("footer")
    settings.all_at_once = true
    G_reader_settings:save("footer", settings)

    local sample_pdf = footer_sample_pdf
    purgeDir(DocSettings:getSidecarDir(sample_pdf))
    os.remove(DocSettings:getHistoryPath(sample_pdf))

    local readerui = ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(sample_pdf),
    })
    assert.is.same(true, readerui.view.footer_visible)
    G_reader_settings:delete("reader_footer_mode")
    readerui:onExit()
    readerui:onClose()
  end)

  it("should setup footer as visible not in all_at_once", function()
    G_reader_settings:save("reader_footer_mode", 1)
    -- default settings

    local sample_pdf = footer_sample_pdf
    purgeDir(DocSettings:getSidecarDir(sample_pdf))
    os.remove(DocSettings:getHistoryPath(sample_pdf))

    local readerui = ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(sample_pdf),
    })
    assert.is.same(true, readerui.view.footer_visible)
    assert.is.same(1, readerui.view.footer.mode, 1)
    G_reader_settings:delete("reader_footer_mode")
    readerui:onExit()
    readerui:onClose()
  end)

  it("should setup footer as invisible in full screen mode", function()
    G_reader_settings:save("reader_footer_mode", 1)
    -- default settings

    local isolated_pdf = get_isolated_file(footer_sample_pdf, "test3")

    local cfg = DocSettings:open(isolated_pdf)
    cfg:save("kopt_full_screen", 0)
    cfg:flush()

    local readerui = ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(isolated_pdf),
    })
    assert.is.same(false, readerui.view.footer_visible)
    G_reader_settings:delete("reader_footer_mode")
    readerui:onExit()
    readerui:onClose()

    cleanup_isolated_file(isolated_pdf)
  end)

  it("should setup footer as visible in mini progress bar mode", function()
    G_reader_settings:save("reader_footer_mode", 1)
    -- default settings

    local isolated_pdf = get_isolated_file(footer_sample_pdf, "test4")

    local cfg = DocSettings:open(isolated_pdf)
    cfg:delete("kopt_full_screen")
    cfg:flush()

    local readerui = ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(isolated_pdf),
    })
    assert.is.same(true, readerui.view.footer_visible)
    G_reader_settings:delete("reader_footer_mode")
    readerui:onExit()
    readerui:onClose()

    cleanup_isolated_file(isolated_pdf)
  end)

  it("should setup footer as invisible", function()
    G_reader_settings:save("reader_footer_mode", 1)
    -- default settings

    local isolated_epub = get_isolated_file(footer_sample_epub, "test5")

    local cfg = DocSettings:open(isolated_epub)
    cfg:save("copt_status_line", 1)
    cfg:flush()

    local readerui = ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(isolated_epub),
    })
    assert.is.same(true, readerui.view.footer_visible)
    G_reader_settings:delete("reader_footer_mode")
    readerui:onExit()
    readerui:onClose()

    cleanup_isolated_file(isolated_epub)
  end)

  it("should setup footer for epub without error", function()
    local settings = G_reader_settings:read("footer")
    settings.all_at_once = true
    G_reader_settings:save("footer", settings)

    local sample_epub = footer_sample_epub
    purgeDir(DocSettings:getSidecarDir(sample_epub))
    os.remove(DocSettings:getHistoryPath(sample_epub))

    local readerui = ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(sample_epub),
    })
    local footer = readerui.view.footer
    footer:onPageUpdate(1)
    footer:onUpdateFooter()
    local timeinfo = footer.textGeneratorMap.time(footer)
    local page_count = readerui.document:getPageCount()
    -- c.f., NOTE above, Statistics are disabled, hence the N/A results
    assert.are.same(
      "1 / "
        .. page_count
        .. " | "
        .. timeinfo
        .. " | ⇒ 0 | 0% | ⤠ 0% | ⏳ N/A | ⤻ N/A",
      footer.footer_text.text
    )
    readerui:onExit()
    readerui:onClose()
  end)

  it("should setup footer for pdf without error", function()
    local settings = G_reader_settings:read("footer")
    settings.all_at_once = true
    G_reader_settings:save("footer", settings)

    local sample_pdf = footer_sample_pdf
    purgeDir(DocSettings:getSidecarDir(sample_pdf))
    os.remove(DocSettings:getHistoryPath(sample_pdf))

    local readerui = ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(sample_pdf),
    })
    local footer = readerui.view.footer
    readerui.view.footer:onUpdateFooter()
    local timeinfo = readerui.view.footer.textGeneratorMap.time(footer)
    assert.are.same(
      "1 / 2 | " .. timeinfo .. " | ⇒ 1 | 0% | ⤠ 50% | ⏳ N/A | ⤻ N/A",
      readerui.view.footer.footer_text.text
    )
    readerui:onExit()
    readerui:onClose()
  end)

  it("should switch between different modes", function()
    local settings = G_reader_settings:read("footer")
    settings.all_at_once = true
    G_reader_settings:save("footer", settings)

    local sample_pdf = footer_sample_pdf
    purgeDir(DocSettings:getSidecarDir(sample_pdf))
    os.remove(DocSettings:getHistoryPath(sample_pdf))

    local readerui = ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(sample_pdf),
    })
    local fake_menu = { setting = {} }
    local footer = readerui.view.footer
    footer:addToMainMenu(fake_menu)
    footer:resetLayout()
    footer:onUpdateFooter()
    local timeinfo = footer.textGeneratorMap.time(footer)
    assert.are.same(
      "1 / 2 | " .. timeinfo .. " | ⇒ 1 | 0% | ⤠ 50% | ⏳ N/A | ⤻ N/A",
      footer.footer_text.text
    )

    -- disable show all at once, page progress should be on the first
    tapFooterMenu(fake_menu, "Show all selected items at once")
    assert.are.same("1 / 2", footer.footer_text.text)

    -- disable page progress, time should follow
    tapFooterMenu(fake_menu, "Current page" .. " (/)")
    assert.are.same(timeinfo, footer.footer_text.text)

    -- disable time, page left should follow
    tapFooterMenu(fake_menu, "Current time" .. " (⌚)")
    assert.are.same("⇒ 1", footer.footer_text.text)

    -- disable page left, battery should follow
    tapFooterMenu(fake_menu, "Pages left in chapter" .. " (⇒)")
    assert.are.same("0%", footer.footer_text.text)

    -- disable battery, percentage should follow
    tapFooterMenu(fake_menu, "Battery percentage" .. " ()")
    assert.are.same("⤠ 50%", footer.footer_text.text)

    -- disable percentage, book time to read should follow
    tapFooterMenu(fake_menu, "Progress percentage" .. " (⤠)")
    assert.are.same("⏳ N/A", footer.footer_text.text)

    -- disable book time to read, chapter time to read should follow
    tapFooterMenu(fake_menu, "Time left to finish book" .. " (⏳)")
    assert.are.same("⤻ N/A", footer.footer_text.text)

    -- disable chapter time to read, text should be empty
    tapFooterMenu(fake_menu, "Time left to finish chapter" .. " (⤻)")
    assert.are.same("", footer.footer_text.text)

    -- re-enable chapter time to read, text should be chapter time to read
    tapFooterMenu(fake_menu, "Time left to finish chapter" .. " (⤻)")
    assert.are.same("⤻ N/A", footer.footer_text.text)
    readerui:onExit()
    readerui:onClose()
  end)

  it("should rotate through different modes", function()
    -- default settings (we'll poke at footer.settings directly post-instantiation)

    local sample_pdf = footer_sample_pdf
    local readerui = ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(sample_pdf),
    })
    local footer = readerui.view.footer
    footer.mode = 0
    footer:TapFooter()
    assert.is.same(1, footer.mode)
    footer:TapFooter()
    -- 2 is pages_left_book, an alternate variant of page_progress, disabled by default (#7047)
    assert.is.same(3, footer.mode)
    footer:TapFooter()
    assert.is.same(4, footer.mode)
    footer:TapFooter()
    assert.is.same(5, footer.mode)
    footer:TapFooter()
    assert.is.same(6, footer.mode)
    footer:TapFooter()
    assert.is.same(7, footer.mode)
    footer:TapFooter()
    assert.is.same(8, footer.mode)
    footer:TapFooter()
    assert.is.same(0, footer.mode)

    footer.settings.all_at_once = true
    footer:_updateFooterTextGenerator()
    footer.mode = 5
    footer:TapFooter()
    assert.is.same(0, footer.mode)
    footer:TapFooter()
    assert.is.same(1, footer.mode)
    footer:TapFooter()
    assert.is.same(0, footer.mode)
    -- Make it visible again to make the following tests behave...
    footer:TapFooter()
    assert.is.same(1, footer.mode)
    readerui:onExit()
    readerui:onClose()
  end)

  it("should pick up screen resize in resetLayout", function()
    local settings = G_reader_settings:read("footer")
    settings.all_at_once = true
    G_reader_settings:save("footer", settings)

    local sample_pdf = footer_sample_pdf
    purgeDir(DocSettings:getSidecarDir(sample_pdf))
    os.remove(DocSettings:getHistoryPath(sample_pdf))

    local readerui = ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(sample_pdf),
    })
    local footer = readerui.view.footer
    local horizontal_margin = Screen:scaleBySize(10) * 2
    footer:onUpdateFooter()
    -- Account for trimming of the leading 0 in the AM
    local expected = is_am() and 362 or 370
    assert.is.same(expected, footer.text_width)
    assert.is.same(
      600,
      footer.progress_bar.width + footer.text_width + horizontal_margin
    )
    expected = is_am() and 218 or 210
    assert.is.same(expected, footer.progress_bar.width)

    local old_screen_getwidth = Screen.getWidth
    Screen.getWidth = function()
      return 900
    end
    local new_horizontal_margin = Screen:scaleBySize(10) * 2
    footer:resetLayout()
    expected = is_am() and 362 or 370
    assert.is.same(expected, footer.text_width)
    assert.is.same(
      900,
      footer.progress_bar.width + footer.text_width + new_horizontal_margin
    )
    expected = (is_am() and 518 or 510)
      - (new_horizontal_margin - horizontal_margin)
    assert.is.same(expected, footer.progress_bar.width)
    Screen.getWidth = old_screen_getwidth
    readerui:onExit()
    readerui:onClose()
  end)

  it("should update width on PosUpdate event", function()
    local settings = G_reader_settings:read("footer")
    settings.all_at_once = true
    G_reader_settings:save("footer", settings)

    local sample_epub = footer_sample_epub
    purgeDir(DocSettings:getSidecarDir(sample_epub))
    os.remove(DocSettings:getHistoryPath(sample_epub))

    local readerui = ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(sample_epub),
    })
    local footer = readerui.view.footer
    footer:onPageUpdate(1)
    local expected = is_am() and 210 or 202
    assert.are.same(expected, footer.progress_bar.width)
    expected = is_am() and 370 or 378
    assert.are.same(expected, footer.text_width)

    footer:onPageUpdate(100)
    expected = is_am() and 186 or 178
    assert.are.same(expected, footer.progress_bar.width)
    expected = is_am() and 394 or 402
    assert.are.same(expected, footer.text_width)
    readerui:onExit()
    readerui:onClose()
  end)

  it("should support chapter markers", function()
    -- default settings (we'll poke at footer.settings directly post-instantiation)

    local sample_epub = footer_sample_epub
    purgeDir(DocSettings:getSidecarDir(sample_epub))
    os.remove(DocSettings:getHistoryPath(sample_epub))

    local readerui = ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(sample_epub),
    })
    local footer = readerui.view.footer
    footer:onPageUpdate(1)
    local page_count = readerui.document:getPageCount()
    assert.are.same(28, #footer.progress_bar.ticks)
    assert.are.same(page_count, footer.progress_bar.last)

    -- test toggle TOC markers
    footer.settings.toc_markers = false
    footer:setTocMarkers()
    assert.are.same(nil, footer.progress_bar.ticks)
    readerui:onExit()
    readerui:onClose()
  end)

  it(
    "should support toggle footer through menu if tap zone is disabled",
    function()
      local DTAP_ZONE_MINIBAR = G_defaults:read("DTAP_ZONE_MINIBAR")
      DTAP_ZONE_MINIBAR.w = 0
      DTAP_ZONE_MINIBAR.h = 0
      G_defaults:save("DTAP_ZONE_MINIBAR", DTAP_ZONE_MINIBAR)

      local sample_pdf = footer_sample_pdf
      purgeDir(DocSettings:getSidecarDir(sample_pdf))
      os.remove(DocSettings:getHistoryPath(sample_pdf))
      UIManager:quit()

      assert.are.same(0, #UIManager._task_queue)

      G_reader_settings:save("reader_footer_mode", 1)
      -- default settings

      local readerui = ReaderUI:new({
        dimen = Screen:getSize(),
        document = DocumentRegistry:openDocument(sample_pdf),
      })
      local footer = readerui.view.footer
      local fake_menu = { setting = {} }
      footer:addToMainMenu(fake_menu)

      local has_toggle_menu = false

      if fake_menu.status_bar then
        for _, subitem in ipairs(fake_menu.status_bar.sub_item_table) do
          if subitem.text == "Toggle mode" then
            has_toggle_menu = true
            break
          end
        end
      end

      assert.is.truthy(has_toggle_menu)

      assert.is.same(1, footer.mode)
      tapFooterMenu(fake_menu, "Toggle mode")
      assert.is.same(3, footer.mode)

      G_defaults:delete("DTAP_ZONE_MINIBAR")
      readerui:onExit()
      readerui:onClose()
    end
  )

  it(
    "should remove and add modes to footer text in all_at_once mode",
    function()
      local sample_pdf = footer_sample_pdf
      purgeDir(DocSettings:getSidecarDir(sample_pdf))
      os.remove(DocSettings:getHistoryPath(sample_pdf))
      UIManager:quit()

      assert.are.same(0, #UIManager._task_queue)

      local settings = G_reader_settings:read("footer")
      settings.all_at_once = true
      settings.battery = false
      settings.time = false
      settings.percentage = false
      settings.book_time_to_read = false
      settings.chapter_time_to_read = false
      G_reader_settings:save("footer", settings)

      local readerui = ReaderUI:new({
        dimen = Screen:getSize(),
        document = DocumentRegistry:openDocument(sample_pdf),
      })
      local footer = readerui.view.footer
      local fake_menu = { setting = {} }
      footer:addToMainMenu(fake_menu)

      assert.are.same("1 / 2 | ⇒ 1", footer.footer_text.text)

      -- remove mode from footer text
      tapFooterMenu(fake_menu, "Pages left in chapter" .. " (⇒)")
      assert.are.same("1 / 2", footer.footer_text.text)

      -- add mode to footer text
      tapFooterMenu(fake_menu, "Progress percentage" .. " (⤠)")
      assert.are.same("1 / 2 | ⤠ 50%", footer.footer_text.text)
      readerui:onExit()
      readerui:onClose()
    end
  )

  it("should initialize text mode in all_at_once mode", function()
    local sample_pdf = footer_sample_pdf
    purgeDir(DocSettings:getSidecarDir(sample_pdf))
    os.remove(DocSettings:getHistoryPath(sample_pdf))
    UIManager:quit()

    assert.are.same(0, #UIManager._task_queue)

    G_reader_settings:save("reader_footer_mode", 0)
    local settings = G_reader_settings:read("footer")
    settings.all_at_once = true
    G_reader_settings:save("footer", settings)

    local readerui = ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(sample_pdf),
    })
    local footer = readerui.view.footer

    assert.is.truthy(footer.settings.all_at_once)
    assert.is.truthy(0, footer.mode)
    assert.is.falsy(readerui.view.footer_visible)
    readerui:onExit()
    readerui:onClose()
  end)

  it("should support disabling all the modes", function()
    local sample_epub = footer_sample_epub
    purgeDir(DocSettings:getSidecarDir(sample_epub))
    os.remove(DocSettings:getHistoryPath(sample_epub))
    UIManager:quit()

    assert.are.same(0, #UIManager._task_queue)

    local settings = G_reader_settings:read("footer")
    settings.battery = false
    settings.time = false
    settings.page_progress = false
    settings.pages_left = false
    settings.percentage = false
    settings.book_time_to_read = false
    settings.chapter_time_to_read = false
    G_reader_settings:save("footer", settings)

    local readerui = ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(sample_epub),
    })
    local footer = readerui.view.footer
    local fake_menu = { setting = {} }
    footer:addToMainMenu(fake_menu)

    assert.is.same(true, footer.has_no_mode)
    assert.is.same(0, footer.text_width)

    tapFooterMenu(fake_menu, "Progress percentage" .. " (⤠)")
    assert.are.same("⤠ 0%", footer.footer_text.text)
    assert.is.same(false, footer.has_no_mode)
    assert.is.same(
      footer.footer_text:getSize().w + footer.horizontal_margin,
      footer.text_width
    )
    tapFooterMenu(fake_menu, "Progress percentage" .. " (⤠)")
    assert.is.same(true, footer.has_no_mode)

    -- test in all at once mode
    tapFooterMenu(fake_menu, "Progress percentage" .. " (⤠)")
    tapFooterMenu(fake_menu, "Show all selected items at once")
    assert.is.same(false, footer.has_no_mode)
    tapFooterMenu(fake_menu, "Progress percentage" .. " (⤠)")
    assert.is.same(true, footer.has_no_mode)
    tapFooterMenu(fake_menu, "Progress percentage" .. " (⤠)")
    assert.is.same(false, footer.has_no_mode)
    readerui:onExit()
    readerui:onClose()
  end)

  it("should return correct footer height in time mode", function()
    local sample_epub = footer_sample_epub
    purgeDir(DocSettings:getSidecarDir(sample_epub))
    os.remove(DocSettings:getHistoryPath(sample_epub))
    UIManager:quit()

    G_reader_settings:save("reader_footer_mode", 2)
    -- default settings

    local readerui = ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(sample_epub),
    })
    local footer = readerui.view.footer

    assert.falsy(footer.has_no_mode)
    assert.truthy(readerui.view.footer_visible)
    assert.is.same(15, footer:getHeight())
    readerui:onExit()
    readerui:onClose()
  end)

  it(
    "should return correct footer height when all modes are disabled",
    function()
      local sample_epub = footer_sample_epub
      purgeDir(DocSettings:getSidecarDir(sample_epub))
      os.remove(DocSettings:getHistoryPath(sample_epub))
      UIManager:quit()

      G_reader_settings:save("reader_footer_mode", 1)
      local settings = G_reader_settings:read("footer")
      settings.battery = false
      settings.time = false
      settings.page_progress = false
      settings.pages_left = false
      settings.percentage = false
      settings.book_time_to_read = false
      settings.chapter_time_to_read = false
      G_reader_settings:save("footer", settings)

      local readerui = ReaderUI:new({
        dimen = Screen:getSize(),
        document = DocumentRegistry:openDocument(sample_epub),
      })
      local footer = readerui.view.footer

      assert.truthy(footer.has_no_mode)
      assert.truthy(readerui.view.footer_visible)
      assert.is.same(15, footer:getHeight())
      readerui:onExit()
      readerui:onClose()
    end
  )

  it(
    "should disable footer when all modes + progressbar are disabled",
    function()
      local sample_epub = footer_sample_epub
      purgeDir(DocSettings:getSidecarDir(sample_epub))
      os.remove(DocSettings:getHistoryPath(sample_epub))
      UIManager:quit()

      G_reader_settings:save("reader_footer_mode", 1)
      local settings = G_reader_settings:read("footer")
      settings.battery = false
      settings.time = false
      settings.page_progress = false
      settings.pages_left = false
      settings.percentage = false
      settings.book_time_to_read = false
      settings.chapter_time_to_read = false
      settings.disable_progress_bar = true
      G_reader_settings:save("footer", settings)

      local readerui = ReaderUI:new({
        dimen = Screen:getSize(),
        document = DocumentRegistry:openDocument(sample_epub),
      })
      local footer = readerui.view.footer

      assert.truthy(footer.has_no_mode)
      assert.falsy(readerui.view.footer_visible)
      readerui:onExit()
      readerui:onClose()
    end
  )

  --[[ This toggling behaviour has been removed:
    it("should toggle between full and min progress bar for cre documents", function()
        local sample_txt = footer_sample_txt
        local readerui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument(sample_txt),
        }
        local footer = readerui.view.footer

        footer:applyFooterMode(0)
        assert.is.same(0, footer.mode)
        assert.falsy(readerui.view.footer_visible)
        readerui.rolling:onSetStatusLine(1)
        assert.is.same(1, footer.mode)
        assert.truthy(readerui.view.footer_visible)

        footer.mode = 1
        readerui.rolling:onSetStatusLine(1)
        assert.is.same(1, footer.mode)
        assert.truthy(readerui.view.footer_visible)

        readerui.rolling:onSetStatusLine(0)
        assert.is.same(0, footer.mode)
        assert.falsy(readerui.view.footer_visible)
        readerui:onExit()
        readerui:onClose()
    end)
    ]]
  --

  it(
    "should update footer when NetworkStateChanged event is broadcasted",
    function()
      local sample_epub = footer_sample_epub
      local settings = G_reader_settings:read("footer")
      settings.wifi_status = true
      settings.item_prefix = "icons"
      settings.all_at_once = true
      G_reader_settings:save("footer", settings)

      local readerui = ReaderUI:new({
        dimen = Screen:getSize(),
        document = DocumentRegistry:openDocument(sample_epub),
      })
      local footer = readerui.view.footer

      -- Mock NetworkMgr status methods
      local NetworkMgr = require("ui/network/manager")
      local original_isWifiOn = NetworkMgr.isWifiOn
      local original_isConnected = NetworkMgr.isConnected
      local original_isOnline = NetworkMgr.isOnline

      NetworkMgr.isWifiOn = function()
        return false
      end
      NetworkMgr.isConnected = function()
        return false
      end
      NetworkMgr.isOnline = function()
        return false
      end

      -- Force update footer to apply mock initial status
      footer:onUpdateFooter()

      -- Default wifi status should be network_off icon "\u{E71C}"
      assert.truthy(footer.footer_text.text:find("\u{E71C}"))

      -- Now change mock status to online
      NetworkMgr.isWifiOn = function()
        return true
      end
      NetworkMgr.isConnected = function()
        return true
      end
      NetworkMgr.isOnline = function()
        return true
      end

      -- Broadcast NetworkStateChanged event
      UIManager:broadcastEvent("NetworkStateChanged")

      -- Footer text should now contain network_online icon "\u{EC87}"
      assert.truthy(footer.footer_text.text:find("\u{EC87}"))
      assert.falsy(footer.footer_text.text:find("\u{E71C}"))

      -- Restore original NetworkMgr methods
      NetworkMgr.isWifiOn = original_isWifiOn
      NetworkMgr.isConnected = original_isConnected
      NetworkMgr.isOnline = original_isOnline

      readerui:onExit()
      readerui:onClose()
    end
  )

  it("should test frontlight and frontlight_warmth text generators", function()
    local sample_epub = footer_sample_epub
    purgeDir(DocSettings:getSidecarDir(sample_epub))
    os.remove(DocSettings:getHistoryPath(sample_epub))

    local readerui = ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(sample_epub),
    })
    local footer = readerui.view.footer
    local Device = require("device")
    local powerd = Device:getPowerDevice()

    local orig_isFrontlightOn = powerd.isFrontlightOn
    local orig_frontlightIntensity = powerd.frontlightIntensity
    local orig_frontlightWarmth = powerd.frontlightWarmth

    powerd.isFrontlightOn = function()
      return true
    end
    powerd.frontlightIntensity = function()
      return 50
    end
    powerd.frontlightWarmth = function()
      return 75
    end

    footer.settings.item_prefix = "icons"
    assert.is.same("☼ 50", footer.textGeneratorMap.frontlight(footer))
    assert.is.same(
      "💡 75%",
      footer.textGeneratorMap.frontlight_warmth(footer)
    )

    -- Off state with hide_empty_generators
    powerd.isFrontlightOn = function()
      return false
    end
    footer.settings.all_at_once = true
    footer.settings.hide_empty_generators = true
    assert.is.same("", footer.textGeneratorMap.frontlight(footer))
    assert.is.same("", footer.textGeneratorMap.frontlight_warmth(footer))

    powerd.isFrontlightOn = orig_isFrontlightOn
    powerd.frontlightIntensity = orig_frontlightIntensity
    powerd.frontlightWarmth = orig_frontlightWarmth
    readerui:onExit()
    readerui:onClose()
  end)

  it("should test page_turning_inverted generator and symbols", function()
    local sample_epub = footer_sample_epub
    purgeDir(DocSettings:getSidecarDir(sample_epub))
    os.remove(DocSettings:getHistoryPath(sample_epub))

    local readerui = ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(sample_epub),
    })
    local footer = readerui.view.footer
    G_reader_settings:save("input_invert_page_turn_keys", true)

    footer.settings.item_prefix = "icons"
    assert.is.same("⇄", footer.textGeneratorMap.page_turning_inverted(footer))

    footer.settings.item_prefix = "letters"
    assert.truthy(
      footer.textGeneratorMap.page_turning_inverted(footer):find("On")
    )

    G_reader_settings:delete("input_invert_page_turn_keys")
    footer.settings.item_prefix = "icons"
    assert.is.same("⇉", footer.textGeneratorMap.page_turning_inverted(footer))

    readerui:onExit()
    readerui:onClose()
  end)

  it("should test book metadata and getFittedText", function()
    local sample_epub = footer_sample_epub
    purgeDir(DocSettings:getSidecarDir(sample_epub))
    os.remove(DocSettings:getHistoryPath(sample_epub))

    local readerui = ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(sample_epub),
    })
    local footer = readerui.view.footer
    readerui.doc_props = {
      display_title = "A Very Long Title That Will Be Fitted To The Max Width Percent",
      authors = "Author Name",
    }
    footer.settings.book_title_max_width_pct = 10
    local fitted_title = footer.textGeneratorMap.book_title(footer)
    assert.truthy(fitted_title ~= "")

    local fitted_author = footer.textGeneratorMap.book_author(footer)
    assert.truthy(fitted_author ~= "")

    -- Book metadata changed handler
    footer:onBookMetadataChanged({ metadata_key_updated = "title" })
    footer:onBookMetadataChanged({ metadata_key_updated = "authors" })

    readerui:onExit()
    readerui:onClose()
  end)

  it("should test custom_text generator and set_custom_text", function()
    local sample_epub = footer_sample_epub
    purgeDir(DocSettings:getSidecarDir(sample_epub))
    os.remove(DocSettings:getHistoryPath(sample_epub))

    local readerui = ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(sample_epub),
    })
    local footer = readerui.view.footer
    footer.custom_text = "TEST"
    footer.custom_text_repetitions = 2

    local text, merge = footer.textGeneratorMap.custom_text(footer)
    assert.is.same("TESTTEST", text)
    assert.is.same(false, merge)

    footer.custom_text = "   "
    footer.custom_text_repetitions = 1
    text, merge = footer.textGeneratorMap.custom_text(footer)
    assert.is.same("   ", text)
    assert.is.same(true, merge)

    readerui:onExit()
    readerui:onClose()
  end)

  it("should test add and remove additional footer content", function()
    local sample_epub = footer_sample_epub
    purgeDir(DocSettings:getSidecarDir(sample_epub))
    os.remove(DocSettings:getHistoryPath(sample_epub))

    local readerui = ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(sample_epub),
    })
    local footer = readerui.view.footer

    local my_content = function()
      return "EXTRA"
    end
    assert.is_true(footer:addAdditionalFooterContent(my_content))
    assert.is_false(footer:addAdditionalFooterContent(my_content))

    assert.is_true(footer:removeAdditionalFooterContent(my_content))
    assert.is_false(footer:removeAdditionalFooterContent(my_content))

    readerui:onExit()
    readerui:onClose()
  end)

  it("should test menu item generators", function()
    local sample_epub = footer_sample_epub
    purgeDir(DocSettings:getSidecarDir(sample_epub))
    os.remove(DocSettings:getHistoryPath(sample_epub))

    local readerui = ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(sample_epub),
    })
    local footer = readerui.view.footer

    -- genItemSymbolsMenuItems
    local icons_item = footer:genItemSymbolsMenuItems("icons")
    assert.is.same(true, icons_item.checked_func())
    icons_item.callback()
    assert.is.same("icons", footer.settings.item_prefix)

    -- genItemSeparatorMenuItems
    local bullet_item = footer:genItemSeparatorMenuItems("bullet")
    assert.is.same(false, bullet_item.checked_func())
    bullet_item.callback()
    assert.is.same("bullet", footer.settings.items_separator)

    -- genAlignmentMenuItems
    local left_align = footer:genAlignmentMenuItems("left")
    left_align.callback()
    assert.is.same("left", footer.settings.align)

    -- genProgressBarChapterMarkerWidthMenuItems
    local thin_marker = footer:genProgressBarChapterMarkerWidthMenuItems(1)
    thin_marker.callback()
    assert.is.same(1, footer.settings.toc_markers_width)

    -- genProgressPercentageFormatMenuItems
    local fmt1 = footer:genProgressPercentageFormatMenuItems("1")
    fmt1.callback()
    assert.is.same("1", footer.settings.progress_pct_format)

    -- genProgressBarPositionMenuItems
    local pos_above = footer:genProgressBarPositionMenuItems("above")
    pos_above.callback()
    assert.is.same("above", footer.settings.progress_bar_position)

    readerui:onExit()
    readerui:onClose()
  end)

  it(
    "should test event handlers onResume, onSetPageHorizMargins, flipping mode",
    function()
      local sample_epub = footer_sample_epub
      purgeDir(DocSettings:getSidecarDir(sample_epub))
      os.remove(DocSettings:getHistoryPath(sample_epub))

      local readerui = ReaderUI:new({
        dimen = Screen:getSize(),
        document = DocumentRegistry:openDocument(sample_epub),
      })
      local footer = readerui.view.footer

      -- onSetPageHorizMargins
      footer.settings.progress_margin = true
      footer:onSetPageHorizMargins({ 20, 20 })
      assert.is.same(20, footer.settings.progress_margin_width)

      -- onTimeFormatChanged
      footer:onTimeFormatChanged()

      -- onSwapPageTurnButtons
      footer.settings.page_turning_inverted = true
      footer:onSwapPageTurnButtons()

      -- onEnterFlippingMode & onExitFlippingMode
      footer:onEnterFlippingMode()
      assert.is.same(footer.mode_list.page_progress, footer.mode)
      footer:onExitFlippingMode()

      -- onResume and onOutOfScreenSaver
      G_reader_settings:save("screensaver_delay", "5m")
      footer:onResume()
      assert.is_true(footer._delayed_screensaver)
      footer:onOutOfScreenSaver()
      assert.is_nil(footer._delayed_screensaver)
      G_reader_settings:delete("screensaver_delay")

      readerui:onExit()
      readerui:onClose()
    end
  )

  it("should handle hold on footer and flipping tap correctly", function()
    local sample_epub = footer_sample_epub
    purgeDir(DocSettings:getSidecarDir(sample_epub))
    os.remove(DocSettings:getHistoryPath(sample_epub))

    local readerui = ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(sample_epub),
    })
    local footer = readerui.view.footer
    local Geom = require("ui/geometry")

    -- Hold footer when skim_widget_on_hold is false
    footer.settings.skim_widget_on_hold = false
    assert.is_nil(footer:onHoldFooter({ pos = Geom:new({ x = 10, y = 10 }) }))

    -- Hold footer when skim_widget_on_hold is true but outside footer dimen
    footer.settings.skim_widget_on_hold = true
    footer.footer_content.dimen = Geom:new({ x = 0, y = 500, w = 600, h = 100 })
    assert.is_nil(footer:onHoldFooter({ pos = Geom:new({ x = 10, y = 10 }) }))

    -- Hold footer within footer dimen
    local broadcasted_event = nil
    local orig_broadcast = UIManager.broadcastEvent
    UIManager.broadcastEvent = function(self_ui, ev)
      broadcasted_event = ev
    end
    assert.is_true(footer:onHoldFooter({ pos = Geom:new({ x = 50, y = 550 }) }))
    assert.is_truthy(broadcasted_event)
    assert.is.same(
      "ShowSkimtoDialog",
      broadcasted_event.handler:gsub("^on", "")
    )
    UIManager.broadcastEvent = orig_broadcast

    -- TapFooter when locked
    footer.settings.lock_tap = true
    assert.is_nil(footer:TapFooter())
    footer.settings.lock_tap = false

    -- TapFooter in flipping mode
    readerui.view.flipping_visible = true
    footer.progress_bar.dimen = Geom:new({ x = 100, y = 500, w = 400, h = 20 })
    local goto_pct = nil
    orig_broadcast = UIManager.broadcastEvent
    UIManager.broadcastEvent = function(self_ui, ev)
      if ev.handler == "onGotoPercentage" then
        goto_pct = ev.args[1]
      end
    end
    assert.is_true(footer:TapFooter({ pos = Geom:new({ x = 300, y = 510 }) }))
    assert.is.same(0.5, goto_pct)
    UIManager.broadcastEvent = orig_broadcast
    readerui.view.flipping_visible = false

    readerui:onExit()
    readerui:onClose()
  end)

  it("should handle chapter progress bar and separators", function()
    local sample_epub = footer_sample_epub
    purgeDir(DocSettings:getSidecarDir(sample_epub))
    os.remove(DocSettings:getHistoryPath(sample_epub))

    local readerui = ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(sample_epub),
    })
    local footer = readerui.view.footer

    -- onToggleChapterProgressBar
    footer.settings.chapter_progress_bar = false
    footer:onToggleChapterProgressBar()
    assert.is_true(footer.settings.chapter_progress_bar)
    footer:onToggleChapterProgressBar()
    assert.is_false(footer.settings.chapter_progress_bar)

    -- genSeparator
    footer.settings.items_separator = "bar"
    assert.is.same(" | ", footer:genSeparator())
    footer.settings.items_separator = "bullet"
    assert.is.same(" • ", footer:genSeparator())
    footer.settings.items_separator = "dot"
    assert.is.same(" · ", footer:genSeparator())
    footer.settings.items_separator = "none"
    footer.settings.item_prefix = "icons"
    assert.is.same("  ", footer:genSeparator())
    footer.settings.item_prefix = "compact_items"
    assert.is.same(" ", footer:genSeparator())

    -- onTocReset, onTimesChange_1M, onSetDimensions, onClose
    footer:onTocReset()
    footer.settings.time = true
    footer:onTimesChange_1M()
    footer:onSetDimensions()

    readerui:onExit()
    readerui:onClose()
  end)
end)
