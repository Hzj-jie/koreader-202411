describe("VocabBuilder plugin", function()
  local VocabBuilder

  setup(function()
    require("commonrequire")
    VocabBuilder = require("plugins/vocabbuilder.koplugin/main")
  end)

  it("should initialize VocabBuilder class", function()
    assert.is_table(VocabBuilder)
    assert.is_function(VocabBuilder.new)
  end)

  it("should populate main menu items", function()
    local vb = VocabBuilder:new({
      ui = {
        menu = {
          registerToMainMenu = function() end,
        },
      },
    })
    local items = {}
    vb:addToMainMenu(items)
    assert.is_table(items.vocabbuilder)
  end)

  it("should test settings initialization and options", function()
    local vb = VocabBuilder:new({
      ui = {
        menu = {
          registerToMainMenu = function() end,
        },
      },
    })
    vb:init()
    assert.is_table(vb.ui)
    assert.is_function(vb.onWordLookedUp)
  end)
end)
