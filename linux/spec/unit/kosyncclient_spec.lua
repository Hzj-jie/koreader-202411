describe("KOSyncClient module", function()
  local KOSyncClient
  local client

  setup(function()
    require("commonrequire")
    KOSyncClient = require("plugins/kosync.koplugin/KOSyncClient")
  end)

  before_each(function()
    client = KOSyncClient:new({
      service_spec = "plugins/kosync.koplugin/api.json",
      username = "test_user",
      password = "test_password",
    })
  end)

  describe("initialization", function()
    it(
      "should initialize KOSyncClient with credentials and Spore client",
      function()
        assert.is_table(client)
        assert.are.equal("test_user", client.username)
        assert.are.equal("test_password", client.password)
        assert.is_table(client.client)
      end
    )
  end)

  describe("register", function()
    local orig_register

    before_each(function()
      orig_register = client.client.register
    end)

    after_each(function()
      client.client.register = orig_register
    end)

    it("returns true and body on successful registration (HTTP 201)", function()
      client.client.register = function()
        return {
          status = 201,
          body = { message = "User created" },
        }
      end

      local success, body = client:register("test_user", "test_password")
      assert.is_true(success)
      assert.is_table(body)
      assert.are.equal("User created", body.message)
    end)

    it("returns false and response body on HTTP failure", function()
      client.client.register = function()
        return {
          status = 400,
          body = { message = "Username already exists" },
        }
      end

      local success, body = client:register("test_user", "test_password")
      assert.is_false(success)
      assert.is_table(body)
      assert.are.equal("Username already exists", body.message)
    end)

    it(
      "returns error message when register pcall fails (fails: line 89 string error indexing)",
      function()
        client.client.register = function()
          error("Connection timed out")
        end

        local success, err = client:register("test_user", "test_password")
        assert.is_false(success)
        -- Production bug in KOSyncClient.lua line 89:
        -- When pcall throws an error, `res` is the string error message.
        -- Line 89 executes `return false, res.body`.
        -- In Lua, indexing a string with `.body` yields nil, discarding the error message.
        assert.are.equal("Connection timed out", err)
      end
    )
  end)

  describe("authorize", function()
    local orig_authorize

    before_each(function()
      orig_authorize = client.client.authorize
    end)

    after_each(function()
      client.client.authorize = orig_authorize
    end)

    it(
      "returns true and body on successful authorization (HTTP 200)",
      function()
        client.client.authorize = function()
          return {
            status = 200,
            body = { authorized = "OK" },
          }
        end

        local success, body = client:authorize("test_user", "test_password")
        assert.is_true(success)
        assert.is_table(body)
        assert.are.equal("OK", body.authorized)
      end
    )

    it("returns false and response body on 401 unauthorized", function()
      client.client.authorize = function()
        return {
          status = 401,
          body = { message = "Invalid credentials" },
        }
      end

      local success, body = client:authorize("test_user", "test_password")
      assert.is_false(success)
      assert.is_table(body)
      assert.are.equal("Invalid credentials", body.message)
    end)

    it(
      "returns error message when authorize pcall fails (fails: line 110 string error indexing)",
      function()
        client.client.authorize = function()
          error("Host unreachable")
        end

        local success, err = client:authorize("test_user", "test_password")
        assert.is_false(success)
        -- Production bug in KOSyncClient.lua line 110:
        -- When pcall throws an error, `res` is the string error message.
        -- Line 110 executes `return false, res.body`.
        -- In Lua, indexing a string with `.body` yields nil, discarding the error message.
        assert.are.equal("Host unreachable", err)
      end
    )
  end)
end)
