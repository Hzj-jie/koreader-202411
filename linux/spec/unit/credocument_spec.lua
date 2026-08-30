local Blitbuffer
local CreDocument
local DocumentRegistry
local Geom

describe("CreDocument unit tests", function()
  local sample_epub = "spec/front/unit/data/leaves.epub"

  setup(function()
    require("commonrequire")
    Blitbuffer = require("ffi/blitbuffer")
    CreDocument = require("document/credocument")
    DocumentRegistry = require("document/documentregistry")
    Geom = require("ui/geometry")
  end)

  describe("Provider registration", function()
    it("should register supported extensions in DocumentRegistry", function()
      local mock_registry = {
        providers = {},
        addProvider = function(self, ext, mimetype, provider, priority)
          table.insert(self.providers, {
            ext = ext,
            mimetype = mimetype,
            provider = provider,
            priority = priority,
          })
        end,
      }
      CreDocument:register(mock_registry)
      assert.is_true(#mock_registry.providers > 0)
    end)
  end)

  describe("Zip content helper", function()
    it("should extract zip content extension for epub", function()
      local ext = CreDocument:zipContentExt(sample_epub)
      assert.truthy(ext)
    end)

    it("should return nil for non-existent file", function()
      local ext = CreDocument:zipContentExt("non_existent_file.zip")
      assert.is_nil(ext)
    end)
  end)

  describe("CreDocument instance operations", function()
    local doc

    setup(function()
      doc = DocumentRegistry:openDocument(sample_epub)
      doc:render()
    end)

    teardown(function()
      if doc then
        doc:close()
      end
    end)

    it("should get DOM versions once engine is initialized", function()
      assert.is_number(doc:getDomVersionWithNormalizedXPointers())
      assert.is_number(doc:getLatestDomVersion())
      assert.are.same(20171225, doc:getOldestDomVersion())
    end)

    it("should load and render document properly", function()
      assert.truthy(doc)
      assert.is_true(doc._loaded)
      assert.is_true(doc.been_rendered)
      assert.truthy(doc:getDocumentFormat())
      assert.truthy(doc:getDocumentProps())
    end)

    it("should handle alt document properties", function()
      doc:setAltDocumentProp("title", "Custom Title")
      doc:setAltDocumentProp("authors", "Custom Author")
      doc:setAltDocumentProp("series", "Custom Series")
      doc:setAltDocumentProp("series_index", 1)
      doc:setAltDocumentProp("series_index", "2")
    end)

    it("should request DOM version", function()
      doc:requestDomVersion(20200101)
    end)

    it("should handle rendering hash and metadata", function()
      local hash = doc:getDocumentRenderingHash(false)
      assert.truthy(hash)
      assert.is_true(doc:_readMetadata())
    end)

    it("should get page count and page dimensions", function()
      local page_count = doc:getPageCount()
      assert.is_number(page_count)
      assert.is_true(page_count > 0)
    end)

    it("should handle page flows and navigation", function()
      doc:setHideNonlinearFlows(true)
      doc:cacheFlows()
      assert.is_boolean(doc:hasNonLinearFlows())
      assert.is_boolean(doc:hasHiddenFlows())

      local first_page = doc:getNextPage(0)
      assert.is_number(first_page)
      local last_page = doc:getPrevPage(0)
      assert.is_number(last_page)

      local next_p = doc:getNextPage(1)
      assert.is_number(next_p)
      local prev_p = doc:getPrevPage(2)
      assert.is_number(prev_p)

      assert.is_number(doc:getPageFlow(1))
      assert.is_number(doc:getLastLinearPage())
      assert.is_number(doc:getFirstPageInFlow(0))
      assert.is_number(doc:getTotalPagesInFlow(0))
      assert.is_number(doc:getPageNumberInFlow(1))
      assert.is_number(doc:getTotalPagesLeft(1))

      doc:setHideNonlinearFlows(false)
      doc:cacheFlows()
      assert.is_number(doc:getNextPage(1))
      assert.is_number(doc:getPrevPage(2))
      assert.is_number(doc:getTotalPagesLeft(1))
    end)

    it("should get cover page image", function()
      local cover = doc:getCoverPageImage()
      if cover then
        assert.truthy(cover:getWidth())
      end
    end)

    it("should handle font settings", function()
      local default_font = doc:getFontFace()
      assert.truthy(default_font)

      doc:setFontFace("Noto Serif")
      doc:setMonospaceFontScaling(100)
      doc:setAdjustedFallbackFontSizes(true)
      doc:setupFallbackFontFaces()
      doc:setFontFamilyFontFaces({ ["serif"] = "Noto Serif" }, true)
      doc:setFontFamilyFontFaces(nil, false)

      local font_size = doc:getFontSize()
      assert.is_number(font_size)

      doc:setFontSize(20)
      assert.are.same(20, doc:getFontSize())

      doc:zoomFont(1)
      doc:setHeaderFont("Noto Sans")
      doc:setFontBaseWeight(0)
      doc:setFontHinting(1)
      doc:setFontKerning(1)
      doc:setMonospaceFontScaling(110)
    end)

    it("should handle typography and hyphenation settings", function()
      doc:setTextMainLang("en")
      doc:setTextEmbeddedLangs(true)
      doc:setTextHyphenation(true)
      doc:setTextHyphenationSoftHyphensOnly(false)
      doc:setTextHyphenationForceAlgorithmic(false)
      doc:getTextMainLangDefaultHyphDictionary()
      doc:setHyphLeftHyphenMin(2)
      doc:setHyphRightHyphenMin(2)
      doc:setTrustSoftHyphens(true)
    end)

    it("should handle spacing and formatting settings", function()
      doc:setInterlineSpacePercent(120)
      doc:setWordSpacing({ 90, 75 })
      doc:setWordExpansion(5)
      doc:setCJKWidthScaling(100)
      doc:setFloatingPunctuation(1)
      doc:setTxtPreFormatted(0)
      doc:setRenderDPI(96)
      doc:setBlockRenderingFlags(0)
      doc:setImageScaling(true)
      doc:setNightmodeImages(false)
    end)

    it("should handle stylesheets", function()
      doc:setStyleSheet("./data/epub.css", "body { font-size: 16px; }")
      doc:setEmbeddedStyleSheet(1)
      doc:setEmbeddedFonts(1)
    end)

    it("should handle page margins and dimensions", function()
      doc:setPageMargins(10, 10, 10, 10)
      local margins = doc:getPageMargins()
      assert.truthy(margins)
      assert.is_number(doc:getHeaderHeight())

      doc:setViewDimen({ w = 600, h = 800 })
    end)

    it("should handle view mode changes", function()
      doc:setViewMode("scroll")
      assert.are.same(doc.SCROLL_VIEW_MODE, doc._view_mode)
      doc:setViewMode("page")
      assert.are.same(doc.PAGE_VIEW_MODE, doc._view_mode)
    end)

    it("should handle XPointers and position calculations", function()
      local xp = doc:getPageXPointer(1)
      if xp then
        assert.is_string(xp)
        assert.is_boolean(doc:isXPointerInDocument(xp))
        doc:gotoXPointer(xp)
        local cur_xp = doc:getXPointer()
        assert.truthy(cur_xp)

        local pos_y = doc:getPosFromXPointer(xp)
        assert.is_number(pos_y)

        local page = doc:getPageFromXPointer(xp)
        assert.is_number(page)

        local screen_y, screen_x = doc:getScreenPositionFromXPointer(xp)
        assert.is_number(screen_y)
        assert.is_number(screen_x)

        assert.is_boolean(doc:isXPointerInCurrentPage(xp))

        local norm_xp = doc:getNormalizedXPointer(xp)
        assert.truthy(norm_xp)

        local comp = doc:compareXPointers(xp, xp)
        assert.truthy(comp)

        doc:getTextFromXPointer(xp)
        doc:getHTMLFromXPointer(xp, 0, false)
        doc:getHTMLFromXPointers(xp, xp, 0, false)
      end
    end)

    it("should handle navigation and position operations", function()
      doc:gotoPage(1)
      assert.are.same(1, doc:getCurrentPage())

      doc:gotoPos(0)
      assert.is_number(doc:getCurrentPos())

      doc:goBack()
      doc:goForward()

      local links = doc:getPageLinks(true)
      assert.truthy(links)

      doc:getLinkFromPosition({ x = 10, y = 10 })
    end)

    it("should handle text selection and word extraction", function()
      doc:clearSelection()
      doc:getWordFromPosition({ x = 50, y = 50 }, true)
      doc:getTextFromPositions({ x = 0, y = 0 }, { x = 100, y = 100 }, true)
      local xp = doc:getPageXPointer(1)
      if xp then
        doc:getScreenBoxesFromPositions(xp, xp, true)
        doc:getSelectedWordContext("word", 2, xp, xp, true)
      end
    end)

    it("should handle text search and regex", function()
      assert.are.same(0, doc:checkRegex("valid_regex.*"))
      assert.are.same(0, doc:getAndClearRegexSearchError())

      doc:findText("leaves", 0, 1, true, 1, false, 10)
      doc:findAllText("leaves", true, 5, 10, false)
    end)

    it("should handle cache, statistics, and entities", function()
      assert.is_boolean(doc:canBePartiallyRerendered())
      assert.is_boolean(doc:isPartialRerenderingEnabled())
      doc:enablePartialRerendering(true)
      assert.is_number(doc:getPartialRerenderingsCount())
      assert.is_boolean(doc:isRerenderingDelayed())
      assert.is_boolean(doc:isBuiltDomStale())
      assert.is_boolean(doc:hasCacheFile())
      assert.is_boolean(doc:isCacheFileStale())
      doc:invalidateCacheFile()
      doc:getCacheFilePath()
      doc:getStatistics()
      doc:getUnknownEntities()
    end)

    it("should handle TOC and PageMap methods", function()
      assert.is_true(doc:canHaveAlternativeToc())
      assert.is_boolean(doc:isTocAlternativeToc())
      doc:buildAlternativeToc()

      doc:buildSyntheticPageMapIfNoneDocumentProvided(1024)
      assert.is_boolean(doc:isPageMapSynthetic())
      assert.is_boolean(doc:hasPageMap())
      doc:getPageMap()
      doc:getPageMapSource()
      doc:getPageMapCurrentPageLabel()
      doc:getPageMapFirstPageLabel()
      doc:getPageMapLastPageLabel()

      local xp = doc:getPageXPointer(1)
      if xp then
        doc:getPageMapXPointerPageLabel(xp)
      end
      doc:getPageMapVisiblePageLabels()
    end)

    it("should handle display, drawing, and status line properties", function()
      doc:getVisiblePageCount()
      doc:setVisiblePageCount(1)
      doc:getVisiblePageNumberCount()
      doc:setBatteryState(100)
      doc:setPageInfoOverride("1 / 10")
      doc:setStatusLineProp("title")
      doc:setBackgroundColor(0xFFFFFF)
      doc:setBackgroundColor(nil)
      doc:setBackgroundImage(nil)
      doc:enableInternalHistory(true)
      doc:enableInternalHistory(false)

      local target = Blitbuffer.new(300, 400)
      local rect = Geom:new({ x = 0, y = 0, w = 300, h = 400 })
      doc:drawCurrentView(target, 0, 0, rect)
      doc:drawCurrentViewByPage(target, 0, 0, rect, 1)
      doc:drawCurrentViewByPos(target, 0, 0, rect, 0)

      doc:updateColorRendering()
    end)

    it("should handle call cache and statistics", function()
      doc:resetCallCache()
      doc:resetBufferCache()

      G_reader_settings:save("use_cre_call_cache_log_stats", true)
      doc:setupCallCache()
      local stats = doc.getCallCacheStatistics()
      assert.is_string(stats)
      G_reader_settings:delete("use_cre_call_cache_log_stats")
    end)

    it("should handle gamma settings", function()
      local gamma = doc:getGammaLevel()
      assert.truthy(gamma)
      doc:setGammaIndex(1)
    end)
  end)

  describe("CreDocument init with fb2 file", function()
    it(
      "should initialize with fb2 file setting default_css to fb2.css",
      function()
        local fb_doc = CreDocument:new({
          file = "test.fb2",
        })
        assert.are.same("./data/fb2.css", fb_doc.default_css)
        assert.is_true(fb_doc.is_fb2)
      end
    )
  end)
end)
