describe("Readerui module", function()
  local DocumentRegistry, ReaderUI, DocSettings, UIManager, Screen
  local sample_epub = "spec/front/unit/data/leaves.epub"
  local readerui
  setup(function()
    require("commonrequire")
    DocumentRegistry = require("document/documentregistry")
    ReaderUI = require("apps/reader/readerui")
    DocSettings = require("docsettings")
    UIManager = require("ui/uimanager")
    Screen = require("device").screen
    sample_epub = "spec/front/unit/data/readerui_leaves.epub"
    require("ffi/util").copyFile(
      "spec/front/unit/data/leaves.epub",
      sample_epub
    )

    readerui = ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(sample_epub),
    })
  end)

  teardown(function()
    DocSettings:open(sample_epub):purge()
    os.remove(sample_epub)
  end)
  it("should save settings", function()
    -- remove history settings and sidecar settings
    DocSettings:open(sample_epub):purge()
    local doc_settings = DocSettings:open(sample_epub)
    assert.are.same(doc_settings.data, { doc_path = sample_epub })
    readerui:saveSettings()
    assert.are_not.same(readerui.doc_settings.data, { doc_path = sample_epub })
    doc_settings = DocSettings:open(sample_epub)
    assert.truthy(doc_settings.data.last_xpointer)
    assert.are.same(
      doc_settings.data.last_xpointer,
      readerui.doc_settings.data.last_xpointer
    )
  end)
  it("should show reader", function()
    UIManager:quit()
    UIManager:show(readerui)
    UIManager:scheduleIn(1, function()
      UIManager:close(readerui)
      -- We haven't torn it down yet
      ReaderUI.instance = readerui
    end)
    UIManager:run()
  end)
  it("should close document", function()
    readerui:onExit()
    assert(readerui.document == nil)
    readerui:onClose()
  end)
  it("should not allow creating a second instance", function()
    ReaderUI:_doShowReader(sample_epub) -- spins up a new, sane instance
    local new_readerui = ReaderUI.instance
    assert.is.truthy(new_readerui.document)

    -- Trying to create a second instance should fail due to assertion in init
    local doc
    assert.has.errors(function()
      doc = DocumentRegistry:openDocument(sample_epub)
      ReaderUI:new({
        dimen = Screen:getSize(),
        document = doc,
      })
    end)
    if doc then
      doc:close()
    end

    -- Cleanup partially initialized ReaderUI from UIManager
    local old_instance = ReaderUI.instance
    for i = #UIManager._window_stack, 1, -1 do
      local w = UIManager._window_stack[i].widget
      if w.name == "ReaderUI" and w ~= new_readerui then
        ReaderUI.instance = w -- trick onClose to pass the assert
        UIManager:close(w)
      end
    end
    ReaderUI.instance = old_instance

    new_readerui:onExit()
    new_readerui:onClose()
  end)

  it(
    "should safely return to File Manager via onHome when document is nil",
    function()
      -- Since the previous test has already closed the global readerui, its document is nil
      assert.is_nil(readerui.document)

      local show_filemanager_called = false
      local original_showFileManager = readerui.showFileManager
      readerui.showFileManager = function(self, f)
        show_filemanager_called = true
        assert.is_nil(f)
      end

      local success = readerui:onHome()
      assert.is_true(success)
      assert.is_true(show_filemanager_called)

      -- Restore original function
      readerui.showFileManager = original_showFileManager
    end
  )

  it("should calculate size via getSize and support module access", function()
    local size = readerui:getSize()
    assert.is_not_nil(size)
    assert.is_true(size.w > 0)
    assert.is_true(size.h > 0)
  end)

  it(
    "should error directly when dealWithLoadDocumentFailure is called outside a coroutine",
    function()
      assert.has_error(
        function()
          readerui:dealWithLoadDocumentFailure()
        end,
        "crengine failed recognizing or parsing this file: unsupported or invalid document"
      )
    end
  )

  it(
    "should show InfoMessage when DocumentRegistry hasProvider is true but getProvider returns nil",
    function()
      local stub = require("luassert.stub")
      local has_stub = stub(DocumentRegistry, "hasProvider", function()
        return true
      end)
      local get_stub = stub(DocumentRegistry, "getProvider", function()
        return nil
      end)
      local show_widget_called = false
      local orig_showWidget = ReaderUI.showWidget
      ReaderUI.showWidget = function(self, widget)
        show_widget_called = true
      end
      local show_fm_called = false
      local orig_showFileManager = ReaderUI.showFileManager
      ReaderUI.showFileManager = function(self, file)
        show_fm_called = true
      end

      assert.has_no.errors(function()
        ReaderUI:showReader(sample_epub)
      end)
      assert.is_true(show_widget_called)
      assert.is_true(show_fm_called)

      has_stub:revert()
      get_stub:revert()
      ReaderUI.showWidget = orig_showWidget
      ReaderUI.showFileManager = orig_showFileManager
    end
  )
end)
