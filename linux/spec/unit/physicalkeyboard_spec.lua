describe("PhysicalKeyboard widget", function()
  local PhysicalKeyboard, Screen

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    PhysicalKeyboard = require("ui/widget/physicalkeyboard")
    Screen = require("device").screen
  end)

  it(
    "should initialize physical keyboard event listener for string input type",
    function()
      local pk = PhysicalKeyboard:new({
        width = Screen:getWidth(),
        inputbox = {
          input_type = "string",
          addChar = function() end,
          addChars = function() end,
        },
      })
      assert.is_table(pk)
    end
  )

  it("should set type to number and handle number mappings", function()
    local pk = PhysicalKeyboard:new({
      width = Screen:getWidth(),
      inputbox = {
        input_type = "number",
        addChar = function() end,
        addChars = function() end,
      },
    })
    pk:setType("number")
    assert.is_table(pk.mapping)
  end)

  it("should handle keypress events safely", function()
    local inserted_chars
    local mock_inputbox = {
      input_type = "number",
      addChar = function(self, char)
        inserted_chars = char
      end,
      addChars = function(self, chars)
        inserted_chars = chars
      end,
    }
    local pk = PhysicalKeyboard:new({
      width = Screen:getWidth(),
      inputbox = mock_inputbox,
    })

    if type(pk.onKeyPress) == "function" then
      pk:onKeyPress("1")
    end
  end)
end)
