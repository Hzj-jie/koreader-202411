-- luacheck: ignore 122
describe("Text Exporter", function()
  local TextExporter, ffiUtil

  setup(function()
    require("commonrequire")
    TextExporter = require("plugins/exporter.koplugin/target/text")
    ffiUtil = require("ffi/util")
  end)

  describe("export", function()
    local exporter

    before_each(function()
      exporter = TextExporter:new({
        name = "text",
        settings = {},
      })
    end)

    it("should format and write clippings to target file", function()
      local temp_path = "/tmp/test_export_text_" .. ffiUtil.getpid() .. ".txt"
      exporter.getFilePath = function() return temp_path end

      local now = 1700000000
      local data = {
        {
          title = "Text Notes Book",
          {
            {
              chapter = "Chapter 1",
              page = 15,
              time = now,
              text = "Highlight content here",
              note = "Annotation note",
            },
          },
          {
            {
              chapter = "Chapter 2",
              page = 25,
              time = now + 100,
              image = true,
            },
          },
        },
      }

      local ok = exporter:export(data)
      assert.is_true(ok)

      local f = io.open(temp_path, "r")
      assert.is_truthy(f)
      local content = f:read("*all")
      f:close()
      os.remove(temp_path)

      assert.is_truthy(content:find("Text Notes Book"))
      assert.is_truthy(content:find("Chapter 1"))
      assert.is_truthy(content:find("-- Page: 15"))
      assert.is_truthy(content:find("Highlight content here"))
      assert.is_truthy(content:find("\n%-%-%-\nAnnotation note"))
      assert.is_truthy(content:find("<An image>"))
      assert.is_truthy(content:find("%-=%-=%-=%-=%-=%-"))
    end)

    it("should return false when target path cannot be opened", function()
      exporter.getFilePath = function() return "/nonexistent/invalid/dir/path.txt" end
      local ok = exporter:export({ { title = "Dummy" } })
      assert.is_false(ok)
    end)

    it("should pass a string to shareText on share", function()
      local shared_content
      exporter.shareText = function(_self, text)
        shared_content = text
      end

      local data = {
        title = "Shareable Book",
        {
          {
            chapter = "Ch 1",
            page = 1,
            time = 1700000000,
            text = "Clipping text",
          },
        },
      }

      exporter:share(data)
      -- format(t) returns a table of lines rather than table.concat(tbl, "\n"),
      -- so shareText receives a table instead of a string
      assert.is_string(shared_content)
    end)
  end)
end)
