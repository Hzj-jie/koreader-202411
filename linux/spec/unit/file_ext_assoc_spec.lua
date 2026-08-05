describe("FileExtAssoc element", function()
  local FileExtAssoc, Device

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    Device = require("device")
    FileExtAssoc = require("ui/elements/file_ext_assoc")
  end)

  it("should set individual file extension associations", function()
    FileExtAssoc:setOne("epub", true)
    assert.is_true(FileExtAssoc.assoc["epub"])

    FileExtAssoc:setOne("epub", false)
    assert.is_nil(FileExtAssoc.assoc["epub"])
  end)

  it(
    "should enable and disable all supported extension associations",
    function()
      local associated_exts = nil
      local old_assoc = Device.associateFileExtensions
      Device.associateFileExtensions = function(self, t)
        associated_exts = t
      end

      FileExtAssoc:setAll(true)
      assert.is_table(associated_exts)
      assert.is_not_nil(associated_exts["epub"])

      FileExtAssoc:setAll(false)
      assert.is_nil(associated_exts["epub"])

      Device.associateFileExtensions = old_assoc
    end
  )

  it(
    "should generate settings menu table for file extension associations",
    function()
      local menu_table = FileExtAssoc:getSettingsMenuTable()
      assert.is_table(menu_table)
      assert.is_true(#menu_table >= 3)
      assert.are.equal("Enable all", menu_table[1].text)
      assert.are.equal("Disable all", menu_table[2].text)

      local mock_menu = { updateItems = function() end }
      menu_table[1].callback(mock_menu)
      menu_table[2].callback(mock_menu)

      -- Test individual extension item callbacks
      if menu_table[3] and menu_table[3].callback then
        menu_table[3].callback(mock_menu)
      end
    end
  )
end)
