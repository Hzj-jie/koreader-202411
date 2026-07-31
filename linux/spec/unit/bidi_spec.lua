describe("BiDi UI and text module", function()
  local Bidi

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    Bidi = require("ui/bidi")
  end)

  it("should setup LTR language configuration", function()
    Bidi.setup("en")
    assert.is_false(Bidi.mirroredUILayout())
    assert.is_false(Bidi.rtlUIText())

    assert.are.equal("east", Bidi.flipDirectionIfMirroredUILayout("east"))
    assert.is_true(Bidi.flipIfMirroredUILayout(true))
  end)

  it("should setup RTL language configuration and direction flipping", function()
    Bidi.setup("ar")
    assert.is_true(Bidi.mirroredUILayout())
    assert.is_true(Bidi.rtlUIText())

    assert.are.equal("west", Bidi.flipDirectionIfMirroredUILayout("east"))
    assert.are.equal("east", Bidi.flipDirectionIfMirroredUILayout("west"))
    assert.is_false(Bidi.flipIfMirroredUILayout(true))
  end)

  it("should handle layout inversion and reset", function()
    Bidi.setup("en")
    assert.is_false(Bidi.mirroredUILayout())

    Bidi.invert()
    assert.is_true(Bidi.mirroredUILayout())

    Bidi.resetInvert()
    assert.is_false(Bidi.mirroredUILayout())
  end)

  it("should format LTR and RTL text isolate strings", function()
    local text = "Hello"
    local ltr_text = Bidi.ltr(text)
    assert.is_string(ltr_text)
    assert.is_true(ltr_text:find("Hello") ~= nil)
  end)
end)
