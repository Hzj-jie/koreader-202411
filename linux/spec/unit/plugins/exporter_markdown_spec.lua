-- luacheck: ignore 122
describe("Markdown Exporter and Template", function()
  local md, MarkdownExporter, UIManager, ffiUtil

  setup(function()
    require("commonrequire")
    md = require("plugins/exporter.koplugin/template/md")
    MarkdownExporter = require("plugins/exporter.koplugin/target/markdown")
    UIManager = require("ui/uimanager")
    ffiUtil = require("ffi/util")
  end)

  describe("md.prepareBookContent", function()
    local default_formatting = {
      lighten = "italic",
      underscore = "underline_markdownit",
      strikeout = "strikethrough",
      invert = "bold",
    }

    it("should format book title, author, and fallback author", function()
      local book1 = {
        title = "My Great Book",
        author = "Author One\nAuthor Two",
      }
      local lines1 = md.prepareBookContent(book1, default_formatting, true)
      assert.is_table(lines1)
      assert.are.equal("# My Great Book", lines1[1])
      assert.are.equal("##### Author One, Author Two\n", lines1[2])

      local book2 = {
        title = "Anonymous Book",
        author = nil,
      }
      local lines2 = md.prepareBookContent(book2, default_formatting, true)
      assert.are.equal("##### N/A\n", lines2[2])
    end)

    it("should group consecutive annotations by chapter and emit new headers on change", function()
      local now = 1700000000
      local book = {
        title = "Chaptered Book",
        author = "Writer",
        {
          {
            chapter = "Chapter 1",
            page = 10,
            time = now,
            drawer = "lighten",
            text = "First note",
          },
        },
        {
          {
            chapter = "Chapter 1",
            page = 12,
            time = now + 60,
            drawer = "lighten",
            text = "Second note",
          },
        },
        {
          {
            chapter = "Chapter 2",
            page = 20,
            time = now + 120,
            drawer = "underscore",
            text = "Third note",
          },
        },
      }

      local lines = md.prepareBookContent(book, default_formatting, true)
      local chapter_headers = {}
      for _, line in ipairs(lines) do
        if line:find("^## ") then
          table.insert(chapter_headers, line)
        end
      end

      assert.are.equal(2, #chapter_headers)
      assert.are.equal("## Chapter 1", chapter_headers[1])
      assert.are.equal("## Chapter 2", chapter_headers[2])
    end)

    it("should format highlights with all 8 formatting styles vs plain text", function()
      local now = 1700000000
      local styles = {
        none = "sample",
        bold = "**sample**",
        highlight = "==sample==",
        italic = "*sample*",
        bold_italic = "**_sample_**",
        underline_markdownit = "++sample++",
        underline_u_tag = "<u>sample</u>",
        strikethrough = "~~sample~~",
      }

      for style_name, expected_formatted in pairs(styles) do
        local custom_formatting = { test_drawer = style_name }
        local book = {
          title = "Style Test",
          author = "Tester",
          {
            {
              chapter = "Ch",
              page = 1,
              time = now,
              drawer = "test_drawer",
              text = "sample",
            },
          },
        }

        local formatted_lines = md.prepareBookContent(book, custom_formatting, true)
        assert.are.equal(expected_formatted, formatted_lines[5])

        local plain_lines = md.prepareBookContent(book, custom_formatting, false)
        assert.are.equal("sample", plain_lines[5])
      end
    end)

    it("should append note when note field is present", function()
      local book = {
        title = "Note Test",
        author = "Tester",
        {
          {
            chapter = "Ch",
            page = 1,
            time = 1700000000,
            drawer = "lighten",
            text = "Highlighted text",
            note = "My personal thoughts",
          },
        },
      }

      local lines = md.prepareBookContent(book, default_formatting, true)
      assert.are.equal("\n---\nMy personal thoughts", lines[6])
    end)

    it("should handle annotations where chapter transitions from a name to nil without crashing", function()
      local book = {
        title = "Nil Chapter Transition",
        author = "Author",
        {
          {
            chapter = "Chapter 1",
            page = 1,
            time = 1700000000,
            drawer = "lighten",
            text = "First highlight",
          },
        },
        {
          {
            chapter = nil,
            page = 2,
            time = 1700000060,
            drawer = "lighten",
            text = "Second highlight without chapter",
          },
        },
      }

      local lines = md.prepareBookContent(book, default_formatting, true)
      assert.is_table(lines)
    end)
  end)

  describe("MarkdownExporter methods", function()
    local exporter

    before_each(function()
      exporter = MarkdownExporter:new({
        name = "markdown",
        settings = {},
      })
    end)

    it("should initialize default formatting_options and highlight_formatting in init_callback and onInit", function()
      local changed, settings = exporter:init_callback({})
      assert.is_true(changed)
      assert.is_table(settings.formatting_options)
      assert.are.equal("italic", settings.formatting_options.lighten)
      assert.are.equal("underline_markdownit", settings.formatting_options.underscore)
      assert.are.equal("strikethrough", settings.formatting_options.strikeout)
      assert.are.equal("bold", settings.formatting_options.invert)
      assert.is_true(settings.highlight_formatting)

      exporter.settings = {}
      local saved = false
      exporter.saveSettings = function() saved = true end
      exporter:onInit()
      assert.is_true(saved)
      assert.is_table(exporter.settings.formatting_options)
      assert.is_true(exporter.settings.highlight_formatting)
    end)

    it("should construct menu table and toggle settings", function()
      exporter.settings = {
        enabled = true,
        highlight_formatting = true,
        formatting_options = {
          lighten = "italic",
          underscore = "underline_markdownit",
          strikeout = "strikethrough",
          invert = "bold",
        },
      }

      local menu_table = exporter:getMenuTable()
      assert.is_table(menu_table)
      assert.is_table(menu_table.sub_item_table)
      assert.are.equal(6, #menu_table.sub_item_table)

      -- Export to Markdown item
      local export_item = menu_table.sub_item_table[1]
      assert.is_true(export_item.checked_func())
      export_item.callback()
      assert.is_false(exporter:isEnabled())

      -- Format highlights item
      local format_item = menu_table.sub_item_table[2]
      assert.is_true(format_item.checked_func())
      format_item.callback()
      assert.is_false(exporter.settings.highlight_formatting)

      -- Edit format style item opens RadioButtonWidget
      local shown_widget
      local old_show = UIManager.show
      UIManager.show = function(_self, widget)
        shown_widget = widget
      end

      local style_item = menu_table.sub_item_table[3] -- Lighten
      local mock_menu = { updateItems = function() end }
      style_item.callback(mock_menu)

      assert.is_table(shown_widget)
      assert.is_table(shown_widget.radio_buttons)
      assert.are.equal(8, #shown_widget.radio_buttons)

      -- Select bold (index 2)
      shown_widget.callback(shown_widget.radio_buttons[2][1])
      assert.are.equal("bold", exporter.settings.formatting_options.lighten)

      UIManager.show = old_show
    end)

    it("should export markdown file and return success status", function()
      local temp_path = "/tmp/test_export_md_" .. ffiUtil.getpid() .. ".md"
      exporter.getFilePath = function() return temp_path end
      exporter.getTimeStamp = function() return "2026-10-10 00:00:00" end
      exporter.settings = {
        formatting_options = {
          lighten = "italic",
        },
        highlight_formatting = true,
      }

      local data = {
        {
          title = "Export Book",
          author = "Book Author",
          {
            {
              chapter = "Chapter A",
              page = 5,
              time = 1700000000,
              drawer = "lighten",
              text = "Exported highlight",
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

      assert.is_truthy(content:find("# Export Book"))
      assert.is_truthy(content:find("*Exported highlight*"))
      assert.is_truthy(content:find("_Generated at: 2026%-10%-10 00:00:00_"))

      -- Failure when path cannot be written
      exporter.getFilePath = function() return "/nonexistent/invalid/dir/path.md" end
      assert.is_false(exporter:export(data))
    end)

    it("should format content and invoke shareText on share", function()
      local shared_text
      exporter.shareText = function(_self, text)
        shared_text = text
      end
      exporter.getTimeStamp = function() return "2026-10-10 00:00:00" end
      exporter.settings = {
        formatting_options = { lighten = "bold" },
        highlight_formatting = true,
      }

      local book = {
        title = "Share Book",
        author = "Sharer",
        {
          {
            chapter = "Intro",
            page = 1,
            time = 1700000000,
            drawer = "lighten",
            text = "Shared highlight",
          },
        },
      }

      exporter:share(book)
      assert.is_string(shared_text)
      assert.is_truthy(shared_text:find("# Share Book"))
      assert.is_truthy(shared_text:find("**Shared highlight**"))
      assert.is_truthy(shared_text:find("_Generated at: 2026%-10%-10 00:00:00_"))
    end)
  end)
end)
