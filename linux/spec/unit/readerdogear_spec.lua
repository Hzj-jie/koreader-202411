describe("ReaderDogear module", function()
  local ReaderDogear

  setup(function()
    require("commonrequire")
    ReaderDogear = require("apps/reader/modules/readerdogear")
  end)

  it(
    "should initialize and calculate dogear offsets using self.ui.view",
    function()
      local mock_ui = {
        view = {
          view_mode = "page",
        },
        document = {
          getHeaderHeight = function()
            return 20
          end,
        },
        rolling = true,
      }

      local dogear = ReaderDogear:new({
        ui = mock_ui,
      })

      assert.is_not_nil(dogear)
      assert.is_true(dogear.dogear_min_size > 0)
      assert.is_true(dogear.dogear_max_size >= dogear.dogear_min_size)

      dogear:updateDogearOffset()
      assert.are.equal(20, dogear.dogear_y_offset)
    end
  )
end)
