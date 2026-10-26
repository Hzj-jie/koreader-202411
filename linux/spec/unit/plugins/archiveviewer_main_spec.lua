-- luacheck: ignore 122
describe("ArchiveViewer main plugin module", function()
  local ArchiveViewer, DocumentRegistry, UIManager, TextViewer, ImageViewer, ButtonDialog, RenderImage

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    DocumentRegistry = require("document/documentregistry")
    UIManager = require("ui/uimanager")
    TextViewer = require("ui/widget/textviewer")
    ImageViewer = require("ui/widget/imageviewer")
    ButtonDialog = require("ui/widget/buttondialog")
    RenderImage = require("ui/renderimage")
    ArchiveViewer = require("plugins/archiveviewer.koplugin/main")
  end)

  local orig_popen, orig_show, orig_close
  local shown_widgets, closed_widgets, popen_commands

  before_each(function()
    shown_widgets = {}
    closed_widgets = {}
    popen_commands = {}

    orig_popen = io.popen
    orig_show = UIManager.show
    orig_close = UIManager.close

    UIManager.show = function(_, widget)
      table.insert(shown_widgets, widget)
    end
    UIManager.close = function(_, widget)
      table.insert(closed_widgets, widget)
    end
  end)

  after_each(function()
    io.popen = orig_popen
    UIManager.show = orig_show
    UIManager.close = orig_close
  end)

  describe("File support & provider registration", function()
    it(
      "should initialize ArchiveViewer plugin and check supported extensions",
      function()
        local instance = ArchiveViewer:new()
        assert.is_table(instance)
        assert.are.equal("archiveviewer", instance.name)
        assert.is_true(instance:isFileTypeSupported("test.cbz"))
        assert.is_true(instance:isFileTypeSupported("test.epub"))
        assert.is_true(instance:isFileTypeSupported("test.zip"))
        assert.is_false(instance:isFileTypeSupported("test.txt"))
        assert.is_false(instance:isFileTypeSupported("test.pdf"))
      end
    )
  end)

  describe("openFile & getZipListTable", function()
    it("should parse unzip list output into nested directory tables", function()
      local sample_unzip_output = {
        "     1024  2026-10-10 10:00   root.txt",
        "        0  2026-10-10 10:00   docs/",
        "      512  2026-10-10 10:00   docs/readme.md",
        "        0  2026-10-10 10:00   docs/sub/",
        "      256  2026-10-10 10:00   docs/sub/notes.txt",
        "     2048  2026-10-10 10:00   photo.png",
      }

      io.popen = function(cmd)
        table.insert(popen_commands, cmd)
        local idx = 0
        return {
          lines = function()
            return function()
              idx = idx + 1
              return sample_unzip_output[idx]
            end
          end,
          close = function() end,
        }
      end

      local instance = ArchiveViewer:new()
      instance:openFile("/books/sample.zip")

      assert.are.equal("zip", instance.arc_type)
      assert.are.equal("/books/sample.zip", instance.arc_file)
      assert.is_table(instance.list_table)
      assert.is_table(instance.menu)
      assert.are.equal(1, #shown_widgets)

      -- Root level
      local root = instance.list_table["/"]
      assert.is_table(root)
      assert.are.equal("1024", root["root.txt"])
      assert.are.equal("2048", root["photo.png"])
      assert.is_false(root["docs"]) -- directory has value false

      -- docs/ directory level
      local docs = instance.list_table["docs/"]
      assert.is_table(docs)
      assert.are.equal("512", docs["readme.md"])
      assert.is_false(docs["sub"])

      -- docs/sub/ directory level
      local sub = instance.list_table["docs/sub/"]
      assert.is_table(sub)
      assert.are.equal("256", sub["notes.txt"])
    end)

    it(
      "should parse 100 MB or larger files without leading whitespace in unzip output",
      function()
        local sample_unzip_output = {
          "104857600  2026-10-10 10:00   bigfile.bin",
        }

        io.popen = function()
          local idx = 0
          return {
            lines = function()
              return function()
                idx = idx + 1
                return sample_unzip_output[idx]
              end
            end,
            close = function() end,
          }
        end

        local instance = ArchiveViewer:new()
        instance:openFile("/books/bigarchive.zip")

        assert.is_table(instance.list_table["/"])
        assert.are.equal("104857600", instance.list_table["/"]["bigfile.bin"])
      end
    )

    it(
      "should handle onMenuSelect for file and folder items in openFile menu",
      function()
        io.popen = function()
          return {
            lines = function()
              return function()
                return nil
              end
            end,
            close = function() end,
          }
        end

        local instance = ArchiveViewer:new()
        instance:openFile("/books/sample.zip")
        assert.is_table(instance.menu)

        -- File selection opens ButtonDialog
        instance.menu.onMenuSelect(
          instance.menu,
          { is_file = true, path = "test.txt" }
        )
        assert.are.equal(2, #shown_widgets)
        local dialog = shown_widgets[2]
        assert.is_table(dialog)

        -- Folder selection switches item table
        local switched_title = nil
        instance.menu.switchItemTable = function(_, title, _)
          switched_title = title
        end
        instance.menu.onMenuSelect(
          instance.menu,
          { is_file = false, path = "subfolder/" }
        )
        assert.are.equal("sample.zip/subfolder/", switched_title)
      end
    )
  end)

  describe("getItemTable and getItemDirMandatory", function()
    local instance

    before_each(function()
      instance = ArchiveViewer:new()
      instance.list_table = {
        ["/"] = {
          ["photo.png"] = "2048",
          ["root.txt"] = "1024",
          ["docs"] = false,
        },
        ["docs/"] = {
          ["readme.md"] = "512",
          ["sub"] = false,
        },
        ["docs/sub/"] = {
          ["notes.txt"] = "256",
        },
      }
    end)

    it(
      "should return root items sorted directories first, then files",
      function()
        local items = instance:getItemTable("")
        assert.is_table(items)
        assert.are.equal(3, #items)

        -- First item is directory "docs/"
        assert.are.equal("docs/", items[1].text)
        assert.is_nil(items[1].is_file)
        assert.are.equal("docs/", items[1].path)

        -- Subsequent items are files sorted alphabetically
        assert.are.equal("photo.png", items[2].text)
        assert.is_true(items[2].is_file)
        assert.are.equal("photo.png", items[2].path)

        assert.are.equal("root.txt", items[3].text)
        assert.is_true(items[3].is_file)
        assert.are.equal("root.txt", items[3].path)
      end
    )

    it("should include parent navigation entry for subdirectories", function()
      local items = instance:getItemTable("docs/")
      assert.is_table(items)
      assert.are.equal(3, #items)

      -- First item is parent navigation "⬆ ../"
      assert.is_true(items[1].text:find("%.%./") ~= nil)

      -- Subdirectory "sub/"
      assert.are.equal("sub/", items[2].text)
      assert.are.equal("docs/sub/", items[2].path)

      -- File "readme.md"
      assert.are.equal("readme.md", items[3].text)
      assert.are.equal("docs/readme.md", items[3].path)
    end)

    it(
      "should format directory mandatory count with and without subfolders",
      function()
        -- docs/ has 1 subfolder and 1 file
        local mandatory_docs = instance:getItemDirMandatory("docs/")
        assert.is_string(mandatory_docs)
        assert.is_true(mandatory_docs:find("1") ~= nil)

        -- docs/sub/ has 0 subfolders and 1 file
        local mandatory_sub = instance:getItemDirMandatory("docs/sub/")
        assert.is_string(mandatory_sub)
        assert.is_true(mandatory_sub:find("1") ~= nil)
      end
    )
  end)

  describe("File viewer & extraction workflows", function()
    local instance

    before_each(function()
      instance = ArchiveViewer:new()
      instance.arc_type = "zip"
      instance.arc_file = "/path/test.zip"
      instance.menu = {
        item_table = {
          { text = "photo.png", is_file = true, path = "photo.png" },
          { text = "readme.txt", is_file = true, path = "readme.txt" },
        },
      }
    end)

    it("should show file dialog with Extract and View options", function()
      instance:showFileDialog("readme.txt")
      assert.are.equal(1, #shown_widgets)
      local dialog = shown_widgets[1]
      assert.is_table(dialog)
      assert.is_table(dialog.buttons)
      assert.is_true(dialog.title:find("readme.txt") ~= nil)
    end)

    it(
      "should open TextViewer for text files and ImageViewer for images with renderImageData",
      function()
        io.popen = function()
          return {
            read = function()
              return "Sample extracted text content"
            end,
            close = function() end,
          }
        end

        -- View text file
        instance:viewFile("readme.txt")
        assert.are.equal(1, #shown_widgets)
        local text_viewer = shown_widgets[1]
        assert.is_table(text_viewer)
        assert.are.equal("readme.txt", text_viewer.title)
        assert.are.equal("Sample extracted text content", text_viewer.text)

        -- View image file
        local orig_render = RenderImage.renderImageData
        local rendered_payload = nil
        RenderImage.renderImageData = function(_, data, size)
          rendered_payload = data
          return {
            getSize = function()
              return { w = 100, h = 100 }
            end,
            getWidth = function()
              return 100
            end,
            getHeight = function()
              return 100
            end,
          }
        end

        instance:viewFile("photo.png")
        assert.are.equal(2, #shown_widgets)
        local img_viewer = shown_widgets[2]
        assert.is_table(img_viewer)
        assert.are.equal(1, img_viewer.images_list_nb)
        assert.is_table(img_viewer.image)
        assert.are.equal(100, img_viewer.image:getWidth())
        assert.are.equal("Sample extracted text content", rendered_payload)

        RenderImage.renderImageData = orig_render
      end
    )

    it("should execute file extraction and content extraction", function()
      local popen_cmd = nil
      io.popen = function(cmd)
        popen_cmd = cmd
        return {
          read = function()
            return "File payload"
          end,
          close = function() end,
        }
      end

      assert.is_nil(instance.fm_updated)
      instance:extractFile("readme.txt")
      assert.is_true(instance.fm_updated)
      assert.is_not_nil(popen_cmd)
      assert.is_true(popen_cmd:find("unzip") ~= nil)
      assert.is_true(popen_cmd:find("readme.txt") ~= nil)

      local content = instance:extractContent("readme.txt")
      assert.are.equal("File payload", content)
    end)
  end)
end)
