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
end)
