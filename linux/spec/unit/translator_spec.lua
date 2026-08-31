local dutch_wikipedia_text =
  "Wikipedia is een meertalige encyclopedie, waarvan de inhoud vrij beschikbaar is. Iedereen kan hier kennis toevoegen!"
local Translator

describe("Translator module", function()
  local orig_http_request
  setup(function()
    require("commonrequire")
    Translator = require("ui/translator")

    local http = require("socket.http")
    orig_http_request = http.request
    http.request = function(request)
      local url_str = type(request) == "table" and request.url or request
      if url_str and string.find(url_str, "error_test") then
        return nil, "Connection refused"
      end
      if url_str and (string.find(url_str, "translate.google") or string.find(url_str, "googleapis.com")) then
        local response_json =
          [=[[[["Wikipedia is a multilingual encyclopedia, the content of which is freely available. Anyone can add knowledge here!", "Wikipedia is een meertalige encyclopedie, waarvan de inhoud vrij beschikbaar is. Iedereen kan hier kennis toevoegen!", null, null, 3]], null, "nl"]]=]
        if type(request) == "table" and request.sink then
          request.sink(response_json)
        end
        return 1,
          200,
          { ["content-type"] = "application/json" },
          "HTTP/1.1 200 OK"
      end
      return 1, 200, {}, "OK"
    end
  end)

  teardown(function()
    local http = require("socket.http")
    http.request = orig_http_request
  end)

  it("should return server", function()
    assert.is.same(
      "https://translate.googleapis.com/",
      Translator:getTransServer()
    )
    G_reader_settings:save("trans_server", "http://translate.google.nl")
    G_reader_settings:flush()
    assert.is.same("http://translate.google.nl", Translator:getTransServer())
    G_reader_settings:delete("trans_server")
    G_reader_settings:flush()
  end)

  it("should return translation and handle errors", function()
    local translation_result = Translator:translate(dutch_wikipedia_text, "en")
    assert.is.truthy(translation_result)
    assert.is_true(#translation_result > 50 and #translation_result < 200)

    -- Test error handling with custom from and to
    local orig_server = Translator.getTransServer
    Translator.getTransServer = function()
      return "https://error_test.com/"
    end
    local ok, err = pcall(function()
      return Translator:translate(dutch_wikipedia_text, "en", "nl")
    end)
    assert.is_false(ok)
    assert.is_not_nil(err)
    Translator.getTransServer = orig_server
  end)

  it("should autodetect language and handle errors", function()
    local detect_result = Translator:detect(dutch_wikipedia_text)
    assert.is.same("nl", detect_result)

    local orig_server = Translator.getTransServer
    Translator.getTransServer = function()
      return "https://error_test.com/"
    end
    local ok, err = pcall(function()
      return Translator:detect(dutch_wikipedia_text)
    end)
    assert.is_false(ok)
    Translator.getTransServer = orig_server
  end)

  it("should map language codes and names correctly", function()
    local name1, supported1 = Translator:getLanguageName("en", "Default")
    assert.is_true(supported1)
    assert.is_string(name1)

    local name2, supported2 = Translator:getLanguageName("zh-CN", "Default")
    assert.is_true(supported2)
    assert.is_string(name2)

    local name3, supported3 =
      Translator:getLanguageName("unknown_xyz", "Default")
    assert.is_false(supported3)
    assert.are.equal("UNKNOWN_XYZ", name3)

    local name4, supported4 = Translator:getLanguageName(nil, "Default")
    assert.is_false(supported4)
    assert.are.equal("Default", name4)
  end)

  it("should get document language and target language", function()
    local ReaderUI = require("apps/reader/readerui")
    local orig_instance = ReaderUI.instance
    ReaderUI.instance = {
      doc_props = { language = "fr-FR" },
    }

    local lang1, name1 = Translator:getDocumentLanguage()
    assert.are.equal("fr", lang1)
    assert.is_string(name1)

    -- Test typography alias fallback
    ReaderUI.instance.doc_props.language = "fra"
    local lang2, name2 = Translator:getDocumentLanguage()
    assert.are.equal("fr", lang2)
    assert.is_string(name2)

    -- When nil
    ReaderUI.instance.doc_props.language = nil
    local lang3 = Translator:getDocumentLanguage()
    assert.is_nil(lang3)

    ReaderUI.instance = orig_instance
  end)

  it("should build and exercise settings menu table", function()
    local menu_entry = Translator:genSettingsMenu()
    assert.is_table(menu_entry)
    assert.is_table(menu_entry.sub_item_table)

    for _, item in ipairs(menu_entry.sub_item_table) do
      if item.text_func then
        assert.is_string(item.text_func())
      end
      if item.enabled_func then
        item.enabled_func()
      end
      if item.callback then
        item.callback()
      end
      if item.checked_func then
        item.checked_func()
      end
      if item.sub_item_table then
        for _, sub in ipairs(item.sub_item_table) do
          if sub.text_func then
            sub.text_func()
          end
          if sub.callback then
            sub.callback()
          end
          if sub.checked_func then
            sub.checked_func()
          end
        end
      end
    end
  end)

  it("should get source and target languages properly", function()
    G_reader_settings:save("trans_source_lang", "es")
    G_reader_settings:save("trans_target_lang", "de")
    assert.are.equal("es", Translator:getSourceLanguage())
    assert.are.equal("de", Translator:getTargetLanguage())

    G_reader_settings:delete("trans_source_lang")
    G_reader_settings:delete("trans_target_lang")
    assert.is_string(Translator:getSourceLanguage())
    assert.is_string(Translator:getTargetLanguage())
  end)

  it("should handle _showTranslation with detailed view, alternates, and definitions", function()
    local UIManager = require("ui/uimanager")
    local Trapper = require("ui/trapper")
    local shown_widget = nil
    local orig_show = UIManager.show
    UIManager.show = function(self, w)
      shown_widget = w
    end

    local mock_result = {
      [1] = {
        { "Hello", "Bonjour" },
      },
      [3] = "fr",
      [6] = {
        { "Bonjour", nil, { { "Hi" }, { "Hello" } } },
      },
      [13] = {
        { "greeting", { { "an expression of greeting", nil, "hello there" } } },
      },
    }

    local orig_loadPage = Translator.loadPage
    Translator.loadPage = function()
      return mock_result
    end

    -- Detailed view = true
    Translator:_showTranslation("Bonjour", true, "fr", "en", false, nil)
    assert.is_not_nil(shown_widget)
    if shown_widget and shown_widget.free then
      shown_widget:free()
    end

    -- Detailed view = false
    shown_widget = nil
    Translator:_showTranslation("Bonjour", false, "fr", "en", false, nil)
    assert.is_not_nil(shown_widget)
    if shown_widget and shown_widget.free then
      shown_widget:free()
    end

    -- Failure path
    Translator.loadPage = function()
      return nil
    end
    shown_widget = nil
    Translator:_showTranslation("Bonjour", false, "fr", "en", false, nil)
    assert.is_not_nil(shown_widget)

    Translator.loadPage = orig_loadPage
    UIManager.show = orig_show
  end)
end)
