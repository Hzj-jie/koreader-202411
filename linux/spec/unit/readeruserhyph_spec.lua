describe("ReaderUserHyph module", function()
  local ReaderUserHyph, DocumentRegistry, ReaderUI, Screen, lfs

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    ReaderUserHyph = require("apps/reader/modules/readeruserhyph")
    DocumentRegistry = require("document/documentregistry")
    ReaderUI = require("apps/reader/readerui")
    Screen = require("device").screen
    lfs = require("libs/libkoreader-lfs")
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

  it("should build menu entry and check availability", function()
    local hyph = ReaderUserHyph:new({
      ui = {
        typography = { hyphenation = true },
      },
    })
    G_reader_settings:save("hyph_user_dict", true)
    assert.is_true(hyph:isAvailable())

    local entry = hyph:getMenuEntry()
    assert.is_table(entry)
    assert.is_function(entry.callback)
    assert.is_function(entry.checked_func)
  end)

  it("should update and scrub dictionary files", function()
    local tmp_file = os.tmpname()

    local hyph = ReaderUserHyph:new({
      ui = {
        typography = { hyphenation = true },
      },
      getDictionaryPath = function()
        return tmp_file
      end,
      loadUserDictionary = function() end,
    })

    hyph:updateDictionary("example", "ex-am-ple")
    assert.is_true(lfs.attributes(tmp_file, "mode") == "file")

    hyph:updateDictionary("apple", "ap-ple")
    hyph:scrubDictionary()

    -- Multiple hyphen modifications
    hyph:updateDictionary("apple", "ap-p-le")
    hyph:updateDictionary("apple", nil) -- deletion

    os.remove(tmp_file)
  end)

  it("should handle modifyUserEntry dialog workflow", function()
    local sample_epub = "spec/front/unit/data/leaves.epub"
    local readerui = ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(sample_epub),
    })

    local userhyph = readerui.userhyph or ReaderUserHyph:new({ ui = readerui })

    local shown_widget
    local UIManager = require("ui/uimanager")
    local orig_show = UIManager.show
    UIManager.show = function(self, w)
      shown_widget = w
    end

    userhyph:modifyUserEntry("multi word test") -- space -> ignored
    assert.is_nil(shown_widget)

    userhyph:modifyUserEntry("hyphenation")
    assert.is_not_nil(shown_widget)

    -- Test language change event
    userhyph:onTypographyLanguageChanged()

    UIManager.show = orig_show
    readerui:onExit()
    readerui:onClose()
  end)
end)
