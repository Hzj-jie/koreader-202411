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

        readerui = ReaderUI:new{
            dimen = Screen:getSize(),
            document = DocumentRegistry:openDocument(sample_epub),
        }
    end)
    it("should save settings", function()
        -- remove history settings and sidecar settings
        DocSettings:open(sample_epub):purge()
        local doc_settings = DocSettings:open(sample_epub)
        assert.are.same(doc_settings.data, {doc_path = sample_epub})
        readerui:saveSettings()
        assert.are_not.same(readerui.doc_settings.data, {doc_path = sample_epub})
        doc_settings = DocSettings:open(sample_epub)
        assert.truthy(doc_settings.data.last_xpointer)
        assert.are.same(doc_settings.data.last_xpointer,
                readerui.doc_settings.data.last_xpointer)
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
            ReaderUI:new{
                dimen = Screen:getSize(),
                document = doc
            }
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
end)
