local Widget = require("ui/widget/widget")
local spy = require("luassert.spy")

describe("Widget lifecycle and auto-cleanup", function()
    local parent
    local mock_uimanager
    local original_uimanager

    before_each(function()
        parent = Widget:new()
        original_uimanager = package.loaded["ui/uimanager"]
        mock_uimanager = {
            show = spy.new(function() end),
            closeIfShown = spy.new(function() end),
        }
        package.loaded["ui/uimanager"] = mock_uimanager
    end)

    after_each(function()
        package.loaded["ui/uimanager"] = original_uimanager
    end)

    describe("showWidget", function()
        it("registers the child and shows it via UIManager", function()
            local child = Widget:new()
            parent:showWidget(child, "arg1", "arg2")

            assert.same({ child }, parent._shown_widgets)
            assert.spy(mock_uimanager.show).was_called_with(mock_uimanager, child, "arg1", "arg2")
        end)
    end)

    describe("uimanagedCleanUp", function()
        it("closes all shown children and nils their named fields in parent", function()
            local child1 = Widget:new()
            local child2 = Widget:new()
            local child3 = Widget:new() -- anonymous

            parent.child1 = child1
            parent.child2 = child2
            -- child3 is not stored in a field

            parent:showWidget(child1)
            parent:showWidget(child2)
            parent:showWidget(child3)

            parent:uimanagedCleanUp()

            -- All children should be closed
            assert.spy(mock_uimanager.closeIfShown).was_called_with(mock_uimanager, child1)
            assert.spy(mock_uimanager.closeIfShown).was_called_with(mock_uimanager, child2)
            assert.spy(mock_uimanager.closeIfShown).was_called_with(mock_uimanager, child3)

            -- Named fields should be nilled
            assert.is_nil(parent.child1)
            assert.is_nil(parent.child2)

            -- _shown_widgets should be cleared
            assert.is_nil(parent._shown_widgets)
        end)

        it("does not nil the array portion (numeric keys) of the parent", function()
            local child = Widget:new()
            parent[1] = child -- stored numerically (like layout children)

            parent:showWidget(child)
            parent:uimanagedCleanUp()

            -- Should be closed
            assert.spy(mock_uimanager.closeIfShown).was_called_with(mock_uimanager, child)

            -- BUT it must NOT be nilled in the array portion
            assert.equal(child, parent[1])
        end)

        it("safely does nothing if no children were shown", function()
            assert.has_no.errors(function()
                parent:uimanagedCleanUp()
            end)
        end)
    end)
end)
