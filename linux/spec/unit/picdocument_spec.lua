describe("PicDocument module", function()
  local PicDocument

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    PicDocument = require("document/picdocument")
  end)

  it("should register image extensions in DocumentRegistry", function()
    local mock_registry = {
      providers = {},
      addProvider = function(self, ext, mime, provider, priority)
        self.providers[ext] = { mime = mime, provider = provider, priority = priority }
      end,
    }

    PicDocument:register(mock_registry)

    assert.is_table(mock_registry.providers["jpg"])
    assert.is_table(mock_registry.providers["png"])
    assert.is_table(mock_registry.providers["gif"])
  end)

  it("should open image document and retrieve metadata", function()
    local img_path = "base/spec/unit/data/sample.jpg"
    local doc = PicDocument:new({ file = img_path })
    doc:init()

    assert.is_true(doc.is_open)
    assert.is_table(doc:getUsedBBox(1))
    assert.is_table(doc:getDocumentProps())

    if doc._document and doc._document.close then
      doc._document:close()
    end
  end)
end)
