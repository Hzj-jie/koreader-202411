describe("PhysicalKeyboard widget", function()
  local PhysicalKeyboard, Screen, Device

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    PhysicalKeyboard = require("ui/widget/physicalkeyboard")
    Screen = require("device").screen
    Device = require("device")
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
      assert.is_true(pk:isVisible())
      pk:setVisibility()
      pk:showKeyboard()
      pk:hideKeyboard()
    end
  )

  it("should set type to number and setup numeric mapping UI", function()
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
    assert.truthy(pk.key_transformer)
    assert.truthy(pk[1])
  end)

  it("should handle keypress events for Back, Del, and normal keys", function()
    local added_chars = nil
    local del_called = false
    local mock_inputbox = {
      input_type = "number",
      addChar = function(self, char)
        added_chars = char
      end,
      addChars = function(self, chars)
        added_chars = chars
      end,
      delChar = function(self)
        del_called = true
      end,
    }
    local pk = PhysicalKeyboard:new({
      width = Screen:getWidth(),
      inputbox = mock_inputbox,
    })
    pk:setType("number")

    -- Back key
    pk:onKeyPress({ key = "Back" })

    -- Del key
    pk:onKeyPress({ key = "Del" })
    assert.is_true(del_called)

    -- Normal key (mapped via numeric layout, e.g. first key 'q' maps to '1')
    local first_key = Device.keyboard_layout[1][1]
    pk:onKeyPress({ key = first_key })
    assert.are.equal("1", added_chars)
  end)
end)
