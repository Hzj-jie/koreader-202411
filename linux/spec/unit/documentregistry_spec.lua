describe("DocumentRegistry", function()
  local DocumentRegistry
  local DocSettings
  local ffiUtil
  local orig_providers_len
  local orig_filetype_provider
  local orig_known_providers
  local orig_mimetype_ext

  setup(function()
    require("commonrequire")
    DocumentRegistry = require("document/documentregistry")
    DocSettings = require("docsettings")
    ffiUtil = require("ffi/util")

    orig_providers_len = #DocumentRegistry.providers
    orig_filetype_provider = {}
    for k, v in pairs(DocumentRegistry.filetype_provider) do
      orig_filetype_provider[k] = v
    end
    orig_known_providers = {}
    for k, v in pairs(DocumentRegistry.known_providers) do
      orig_known_providers[k] = v
    end
    orig_mimetype_ext = {}
    for k, v in pairs(DocumentRegistry.mimetype_ext) do
      orig_mimetype_ext[k] = v
    end
  end)

  after_each(function()
    -- Restore DocumentRegistry.providers
    while #DocumentRegistry.providers > orig_providers_len do
      table.remove(DocumentRegistry.providers)
    end
    -- Restore filetype_provider
    for k in pairs(DocumentRegistry.filetype_provider) do
      if not orig_filetype_provider[k] then
        DocumentRegistry.filetype_provider[k] = nil
      end
    end
    -- Restore known_providers
    for k in pairs(DocumentRegistry.known_providers) do
      if not orig_known_providers[k] then
        DocumentRegistry.known_providers[k] = nil
      end
    end
    -- Restore mimetype_ext
    for k in pairs(DocumentRegistry.mimetype_ext) do
      if not orig_mimetype_ext[k] then
        DocumentRegistry.mimetype_ext[k] = nil
      end
    end
    -- Reset registry
    DocumentRegistry.registry = {}
    -- Reset G_reader_settings "provider" table
    local p = G_reader_settings:readTableRef("provider")
    for k in pairs(p) do
      p[k] = nil
    end
  end)

  describe("Provider Registration", function()
    it("should register providers via addProvider and addAuxProvider", function()
      local mock_doc_prov = { provider = "MockDocProvider" }
      DocumentRegistry:addProvider("xyz", "application/x-xyz", mock_doc_prov, 120)

      assert.is_true(DocumentRegistry.filetype_provider["xyz"])
      assert.are.equal("xyz", DocumentRegistry.mimetype_ext["application/x-xyz"])
      assert.are.equal(mock_doc_prov, DocumentRegistry.known_providers["MockDocProvider"])

      local mock_aux_prov = { provider = "MockAuxProvider", order = 10 }
      DocumentRegistry:addAuxProvider(mock_aux_prov)
      assert.are.equal(mock_aux_prov, DocumentRegistry.known_providers["MockAuxProvider"])
    end)
  end)

  describe("hasProvider", function()
    it("should check providers by extension, mimetype, and settings", function()
      assert.is_false(DocumentRegistry:hasProvider(nil))
      assert.is_false(DocumentRegistry:hasProvider("file.unregistered_ext_123"))

      -- By file extension and case-insensitivity
      assert.is_true(DocumentRegistry:hasProvider("book.epub"))
      assert.is_true(DocumentRegistry:hasProvider("book.EPUB"))
      assert.is_true(DocumentRegistry:hasProvider("doc.pdf"))

      -- By mimetype
      assert.is_true(DocumentRegistry:hasProvider(nil, "application/epub+zip"))
      assert.is_false(DocumentRegistry:hasProvider(nil, "unknown/mime"))

      -- By G_reader_settings "provider" table
      local mock_aux = { provider = "MockAux", order = 5 }
      local mock_doc = { provider = "MockDoc" }
      DocumentRegistry:addAuxProvider(mock_aux)
      DocumentRegistry.known_providers["MockDoc"] = mock_doc

      G_reader_settings:readTableRef("provider")["customext"] = "MockDoc"
      assert.is_true(DocumentRegistry:hasProvider("test.customext", nil, false))

      G_reader_settings:readTableRef("provider")["customaux"] = "MockAux"
      assert.is_false(DocumentRegistry:hasProvider("test.customaux", nil, false))
      assert.is_true(DocumentRegistry:hasProvider("test.customaux", nil, true))

      -- By DocSettings sidecar
      local tmp_file = "/tmp/test_registry_" .. ffiUtil.getpid() .. ".unknown"
      local f = assert(io.open(tmp_file, "w"))
      f:write("content")
      f:close()

      local ds = DocSettings:open(tmp_file)
      ds:save("provider", "MockDoc")
      ds:flush()

      assert.is_true(DocumentRegistry:hasProvider(tmp_file))

      ds:purge()
      os.remove(tmp_file)
    end)
  end)

  describe("getProvider and getProviders", function()
    it("should return providers with weights and fallbacks", function()
      local prov_low = { provider = "ProvLow" }
      local prov_high = { provider = "ProvHigh" }
      DocumentRegistry:addProvider("abc", "application/x-abc", prov_low, 50)
      DocumentRegistry:addProvider("abc", "application/x-abc", prov_high, 150)

      local list = DocumentRegistry:getProviders("test.abc")
      assert.is_table(list)
      assert.are.equal(2, #list)
      assert.are.equal("ProvHigh", list[1].provider.provider)
      assert.are.equal("ProvLow", list[2].provider.provider)

      -- Deduplication by weight for same provider key
      DocumentRegistry:addProvider("abc", "application/x-abc", prov_low, 30)
      list = DocumentRegistry:getProviders("test.abc")
      assert.are.equal(2, #list)

      DocumentRegistry:addProvider("abc", "application/x-abc", prov_low, 200)
      list = DocumentRegistry:getProviders("test.abc")
      assert.are.equal(2, #list)
      assert.are.equal("ProvLow", list[1].provider.provider)
      assert.are.equal(200, list[1].weight)

      -- getProvider returns highest weighted
      assert.are.equal(prov_low, DocumentRegistry:getProvider("test.abc"))

      -- getProvider with auxiliary
      local mock_aux = { provider = "MockAuxABC", order = 1 }
      DocumentRegistry:addAuxProvider(mock_aux)
      G_reader_settings:readTableRef("provider")["abc"] = "MockAuxABC"
      assert.are.equal(prov_low, DocumentRegistry:getProvider("test.abc", false))
      assert.are.equal(mock_aux, DocumentRegistry:getProvider("test.abc", true))

      -- Fallback provider for unregistered extension
      assert.are.equal(DocumentRegistry:getFallbackProvider(), DocumentRegistry:getProvider("file.unregistered"))
      assert.is_not_nil(DocumentRegistry:getFallbackProvider())

      -- getProviders on unregistered file returns nil
      assert.is_nil(DocumentRegistry:getProviders("file.unregistered"))
    end)

    it("should get provider from key", function()
      local mock = { provider = "KeyProvider" }
      DocumentRegistry.known_providers["KeyProvider"] = mock
      assert.are.equal(mock, DocumentRegistry:getProviderFromKey("KeyProvider"))
      assert.is_nil(DocumentRegistry:getProviderFromKey("NonExistentKey"))
    end)
  end)

  describe("getAssociatedProviderKey and setProvider", function()
    it("should handle per-document and global provider associations", function()
      local tmp_file = "/tmp/test_assoc_" .. ffiUtil.getpid() .. ".epub"
      local f = assert(io.open(tmp_file, "w"))
      f:write("content")
      f:close()

      local mock_prov = { provider = "CustomEpub" }
      DocumentRegistry.known_providers["CustomEpub"] = mock_prov

      -- file = nil returns entire provider table
      assert.are.equal(G_reader_settings:readTableRef("provider"), DocumentRegistry:getAssociatedProviderKey(nil))

      -- Initially no associated provider
      assert.is_nil(DocumentRegistry:getAssociatedProviderKey(tmp_file))

      -- setProvider per-document (all = false or nil)
      DocumentRegistry:setProvider(tmp_file, mock_prov, false)
      assert.are.equal("CustomEpub", DocumentRegistry:getAssociatedProviderKey(tmp_file, false))
      assert.are.equal("CustomEpub", DocumentRegistry:getAssociatedProviderKey(tmp_file, nil))
      assert.is_nil(DocumentRegistry:getAssociatedProviderKey(tmp_file, true))

      -- setProvider global (all = true)
      local global_prov = { provider = "GlobalEpub" }
      DocumentRegistry.known_providers["GlobalEpub"] = global_prov
      DocumentRegistry:setProvider(tmp_file, global_prov, true)
      assert.are.equal("GlobalEpub", DocumentRegistry:getAssociatedProviderKey(tmp_file, true))

      -- When both exist, all = nil prefers per-document
      assert.are.equal("CustomEpub", DocumentRegistry:getAssociatedProviderKey(tmp_file, nil))

      -- setProvider with nil provider resets
      DocumentRegistry:setProvider(tmp_file, nil, false)
      assert.is_nil(DocumentRegistry:getAssociatedProviderKey(tmp_file, false))
      assert.are.equal("GlobalEpub", DocumentRegistry:getAssociatedProviderKey(tmp_file, nil))

      DocSettings:open(tmp_file):purge()
      os.remove(tmp_file)
    end)
  end)

  describe("Auxiliary providers, extensions, and mimetypes", function()
    it("should get sorted aux providers, extension map, and mime conversions", function()
      local aux1 = { provider = "Aux1", order = 20 }
      local aux2 = { provider = "Aux2", order = 5 }
      local aux3 = { provider = "Aux3", order = 15 }
      DocumentRegistry:addAuxProvider(aux1)
      DocumentRegistry:addAuxProvider(aux2)
      DocumentRegistry:addAuxProvider(aux3)

      local aux_list = DocumentRegistry:getAuxProviders()
      assert.is_table(aux_list)
      local pos1, pos2, pos3
      for idx, prov in ipairs(aux_list) do
        if prov.provider == "Aux1" then pos1 = idx end
        if prov.provider == "Aux2" then pos2 = idx end
        if prov.provider == "Aux3" then pos3 = idx end
      end
      assert.is_true(pos2 < pos3)
      assert.is_true(pos3 < pos1)

      -- getExtensions
      local ext_map = DocumentRegistry:getExtensions()
      assert.is_table(ext_map)
      assert.is_table(ext_map["epub"])
      assert.is_table(ext_map["pdf"])

      -- mimeToExt
      assert.are.equal("log", DocumentRegistry:mimeToExt("text/plain"))
      assert.is_nil(DocumentRegistry:mimeToExt("application/xhtml"))
      assert.is_nil(DocumentRegistry:mimeToExt("text/xhtml"))
      assert.is_nil(DocumentRegistry:mimeToExt("non/existent/mime"))

      DocumentRegistry:addProvider("xhtml", "application/xhtml", { provider = "MockXHTML" })
      assert.are.equal("xhtml", DocumentRegistry:mimeToExt("application/xhtml"))
    end)
  end)

  describe("openDocument, closeDocument, and getReferenceCount", function()
    it("should manage reference counting and lifecycle", function()
      local mock_doc_instance = { is_open = true }
      local mock_provider = {
        provider = "LifecycleProvider",
        new = function(_self, _args)
          return mock_doc_instance
        end,
      }
      local test_file = "/tmp/test_lifecycle_" .. ffiUtil.getpid() .. ".doc"

      -- First open
      local doc = DocumentRegistry:openDocument(test_file, mock_provider)
      assert.are.equal(mock_doc_instance, doc)
      assert.are.equal(1, DocumentRegistry:getReferenceCount(test_file))

      -- Second open
      local doc2 = DocumentRegistry:openDocument(test_file, mock_provider)
      assert.are.equal(mock_doc_instance, doc2)
      assert.are.equal(2, DocumentRegistry:getReferenceCount(test_file))

      -- First close
      local remaining_refs = DocumentRegistry:closeDocument(test_file)
      assert.are.equal(1, remaining_refs)
      assert.are.equal(1, DocumentRegistry:getReferenceCount(test_file))

      -- Second close (unregisters)
      remaining_refs = DocumentRegistry:closeDocument(test_file)
      assert.are.equal(0, remaining_refs)
      assert.is_nil(DocumentRegistry:getReferenceCount(test_file))

      -- Third close on unregistered file raises error
      assert.has_error(function()
        DocumentRegistry:closeDocument(test_file)
      end, "Tried to close an unregistered file.")

      -- Error during provider.new returns nil
      local failing_provider = {
        provider = "FailProvider",
        new = function()
          error("Failed to open")
        end,
      }
      local fail_file = "/tmp/test_fail_" .. ffiUtil.getpid() .. ".fail"
      local fail_doc = DocumentRegistry:openDocument(fail_file, failing_provider)
      assert.is_nil(fail_doc)
      assert.is_nil(DocumentRegistry:getReferenceCount(fail_file))
    end)
  end)

  describe("isImageFile", function()
    it("should identify supported image extensions case-insensitively", function()
      assert.is_true(DocumentRegistry:isImageFile("photo.png"))
      assert.is_true(DocumentRegistry:isImageFile("photo.PNG"))
      assert.is_true(DocumentRegistry:isImageFile("photo.jpg"))
      assert.is_true(DocumentRegistry:isImageFile("photo.jpeg"))
      assert.is_true(DocumentRegistry:isImageFile("photo.gif"))
      assert.is_true(DocumentRegistry:isImageFile("photo.svg"))
      assert.is_true(DocumentRegistry:isImageFile("photo.tif"))
      assert.is_true(DocumentRegistry:isImageFile("photo.tiff"))
      assert.is_true(DocumentRegistry:isImageFile("photo.webp"))

      assert.is_false(DocumentRegistry:isImageFile("book.epub"))
      assert.is_false(DocumentRegistry:isImageFile("paper.pdf"))
      assert.is_false(DocumentRegistry:isImageFile("notes.txt"))
      assert.is_false(DocumentRegistry:isImageFile("archive.zip"))
    end)
  end)
end)
