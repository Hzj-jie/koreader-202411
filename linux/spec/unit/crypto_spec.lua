local ffi
local crypto
local ssl
local turbo

describe("crypto and ssl modules", function()
  setup(function()
    require("commonrequire")
    ffi = require("ffi")
    require("ffi/loadlib")
    require("ffi/posix_h")
    crypto = require("ffi/crypto")
    ssl = require("ssl")
    _G.TURBO_SSL = true
    turbo = require("turbo")
  end)

  it("calculates pbkdf2_hmac_sha1 matching standard test vector", function()
    local key = crypto.pbkdf2_hmac_sha1("password", "salt", 1, 20)
    assert.are.equal(20, #key)
    local hex = ""
    for i = 1, #key do
      hex = hex .. string.format("%02x", key:byte(i))
    end
    assert.are.equal("0c60c80f961f0e71f3a9b524af6012062fe037a6", hex)
  end)

  it("loads ssl module successfully", function()
    assert.is_not_nil(ssl)
    assert.is_not_nil(ssl._VERSION)
  end)

  it("computes turbo SHA1 hash", function()
    local turbo_hash = require("turbo.hash")
    local h = turbo_hash.SHA1("hello"):hex()
    assert.are.equal("aaf4c61ddcc5e8a2dabede0f3b482cd9aea9434d", h)
  end)

  it("loads turbo.crypto module successfully", function()
    local turbo_crypto = require("turbo.crypto")
    assert.is_not_nil(turbo_crypto)
    assert.is_not_nil(turbo_crypto.X509_FILETYPE_PEM)
  end)
end)
