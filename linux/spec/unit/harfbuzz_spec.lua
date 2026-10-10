local FT
local HB
local coverage

describe("ffi/harfbuzz module", function()
  local font_path = "../koreader/fonts/droid/DroidSansMono.ttf"

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

  it(
    "safely handles languages with zero glyphs in getCoverage without nil comparison crash",
    function()
      local ftsize = FT.newFaceSize(font_path, nil, 0)
      local hbface = HB.hb_ft_face_create_referenced(ftsize.face)

      -- Register an empty language set in coverage.langs
      local empty_set = HB.hb_set_create()
      coverage.langs["empty_test_lang"] = empty_set

      local ok, err = pcall(function()
        return hbface:getCoverage()
      end)

      coverage.langs["empty_test_lang"] = nil
      HB.hb_set_destroy(empty_set)
      hbface:destroy()
      ftsize:done()

      -- In expected behavior, an empty language definition with total == 0 should yield 0 coverage.
      -- In production line 88, `if total > coverage_thresholds[i]` fails for total == 0,
      -- leaving `found = nil` and crashing at line 92 with `attempt to compare number with nil`.
      assert.is_true(ok, tostring(err))
    end
  )
end)
