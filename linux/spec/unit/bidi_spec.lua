describe("BiDi UI and text module", function()
  local Bidi, gettext

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    Bidi = require("ui/bidi")
    gettext = require("gettext")
  end)

  it("should setup LTR language configuration", function()
    Bidi.setup("en")
    assert.is_false(Bidi.mirroredUILayout())
    assert.is_false(Bidi.rtlUIText())

    assert.are.equal("east", Bidi.flipDirectionIfMirroredUILayout("east"))
    assert.is_true(Bidi.flipIfMirroredUILayout(true))
    assert.is_false(Bidi.flipIfMirroredUILayout(false))

    -- Untranslated string wrapping in LTR
    assert.are.equal("Hello World", gettext.wrapUntranslated("Hello World"))
  end)

  it("should setup RTL language configuration and direction flipping", function()
    Bidi.setup("ar")
    assert.is_true(Bidi.mirroredUILayout())
    assert.is_true(Bidi.rtlUIText())

    assert.are.equal("west", Bidi.flipDirectionIfMirroredUILayout("east"))
    assert.are.equal("east", Bidi.flipDirectionIfMirroredUILayout("west"))
    assert.are.equal("northwest", Bidi.flipDirectionIfMirroredUILayout("northeast"))
    assert.are.equal("northeast", Bidi.flipDirectionIfMirroredUILayout("northwest"))
    assert.are.equal("southwest", Bidi.flipDirectionIfMirroredUILayout("southeast"))
    assert.are.equal("southeast", Bidi.flipDirectionIfMirroredUILayout("southwest"))
    assert.are.equal("custom_dir", Bidi.flipDirectionIfMirroredUILayout("custom_dir"))

    assert.is_false(Bidi.flipIfMirroredUILayout(true))
    assert.is_true(Bidi.flipIfMirroredUILayout(false))

    -- Untranslated string wrapping in RTL (split by lines)
    local wrapped = gettext.wrapUntranslated("Line 1\nLine 2\n")
    assert.is_string(wrapped)
    assert.is_true(wrapped:find("Line 1") ~= nil)
    assert.is_true(wrapped:find("Line 2") ~= nil)

    -- Reset back to en
    Bidi.setup("en")
  end)

  it("should handle development settings overrides for mirroring and text direction", function()
    -- Reverse layout mirroring
    G_reader_settings:save("dev_reverse_ui_layout_mirroring", true)
    Bidi.setup("en")
    assert.is_true(Bidi.mirroredUILayout())
    G_reader_settings:save("dev_reverse_ui_layout_mirroring", nil)

    -- Reverse text direction
    G_reader_settings:save("dev_reverse_ui_text_direction", true)
    Bidi.setup("en")
    assert.is_true(Bidi.rtlUIText())
    G_reader_settings:save("dev_reverse_ui_text_direction", nil)

    -- xtext_alt_lang and use_xtext
    G_reader_settings:save("xtext_alt_lang", "fr")
    G_reader_settings:save("use_xtext", false)
    Bidi.setup("en")
    G_reader_settings:save("xtext_alt_lang", nil)
    G_reader_settings:save("use_xtext", nil)

    Bidi.setup("en")
  end)

  it("should handle layout inversion and reset (including idempotent calls)", function()
    Bidi.setup("en")
    assert.is_false(Bidi.mirroredUILayout())

    Bidi.invert()
    assert.is_true(Bidi.mirroredUILayout())
    -- Calling invert again when already inverted is a no-op
    Bidi.invert()
    assert.is_true(Bidi.mirroredUILayout())

    Bidi.resetInvert()
    assert.is_false(Bidi.mirroredUILayout())
    -- Calling resetInvert again is a no-op
    Bidi.resetInvert()
    assert.is_false(Bidi.mirroredUILayout())
  end)

  it("should format LTR, RTL, auto, default, nowrap, and wrap isolates", function()
    local text = "Hello"
    assert.is_true(Bidi.ltr(text):find("Hello") ~= nil)
    assert.is_true(Bidi.rtl(text):find("Hello") ~= nil)
    assert.is_true(Bidi.auto(text):find("Hello") ~= nil)
    assert.are.equal("Hello", Bidi.nowrap("Hello"))

    Bidi.setup("en")
    assert.is_true(Bidi.default("Hello"):find("Hello") ~= nil)
    assert.are.equal("Hello", Bidi.wrap("Hello"))

    Bidi.setup("ar")
    assert.is_true(Bidi.default("Hello"):find("Hello") ~= nil)
    assert.is_true(Bidi.wrap("Hello"):find("Hello") ~= nil)
    Bidi.setup("en")
  end)

  it("should format filenames, filepaths, and paths in LTR and RTL", function()
    -- Filename LTR
    assert.is_string(Bidi._filename_ltr("book.epub"))
    assert.is_string(Bidi._filename_ltr("book_without_extension"))

    -- Filename RTL
    assert.is_string(Bidi._filename_rtl("book.epub"))
    assert.is_string(Bidi._filename_rtl("book_without_extension"))

    -- Auto extension right
    assert.is_string(Bidi._filename_auto_ext_right("book.epub"))
    assert.is_string(Bidi._filename_auto_ext_right("book_without_extension"))

    -- Path
    assert.is_string(Bidi._path("/home/user/books/"))

    -- Filepath LTR and RTL
    assert.is_string(Bidi._filepath_ltr("/home/user/books/book.epub"))
    assert.is_string(Bidi._filepath_rtl("/home/user/books/book.epub"))
  end)
end)
