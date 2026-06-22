local spy = require("luassert.spy")
local mock = require("luassert.mock")

describe("TextViewer", function()
  local TextViewer
  local UIManager
  local temp_file_small = "spec/unit/test_small.txt"
  local temp_file_large = "spec/unit/test_large.txt"

  setup(function()
    require("commonrequire")
    TextViewer = require("ui/widget/textviewer")
    UIManager = require("ui/uimanager")

    -- Create small file (10 bytes)
    local f = io.open(temp_file_small, "w")
    f:write("Small file")
    f:close()

    -- Create large file (> 400,000 bytes, e.g. 400,010 bytes)
    f = io.open(temp_file_large, "w")
    f:write(string.rep("A", 400010))
    f:close()
  end)

  teardown(function()
    os.remove(temp_file_small)
    os.remove(temp_file_large)
  end)

  it("opens small file directly", function()
    spy.on(UIManager, "show")

    TextViewer:openFile(temp_file_small)

    assert.spy(UIManager.show).was.called(1)
    local widget = UIManager.show.calls[1].refs[2]
    assert.is_not_nil(widget)
    assert.equal("Small file", widget.text)
    assert.equal(temp_file_small, widget.title)

    UIManager:close(widget)
    UIManager.show:revert()
  end)

  it("shows ConfirmBox for large file, and opens it after OK", function()
    spy.on(UIManager, "show")

    TextViewer:openFile(temp_file_large)

    -- Should show ConfirmBox first
    assert.spy(UIManager.show).was.called(1)
    local confirm_box = UIManager.show.calls[1].refs[2]
    assert.is_not_nil(confirm_box)

    -- We cannot easily check the class name, but we can check if it has ok_text and cancel_text
    assert.equal("Open", confirm_box.ok_text)

    -- Now trigger OK callback
    confirm_box.ok_callback()

    -- Should show TextViewer now (total 2 calls to UIManager.show)
    assert.spy(UIManager.show).was.called(2)
    local text_viewer = UIManager.show.calls[2].refs[2]
    assert.is_not_nil(text_viewer)
    assert.equal(temp_file_large, text_viewer.title)
    assert.equal(400010, #text_viewer.text)

    UIManager:close(confirm_box)
    UIManager:close(text_viewer)
    UIManager.show:revert()
  end)
end)
