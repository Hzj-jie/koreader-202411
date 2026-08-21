describe("Readertoc module", function()
  local DocumentRegistry, ReaderUI, Screen, DEBUG
  local readerui, toc, toc_max_depth, title

  setup(function()
    require("commonrequire")
    DocumentRegistry = require("document/documentregistry")
    ReaderUI = require("apps/reader/readerui")
    Screen = require("device").screen
    DEBUG = require("dbg")

    local DataStorage = require("datastorage")
    local sample_epub = DataStorage:getDataDir() .. "/readertoc_juliet.epub"
    require("ffi/util").copyFile(
      "spec/front/unit/data/juliet.epub",
      sample_epub
    )

    -- Clear settings from previous tests
    local DocSettings = require("docsettings")
    local doc_settings = DocSettings:open(sample_epub)
    doc_settings:close()
    doc_settings:purge()

    readerui = ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(sample_epub),
    })
    -- reset book to first page
    readerui.rolling:onGotoPage(0)
    toc = readerui.toc
  end)

  teardown(function()
    if readerui then
      readerui:onExit()
    end
    local sample_epub = require("datastorage"):getDataDir()
      .. "/readertoc_juliet.epub"
    require("docsettings"):open(sample_epub):purge()
    os.remove(sample_epub)
  end)

  it("should get max toc depth", function()
    toc_max_depth = toc:getMaxDepth()
    assert.are.same(2, toc_max_depth)
  end)
  it("should get toc title from page", function()
    title = toc:getTocTitleByPage(60)
    DEBUG("toc", toc.toc)
    assert.is.equal("SCENE V. A hall in Capulet's house.", title)
    title = toc:getTocTitleByPage(187)
    assert.is.equal("SCENE I. Friar Laurence's cell.", title)
  end)
  describe("getTocTicks API", function()
    local ticks_level_1 = nil
    it("should get ticks of level 1", function()
      ticks_level_1 = toc:getTocTicks(1)
      assert.are.same(7, #ticks_level_1)
    end)
    local ticks_level_2 = nil
    it("should get ticks of level 2", function()
      ticks_level_2 = toc:getTocTicks(2)
      assert.are.same(26, #ticks_level_2)
    end)
    local ticks_level_m1 = nil
    it("should get ticks of level -1", function()
      ticks_level_m1 = toc:getTocTicks(-1)
      assert.are.same(26, #ticks_level_m1)
    end)
    it("should get the same ticks of level -1 and level 2", function()
      if toc_max_depth == 2 then
        assert.are.same(ticks_level_2, ticks_level_m1)
      end
    end)
    local ticks_level_flat = nil
    it("should get all ticks (flattened)", function()
      ticks_level_flat = toc:getTocTicksFlattened()
      assert.are.same(28, #ticks_level_flat)
    end)
  end)
  it("should get page of next chapter", function()
    assert.truthy(toc:getNextChapter(10) > 10)
    assert.truthy(toc:getNextChapter(100) > 100)
    assert.are.same(nil, toc:getNextChapter(290))
  end)
  it("should get page of previous chapter", function()
    assert.truthy(toc:getPreviousChapter(10) < 10)
    assert.truthy(toc:getPreviousChapter(100) < 100)
    assert.truthy(toc:getPreviousChapter(200) < 200)
  end)
  it("should get page left of chapter", function()
    assert.truthy(toc:getChapterPagesLeft(10) > 10)
    assert.truthy(toc:getChapterPagesLeft(95) > 10)
    -- assert.are.same(nil, toc:getChapterPagesLeft(290))
    -- Previous line somehow fails, but not if written this way:
    local pagesleft = toc:getChapterPagesLeft(290)
    assert.are.same(nil, pagesleft)
  end)
  it("should get page done of chapter", function()
    assert.truthy(toc:getChapterPagesDone(11) < 5)
    assert.truthy(toc:getChapterPagesDone(88) < 5)
    assert.truthy(toc:getChapterPagesDone(290) > 10)
  end)
  describe("collasible TOC", function()
    it("should collapse the secondary toc nodes by default", function()
      toc:onShowToc()
      assert.are.same(7, #toc.collapsed_toc)
    end)
    it("should not expand toc nodes that have no child nodes", function()
      toc:expandToc(2)
      assert.are.same(7, #toc.collapsed_toc)
    end)
    it("should expand toc nodes that have child nodes", function()
      toc:expandToc(3)
      assert.are.same(13, #toc.collapsed_toc)
      toc:expandToc(18)
      assert.are.same(18, #toc.collapsed_toc)
    end)
    it("should collapse toc nodes that have been expanded", function()
      toc:collapseToc(3)
      assert.are.same(12, #toc.collapsed_toc)
      toc:collapseToc(18)
      assert.are.same(7, #toc.collapsed_toc)

      --- @note: Delay the teardown 'til the last test, because of course the tests rely on incremental state changes across tests...
      readerui:onExit()
      readerui:onClose()
    end)
  end)

  describe("safe nil TOC behavior", function()
    it("should safely handle document returning nil TOC", function()
      local ReaderToc = require("apps/reader/modules/readertoc")
      local sample_epub = "spec/front/unit/data/leaves.epub"

      -- Open standard document
      local doc = DocumentRegistry:openDocument(sample_epub)
      -- Mock getToc to return nil explicitly
      doc.getToc = function()
        return nil
      end

      -- Instantiate a safe mock of ReaderUI context
      local mock_readerui = {
        dialog = {},
        view = {},
        document = doc,
        doc_settings = require("docsettings"):open(sample_epub),
        menu = {
          registerToMainMenu = function() end,
        },
        registerModule = function() end,
      }

      -- Instantiate ReaderToc with our mock context
      local readertoc = ReaderToc:new({
        dialog = mock_readerui.dialog,
        view = mock_readerui.view,
        ui = mock_readerui,
      })

      -- Trigger full fillToc load path
      readertoc:fillToc()

      -- Verify toc is initialized as a safe empty table instead of remaining nil
      assert.is_table(readertoc.toc)
      assert.are.equal(#readertoc.toc, 0)

      -- Verify downstream methods do not crash on empty TOC
      local depth = readertoc:getMaxDepth()
      assert.are.equal(depth, 0)

      local index = readertoc:getTocIndexByPage(1)
      assert.is_nil(index)

      local safe_title = readertoc:getTocTitleByPage(1)
      assert.are.equal(safe_title, "")
      local menu_items = {}
      readertoc:addToMainMenu(menu_items)
      assert.is_nil(menu_items.table_of_contents)

      -- Cleanup
      doc:close()
    end)

    it(
      "should dynamically register table_of_contents menu if a manual/handmade TOC is added",
      function()
        local ReaderToc = require("apps/reader/modules/readertoc")
        local sample_epub = "spec/front/unit/data/leaves.epub"

        local doc = DocumentRegistry:openDocument(sample_epub)
        -- Mock getToc to return nil initially (simulating no native TOC)
        local current_toc = nil
        doc.getToc = function()
          return current_toc
        end

        local mock_readerui = {
          dialog = {},
          view = {},
          document = doc,
          doc_settings = require("docsettings"):open(sample_epub),
          menu = {
            registerToMainMenu = function() end,
          },
          registerModule = function() end,
        }

        local readertoc = ReaderToc:new({
          dialog = mock_readerui.dialog,
          view = mock_readerui.view,
          ui = mock_readerui,
        })

        -- 1. Verify table_of_contents is nil initially
        local menu_items = {}
        readertoc:addToMainMenu(menu_items)
        assert.is_nil(menu_items.table_of_contents)

        -- 2. Simulate user adding a handmade TOC
        readertoc:resetToc()
        current_toc = {
          { title = "Custom Chapter 1", page = 5, depth = 1 },
        }

        -- Re-add to menu
        menu_items = {}
        readertoc:addToMainMenu(menu_items)
        assert.is_not_nil(menu_items.table_of_contents)

        -- 3. Simulate user clearing handmade TOC
        readertoc:resetToc()
        current_toc = {}
        menu_items = {}
        readertoc:addToMainMenu(menu_items)
        assert.is_nil(menu_items.table_of_contents)

        doc:close()
      end
    )
  end)

  describe("cleanUpTocTitle", function()
    it(
      "should strip carriage returns and replace empty titles when requested",
      function()
        assert.are.equal(
          "Chapter 1",
          toc:cleanUpTocTitle("Chapter 1\13", false)
        )
        assert.are.equal("\u{2013}", toc:cleanUpTocTitle("   \13", true))
        assert.are.equal("   ", toc:cleanUpTocTitle("   ", false))
      end
    )
  end)

  describe("getTitle", function()
    it(
      "should return standard and formatted titles depending on TOC state",
      function()
        local ReaderToc = require("apps/reader/modules/readertoc")
        local mock_ui = {
          handmade = {
            isHandmadeTocEnabled = function()
              return false
            end,
            custom_toc_symbol = "[H]",
          },
          document = {
            isTocAlternativeToc = function()
              return false
            end,
          },
          menu = { registerToMainMenu = function() end },
        }
        local test_toc = ReaderToc:new({ ui = mock_ui })
        assert.are.equal("Table of contents", test_toc:getTitle())

        mock_ui.handmade.isHandmadeTocEnabled = function()
          return true
        end
        assert.is_not_nil(test_toc:getTitle():find("[H]", 1, true))

        mock_ui.handmade.isHandmadeTocEnabled = function()
          return false
        end
        mock_ui.document.isTocAlternativeToc = function()
          return true
        end
        assert.is_not_nil(
          test_toc:getTitle():find(test_toc.alt_toc_symbol, 1, true)
        )
      end
    )
  end)

  describe("settings management", function()
    it("should read and save TOC settings", function()
      local mock_config = {
        readTableRef = function(self, key)
          if key == "toc_ticks_ignored_levels" then
            return { [2] = true }
          end
        end,
        read = function(self, key)
          if key == "toc_chapter_navigation_bind_to_ticks" then
            return true
          end
          if key == "toc_chapter_title_bind_to_ticks" then
            return false
          end
        end,
      }
      toc:onReadSettings(mock_config)
      assert.is_true(toc.toc_ticks_ignored_levels[2])
      assert.is_true(toc.toc_chapter_navigation_bind_to_ticks)
      assert.is_false(toc.toc_chapter_title_bind_to_ticks)

      local saved = {}
      local orig_save = toc.ui.doc_settings.save
      toc.ui.doc_settings.save = function(self, key, val)
        saved[key] = val
      end
      toc:onSaveSettings()
      assert.is_true(saved.toc_chapter_navigation_bind_to_ticks)
      assert.is_false(saved.toc_chapter_title_bind_to_ticks)
      toc.ui.doc_settings.save = orig_save
    end)
  end)

  describe("validateAndFixToc", function()
    it("should fix bogus TOC items with out-of-order page numbers", function()
      local ReaderToc = require("apps/reader/modules/readertoc")
      local mock_doc = {
        getToc = function()
          return {
            { title = "Sec 1", page = 10, depth = 1 },
            { title = "Sec 2", page = 5, depth = 1 },
            { title = "Sec 3", page = 15, depth = 1 },
          }
        end,
        getPageFlow = function()
          return 0
        end,
        canHaveAlternativeToc = function()
          return false
        end,
      }
      local mock_ui = {
        document = mock_doc,
        doc_settings = { read = function() end, isTrue = function() end },
        menu = { registerToMainMenu = function() end },
      }
      local test_toc = ReaderToc:new({ ui = mock_ui })
      test_toc:fillToc()
      assert.are.equal(1, test_toc.toc[1].page)
      assert.are.equal(10, test_toc.toc[1].orig_page)
      assert.are.equal(5, test_toc.toc[2].page)
    end)
  end)

  describe("completeTocWithChapterLengths", function()
    it("should calculate chapter lengths based on page differences", function()
      local ReaderToc = require("apps/reader/modules/readertoc")
      local mock_doc = {
        getToc = function()
          return {
            { title = "Ch 1", page = 1, depth = 1 },
            { title = "Ch 2", page = 10, depth = 1 },
          }
        end,
        getPageCount = function()
          return 25
        end,
        getPageFlow = function()
          return 0
        end,
        canHaveAlternativeToc = function()
          return false
        end,
      }
      local mock_ui = {
        document = mock_doc,
        doc_settings = { read = function() end, isTrue = function() end },
        menu = { registerToMainMenu = function() end },
      }
      local test_toc = ReaderToc:new({ ui = mock_ui })
      test_toc:fillToc()
      test_toc:completeTocWithChapterLengths()
      assert.are.equal(9, test_toc.toc[1].chapter_length)
      assert.are.equal(15, test_toc.toc[2].chapter_length)
    end)
  end)

  describe("chapter title and navigation helpers", function()
    it("should get full chapter title hierarchy and helper statuses", function()
      local titles = toc:getFullTocTitleByPage(60)
      assert.is_table(titles)
      assert.is_true(#titles > 0)

      toc:onPageUpdate(60)
      assert.are.equal(60, toc.pageno)
      assert.is_string(toc:getTocTitleOfCurrentPage())

      toc:onPosUpdate(nil, 65)
      assert.are.equal(65, toc.pageno)

      assert.is_boolean(toc:isChapterStart(10))
      assert.is_boolean(toc:isChapterEnd(10))

      assert.is_true(toc:onUpdateToc())
      assert.is_nil(toc.toc)
    end)
  end)
end)
