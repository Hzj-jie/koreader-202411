describe("Checkers ButtonTable widget", function()
  local CheckersButtonTable, Button

  setup(function()
    require("commonrequire")
    Button = require("ui/widget/button")
    CheckersButtonTable = require("plugins/checkers.koplugin/buttontable")
  end)

  describe("Initialization & alpha propagation", function()
    it("should initialize CheckersButtonTable with standard text buttons", function()
      local widget = CheckersButtonTable:new({
        buttons = {
          { { text = "Cancel" }, { text = "OK" } },
        },
      })
      assert.is_table(widget)
      assert.is_table(widget.buttons_layout)
      assert.is_table(widget.buttons_layout[1])
      local btn1 = widget.buttons_layout[1][1]
      local btn2 = widget.buttons_layout[1][2]
      assert.is_nil(btn1.alpha)
      assert.is_nil(btn2.alpha)
    end)

    it("should pass alpha to Button and re-create IconWidget with alpha", function()
      local dummy_icon = "dummy_checkers_icon"
      local widget = CheckersButtonTable:new({
        buttons = {
          {
            {
              icon = dummy_icon,
              alpha = 0.75,
              icon_width = 32,
              icon_height = 32,
            },
            {
              text = "Plain",
            },
          },
        },
      })

      assert.is_table(widget)
      local icon_btn = widget.buttons_layout[1][1]
      local text_btn = widget.buttons_layout[1][2]

      assert.are.equal(0.75, icon_btn.alpha)
      assert.is_nil(text_btn.alpha)

      -- Verify that Button:init re-created label_widget as an IconWidget with alpha
      assert.is_table(icon_btn.label_widget)
      assert.are.equal(0.75, icon_btn.label_widget.alpha)
      assert.are.equal(dummy_icon, icon_btn.label_widget.icon)
      assert.are.equal(32, icon_btn.label_widget.width)
      assert.are.equal(32, icon_btn.label_widget.height)
    end)

    it("should correctly map alphas across multiple rows and columns", function()
      local widget = CheckersButtonTable:new({
        buttons = {
          {
            { text = "R1C1", alpha = 0.2 },
            { text = "R1C2", alpha = 0.4 },
          },
          {
            { text = "R2C1", alpha = 0.6 },
            { text = "R2C2", alpha = 0.8 },
          },
        },
      })

      assert.are.equal(0.2, widget.buttons_layout[1][1].alpha)
      assert.are.equal(0.4, widget.buttons_layout[1][2].alpha)
      assert.are.equal(0.6, widget.buttons_layout[2][1].alpha)
      assert.are.equal(0.8, widget.buttons_layout[2][2].alpha)
    end)

    it("should preserve alpha alignment when earlier button has nil alpha", function()
      local widget = CheckersButtonTable:new({
        buttons = {
          {
            { text = "NoAlpha", alpha = nil },
            { text = "HasAlpha", alpha = 0.5 },
          },
        },
      })

      assert.is_nil(widget.buttons_layout[1][1].alpha)
      assert.are.equal(0.5, widget.buttons_layout[1][2].alpha)
    end)
  end)

  describe("Button.new lifecycle and cleanup", function()
    it("should restore Button.new to original constructor after instantiation", function()
      local orig_btn_new = Button.new
      local widget = CheckersButtonTable:new({
        buttons = {
          { { text = "Test", alpha = 0.5 } },
        },
      })
      assert.is_table(widget)
      assert.are.equal(orig_btn_new, Button.new)
    end)

    it("should restore Button.new even when table initialization fails", function()
      local orig_btn_new = Button.new

      local bad_table = {
        buttons = {
          {
            {
              text = "Faulty",
              alpha = 0.5,
            },
          },
        },
      }

      local orig_btn_init = Button.init
      Button.init = function()
        error("Simulated Button Table Init Error")
      end

      local ok, _ = pcall(function()
        CheckersButtonTable.init(bad_table)
      end)
      Button.init = orig_btn_init

      assert.is_false(ok)
      assert.are.equal(orig_btn_new, Button.new)
    end)
  end)
end)
