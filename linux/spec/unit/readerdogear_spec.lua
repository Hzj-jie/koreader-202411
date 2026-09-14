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

  it("should set dogear visibility on self.ui.view", function()
      local mock_ui = {
        view = {
          dogear_visible = false,
        },
      }
      local dogear = ReaderDogear:new({
        ui = mock_ui,
      })
      assert.is_true(dogear:onSetDogearVisibility(true))
      assert.is_true(mock_ui.view.dogear_visible)

      assert.is_true(dogear:onSetDogearVisibility(false))
      assert.is_false(mock_ui.view.dogear_visible)
    end)

    it("should return icon dimen as refresh region", function()
      local mock_ui = {
        view = {
          view_mode = "page",
        },
      }
      local dogear = ReaderDogear:new({
        ui = mock_ui,
      })
      local Blitbuffer = require("ffi/blitbuffer")
      local bb = Blitbuffer.new(600, 800)
      dogear[1]:paintTo(bb, 0, 0)
      local region = dogear:getRefreshRegion()
      assert.is_not_nil(region)
      assert.are.equal(dogear.icon.dimen, region)
    end)

    it("should handle onSetPageMargins and onReadSettings", function()
      local mock_ui = {
        rolling = true,
        view = {
          view_mode = "page",
        },
        document = {
          configurable = {
            h_page_margins = { 15, 25 },
            t_page_margin = 20,
            b_page_margin = 20,
          },
          getHeaderHeight = function()
            return 15
          end,
        },
      }
      local dogear = ReaderDogear:new({
        ui = mock_ui,
      })

      dogear:onSetPageMargins({ 15, 30, 30, 20 })
      assert.is_true(dogear.dogear_size >= dogear.dogear_min_size)
      assert.is_true(dogear.dogear_size <= dogear.dogear_max_size)

      dogear:onReadSettings(nil)

      -- Non-rolling does nothing
      dogear.ui.rolling = false
      dogear:onSetPageMargins({ 0, 0, 0, 0 })
    end)

    it("should update dogear offset on lifecycle events", function()
      local mock_ui = {
        rolling = true,
        view = {
          view_mode = "page",
        },
        document = {
          getHeaderHeight = function()
            return 25
          end,
        },
      }
      local dogear = ReaderDogear:new({
        ui = mock_ui,
      })

      dogear:onReaderReady()
      assert.are.equal(25, dogear.dogear_y_offset)

      mock_ui.document.getHeaderHeight = function()
        return 30
      end
      dogear:onDocumentRerendered()
      assert.are.equal(30, dogear.dogear_y_offset)

      mock_ui.view.view_mode = "scroll"
      dogear:onChangeViewMode()
      assert.are.equal(0, dogear.dogear_y_offset)
    end)
end)

describe("ReaderDogear module integration", function()
  local ReaderDogear, DocumentRegistry, ReaderUI, Screen

  setup(function()
    require("commonrequire")
    ReaderDogear = require("apps/reader/modules/readerdogear")
    DocumentRegistry = require("document/documentregistry")
    ReaderUI = require("apps/reader/readerui")
    Screen = require("device").screen
  end)

  it("should initialize dogear module", function()
    local sample_epub = "spec/front/unit/data/leaves.epub"
    local readerui = ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(sample_epub),
    })

    local readerdogear = readerui.dogear or ReaderDogear:new({ ui = readerui })
    assert.is_table(readerdogear)

    readerui:onExit()
    readerui:onClose()
  end)
end)
