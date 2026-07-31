describe("KOSyncClient plugin module", function()
  local KOSyncClient

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    KOSyncClient = require("plugins/kosync.koplugin/KOSyncClient")
    KOSyncClient.service_spec = "{}"
  end)

  it("should instantiate KOSyncClient instance", function()
    local mock_client = {
      reset_middlewares = function() end,
      enable = function() end,
      register = function() return { status = 201, body = { message = "User created" } } end,
      authorize = function() return { status = 200, body = { key = "secret_key" } } end,
      update_progress = function() return { status = 200, body = { progress = "10" } } end,
      get_progress = function() return { status = 200, body = { progress = "10" } } end,
    }

    local inst = setmetatable({ client = mock_client }, { __index = KOSyncClient })
    assert.is_table(inst)
    assert.are.equal(mock_client, inst.client)
  end)

  it("should register new user", function()
    local mock_client = {
      reset_middlewares = function() end,
      enable = function() end,
      register = function(self, args)
        return { status = 201, body = { username = args.username } }
      end,
    }

    local inst = setmetatable({ client = mock_client }, { __index = KOSyncClient })
    local success, body = inst:register("testuser", "password123")

    assert.is_true(success)
    assert.is_table(body)
    assert.are.equal("testuser", body.username)
  end)

  it("should authorize user login", function()
    local mock_client = {
      reset_middlewares = function() end,
      enable = function() end,
      authorize = function()
        return { status = 200, body = { key = "auth_key" } }
      end,
    }

    local inst = setmetatable({ client = mock_client }, { __index = KOSyncClient })
    local success, body = inst:authorize("testuser", "auth_key")

    assert.is_true(success)
    assert.are.equal("auth_key", body.key)
  end)

  it("should push and pull reading progress", function()
    local mock_client = {
      reset_middlewares = function() end,
      enable = function() end,
      update_progress = function()
        return { status = 200, body = { ok = true } }
      end,
      get_progress = function()
        return { status = 200, body = { progress = "50" } }
      end,
    }

    local inst = setmetatable({ client = mock_client }, { __index = KOSyncClient })

    local push_success = nil
    inst:update_progress("user", "key", "doc.epub", 50, 0.5, "Kobo", "123", function(ok, body)
      push_success = ok
    end)
    assert.is_true(push_success)

    local pull_body = nil
    inst:get_progress("user", "key", "doc.epub", function(ok, body)
      pull_body = body
    end)
    assert.is_table(pull_body)
    assert.are.equal("50", pull_body.progress)
  end)
end)
