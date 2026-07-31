describe("Coverbrowser ListMenu module", function()
  local ListMenu, Geom

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    Geom = require("ui/geometry")
    ListMenu = require("plugins/coverbrowser.koplugin/listmenu")
  end)

  describe("Initialization & Mixin", function()
    it("should expose ListMenu methods table", function()
      assert.is_table(ListMenu)
      assert.is_function(ListMenu._recalculateDimen)
    end)

    it("should allow mixing ListMenu methods into a menu object", function()
      local mock_menu = {
        item_table = {
          { text = "Book 1", path = "/tmp/book1.epub" },
        },
        page = 1,
        perpage = 1,
        width = 400,
        height = 600,
        item_group = {},
        layout = {},
        items_to_update = {},
        path_items = {},
        inner_dimen = Geom:new({ x = 0, y = 0, w = 400, h = 600 }),
        item_dimen = Geom:new({ x = 0, y = 0, w = 400, h = 50 }),
      }
      setmetatable(mock_menu, { __index = ListMenu })

      if type(mock_menu._recalculateDimen) == "function" then
        mock_menu:_recalculateDimen()
        assert.is_boolean(mock_menu.portrait_mode)
      end
    end)
  end)
end)
