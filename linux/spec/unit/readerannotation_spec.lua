describe("ReaderAnnotation module", function()
  local ReaderAnnotation

  setup(function()
    require("commonrequire")
    ReaderAnnotation = require("apps/reader/modules/readerannotation")
  end)

  it(
    "should build annotation using decoupled self.ui.view.highlight reference",
    function()
      local mock_ui = {
        view = {
          highlight = {
            saved_drawer = "lighten",
            saved_color = "yellow",
          },
        },
        bookmark = {
          isBookmarkAutoText = function()
            return false
          end,
        },
        toc = {
          getTocTitleByPage = function()
            return "Chapter 1"
          end,
        },
      }

      local annotation_module = ReaderAnnotation:new({
        ui = mock_ui,
        document = {
          hasHiddenFlows = function()
            return false
          end,
        },
      })

      local bm = {
        text = "Sample Note",
        chapter = "Chapter 1",
        page = 5,
        highlighted = true,
        pos0 = { page = 5, x = 10, y = 20 },
        pos1 = { page = 5, x = 30, y = 40 },
        datetime_updated = "2026-09-29 12:00:00",
      }
      local highlights = {}

      local data = {
        bookmarks = { bm },
        highlight = highlights,
      }
      local config = {
        doc_path = "/path/to/book.pdf",
        has = function(self, k)
          return data[k] ~= nil
        end,
        hasNot = function(self, k)
          return data[k] == nil
        end,
        readTable = function(self, k)
          return data[k]
        end,
        readTableRef = function(self, k)
          if data[k] == nil then
            data[k] = {}
          end
          return data[k]
        end,
        save = function(self, k, v)
          data[k] = v
        end,
        delete = function(self, k)
          data[k] = nil
        end,
        isTrue = function(self, k)
          return data[k] == true
        end,
      }

      local result = ReaderAnnotation.loadFromSettings(config, mock_ui)
      assert.are.equal(1, #result)
      local ann = result[1]
      assert.is_not_nil(ann)
      assert.are.equal("Sample Note", ann.note)
      assert.are.equal("lighten", ann.drawer)
      assert.are.equal("yellow", ann.color)
      assert.are.equal("2026-09-29 12:00:00", ann.datetime_updated)
    end
  )
end)

describe("ReaderAnnotation module", function()
  local ReaderAnnotation, DocumentRegistry, ReaderUI, Screen

  setup(function()
    require("commonrequire")
    ReaderAnnotation = require("apps/reader/modules/readerannotation")
    DocumentRegistry = require("document/documentregistry")
    ReaderUI = require("apps/reader/readerui")
    Screen = require("device").screen
  end)

  local function create_mock_config(data, doc_path)
    return {
      doc_path = doc_path,
      has = function(self, k)
        return data[k] ~= nil
      end,
      hasNot = function(self, k)
        return data[k] == nil
      end,
      read = function(self, k)
        return data[k]
      end,
      readTable = function(self, k)
        return data[k]
      end,
      readTableRef = function(self, k)
        if data[k] == nil then
          data[k] = {}
        end
        return data[k]
      end,
      save = function(self, k, v)
        data[k] = v
      end,
      delete = function(self, k)
        data[k] = nil
      end,
      isTrue = function(self, k)
        return data[k] == true
      end,
    }
  end

  it("should initialize annotation module with EPUB and PDF", function()
    local sample_epub = "spec/front/unit/data/leaves.epub"
    local readerui = ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(sample_epub),
    })

    local annotation = readerui.annotation
    assert.is_table(annotation)
    assert.is_table(annotation.annotations)
    assert.is_boolean(annotation:hasAnnotations())
    assert.is_number(annotation:getNumberOfAnnotations())
    local hls, notes = annotation:getNumberOfHighlightsAndNotes()
    assert.is_number(hls)
    assert.is_number(notes)

    readerui:onExit()
    readerui:onClose()
  end)

  describe("Annotation building and operations", function()
    local mock_doc, mock_ui, ann

    before_each(function()
      mock_doc = {
        getPageCount = function()
          return 100
        end,
        getPageFromXPointer = function(_, xp)
          return 5
        end,
        compareXPointers = function(_, a, b)
          if a == b then
            return 0
          end
          return a > b and 1 or -1
        end,
        comparePositions = function(_, a, b)
          if not a or not b then
            return 0
          end
          if a.x == b.x then
            return a.y == b.y and 0 or (a.y < b.y and 1 or -1)
          end
          return a.x < b.x and 1 or -1
        end,
        getPageBoxesFromPositions = function()
          return { { x = 0, y = 0, w = 50, h = 20 } }
        end,
        hasHiddenFlows = function()
          return true
        end,
        getPageFlow = function(_, pn)
          return pn == 10 and 1 or 0
        end,
        getPageNumberInFlow = function(_, pn)
          return pn
        end,
        configurable = { text_wrap = 0 },
      }

      local mock_view = {
        highlight = {
          saved_drawer = "lighten",
          saved_color = "yellow",
        },
      }

      mock_ui = {
        rolling = true,
        document = mock_doc,
        view = mock_view,
        toc = {
          getTocTitleByPage = function(_, p)
            return "Chapter 1"
          end,
        },
        bookmark = {
          isBookmarkAutoText = function(_, bm)
            return bm.text == "AutoText"
          end,
        },
      }

      ann = ReaderAnnotation:new({
        ui = mock_ui,
        view = mock_view,
        document = mock_doc,
        annotations = {},
      })
    end)

    it(
      "should build annotation from bookmarks and highlights in rolling mode",
      function()
        local bm = {
          datetime = "2026-08-25 00:00:00",
          highlighted = true,
          notes = "Sample Highlight",
          text = "My Note",
          page = "/body/div/p[1]",
          pos0 = "/body/div/p[1]",
          pos1 = "/body/div/p[2]",
        }
        local highlights = {
          [5] = {
            {
              pos0 = "/body/div/p[1]",
              pos1 = "/body/div/p[2]",
              drawer = "lighten",
              color = "yellow",
            },
          },
        }

        local data = {
          highlights_imported = true,
          bookmarks = { bm },
          highlight = highlights,
        }
        local config = {
          doc_path = "/path/to/book.epub",
          has = function(self, k)
            return data[k] ~= nil
          end,
          hasNot = function(self, k)
            return data[k] == nil
          end,
          readTable = function(self, k)
            return data[k]
          end,
          readTableRef = function(self, k)
            if data[k] == nil then
              data[k] = {}
            end
            return data[k]
          end,
          save = function(self, k, v)
            data[k] = v
          end,
          delete = function(self, k)
            data[k] = nil
          end,
          isTrue = function(self, k)
            return data[k] == true
          end,
        }

        local items = ReaderAnnotation.loadFromSettings(config, mock_ui)
        assert.are.equal(1, #items)
        local item = items[1]
        assert.is_table(item)
        assert.are.equal("Sample Highlight", item.text)
        assert.are.equal("My Note", item.note)
        assert.are.equal("Chapter 1", item.chapter)
        assert.are.equal(5, item.pageno)
      end
    )

    it(
      "should add item and find item index with binary and linear search fallback",
      function()
        local item = {
          page = 5,
          pageno = 5,
          pos0 = "/body/div/p[1]",
          pos1 = "/body/div/p[2]",
          datetime = "2026-08-25 00:00:00",
        }
        local idx = ann:addItem(item)
        assert.are.equal(1, idx)
        assert.is_nil(item.datetime_updated)
        assert.are.equal(1, ann:getItemIndex(item))
        assert.are.equal(1, ann:getItemIndex(item, true))
      end
    )

    it("should update item chapter by xpointer", function()
      local item = {
        page = "/body/div/p[1]",
        pos0 = "/body/div/p[1]",
        pos1 = "/body/div/p[2]",
      }
      ann:updateItemByXPointer(item)
      assert.are.equal("Chapter 1", item.chapter)
    end)

    it(
      "should compute page reference strings for normal and hidden flows",
      function()
        local pref = ann:getPageRef("/body/div/p[1]", 10)
        assert.are.equal("[10]1", pref)
        local pref0 = ann:getPageRef("/body/div/p[1]", 5)
        assert.are.equal("5", pref0)
      end
    )

    it("should handle paging mode sorting and insertion", function()
      mock_ui.rolling = false
      mock_ui.paging = true

      local item1 = {
        page = 1,
        pos0 = { x = 10, y = 10, page = 1 },
        pos1 = { x = 50, y = 10, page = 1 },
        drawer = "lighten",
        datetime = "2026-08-25 00:00:01",
      }
      local item2 = {
        page = 1,
        pos0 = { x = 60, y = 10, page = 1 },
        pos1 = { x = 90, y = 10, page = 1 },
        drawer = "lighten",
        datetime = "2026-08-25 00:00:02",
      }
      local item3 = {
        page = 2,
        pos0 = { x = 10, y = 10, page = 2 },
        pos1 = { x = 50, y = 10, page = 2 },
        drawer = "lighten",
        datetime = "2026-08-25 00:00:03",
      }

      ann.annotations = {}
      ann:addItem(item2)
      ann:addItem(item1)
      ann:addItem(item3)

      assert.are.equal(3, #ann.annotations)
      assert.are.same(item1, ann.annotations[1])
      assert.are.same(item2, ann.annotations[2])
      assert.are.same(item3, ann.annotations[3])
    end)

    it("should handle settings read, save, and migrations", function()
      local data = {
        annotations = {
          {
            page = 1,
            text = "Old Page",
            pos0 = { x = 0, y = 0 },
            pos1 = { x = 10, y = 10 },
          },
        },
        annotations_externally_modified = true,
      }
      local config = {
        has = function(self, k)
          return data[k] ~= nil
        end,
        hasNot = function(self, k)
          return data[k] == nil
        end,
        read = function(self, k)
          return data[k]
        end,
        readTable = function(self, k)
          return data[k]
        end,
        readTableRef = function(self, k)
          return data[k]
        end,
        save = function(self, k, v)
          data[k] = v
        end,
        delete = function(self, k)
          data[k] = nil
        end,
        isTrue = function(self, k)
          return data[k] == true
        end,
      }

      ann:onReadSettings(config)
      if ann.onPostReaderReady then
        ann.onPostReaderReady()
      end
      assert.is_table(ann.annotations)

      ann:setNeedsUpdateFlag()
      ann:onDocumentRerendered()
      ann:onCloseDocument()
      ann:onSaveSettings()
    end)

    it("should migrate legacy bookmarks and highlights formats", function()
      local data = {
        bookmarks = {
          { page = 1, datetime = "2026-08-25 00:00:00", notes = "Bookmark" },
        },
        highlight = {
          [1] = {
            {
              text = "Highlight",
              datetime = "2026-08-25 00:00:00",
              pos0 = { x = 0, y = 0 },
              pos1 = { x = 10, y = 0 },
            },
          },
        },
      }
      local config = {
        has = function(self, k)
          return data[k] ~= nil
        end,
        hasNot = function(self, k)
          return data[k] == nil
        end,
        read = function(self, k)
          return data[k]
        end,
        readTable = function(self, k)
          return data[k]
        end,
        readTableRef = function(self, k)
          return data[k]
        end,
        save = function(self, k, v)
          data[k] = v
        end,
        delete = function(self, k)
          data[k] = nil
        end,
        isTrue = function(self, k)
          return data[k] == true
        end,
      }

      mock_ui.rolling = false
      mock_ui.paging = true
      ann:onReadSettings(config)
      assert.is_table(ann.annotations)
      assert.is_true(#ann.annotations > 0)
    end)

    it(
      "should delegate onReadSettings to loadFromSettings and handle quarantine",
      function()
        local data = {
          annotations = {
            { page = 1 },
            { page = 1, drawer = "lighten" },
          },
        }
        local config = {
          has = function(self, k)
            return data[k] ~= nil
          end,
          hasNot = function(self, k)
            return data[k] == nil
          end,
          read = function(self, k)
            return data[k]
          end,
          readTable = function(self, k)
            return data[k]
          end,
          readTableRef = function(self, k)
            return data[k]
          end,
          save = function(self, k, v)
            data[k] = v
          end,
          delete = function(self, k)
            data[k] = nil
          end,
          isTrue = function(self, k)
            return data[k] == true
          end,
        }

        mock_ui.rolling = false
        mock_ui.paging = true
        ann:onReadSettings(config)
        assert.are.equal(1, #ann.annotations)
        assert.is_not_nil(data.annotations_invalid)
        assert.are.equal(1, #data.annotations_invalid)
        assert.is_not_nil(ann.onPostReaderReady)

        ann.onPostReaderReady()
        assert.is_nil(data.annotations_externally_modified)
      end
    )

    it(
      "should defer legacy migration in rolling mode when annotations is absent until onReaderInited",
      function()
        local data = {
          highlights_imported = true,
          bookmarks = {
            {
              page = "/body/div/p[1]",
              datetime = "2026-08-25 00:00:00",
              notes = "Rolling Note",
            },
          },
          highlight = {},
        }
        local config = create_mock_config(data)
        mock_ui.rolling = true

        ann:onReadSettings(config)
        assert.are.same({}, ann.annotations)
        assert.is_function(ann.onReaderInited)
        assert.is_nil(data.annotations)

        ann.onReaderInited()
        assert.are.equal(1, #ann.annotations)
        assert.are.equal("/body/div/p[1]", ann.annotations[1].page)
        assert.is_not_nil(data.annotations)
        assert.is_true(data.annotations_externally_modified)
      end
    )
  end)

  describe("ReaderAnnotation.doesMatch", function()
    it(
      "should match paging bookmarks on same page and distinguish different pages",
      function()
        local bm1 = { page = 5 }
        local bm2 = { page = 5 }
        local bm3 = { page = 6 }
        assert.is_true(ReaderAnnotation.doesMatch(bm1, bm2))
        assert.is_false(ReaderAnnotation.doesMatch(bm1, bm3))
      end
    )

    it("should distinguish bookmark from highlight", function()
      local bm = { page = 5 }
      local hl = {
        page = 5,
        drawer = "lighten",
        pos0 = { x = 1, y = 2 },
        pos1 = { x = 3, y = 4 },
      }
      assert.is_false(ReaderAnnotation.doesMatch(bm, hl))
      assert.is_false(ReaderAnnotation.doesMatch(hl, bm))
    end)

    it(
      "should match and distinguish paging highlights by coordinates",
      function()
        local hl1 = {
          page = 5,
          drawer = "lighten",
          pos0 = { x = 10, y = 20 },
          pos1 = { x = 30, y = 40 },
        }
        local hl2 = {
          page = 5,
          drawer = "lighten",
          pos0 = { x = 10, y = 20 },
          pos1 = { x = 30, y = 40 },
        }
        local hl_diff_x = {
          page = 5,
          drawer = "lighten",
          pos0 = { x = 15, y = 20 },
          pos1 = { x = 30, y = 40 },
        }
        local hl_diff_y = {
          page = 5,
          drawer = "lighten",
          pos0 = { x = 10, y = 20 },
          pos1 = { x = 30, y = 45 },
        }
        local hl_diff_page = {
          page = 6,
          drawer = "lighten",
          pos0 = { x = 10, y = 20 },
          pos1 = { x = 30, y = 40 },
        }

        assert.is_true(ReaderAnnotation.doesMatch(hl1, hl2))
        assert.is_false(ReaderAnnotation.doesMatch(hl1, hl_diff_x))
        assert.is_false(ReaderAnnotation.doesMatch(hl1, hl_diff_y))
        assert.is_false(ReaderAnnotation.doesMatch(hl1, hl_diff_page))
      end
    )

    it(
      "should match and distinguish rolling highlights by XPointer positions",
      function()
        local hl1 = {
          page = "/body/p[1]",
          pos0 = "/body/p[1]",
          pos1 = "/body/p[2]",
          drawer = "lighten",
        }
        local hl2 = {
          page = "/body/p[1]",
          pos0 = "/body/p[1]",
          pos1 = "/body/p[2]",
          drawer = "lighten",
        }
        local hl_diff_end = {
          page = "/body/p[1]",
          pos0 = "/body/p[1]",
          pos1 = "/body/p[3]",
          drawer = "lighten",
        }
        local hl_diff_start = {
          page = "/body/p[2]",
          pos0 = "/body/p[2]",
          pos1 = "/body/p[2]",
          drawer = "lighten",
        }

        assert.is_true(ReaderAnnotation.doesMatch(hl1, hl2))
        assert.is_false(ReaderAnnotation.doesMatch(hl1, hl_diff_end))
        assert.is_false(ReaderAnnotation.doesMatch(hl1, hl_diff_start))
      end
    )

    it("should honor datetime matching rules", function()
      local a = { page = 5, datetime = "2026-08-25 10:00:00" }
      local b = { page = 5, datetime = "2026-08-25 10:00:00" }
      local c = { page = 5, datetime = "2026-08-25 11:00:00" }
      local d = { page = 5 }

      assert.is_true(ReaderAnnotation.doesMatch(a, b))
      assert.is_false(ReaderAnnotation.doesMatch(a, c))
      assert.is_true(ReaderAnnotation.doesMatch(a, d))
      assert.is_true(ReaderAnnotation.doesMatch(d, a))
    end)
  end)

  describe("ReaderAnnotation.isValidItem", function()
    it("should reject non-table items or missing page", function()
      assert.is_false(ReaderAnnotation.isValidItem(nil))
      assert.is_false(ReaderAnnotation.isValidItem("not a table"))
      assert.is_false(ReaderAnnotation.isValidItem(123))
      assert.is_false(ReaderAnnotation.isValidItem({}))
      assert.is_false(ReaderAnnotation.isValidItem({ page = "" }))
    end)

    it("should validate paging bookmarks", function()
      assert.is_true(ReaderAnnotation.isValidItem({ page = 5 }))
      -- Bookmark with pos0 or pos1 is invalid
      assert.is_false(
        ReaderAnnotation.isValidItem({ page = 5, pos0 = { x = 0, y = 0 } })
      )
      assert.is_false(
        ReaderAnnotation.isValidItem({ page = 5, pos1 = { x = 0, y = 0 } })
      )
    end)

    it("should validate paging highlights", function()
      local valid_hl = {
        page = 5,
        drawer = "lighten",
        pos0 = { x = 10, y = 20 },
        pos1 = { x = 30, y = 40 },
      }
      assert.is_true(ReaderAnnotation.isValidItem(valid_hl))

      -- Missing pos0 or pos1
      assert.is_false(ReaderAnnotation.isValidItem({
        page = 5,
        drawer = "lighten",
        pos1 = { x = 30, y = 40 },
      }))
      -- Non-table pos0
      assert.is_false(ReaderAnnotation.isValidItem({
        page = 5,
        drawer = "lighten",
        pos0 = "not a table",
        pos1 = { x = 30, y = 40 },
      }))
      -- Missing coordinate numbers
      assert.is_false(ReaderAnnotation.isValidItem({
        page = 5,
        drawer = "lighten",
        pos0 = { x = 10 },
        pos1 = { x = 30, y = 40 },
      }))
    end)

    it("should validate rolling bookmarks and highlights", function()
      assert.is_true(ReaderAnnotation.isValidItem({ page = "/body/p[1]" }))

      local valid_rolling_hl = {
        page = "/body/p[1]",
        drawer = "lighten",
        pos0 = "/body/p[1]",
        pos1 = "/body/p[2]",
      }
      assert.is_true(ReaderAnnotation.isValidItem(valid_rolling_hl))

      -- Missing pos0 is invalid
      local missing_pos0_rolling_hl = {
        page = "/body/p[1]",
        drawer = "lighten",
        pos1 = "/body/p[2]",
      }
      assert.is_false(ReaderAnnotation.isValidItem(missing_pos0_rolling_hl))

      -- Missing or empty pos1
      assert.is_false(ReaderAnnotation.isValidItem({
        page = "/body/p[1]",
        drawer = "lighten",
        pos1 = "",
      }))
      -- Non-string pos0 when page is string
      assert.is_false(ReaderAnnotation.isValidItem({
        page = "/body/p[1]",
        drawer = "lighten",
        pos0 = { x = 10, y = 20 },
        pos1 = "/body/p[2]",
      }))
    end)

    it(
      "should validate datetime and datetime_updated fields when present",
      function()
        assert.is_true(ReaderAnnotation.isValidItem({
          page = 1,
          datetime = "2026-08-25 10:00:00",
        }))
        assert.is_true(ReaderAnnotation.isValidItem({
          page = 1,
          datetime = "2026-08-25 10:00:00",
          datetime_updated = "2026-08-25 11:00:00",
        }))

        assert.is_false(
          ReaderAnnotation.isValidItem({ page = 1, datetime = 123456 })
        )
        assert.is_false(
          ReaderAnnotation.isValidItem({ page = 1, datetime = { "timestamp" } })
        )
        assert.is_false(
          ReaderAnnotation.isValidItem({ page = 1, datetime = "" })
        )

        assert.is_false(
          ReaderAnnotation.isValidItem({ page = 1, datetime_updated = 123456 })
        )
        assert.is_false(
          ReaderAnnotation.isValidItem({ page = 1, datetime_updated = {} })
        )
        assert.is_false(
          ReaderAnnotation.isValidItem({ page = 1, datetime_updated = "" })
        )
      end
    )
  end)

  describe("ReaderAnnotation.loadFromSettings", function()
    it(
      "should error when config is nil and return empty list when config is empty",
      function()
        assert.has_error(function()
          ReaderAnnotation.loadFromSettings(nil)
        end)
        local config = create_mock_config({})
        assert.are.same({}, ReaderAnnotation.loadFromSettings(config))
      end
    )

    it("should load existing annotations directly", function()
      local data = {
        annotations = {
          { page = 1, datetime = "2026-08-25 10:00:00" },
        },
      }
      local config = create_mock_config(data)
      local result = ReaderAnnotation.loadFromSettings(config)
      assert.are.equal(1, #result)
      assert.are.equal(1, result[1].page)
    end)

    it(
      "should swap incompatible annotations and mark externally modified",
      function()
        local data = {
          annotations = {
            { page = "/body/p[1]", datetime = "2026-08-25 10:00:00" },
          },
          annotations_paging = {
            { page = 10, datetime = "2026-08-25 09:00:00" },
          },
        }
        local config = create_mock_config(data)
        config.doc_path = "/path/to/book.pdf"
        local result = ReaderAnnotation.loadFromSettings(config)
        assert.are.equal(1, #result)
        assert.are.equal(10, result[1].page)
        assert.is_true(data.annotations_externally_modified)
        assert.are.equal("/body/p[1]", data.annotations_rolling[1].page)
      end
    )

    it(
      "should migrate legacy bookmarks and highlights when annotations key is missing",
      function()
        local data = {
          highlights_imported = true,
          bookmarks = {
            {
              page = 1,
              datetime = "2026-08-25 00:00:00",
              notes = "Sample text",
              text = "My note",
              highlighted = true,
              pos0 = { x = 0, y = 0 },
              pos1 = { x = 10, y = 0 },
            },
          },
          highlight = {
            [1] = {
              {
                page = 1,
                datetime = "2026-08-25 00:00:00",
                drawer = "underscore",
                color = "red",
                pboxes = { { x = 0, y = 0, w = 10, h = 5 } },
                ext = true,
                edited = true,
                pos0 = { x = 0, y = 0 },
                pos1 = { x = 10, y = 0 },
              },
            },
          },
        }
        local config = create_mock_config(data)
        local result = ReaderAnnotation.loadFromSettings(config, false)
        assert.are.equal(1, #result)
        assert.are.equal(1, result[1].page)
        assert.are.equal("underscore", result[1].drawer)
        assert.are.equal("red", result[1].color)
        assert.is_not_nil(result[1].pboxes)
        assert.is_true(result[1].ext)
        assert.is_true(result[1].text_edited)
        assert.are.equal(1, result[1].pos0.page)
        assert.are.equal(1, result[1].pos1.page)
        assert.are.equal("My note", result[1].note)
        assert.are.equal("Sample text", result[1].text)
        assert.is_true(data.annotations_externally_modified)
        assert.is_not_nil(data.annotations)
      end
    )

    it(
      "should import pre-2014 orphan highlights when highlights_imported is missing",
      function()
        local data = {
          bookmarks = {},
          highlight = {
            [1] = {
              {
                page = 1,
                datetime = "2013-05-01 12:00:00",
                text = "Pre-2014 highlight",
                drawer = "underscore",
                color = "red",
                pos0 = { x = 0, y = 0 },
                pos1 = { x = 10, y = 0 },
              },
            },
          },
        }
        local config = create_mock_config(data)
        local result = ReaderAnnotation.loadFromSettings(config, false)
        assert.are.equal(1, #result)
        assert.are.equal(1, result[1].page)
        assert.are.equal("Pre-2014 highlight", result[1].text)
        assert.are.equal("underscore", result[1].drawer)
        assert.are.equal("red", result[1].color)
        assert.is_true(data.highlights_imported)
      end
    )

    it(
      "should persist annotations and avoid re-migration when bookmarks are empty",
      function()
        local data = {
          bookmarks = {},
          highlight = {},
        }
        local config = create_mock_config(data)
        local result = ReaderAnnotation.loadFromSettings(config)
        assert.are.equal(0, #result)
        assert.is_not_nil(data.annotations)
        assert.is_true(config:has("annotations"))
        assert.are.equal(data.annotations, result)
      end
    )

    it(
      "should preserve table reference for empty existing annotations",
      function()
        local data = {
          annotations = {},
        }
        local config = create_mock_config(data)
        local result = ReaderAnnotation.loadFromSettings(config)
        assert.are.equal(0, #result)
        assert.are.equal(data.annotations, result)
      end
    )

    it(
      "should detect rolling vs paging using DocumentRegistry provider",
      function()
        local config_epub = create_mock_config({
          annotations = {
            { page = "/body/p[1]", datetime = "2026-08-25 10:00:00" },
          },
        }, "/path/to/book.epub")
        local res_epub = ReaderAnnotation.loadFromSettings(config_epub)
        assert.are.equal(1, #res_epub)
        assert.are.equal("/body/p[1]", res_epub[1].page)

        local config_pdf = create_mock_config({
          annotations = {
            { page = 5, datetime = "2026-08-25 10:00:00" },
          },
        }, "/path/to/doc.pdf")
        local res_pdf = ReaderAnnotation.loadFromSettings(config_pdf)
        assert.are.equal(1, #res_pdf)
        assert.are.equal(5, res_pdf[1].page)
      end
    )

    it(
      "should not trigger swap when first annotation is corrupt but subsequent items match format",
      function()
        local data = {
          annotations = {
            { page = nil, drawer = "lighten" },
            { page = 5, datetime = "2026-08-25 10:00:00" },
          },
        }
        local config = create_mock_config(data)
        local result = ReaderAnnotation.loadFromSettings(config, false)
        assert.are.equal(1, #result)
        assert.are.equal(5, result[1].page)
        assert.is_nil(data.annotations_rolling)
        assert.is_not_nil(data.annotations_invalid)
        assert.are.equal(1, #data.annotations_invalid)
      end
    )

    it(
      "should not enter swap branch or mark externally modified when annotations is empty",
      function()
        local data = {
          annotations = {},
        }
        local config = create_mock_config(data)
        local result = ReaderAnnotation.loadFromSettings(config, false)
        assert.are.same({}, result)
        assert.is_nil(data.annotations_externally_modified)
        assert.is_nil(data.annotations_rolling)
      end
    )

    it(
      "should accept explicit is_rolling parameter and default to false when undefined",
      function()
        -- Explicit rolling: number page is quarantined
        local config_rolling = create_mock_config({
          annotations = {
            { page = "/body/p[1]", datetime = "2026-08-25 10:00:00" },
            { page = 5, datetime = "2026-08-25 10:00:00" },
          },
        })
        local result_rolling =
          ReaderAnnotation.loadFromSettings(config_rolling, true)
        assert.are.equal(1, #result_rolling)
        assert.are.equal("/body/p[1]", result_rolling[1].page)

        -- Explicit paging: string page is quarantined
        local config_paging = create_mock_config({
          annotations = {
            { page = 5, datetime = "2026-08-25 10:00:00" },
            { page = "/body/p[1]", datetime = "2026-08-25 10:00:00" },
          },
        })
        local result_paging =
          ReaderAnnotation.loadFromSettings(config_paging, false)
        assert.are.equal(1, #result_paging)
        assert.are.equal(5, result_paging[1].page)

        -- is_rolling undefined without doc_path: defaults to false (paging)
        local config_default = create_mock_config({
          annotations = {
            { page = 5, datetime = "2026-08-25 10:00:00" },
          },
        })
        local result_default =
          ReaderAnnotation.loadFromSettings(config_default, nil)
        assert.are.equal(1, #result_default)
        assert.are.equal(5, result_default[1].page)
      end
    )

    it(
      "should quarantine invalid annotations to annotations_invalid and return valid ones",
      function()
        local data = {
          annotations = {
            {
              page = 1,
              datetime = "2026-08-25 00:00:00",
              drawer = "lighten",
              pos0 = { x = 0, y = 0 },
              pos1 = { x = 10, y = 10 },
            },
            {
              page = 1,
              datetime = "2026-08-25 00:00:00",
              drawer = "lighten",
              -- Corrupt: drawer present but pos0 and pos1 missing
            },
          },
        }
        local config = create_mock_config(data)
        local result = ReaderAnnotation.loadFromSettings(config)
        assert.are.equal(1, #result)
        assert.are.equal(1, #data.annotations)
        assert.is_not_nil(data.annotations_invalid)
        assert.are.equal(1, #data.annotations_invalid)
        assert.is_true(data.annotations_externally_modified)
      end
    )

    it(
      "should append newly quarantined items to existing annotations_invalid",
      function()
        local data = {
          annotations_invalid = {
            { page = 99, corrupt = true },
          },
          annotations = {
            { page = 1 },
            { page = 2, drawer = "lighten" }, -- invalid highlight
          },
        }
        local config = create_mock_config(data)
        local result = ReaderAnnotation.loadFromSettings(config)
        assert.are.equal(1, #result)
        assert.are.equal(1, result[1].page)
        assert.are.equal(2, #data.annotations_invalid)
        assert.are.equal(99, data.annotations_invalid[1].page)
        assert.are.equal(2, data.annotations_invalid[2].page)
      end
    )

    describe("legacy migration format-mismatch and backup branches", function()
      it(
        "should backup paging bookmarks to annotations_paging and load bookmarks_rolling in rolling mode",
        function()
          local data = {
            highlights_imported = true,
            bookmarks = {
              {
                page = 1,
                datetime = "2026-08-25 00:00:00",
                notes = "Paging note",
              },
            },
            highlight = {},
            bookmarks_rolling = {
              {
                page = "/body/p[1]",
                datetime = "2026-08-25 00:00:00",
                notes = "Rolling note",
              },
            },
            highlight_rolling = {},
          }
          local config = create_mock_config(data)
          local result =
            ReaderAnnotation.loadFromSettings(config, { rolling = true })
          assert.are.equal(1, #result)
          assert.are.equal("/body/p[1]", result[1].page)
          assert.is_not_nil(data.annotations_paging)
          assert.are.equal(1, #data.annotations_paging)
          assert.are.equal(1, data.annotations_paging[1].page)
          assert.is_nil(data.bookmarks_rolling)
          assert.is_nil(data.highlight_rolling)
          assert.is_true(data.annotations_externally_modified)
          assert.are.equal(data.annotations, result)
        end
      )

      it(
        "should backup rolling bookmarks to annotations_rolling and load bookmarks_paging in paging mode",
        function()
          local data = {
            highlights_imported = true,
            bookmarks = {
              {
                page = "/body/p[1]",
                datetime = "2026-08-25 00:00:00",
                notes = "Rolling note",
              },
            },
            highlight = {},
            bookmarks_paging = {
              {
                page = 2,
                datetime = "2026-08-25 00:00:00",
                notes = "Paging note",
              },
            },
            highlight_paging = {},
          }
          local config = create_mock_config(data)
          local result =
            ReaderAnnotation.loadFromSettings(config, { paging = true })
          assert.are.equal(1, #result)
          assert.are.equal(2, result[1].page)
          assert.is_not_nil(data.annotations_rolling)
          assert.are.equal(1, #data.annotations_rolling)
          assert.are.equal("/body/p[1]", data.annotations_rolling[1].page)
          assert.is_nil(data.bookmarks_paging)
          assert.is_nil(data.highlight_paging)
          assert.is_true(data.annotations_externally_modified)
          assert.are.equal(data.annotations, result)
        end
      )

      it(
        "should migrate bookmarks_paging into annotations_paging when compatible rolling bookmarks loaded",
        function()
          local data = {
            highlights_imported = true,
            bookmarks = {
              {
                page = "/body/p[1]",
                datetime = "2026-08-25 00:00:00",
                notes = "Rolling note",
              },
            },
            highlight = {},
            bookmarks_paging = {
              {
                page = 10,
                datetime = "2026-08-25 00:00:00",
                notes = "Paging note",
              },
            },
            highlight_paging = {},
          }
          local config = create_mock_config(data)
          local result =
            ReaderAnnotation.loadFromSettings(config, { rolling = true })
          assert.are.equal(1, #result)
          assert.are.equal("/body/p[1]", result[1].page)
          assert.is_not_nil(data.annotations_paging)
          assert.are.equal(1, #data.annotations_paging)
          assert.are.equal(10, data.annotations_paging[1].page)
          assert.is_nil(data.bookmarks_paging)
          assert.is_nil(data.highlight_paging)
          assert.is_true(data.annotations_externally_modified)
        end
      )

      it(
        "should migrate bookmarks_rolling into annotations_rolling when compatible paging bookmarks loaded",
        function()
          local data = {
            highlights_imported = true,
            bookmarks = {
              {
                page = 5,
                datetime = "2026-08-25 00:00:00",
                notes = "Paging note",
              },
            },
            highlight = {},
            bookmarks_rolling = {
              {
                page = "/body/p[5]",
                datetime = "2026-08-25 00:00:00",
                notes = "Rolling note",
              },
            },
            highlight_rolling = {},
          }
          local config = create_mock_config(data)
          local result =
            ReaderAnnotation.loadFromSettings(config, { paging = true })
          assert.are.equal(1, #result)
          assert.are.equal(5, result[1].page)
          assert.is_not_nil(data.annotations_rolling)
          assert.are.equal(1, #data.annotations_rolling)
          assert.are.equal("/body/p[5]", data.annotations_rolling[1].page)
          assert.is_nil(data.bookmarks_rolling)
          assert.is_nil(data.highlight_rolling)
          assert.is_true(data.annotations_externally_modified)
        end
      )
    end)

    describe("rolling-mode swap and empty annotations restore", function()
      it(
        "should swap paging annotations to annotations_paging and load annotations_rolling in rolling mode",
        function()
          local data = {
            annotations = {
              { page = 5, datetime = "2026-08-25 10:00:00" },
            },
            annotations_rolling = {
              { page = "/body/p[1]", datetime = "2026-08-25 10:00:00" },
            },
          }
          local config = create_mock_config(data)
          local result =
            ReaderAnnotation.loadFromSettings(config, { rolling = true })
          assert.are.equal(1, #result)
          assert.are.equal("/body/p[1]", result[1].page)
          assert.is_not_nil(data.annotations_paging)
          assert.are.equal(1, #data.annotations_paging)
          assert.are.equal(5, data.annotations_paging[1].page)
          assert.is_nil(data.annotations_rolling)
          assert.is_true(data.annotations_externally_modified)
          assert.are.equal(data.annotations, result)
        end
      )

      it(
        "should restore from annotations_rolling when annotations is empty in rolling mode",
        function()
          local data = {
            annotations = {},
            annotations_rolling = {
              { page = "/body/p[1]", datetime = "2026-08-25 10:00:00" },
            },
          }
          local config = create_mock_config(data)
          local result =
            ReaderAnnotation.loadFromSettings(config, { rolling = true })
          assert.are.equal(1, #result)
          assert.are.equal("/body/p[1]", result[1].page)
          assert.is_nil(data.annotations_rolling)
          assert.is_nil(data.annotations_paging)
          assert.is_true(data.annotations_externally_modified)
          assert.are.equal(data.annotations, result)
        end
      )

      it(
        "should restore from annotations_paging when annotations is empty in paging mode",
        function()
          local data = {
            annotations = {},
            annotations_paging = {
              { page = 5, datetime = "2026-08-25 10:00:00" },
            },
          }
          local config = create_mock_config(data)
          local result =
            ReaderAnnotation.loadFromSettings(config, { paging = true })
          assert.are.equal(1, #result)
          assert.are.equal(5, result[1].page)
          assert.is_nil(data.annotations_paging)
          assert.is_nil(data.annotations_rolling)
          assert.is_true(data.annotations_externally_modified)
          assert.are.equal(data.annotations, result)
        end
      )
    end)

    describe("orphaned highlighted bookmark in paging mode", function()
      it(
        "should restore single-page highlight pboxes using start and end positions",
        function()
          local page_boxes_args = nil
          local mock_paging_ui = {
            paging = true,
            view = {
              highlight = {
                saved_drawer = "lighten",
                saved_color = "yellow",
              },
            },
            document = {
              hasHiddenFlows = function()
                return false
              end,
              getPageBoxesFromPositions = function(self, page, pos0, pos1)
                page_boxes_args = { page = page, pos0 = pos0, pos1 = pos1 }
                return { { x = 10, y = 20, w = 20, h = 20 } }
              end,
            },
          }
          local bm = {
            page = 5,
            highlighted = true,
            pos0 = { page = 5, x = 10, y = 20 },
            pos1 = { page = 5, x = 30, y = 40 },
            notes = "Single page highlight text",
            datetime = "2026-08-25 00:00:00",
          }
          local data = {
            highlights_imported = true,
            bookmarks = { bm },
            highlight = {},
          }
          local config = create_mock_config(data)
          local result =
            ReaderAnnotation.loadFromSettings(config, mock_paging_ui)
          assert.are.equal(1, #result)
          local ann_item = result[1]
          assert.are.equal(5, ann_item.page)
          assert.are.equal("lighten", ann_item.drawer)
          assert.are.equal("yellow", ann_item.color)
          assert.is_not_nil(ann_item.pboxes)
          assert.are.equal(1, #ann_item.pboxes)
          assert.are.same(
            { x = 10, y = 20, w = 20, h = 20 },
            ann_item.pboxes[1]
          )
          assert.is_not_nil(page_boxes_args)
          assert.are.equal(5, page_boxes_args.page)
          assert.are.same(bm.pos0, page_boxes_args.pos0)
          assert.are.same(bm.pos1, page_boxes_args.pos1)
        end
      )

      it(
        "should restore multi-page highlight pboxes using start position only",
        function()
          local page_boxes_args = nil
          local mock_paging_ui = {
            paging = true,
            view = {
              highlight = {
                saved_drawer = "underscore",
                saved_color = "green",
              },
            },
            document = {
              hasHiddenFlows = function()
                return false
              end,
              getPageBoxesFromPositions = function(self, page, pos0, pos1)
                page_boxes_args = { page = page, pos0 = pos0, pos1 = pos1 }
                return { { x = 10, y = 20, w = 50, h = 15 } }
              end,
            },
          }
          local bm = {
            page = 5,
            highlighted = true,
            pos0 = { page = 5, x = 10, y = 20 },
            pos1 = { page = 6, x = 30, y = 40 },
            notes = "Multi page highlight text",
            datetime = "2026-08-25 00:00:00",
          }
          local data = {
            highlights_imported = true,
            bookmarks = { bm },
            highlight = {},
          }
          local config = create_mock_config(data)
          local result =
            ReaderAnnotation.loadFromSettings(config, mock_paging_ui)
          assert.are.equal(1, #result)
          local ann_item = result[1]
          assert.are.equal(5, ann_item.page)
          assert.are.equal("underscore", ann_item.drawer)
          assert.are.equal("green", ann_item.color)
          assert.is_not_nil(ann_item.pboxes)
          assert.are.equal(1, #ann_item.pboxes)
          assert.are.same(
            { x = 10, y = 20, w = 50, h = 15 },
            ann_item.pboxes[1]
          )
          assert.is_not_nil(page_boxes_args)
          assert.are.equal(5, page_boxes_args.page)
          assert.are.same(bm.pos0, page_boxes_args.pos0)
          assert.are.same(bm.pos0, page_boxes_args.pos1)
        end
      )
    end)
  end)

  describe("ReaderAnnotation.markUpdated", function()
    it("should set datetime_updated with formatted timestamp", function()
      local item = { datetime = "2026-08-25 10:00:00" }
      ReaderAnnotation.markUpdated(item)
      assert.is_string(item.datetime_updated)
      assert.is_true(
        item.datetime_updated:match("^%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d$")
          ~= nil
      )
    end)

    it("should return the modified annotation table", function()
      local item = { datetime = "2026-08-25 10:00:00" }
      local ret = ReaderAnnotation.markUpdated(item)
      assert.are.equal(item, ret)
    end)

    it("should overwrite existing datetime_updated timestamp", function()
      local item = {
        datetime = "2026-08-25 10:00:00",
        datetime_updated = "2020-01-01 00:00:00",
      }
      ReaderAnnotation.markUpdated(item)
      assert.are_not.equal("2020-01-01 00:00:00", item.datetime_updated)
    end)

    it("should error cleanly when passed nil", function()
      assert.has_error(function()
        ReaderAnnotation.markUpdated(nil)
      end)
    end)
  end)

  describe("Defect verifications", function()
    it("getNumberOfHighlightsAndNotes counts items with drawer", function()
      local annotation = ReaderAnnotation:new({
        ui = {},
        document = {},
      })
      annotation.annotations = {
        { page = 3, note = "Chapter notes" },
        { page = 4, drawer = "lighten", note = "Drawer note" },
        { page = 5, drawer = "underscore" },
      }
      local highlights, notes = annotation:getNumberOfHighlightsAndNotes()
      assert.are.equal(1, highlights)
      assert.are.equal(1, notes)
    end)
  end)

  describe("ReaderAnnotation.willChangeAnnotations API", function()
    local UIManager = require("ui/uimanager")
    local Widget = require("ui/widget/widget")

    local function fastforward()
      UIManager:shiftScheduledTasksBy(-1e9)
      UIManager:_checkTasks()
    end

    local annotation, mock_ui

    before_each(function()
      mock_ui = {
        document = {
          file = "/tmp/test_book.epub",
          hasHiddenFlows = function()
            return false
          end,
        },
      }
      annotation = ReaderAnnotation:new({
        ui = mock_ui,
      })
    end)

    after_each(function()
      annotation:_releaseChangingFile()
      fastforward()
    end)

    it(
      "runs immediately and returns false when file is free, and file is free afterwards",
      function()
        local ran = false
        local ret = ReaderAnnotation.willChangeAnnotations(
          "/tmp/test_book.epub",
          function()
            ran = true
          end
        )
        assert.is_false(ret)
        assert.is_true(ran)

        local ran2 = false
        local ret2 = ReaderAnnotation.willChangeAnnotations(
          "/tmp/test_book.epub",
          function()
            ran2 = true
          end
        )
        assert.is_false(ret2)
        assert.is_true(ran2)
      end
    )

    it(
      "queues callback, returns true while session holds file, and runs after session ends (one tick)",
      function()
        local widget = Widget:new()
        annotation:trackChangingWidget(widget)

        local waiter_ran = false
        local ret = ReaderAnnotation.willChangeAnnotations(
          "/tmp/test_book.epub",
          function()
            waiter_ran = true
          end
        )
        assert.is_true(ret)
        assert.is_false(waiter_ran)

        widget:onClose()
        assert.is_false(waiter_ran)

        fastforward()
        assert.is_true(waiter_ran)
      end
    )

    it("executes queued callbacks in FIFO order across 3 callbacks", function()
      local widget = Widget:new()
      annotation:trackChangingWidget(widget)

      local order = {}
      ReaderAnnotation.willChangeAnnotations("/tmp/test_book.epub", function()
        table.insert(order, 1)
      end)
      ReaderAnnotation.willChangeAnnotations("/tmp/test_book.epub", function()
        table.insert(order, 2)
      end)
      ReaderAnnotation.willChangeAnnotations("/tmp/test_book.epub", function()
        table.insert(order, 3)
      end)
      assert.are.same({}, order)

      widget:onClose()
      fastforward()
      assert.are.same({ 1, 2, 3 }, order)
    end)

    it("maintains per-file independence", function()
      local ran_a, ran_b = false, false
      ReaderAnnotation.willChangeAnnotations("/tmp/file_a.epub", function()
        ran_a = true
      end)
      ReaderAnnotation.willChangeAnnotations("/tmp/file_b.epub", function()
        ran_b = true
      end)
      assert.is_true(ran_a)
      assert.is_true(ran_b)
    end)

    it(
      "handles callback errors: propagates error and leaves file free for next call",
      function()
        local ok, err = pcall(function()
          ReaderAnnotation.willChangeAnnotations(
            "/tmp/test_book.epub",
            function()
              error("test boom")
            end
          )
        end)
        assert.is_false(ok)
        assert.truthy(err:find("test boom"))
        assert.truthy(err:find("stack traceback:"))

        local ran = false
        local ret = ReaderAnnotation.willChangeAnnotations(
          "/tmp/test_book.epub",
          function()
            ran = true
          end
        )
        assert.is_false(ret)
        assert.is_true(ran)
      end
    )

    it(
      "runs second queued callback and frees file even if first queued callback raises",
      function()
        local widget = Widget:new()
        annotation:trackChangingWidget(widget)

        local second_ran = false
        ReaderAnnotation.willChangeAnnotations("/tmp/test_book.epub", function()
          error("first callback failed")
        end)
        ReaderAnnotation.willChangeAnnotations("/tmp/test_book.epub", function()
          second_ran = true
        end)

        widget:onClose()
        local ok, err = pcall(function()
          fastforward()
        end)
        assert.is_false(ok)
        assert.truthy(err:find("first callback failed"))
        assert.is_true(second_ran)

        local ran = false
        local ret = ReaderAnnotation.willChangeAnnotations(
          "/tmp/test_book.epub",
          function()
            ran = true
          end
        )
        assert.is_false(ret)
        assert.is_true(ran)
      end
    )

    it(
      "runs all queued callbacks and propagates first error when multiple queued callbacks raise",
      function()
        local widget = Widget:new()
        annotation:trackChangingWidget(widget)

        local first_ran = false
        local second_ran = false
        ReaderAnnotation.willChangeAnnotations("/tmp/test_book.epub", function()
          first_ran = true
          error("first callback failed")
        end)
        ReaderAnnotation.willChangeAnnotations("/tmp/test_book.epub", function()
          second_ran = true
          error("second callback failed")
        end)

        widget:onClose()
        local ok, err = pcall(function()
          fastforward()
        end)
        assert.is_false(ok)
        assert.is_true(first_ran)
        assert.is_true(second_ran)
        assert.truthy(err:find("first callback failed"))
        assert.falsy(err:find("second callback failed"))

        local ran = false
        local ret = ReaderAnnotation.willChangeAnnotations(
          "/tmp/test_book.epub",
          function()
            ran = true
          end
        )
        assert.is_false(ret)
        assert.is_true(ran)
      end
    )

    it(
      "asserts on nested willChangeAnnotations for the same file from inside callback",
      function()
        local asserted = false
        ReaderAnnotation.willChangeAnnotations("/tmp/test_book.epub", function()
          local ok, err = pcall(function()
            ReaderAnnotation.willChangeAnnotations(
              "/tmp/test_book.epub",
              function() end
            )
          end)
          assert.is_false(ok)
          assert.truthy(
            err:find(
              "willChangeAnnotations called from a callback changing /tmp/test_book.epub"
            )
          )
          asserted = true
        end)
        assert.is_true(asserted)
      end
    )

    it(
      "asserts on trackChangingWidget from inside a running callback for the same file",
      function()
        local asserted = false
        ReaderAnnotation.willChangeAnnotations("/tmp/test_book.epub", function()
          local ok, err = pcall(function()
            annotation:trackChangingWidget(Widget:new())
          end)
          assert.is_false(ok)
          asserted = true
        end)
        assert.is_true(asserted)
      end
    )
  end)

  describe("ReaderAnnotation:trackChangingWidget and dialog lock", function()
    local UIManager = require("ui/uimanager")
    local ButtonDialog = require("ui/widget/buttondialog")
    local Widget = require("ui/widget/widget")

    local function fastforward()
      UIManager:shiftScheduledTasksBy(-1e9)
      UIManager:_checkTasks()
    end

    local annotation, mock_ui

    before_each(function()
      mock_ui = {
        document = {
          file = "/tmp/test_book.epub",
          hasHiddenFlows = function()
            return false
          end,
        },
      }
      annotation = ReaderAnnotation:new({
        ui = mock_ui,
      })
    end)

    after_each(function()
      annotation:_releaseChangingFile()
      fastforward()
    end)

    it("(1) waiter fn does not run while a highlight dialog is open", function()
      local widget = Widget:new()
      annotation:trackChangingWidget(widget)

      local waiter_ran = false
      local ret = ReaderAnnotation.willChangeAnnotations(
        "/tmp/test_book.epub",
        function()
          waiter_ran = true
        end
      )
      assert.is_true(ret)
      assert.is_false(waiter_ran)

      widget:onClose()
      fastforward()
      assert.is_true(waiter_ran)
    end)

    it(
      "(2) waiter fn does not run across close(A) and open(B) in one call",
      function()
        local widget_a = Widget:new()
        local widget_b = Widget:new()
        annotation:trackChangingWidget(widget_a)

        local waiter_ran = false
        ReaderAnnotation.willChangeAnnotations("/tmp/test_book.epub", function()
          waiter_ran = true
        end)
        assert.is_false(waiter_ran)

        widget_a:onClose()
        annotation:trackChangingWidget(widget_b)

        fastforward()
        assert.is_false(waiter_ran)

        widget_b:onClose()
        fastforward()
        assert.is_true(waiter_ran)
      end
    )

    it(
      "(3) waiter fn does not run across bookmark-menu close-and-reopen",
      function()
        local bm_menu_1 = Widget:new()
        local bm_menu_2 = Widget:new()
        annotation:trackChangingWidget(bm_menu_1)

        local waiter_ran = false
        ReaderAnnotation.willChangeAnnotations("/tmp/test_book.epub", function()
          waiter_ran = true
        end)
        assert.is_false(waiter_ran)

        bm_menu_1:onClose()
        annotation:trackChangingWidget(bm_menu_2)

        fastforward()
        assert.is_false(waiter_ran)

        bm_menu_2:onClose()
        fastforward()
        assert.is_true(waiter_ran)
      end
    )

    it(
      "(4) tracked dialog on top: closing it does not release; closing the bottom one does after one tick",
      function()
        local bottom = Widget:new()
        local top = Widget:new()
        annotation:trackChangingWidget(bottom)
        annotation:trackChangingWidget(top)

        local waiter_ran = false
        ReaderAnnotation.willChangeAnnotations("/tmp/test_book.epub", function()
          waiter_ran = true
        end)
        assert.is_false(waiter_ran)

        top:onClose()
        fastforward()
        assert.is_false(waiter_ran)

        bottom:onClose()
        fastforward()
        assert.is_true(waiter_ran)
      end
    )

    it(
      "(5) open(B) then close(A) in one call keeps lock and waiter runs after B closes",
      function()
        local widget_a = Widget:new()
        local widget_b = Widget:new()
        annotation:trackChangingWidget(widget_a)

        local waiter_ran = false
        ReaderAnnotation.willChangeAnnotations("/tmp/test_book.epub", function()
          waiter_ran = true
        end)
        assert.is_false(waiter_ran)

        annotation:trackChangingWidget(widget_b)
        widget_a:onClose()

        fastforward()
        assert.is_false(waiter_ran)

        widget_b:onClose()
        fastforward()
        assert.is_true(waiter_ran)
      end
    )

    it(
      "(6) waiter fn runs once chain ends via button, onExit, or UIManager:close after one tick",
      function()
        -- 6a: via UIManager:close / onClose
        local widget = Widget:new()
        annotation:trackChangingWidget(widget)

        local waiter_ran = false
        ReaderAnnotation.willChangeAnnotations("/tmp/test_book.epub", function()
          waiter_ran = true
        end)
        assert.is_false(waiter_ran)

        widget:onClose()
        assert.is_false(waiter_ran)

        fastforward()
        assert.is_true(waiter_ran)

        -- 6b: via onExit (e.g. tap-outside or Back on ButtonDialog)
        local dialog = ButtonDialog:new({
          buttons = {
            {
              { text = "OK" },
            },
          },
        })
        annotation:trackChangingWidget(dialog)
        UIManager:show(dialog)

        waiter_ran = false
        ReaderAnnotation.willChangeAnnotations("/tmp/test_book.epub", function()
          waiter_ran = true
        end)
        assert.is_false(waiter_ran)

        dialog:onExit()
        assert.is_false(waiter_ran)

        fastforward()
        assert.is_true(waiter_ran)
      end
    )

    it("(7a) onCloseDocument with a dialog open releases once", function()
      local widget = Widget:new()
      annotation:trackChangingWidget(widget)

      local waiter_ran = false
      ReaderAnnotation.willChangeAnnotations("/tmp/test_book.epub", function()
        waiter_ran = true
      end)
      assert.is_false(waiter_ran)

      annotation:onCloseDocument()
      assert.is_true(waiter_ran)

      local ran_new = false
      local ret = ReaderAnnotation.willChangeAnnotations(
        "/tmp/test_book.epub",
        function()
          ran_new = true
        end
      )
      assert.is_false(ret)
      assert.is_true(ran_new)

      assert.has_no.errors(function()
        widget:onClose()
        fastforward()
      end)
    end)

    it("(7b) onClose with a dialog open releases once", function()
      local widget = Widget:new()
      annotation:trackChangingWidget(widget)

      local waiter_ran = false
      ReaderAnnotation.willChangeAnnotations("/tmp/test_book.epub", function()
        waiter_ran = true
      end)
      assert.is_false(waiter_ran)

      annotation:onClose()
      assert.is_true(waiter_ran)

      local ran_new = false
      local ret = ReaderAnnotation.willChangeAnnotations(
        "/tmp/test_book.epub",
        function()
          ran_new = true
        end
      )
      assert.is_false(ret)
      assert.is_true(ran_new)

      assert.has_no.errors(function()
        widget:onClose()
        fastforward()
      end)
    end)

    it("asserts in trackChangingWidget and onClose on state violations", function()
      local widget = Widget:new()
      annotation:trackChangingWidget(widget)

      local other_widget = Widget:new()
      local orig_file = annotation.ui.document.file
      annotation.ui.document.file = "/tmp/different_book.epub"
      assert.has_error(function()
        annotation:trackChangingWidget(other_widget)
      end)
      annotation.ui.document.file = orig_file

      widget:onClose()

      local dummy_widget = Widget:new()
      annotation:trackChangingWidget(dummy_widget)
      annotation._changing_widgets = 0
      assert.has_error(function()
        dummy_widget:onClose()
      end)
      fastforward()
    end)
  end)
end)
