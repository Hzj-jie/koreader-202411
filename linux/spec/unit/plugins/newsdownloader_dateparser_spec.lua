describe("NewsDownloader dateparser module", function()
  local dateparser

  setup(function()
    require("commonrequire")
    package.unloadAll()

    dateparser = require("plugins/newsdownloader.koplugin/lib/dateparser")
  end)

  it("should return error or falsy for invalid/unparseable dates", function()
    assert.is_falsy(dateparser.parse("not a valid date at all"))
    assert.is_string(dateparser.parse("2024-05-15", "NON_EXISTENT_FORMAT"))
  end)

  it("should parse W3CDTF / RFC3339 date strings", function()
    local ts = dateparser.parse("2024-05-15T12:34:56Z", "W3CDTF")
    assert.is_number(ts)

    local ts_auto = dateparser.parse("2024-05-15T12:34:56+02:00")
    assert.is_number(ts_auto)

    local ts_frac = dateparser.parse("2024-05-15T12:34:56.789Z", "RFC3339")
    assert.is_number(ts_frac)
  end)

  it(
    "should parse RFC2822 / RFC822 date strings with timezone names and offsets",
    function()
      local ts1 = dateparser.parse("Wed, 15 May 2024 12:34:56 GMT", "RFC2822")
      assert.is_number(ts1)

      local ts2 = dateparser.parse("15 May 2024 12:34:56 +0000", "RFC822")
      assert.is_number(ts2)

      local ts3 = dateparser.parse("Wed, 15 May 2024 12:34:56 EST")
      assert.is_number(ts3)
    end
  )

  it(
    "should register custom date format handlers and handle invalid registration",
    function()
      local ok, err = dateparser.register_format("custom", function(s)
        if s == "valid_custom" then
          return 1234567890
        end
      end)
      assert.is_true(ok)

      assert.are.equal(1234567890, dateparser.parse("valid_custom", "custom"))

      local bad_ok, bad_err = dateparser.register_format(123, nil)
      assert.is_nil(bad_ok)
      assert.is_string(bad_err)
    end
  )
end)
