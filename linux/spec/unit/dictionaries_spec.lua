local dictionaries

describe("ui/data/dictionaries module", function()
  setup(function()
    require("commonrequire")
    dictionaries = require("ui/data/dictionaries")
  end)

  it("contains populated list of dictionaries with required fields", function()
    assert.is_table(dictionaries)
    assert.is_true(#dictionaries > 100)

    for i, dict in ipairs(dictionaries) do
      assert.is_string(dict.name, "Missing name at index " .. i)
      assert.is_string(dict.lang_in, "Missing lang_in at index " .. i)
      assert.is_string(dict.lang_out, "Missing lang_out at index " .. i)
      assert.is_string(dict.url, "Missing url at index " .. i)
      assert.is_true(
        dict.url:match("^https?://") ~= nil,
        "Invalid url at index " .. i
      )
    end
  end)

  it(
    "configures Esperanto-English dictionary with ISO 639-3 code 'epo'",
    function()
      local esperanto_dict
      for _, dict in ipairs(dictionaries) do
        if dict.name == "Esperanto-English dictionary by Paul Denisowski" then
          esperanto_dict = dict
          break
        end
      end

      assert.is_not_nil(esperanto_dict)
      assert.are.equal("eng", esperanto_dict.lang_out)

      -- Esperanto's ISO 639-3 code is "epo".
      assert.are.equal("epo", esperanto_dict.lang_in)
    end
  )
end)
