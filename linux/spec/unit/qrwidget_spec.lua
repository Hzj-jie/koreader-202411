describe("QRWidget", function()
  local QRWidget
  local qrencode

  setup(function()
    require("commonrequire")
    QRWidget = require("ui/widget/qrwidget")
    qrencode = require("ffi/qrencode")
  end)

  it("should generate QR blitbuffer for short text", function()
    local qr = QRWidget:new({
      text = "https://koreader.rocks",
      width = 200,
      height = 200,
    })

    assert.truthy(qr.image)
  end)

  it("should truncate long text (> 2953 chars)", function()
    local long_text = string.rep("A", 3000)
    local qr = QRWidget:new({
      text = long_text,
      width = 250,
    })

    assert.truthy(qr.image)
  end)

  it("should handle width only, height only, and no dimensions", function()
    local qr_w = QRWidget:new({
      text = "Width only",
      width = 150,
    })
    assert.truthy(qr_w.image)

    local qr_h = QRWidget:new({
      text = "Height only",
      height = 150,
    })
    assert.truthy(qr_h.image)

    local qr_none = QRWidget:new({
      text = "No dim",
    })
    assert.truthy(qr_none.image)
  end)

  it("should handle failure when qrencode fails", function()
    local orig_qrcode = qrencode.qrcode
    qrencode.qrcode = function(text)
      return false, "failed"
    end

    local qr_fail = QRWidget:new({
      text = "Fail test",
    })
    assert.is_nil(qr_fail.image)

    qrencode.qrcode = orig_qrcode
  end)
end)
