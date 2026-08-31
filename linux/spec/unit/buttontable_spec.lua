describe("ButtonTable widget module", function()
  local ButtonTable
  local Device
  local Size

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    ButtonTable = require("ui/widget/buttontable")
    Device = require("device")
    Size = require("ui/size")
  end)

  describe("Initialization", function()
    it("should initialize button table instance with layout and callbacks", function()
      local btn1_clicked = false
      local btn2_held = false
      local buttons = {
        {
          {
            id = "btn1",
            text = "Btn1",
            callback = function()
              btn1_clicked = true
            end,
          },
          {
            id = "btn2",
            text = "Btn2",
            enabled = true,
            hold_callback = function()
              btn2_held = true
            end,
            allow_hold_when_disabled = true,
            no_vertical_sep = true,
          },
        },
      }
      local table_widget = ButtonTable:new({
        buttons = buttons,
        width = 300,
        zero_sep = true,
      })
      assert.is_table(table_widget)
      assert.truthy(table_widget:getButtonById("btn1"))
      assert.truthy(table_widget:getButtonById("btn2"))
      assert.is_nil(table_widget:getButtonById("btn3"))

      -- Trigger button callback
      local b1 = table_widget:getButtonById("btn1")
      b1.callback()
      assert.is_true(btn1_clicked)

      local b2 = table_widget:getButtonById("btn2")
      b2.hold_callback()
      assert.is_true(btn2_held)
    end)

    it("should handle parent movable container resetEventState in button callback", function()
      local reset_called = false
      local mock_parent = {
        movable = {
          resetEventState = function()
            reset_called = true
          end,
        },
      }

      local btn_clicked = false
      local table_widget = ButtonTable:new({
        buttons = {
          {
            {
              id = "test_btn",
              text = "Test",
              callback = function()
                btn_clicked = true
              end,
            },
          },
        },
      })
      table_widget.showParent = function()
        return mock_parent
      end

      local b = table_widget:getButtonById("test_btn")
      b.callback()
      assert.is_true(reset_called)
      assert.is_true(btn_clicked)
    end)

    it("should handle DPad devices and shortcuts", function()
      local orig_hasDPad = Device.hasDPad
      Device.hasDPad = function() return true end

      local table_widget = ButtonTable:new({
        buttons = {
          {
            { text = "A", callback = function() end },
            { text = "B", callback = function() end },
          },
        },
        enable_shortcut = true,
      })

      assert.truthy(table_widget.layout)
      assert.are.equal(1, #table_widget.layout)

      Device.hasDPad = orig_hasDPad
    end)

    it("should handle shrink_unneeded_width", function()
      local table_widget = ButtonTable:new({
        buttons = {
          {
            { text = "OK", callback = function() end },
            { text = "Cancel", callback = function() end },
          },
        },
        width = 600,
        shrink_unneeded_width = true,
      })

      assert.is_table(table_widget)
      assert.is_true(table_widget.width <= 600)
    end)

    it("should setup grid scroll behaviour and step scroll grid", function()
      local table_widget = ButtonTable:new({
        buttons = {
          {
            { text = "Row1Btn1", callback = function() end },
            { text = "Row1Btn2", callback = function() end },
          },
          {
            { text = "Row2Btn1", callback = function() end },
            { text = "Row2Btn2", callback = function() end },
          },
        },
        width = 300,
      })

      table_widget:setupGridScrollBehaviour()
      local grid = table_widget:getStepScrollGrid()
      assert.is_table(grid)
      assert.is_true(#grid >= 2)
      assert.are.equal(1, grid[1].row_num)
      assert.are.equal(2, grid[2].row_num)
    end)
  end)
end)
