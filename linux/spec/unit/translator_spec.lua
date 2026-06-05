local dutch_wikipedia_text = "Wikipedia is een meertalige encyclopedie, waarvan de inhoud vrij beschikbaar is. Iedereen kan hier kennis toevoegen!"
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
            if type(request) == "table" and url_str then
                if string.find(url_str, "translate.googleapis.com") then
                    local response_json = [=[[[["Wikipedia is a multilingual encyclopedia, the content of which is freely available. Anyone can add knowledge here!", "Wikipedia is een meertalige encyclopedie, waarvan de inhoud vrij beschikbaar is. Iedereen kan hier kennis toevoegen!", null, null, 3]], null, "nl"]]=]
                    if request.sink then
                        request.sink(response_json)
                    end
                    return 1, 200, { ["content-type"] = "application/json" }, "HTTP/1.1 200 OK"
                end
            end
            return orig_http_request(request)
        end
    end)

    teardown(function()
        local http = require("socket.http")
        http.request = orig_http_request
    end)
    it("should return server", function()
        assert.is.same("https://translate.googleapis.com/", Translator:getTransServer())
        G_reader_settings:save("trans_server", "http://translate.google.nl")
        G_reader_settings:flush()
        assert.is.same("http://translate.google.nl", Translator:getTransServer())
        G_reader_settings:delete("trans_server")
        G_reader_settings:flush()
    end)
    -- add " #notest #nocov" to the it("description string") when it does not work anymore
    it("should return translation #internet", function()
        local translation_result = Translator:translate(dutch_wikipedia_text, "en")
        assert.is.truthy(translation_result)
        -- while some minor variation in the translation is possible it should
        -- be between about 100 and 130 characters
        assert.is_true(#translation_result > 50 and #translation_result < 200)
    end)
    it("should autodetect language #internet", function()
        local detect_result = Translator:detect(dutch_wikipedia_text)
        assert.is.same("nl", detect_result)
    end)
end)
