describe("BookStatusWidget widget module", function()
  local BookStatusWidget, DocSettings

  setup(function()
    require("commonrequire")
    DocSettings = require("docsettings")
    stub(DocSettings, "findCustomCoverFile")
    BookStatusWidget = require("ui/widget/bookstatuswidget")
  end)

  teardown(function()
    if DocSettings.findCustomCoverFile.revert then
      DocSettings.findCustomCoverFile:revert()
    end
  end)

  it("should initialize BookStatusWidget instance", function()
    local mock_ui = {
      document = {
        getProps = function()
          return { title = "Test Title", authors = "Test Author" }
        end,
        getPageCount = function()
          return 100
        end,
        getCoverPageImage = function()
          return nil
        end,
      },
      doc_props = {
        display_title = "Test Title",
        authors = "Test Author",
        language = "en",
      },
      doc_settings = {
        data = { doc_path = "/tmp/test.epub" },
        save = function() end,
        readSetting = function()
          return nil
        end,
        readTableRef = function(self, key)
          if key == "summary" then
            return { rating = 4, status = "reading" }
          end
          return nil
        end,
      },
      getCurrentPage = function()
        return 10
      end,
    }

    local widget = BookStatusWidget:new({
      ui = mock_ui,
    })
    assert.is_table(widget)
  end)
end)
