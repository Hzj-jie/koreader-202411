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

  it("should initialize annotation module", function()
    local sample_epub = "spec/front/unit/data/leaves.epub"
    local readerui = ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(sample_epub),
    })

    local annotation = readerui.annotation
    assert.is_table(annotation)

    readerui:onExit()
    readerui:onClose()
  end)
end)
