describe("IconWidget", function()
  local IconWidget

  setup(function()
    require("commonrequire")
    IconWidget = require("ui/widget/iconwidget")
  end)

  it("should initialize with found icon", function()
    local icon = IconWidget:new({
      icon = "appbar.menu",
    })

    assert.truthy(icon.file)
    assert.is_true(icon.is_icon)
  end)

  it("should fallback to icon-not-found for missing icon", function()
    local icon = IconWidget:new({
      icon = "nonexistent_custom_icon_xyz",
    })

    assert.truthy(icon.file)
    assert.truthy(icon.file:find("icon-not-found", 1, true))
  end)

  it("should pass through existing image or file attribute", function()
    local icon_img = IconWidget:new({
      file = "/tmp/test.png",
    })
    assert.are.equal("/tmp/test.png", icon_img.file)
  end)

  describe("Defect verifications", function()
    it(
      "exposes permanent caching of ICON_NOT_FOUND on initial lookup miss",
      function()
        local lfs = require("libs/libkoreader-lfs")
        local orig_attributes = lfs.attributes
        local late_icon_name = "late_added_test_icon_" .. os.time()
        local late_icon_path = "resources/icons/" .. late_icon_name .. ".svg"

        local iw1 = IconWidget:new({ icon = late_icon_name })
        assert.truthy(iw1.file:find("icon-not-found", 1, true))

        lfs.attributes = function(path, req)
          if path == late_icon_path then
            return "file"
          end
          return orig_attributes(path, req)
        end

        local iw2 = IconWidget:new({ icon = late_icon_name })
        lfs.attributes = orig_attributes
        assert.are.equal(late_icon_path, iw2.file)
      end
    )
  end)
end)
