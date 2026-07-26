describe("ParserHelp module for Calculator", function()
  local ParserHelp

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    package.path = "plugins/calculator.koplugin/formulaparser/?.lua;" .. package.path
    ParserHelp = require("plugins/calculator.koplugin/formulaparser/parserhelp")
  end)

  describe("Help text & table exposure", function()
    it("should expose help text and functions table", function()
      assert.is_table(ParserHelp)
      assert.is_string(ParserHelp.help_text)
      assert.True(#ParserHelp.help_text > 0)
      if type(ParserHelp.getHelp) == "function" then
        local help = ParserHelp:getHelp()
        assert.is_table(help)
      end
    end)
  end)
end)
