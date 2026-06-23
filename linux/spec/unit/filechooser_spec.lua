describe("FileChooser module", function()
    local FileChooser, DocSettings, Screen
    local sample_epub = "spec/front/unit/data/leaves.epub"

    setup(function()
        require("commonrequire")
        -- Make sure canvas context is initialized
        require("document/canvascontext"):init(require("device"))
        FileChooser = require("ui/widget/filechooser")
        DocSettings = require("docsettings")
        Screen = require("device").screen
    end)

    it("should safely sort by percent_natural when sidecar has nil summary table", function()
        -- Ensure sidecar has NO summary table (mock or purge first)
        local doc_settings = DocSettings:open(sample_epub)
        doc_settings:save("summary", nil) -- Explicitly nil the summary table!
        doc_settings:save("percent_finished", 0.5)
        doc_settings:close()

        local filechooser = FileChooser:new({
            dimen = Screen:getSize(),
            path = "spec/front/unit/data",
        })

        -- Build mock item list to be sorted
        local items = {
            { text = "leaves.epub", path = sample_epub, attr = { size = 1000 } },
            { text = "another.epub", path = "spec/front/unit/data/another.epub", attr = { size = 2000 } }
        }

        -- Get the percent_natural sorting structure
        local collate = filechooser.collates.percent_natural
        assert.is_table(collate)

        -- Initialize items using collate.item_func (which populates item.sort_percent!)
        -- This is the code path containing the bug!
        assert.has_no.errors(function()
            collate.item_func(items[1])
            collate.item_func(items[2])
        end)

        -- Verify sort_percent is populated successfully without raising a nil index error
        assert.is_number(items[1].sort_percent)
        assert.is_number(items[2].sort_percent)

        -- Clean up doc settings cache residues
        DocSettings:open(sample_epub):purge()
    end)

    it("should respect instance's show_finished setting", function()
        local filemanagerutil = require("apps/filemanager/filemanagerutil")
        local original_getStatus = filemanagerutil.getStatus

        filemanagerutil.getStatus = function(path)
            if path == "test_complete.epub" then
                return "complete"
            end
            return "incomplete"
        end

        local fc_show = FileChooser:new({
            dimen = Screen:getSize(),
            show_finished = true,
        })
        assert.is_true(fc_show:show_file("test_complete.epub", "test_complete.epub"))

        local fc_hide = FileChooser:new({
            dimen = Screen:getSize(),
            show_finished = false,
        })
        assert.is_false(fc_hide:show_file("test_complete.epub", "test_complete.epub"))

        filemanagerutil.getStatus = original_getStatus
    end)
end)
