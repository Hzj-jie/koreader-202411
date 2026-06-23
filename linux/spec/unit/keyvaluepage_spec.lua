describe("KeyValuePage UI component", function()
    local Device, KeyValuePage

    setup(function()
        require("commonrequire")
        package.unloadAll()
        local device = require("device")
        require("document/canvascontext"):init(device)

        Device = require("device")
        KeyValuePage = require("ui/widget/keyvaluepage")
    end)

    before_each(function()
        _G.G_reader_settings = {
            read = function(self, key)
                if key == "keyvalues_per_page" then
                    return 5
                end
                return nil
            end,
        }
    end)

    it("should instantiate without crashing and populate items correctly", function()
        local kv_pairs = {
            { "Key 1", "Value 1" },
            { "Key 2", "Value 2" },
        }

        local page
        assert.has_no.errors(function()
            page = KeyValuePage:new({
                title = "Test KV Page",
                kv_pairs = kv_pairs,
                callback_return = function() end,
            })
        end)

        assert.is_not_nil(page)
        assert.is.same(2, #page.kv_pairs)
        assert.is.same("Key 1", page.kv_pairs[1][1])
        assert.is.same("Value 1", page.kv_pairs[1][2])
    end)
end)
