describe("NewsDownloader dateparser module", function()
  local dateparser

  setup(function()
    require("commonrequire")
    package.unloadAll()

    dateparser = require("plugins/newsdownloader.koplugin/lib/dateparser")
  end)

  describe("RFC2822 and RFC822 formats", function()
    it("should parse dates with and without weekday prefix", function()
      local ts1 = dateparser.parse("Mon, 01 May 2023 12:00:00 GMT", "RFC2822")
      assert.is_number(ts1)

      local ts2 = dateparser.parse("01 May 2023 12:00:00 GMT", "RFC822")
      assert.is_number(ts2)
      assert.are.equal(ts1, ts2)
    end)

    it("should handle 2-digit years (< 50 and >= 50)", function()
      local ts_23 = dateparser.parse("01 May 23 12:00:00 GMT", "RFC2822")
      local ts_2023 = dateparser.parse("01 May 2023 12:00:00 GMT", "RFC2822")
      assert.are.equal(ts_2023, ts_23)

      local ts_85 = dateparser.parse("01 May 85 12:00:00 GMT", "RFC2822")
      local ts_1985 = dateparser.parse("01 May 1985 12:00:00 GMT", "RFC2822")
      assert.are.equal(ts_1985, ts_85)
    end)

    it("should parse named timezones and numeric offsets", function()
      local ts_gmt = dateparser.parse("01 May 2023 12:00:00 GMT", "RFC2822")
      local ts_est = dateparser.parse("01 May 2023 07:00:00 EST", "RFC2822")
      assert.are.equal(ts_gmt, ts_est)

      local ts_pdt = dateparser.parse("01 May 2023 05:00:00 PDT", "RFC2822")
      assert.are.equal(ts_gmt, ts_pdt)

      local ts_m = dateparser.parse("02 May 2023 00:00:00 M", "RFC2822")
      assert.are.equal(ts_gmt, ts_m)

      local ts_pos_num = dateparser.parse("01 May 2023 14:30:00 +0230", "RFC2822")
      assert.are.equal(ts_gmt, ts_pos_num)

      local ts_neg_num = dateparser.parse("01 May 2023 07:00:00 -0500", "RFC2822")
      assert.are.equal(ts_gmt, ts_neg_num)
    end)
  end)

  describe("W3CDTF and RFC3339 formats", function()
    it("should parse full date with fractional seconds and timezone offsets", function()
      local ts_z = dateparser.parse("2023-05-01T12:00:00Z", "W3CDTF")
      assert.is_number(ts_z)

      local ts_frac = dateparser.parse("2023-05-01T12:00:00.5Z", "RFC3339")
      assert.is_number(ts_frac)
      assert.are.equal(ts_z + 0.5, ts_frac)

      local ts_pos_offset = dateparser.parse("2023-05-01T14:00:00+02:00", "W3CDTF")
      assert.are.equal(ts_z, ts_pos_offset)

      local ts_neg_offset = dateparser.parse("2023-05-01T07:00:00-05:00", "W3CDTF")
      assert.are.equal(ts_z, ts_neg_offset)
    end)

    it("should reject invalid date bounds and garbage strings", function()
      assert.is_falsy(dateparser.parse("2023-05-01T12:00:00ZEXTRA", "W3CDTF"))
    end)
  end)

  describe("failing tests for production bugs", function()
    it("should correctly subtract negative timezone offset with non-zero minutes in W3CDTF and RFC2822 (fails due to sign bug)", function()
      -- W3CDTF: "2023-05-01T12:00:00-03:30" should equal "2023-05-01T15:30:00Z"
      -- Currently tonumber("-03") + 30/60 = -3 + 0.5 = -2.5 hours instead of -3.5 hours
      local ts_w3c_utc = dateparser.parse("2023-05-01T15:30:00Z", "W3CDTF")
      local ts_w3c_neg = dateparser.parse("2023-05-01T12:00:00-03:30", "W3CDTF")
      assert.are.equal(ts_w3c_utc, ts_w3c_neg)

      -- RFC2822: "01 May 2023 12:00:00 -0330" should equal "01 May 2023 15:30:00 GMT"
      local ts_rfc_utc = dateparser.parse("01 May 2023 15:30:00 GMT", "RFC2822")
      local ts_rfc_neg = dateparser.parse("01 May 2023 12:00:00 -0330", "RFC2822")
      assert.are.equal(ts_rfc_utc, ts_rfc_neg)
    end)

    it("should return nil and error message for unknown format name (fails due to returning error string as 1st value)", function()
      local res, err = dateparser.parse("2023-05-01", "NONEXISTENT_FORMAT")
      assert.is_nil(res)
      assert.is_string(err)
    end)

    it("should return nil for unparseable date string without explicit format (fails due to line 67 returning false)", function()
      local res = dateparser.parse("not a valid date")
      assert.is_nil(res)
    end)

    it("should parse year-only, year-month, and year-day-of-year in W3CDTF (fails due to rest nil crash in W3CDTF)", function()
      local ts_year = dateparser.parse("2023", "W3CDTF")
      assert.is_number(ts_year)

      local ts_year_month = dateparser.parse("2023-05", "W3CDTF")
      assert.is_number(ts_year_month)

      local ts_doy = dateparser.parse("2023-120", "W3CDTF")
      assert.is_number(ts_doy)
    end)
  end)

  describe("register_format", function()
    it("should handle valid and invalid registrations", function()
      local bad_ok1, bad_err1 = dateparser.register_format(123, function() end)
      assert.is_nil(bad_ok1)
      assert.is_string(bad_err1)

      local bad_ok2, bad_err2 = dateparser.register_format("test_format", "not_a_func")
      assert.is_nil(bad_ok2)
      assert.is_string(bad_err2)

      local custom_called = false
      local custom_func = function(s)
        custom_called = true
        if s == "custom_value" then
          return 1700000000
        end
      end

      local ok = dateparser.register_format("custom", custom_func)
      assert.is_true(ok)
      assert.are.equal(1700000000, dateparser.parse("custom_value", "custom"))
      assert.is_true(custom_called)

      local ok_dup = dateparser.register_format("custom_dup", custom_func)
      assert.is_true(ok_dup)
    end)
  end)
end)
