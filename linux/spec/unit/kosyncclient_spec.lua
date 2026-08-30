describe("KOSyncClient module", function()
  local KOSyncClient

  setup(function()
    require("commonrequire")
    KOSyncClient = require("plugins/kosync.koplugin/KOSyncClient")
  end)

  it("should initialize KOSyncClient", function()
    local client = KOSyncClient:new({
      service_spec = "plugins/kosync.koplugin/api.json",
      username = "test_user",
      password = "test_password",
    })

    assert.is_table(client)
    assert.are.equal("test_user", client.username)
  end)

  it("should initialize KOSyncClient with custom_url and set middlewares", function()
    local client = KOSyncClient:new({
      service_spec = "plugins/kosync.koplugin/api.json",
      custom_url = "https://custom.sync.server:8080",
    })

    assert.is_table(client)
    assert.are.equal("https://custom.sync.server:8080", client.custom_url)

    -- Test GinClient middleware header
    local gin_middleware = require("Spore.Middleware.GinClient")
    assert.is_table(gin_middleware)
    local mock_req = { headers = {} }
    gin_middleware.call(nil, mock_req)
    assert.are.equal("application/vnd.koreader.v1+json", mock_req.headers["accept"])

    -- Test KOSyncAuth middleware headers
    local auth_middleware = require("Spore.Middleware.KOSyncAuth")
    assert.is_table(auth_middleware)
    local auth_req = { headers = {} }
    auth_middleware.call({ username = "u1", userkey = "k1" }, auth_req)
    assert.are.equal("u1", auth_req.headers["x-auth-user"])
    assert.are.equal("k1", auth_req.headers["x-auth-key"])
  end)
end)
