describe("ReaderAnnotation module", function()
  local ReaderAnnotation

  setup(function()
    require("commonrequire")
    ReaderAnnotation = require("apps/reader/modules/readerannotation")
  end)

  it("should build annotation using decoupled self.ui.view.highlight reference", function()
    local mock_ui = {
      view = {
        highlight = {
          saved_drawer = "lighten",
          saved_color = "yellow",
        },
      },
      bookmark = {
        isBookmarkAutoText = function() return false end,
      },
      toc = {
        getTocTitleByPage = function() return "Chapter 1" end,
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
  end)
end)
