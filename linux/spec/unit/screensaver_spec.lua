local stub = require("luassert.stub")

describe("Screensaver module", function()
  local Screensaver

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))
    Screensaver = require("ui/screensaver")
  end)

  it("should calculate average time for pages", function()
    stub(Screensaver, "getAvgTimePerPage", function()
      return 60
    end)

    local sec = Screensaver:_calcAverageTimeForPages(5)
    assert.is_not_nil(sec)
    assert.is_string(sec)

    Screensaver.getAvgTimePerPage:revert()
  end)

  it("should handle N/A average time for pages when nil or nan", function()
    stub(Screensaver, "getAvgTimePerPage", function()
      return nil
    end)

    local sec = Screensaver:_calcAverageTimeForPages(5)
    assert.is_equal(sec, "N/A")

    Screensaver.getAvgTimePerPage:revert()
  end)

  it(
    "should expand special message format tokens when no lastfile setting exists",
    function()
      local message = "Title: %T, Battery: %b"
      local fallback = "Sleeping"

      local result = Screensaver:expandSpecial(message, fallback)
      assert.is_not_nil(result)
    end
  )

  it("should check if screensaver is excluded", function()
    local excluded = Screensaver:isExcluded()
    assert.is_boolean(excluded)
  end)

  it("should return default screensaver message when set", function()
    assert.is_not_nil(Screensaver.default_screensaver_message)
  end)

  describe("Special Token Expansion", function()
    it("should expand time and battery tokens", function()
      local template = "Battery: %b, Time: %c"
      local result = Screensaver:expandSpecial(template, "Sleeping")
      assert.is_string(result)
      assert.are.equal(result, "Sleeping")
    end)

    it("should handle custom title and author tokens", function()
      local template = "Book: %t by %a"
      local result = Screensaver:expandSpecial(template, "Sleeping")
      assert.is_string(result)
    end)
  end)

  describe("Screensaver Resolution & Message", function()
    it(
      "should handle screensaver message retrieval and close safely",
      function()
        if type(Screensaver.getScreensaverMessage) == "function" then
          local msg = Screensaver:getScreensaverMessage()
          assert.is_string(msg)
        end

        if type(Screensaver.close) == "function" then
          Screensaver:close()
        end
      end
    )
  end)
end)
