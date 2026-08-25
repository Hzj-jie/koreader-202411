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
        pos0 = { page = 5 },
        pos1 = { page = 5 },
      }
      local highlights = {}

      local ann = annotation_module:buildAnnotation(bm, highlights, true)
      assert.is_not_nil(ann)
      assert.are.equal("Sample Note", ann.note)
      assert.are.equal("lighten", ann.drawer)
      assert.are.equal("yellow", ann.color)
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
        getPageCount = function() return 100 end,
        getPageFromXPointer = function(_, xp) return 5 end,
        compareXPointers = function(_, a, b)
          if a == b then return 0 end
          return a > b and 1 or -1
        end,
        comparePositions = function(_, a, b)
          if not a or not b then return 0 end
          if a.x == b.x then
            return a.y == b.y and 0 or (a.y < b.y and 1 or -1)
          end
          return a.x < b.x and 1 or -1
        end,
        getPageBoxesFromPositions = function()
          return { { x = 0, y = 0, w = 50, h = 20 } }
        end,
        hasHiddenFlows = function() return true end,
        getPageFlow = function(_, pn) return pn == 10 and 1 or 0 end,
        getPageNumberInFlow = function(_, pn) return pn end,
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
          getTocTitleByPage = function(_, p) return "Chapter 1" end,
        },
        bookmark = {
          isBookmarkAutoText = function(_, bm) return bm.text == "AutoText" end,
        },
      }

      ann = ReaderAnnotation:new({
        ui = mock_ui,
        view = mock_view,
        document = mock_doc,
        annotations = {},
      })
    end)

    it("should build annotation from bookmarks and highlights in rolling mode", function()
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
            page = "/body/div/p[1]",
            pos1 = "/body/div/p[2]",
            drawer = "lighten",
            color = "yellow",
          }
        }
      }

      local item = ann:buildAnnotation(bm, highlights, true)
      assert.is_table(item)
      assert.are.equal("Sample Highlight", item.text)
      assert.are.equal("My Note", item.note)
      assert.are.equal("Chapter 1", item.chapter)
      assert.are.equal(5, item.pageno)

      -- Add item and verify insertion & indexing
      local idx = ann:addItem(item)
      assert.are.equal(1, idx)
      assert.are.equal(1, ann:getItemIndex(item))
      assert.are.equal(1, ann:getItemIndex(item, true)) -- linear search fallback

      -- Update item by xpointer
      ann:updateItemByXPointer(item)
      assert.are.equal("Chapter 1", item.chapter)

      -- Page reference string
      local pref = ann:getPageRef("/body/div/p[1]", 10)
      assert.are.equal("[10]1", pref)
      local pref0 = ann:getPageRef("/body/div/p[1]", 5)
      assert.are.equal("5", pref0)
    end)

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
          { page = 1, text = "Old Page", pos0 = { x = 0, y = 0 }, pos1 = { x = 10, y = 10 } }
        },
        annotations_externally_modified = true,
      }
      local config = {
        has = function(self, k) return data[k] ~= nil end,
        hasNot = function(self, k) return data[k] == nil end,
        read = function(self, k) return data[k] end,
        readTable = function(self, k) return data[k] end,
        readTableRef = function(self, k) return data[k] end,
        save = function(self, k, v) data[k] = v end,
        delete = function(self, k) data[k] = nil end,
        isTrue = function(self, k) return data[k] == true end,
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
          { page = 1, datetime = "2026-08-25 00:00:00", notes = "Bookmark" }
        },
        highlight = {
          [1] = {
            { text = "Highlight", datetime = "2026-08-25 00:00:00", pos0 = { x = 0, y = 0 }, pos1 = { x = 10, y = 0 } }
          }
        }
      }
      local config = {
        has = function(self, k) return data[k] ~= nil end,
        hasNot = function(self, k) return data[k] == nil end,
        read = function(self, k) return data[k] end,
        readTable = function(self, k) return data[k] end,
        readTableRef = function(self, k) return data[k] end,
        save = function(self, k, v) data[k] = v end,
        delete = function(self, k) data[k] = nil end,
        isTrue = function(self, k) return data[k] == true end,
      }

      mock_ui.rolling = false
      mock_ui.paging = true
      ann:onReadSettings(config)
      assert.is_table(ann.annotations)
      assert.is_true(#ann.annotations > 0)
    end)
  end)
end)

