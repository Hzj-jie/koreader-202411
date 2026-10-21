local FT
local HB
local coverage

describe("ffi/harfbuzz module", function()
  local font_path = "fonts/droid/DroidSansMono.ttf"

  setup(function()
    require("commonrequire")
    FT = require("ffi/freetype")
    HB = require("ffi/harfbuzz")
    coverage = require("ffi/harfbuzz_coverage")
  end)

  it("extracts names and scripts from font face", function()
    local ftsize = FT.newFaceSize(font_path, nil, 0)
    assert.is_not_nil(ftsize)
    local hbface = HB.hb_ft_face_create_referenced(ftsize.face)
    assert.is_not_nil(hbface)

    local names = hbface:getNames()
    assert.is_table(names)

    local scripts, langs = hbface:getCoverage()
    assert.is_table(scripts)
    assert.is_table(langs)
    local script_count = 0
    for _ in pairs(scripts) do
      script_count = script_count + 1
    end
    assert.is_true(script_count > 0)

    hbface:destroy()
    ftsize:done()
  end)
end)
