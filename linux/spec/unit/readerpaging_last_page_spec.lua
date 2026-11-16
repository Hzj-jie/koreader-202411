describe("ReaderPaging last_page recovery", function()
  local Blitbuffer, DocSettings, DocumentRegistry, ReaderUI, Screen, UIManager
  local readerui, tmp_pdf

  setup(function()
    require("commonrequire")
    require("document/canvascontext"):init(require("device"))

    Blitbuffer = require("ffi/blitbuffer")
    DocSettings = require("docsettings")
    DocumentRegistry = require("document/documentregistry")
    ReaderUI = require("apps/reader/readerui")
    Screen = require("device").screen
    UIManager = require("ui/uimanager")

    tmp_pdf = require("datastorage"):getDataDir()
      .. "/readerpaging_last_page_sample.pdf"
    require("ffi/util").copyFile("spec/front/unit/data/sample.pdf", tmp_pdf)
  end)

  after_each(function()
    if readerui then
      if UIManager:isWindowWidget(readerui) or readerui.document then
        readerui:onExit(true)
      end
      if ReaderUI.instance == readerui then
        readerui:onClose()
      end
      readerui = nil
    end
    DocSettings:open(tmp_pdf):purge()
  end)

  teardown(function()
    if tmp_pdf then
      os.remove(tmp_pdf)
    end
  end)

  it(
    "clamps sidecar last_page = 0 to page 1 on open, paint, and exit",
    function()
      local doc_settings = DocSettings:open(tmp_pdf)
      doc_settings:save("last_page", 0)
      doc_settings:flush()

      readerui = ReaderUI:new({
        dimen = Screen:getSize(),
        document = DocumentRegistry:openDocument(tmp_pdf),
      })

      local bb = Blitbuffer.new(
        Screen:getWidth(),
        Screen:getHeight(),
        Blitbuffer.TYPE_BB8
      )
      finally(function()
        bb:free()
      end)

      readerui:paintTo(bb, 0, 0)
      assert.equals(1, readerui.paging.current_page)
      assert.equals(1, readerui.view.footer.pageno)
      assert.is_not_nil(readerui.view.footer.progress_bar.percentage)

      readerui:onExit(true)
      assert.is_false(UIManager:isWindowWidget(readerui))
      readerui = nil
      assert.equals(1, DocSettings:open(tmp_pdf):read("last_page"))
    end
  )

  it("clamps _gotoPage(0) to page 1 when current_page is 0", function()
    readerui = ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(tmp_pdf),
    })
    readerui.paging.current_page = 0
    readerui.paging:_gotoPage(0)
    assert.equals(1, readerui.paging.current_page)
  end)
end)
