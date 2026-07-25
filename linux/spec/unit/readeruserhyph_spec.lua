describe("ReaderUserHyph module", function()
  local ReaderUserHyph, DocumentRegistry, ReaderUI, Screen

  setup(function()
    require("commonrequire")
    ReaderUserHyph = require("apps/reader/modules/readeruserhyph")
    DocumentRegistry = require("document/documentregistry")
    ReaderUI = require("apps/reader/readerui")
    Screen = require("device").screen
  end)

  it("should initialize user hyph module", function()
    local sample_epub = "spec/front/unit/data/leaves.epub"
    local readerui = ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(sample_epub),
    })

    local userhyph = readerui.userhyph
    assert.is_table(userhyph)
    assert.is_function(userhyph.getDictionaryPath)

    local dict_path = userhyph:getDictionaryPath()
    assert.is_string(dict_path)

    readerui:onExit()
    readerui:onClose()
  end)

  it("should validate hyphenation suggestions", function()
    assert.is_true(
      ReaderUserHyph:checkHyphenation("hy-phe-na-tion", "hyphenation")
    )
    assert.is_false(
      ReaderUserHyph:checkHyphenation("hy--phenation", "hyphenation")
    )
    assert.is_false(ReaderUserHyph:checkHyphenation("different", "hyphenation"))
  end)
end)
