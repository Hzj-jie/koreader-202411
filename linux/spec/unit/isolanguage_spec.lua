describe("IsoLanguage", function()
  local IsoLanguage

  setup(function()
    require("commonrequire")
    IsoLanguage = require("ui/data/isolanguage")
  end)

  it("should get localized language for known and unknown codes", function()
    assert.are.equal("English", IsoLanguage:getLocalizedLanguage("eng"))
    assert.are.equal("French", IsoLanguage:getLocalizedLanguage("fra"))
    assert.are.equal("German", IsoLanguage:getLocalizedLanguage("deu"))
    assert.are.equal("unknown_code", IsoLanguage:getLocalizedLanguage("unknown_code"))
  end)

  it("should get BCP language tag for known and unknown codes", function()
    assert.are.equal("en", IsoLanguage:getBCPLanguageTag("eng"))
    assert.are.equal("fr", IsoLanguage:getBCPLanguageTag("fra"))
    assert.are.equal("de", IsoLanguage:getBCPLanguageTag("deu"))
    assert.are.equal("zh", IsoLanguage:getBCPLanguageTag("zho"))
    assert.are.equal("custom_code", IsoLanguage:getBCPLanguageTag("custom_code"))
  end)
end)
