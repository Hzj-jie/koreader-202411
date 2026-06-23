local luxl

describe("luxl", function()
    setup(function()
        require("commonrequire")
        luxl = require("luxl")
    end)

    -- Helper to run lexer and return event list
    local function lex(str)
        local lx = luxl.new(str, #str)
        local results = {}
        for event, offset, size in lx:Lexemes() do
            local text = str:sub(offset + 1, offset + size)
            table.insert(results, {event = event, text = text})
        end
        return results
    end

    it("should lex simple tags", function()
        local res = lex("<tag></tag>")
        assert.is.same({
            { event = luxl.EVENT_START, text = "tag" },
            { event = luxl.EVENT_END, text = "/tag" },
        }, res)
    end)

    it("should lex self-closing tags with space", function()
        local res = lex("<tag />")
        assert.is.same({
            { event = luxl.EVENT_START, text = "tag" },
            { event = luxl.EVENT_END, text = "/" },
        }, res)
    end)

    it("should lex tags with text content", function()
        local res = lex("<tag>hello world</tag>")
        assert.is.same({
            { event = luxl.EVENT_START, text = "tag" },
            { event = luxl.EVENT_TEXT, text = "hello world" },
            { event = luxl.EVENT_END, text = "/tag" },
        }, res)
    end)

    it("should lex tags with attributes", function()
        local res = lex('<tag key="val" />')
        assert.is.same({
            { event = luxl.EVENT_START, text = "tag" },
            { event = luxl.EVENT_ATTR_NAME, text = "key" },
            { event = luxl.EVENT_ATTR_VAL, text = "val" },
            { event = luxl.EVENT_END, text = "/" },
        }, res)
    end)

    it("should lex tags with multiple attributes", function()
        local res = lex('<tag k1="v1" k2="v2" />')
        assert.is.same({
            { event = luxl.EVENT_START, text = "tag" },
            { event = luxl.EVENT_ATTR_NAME, text = "k1" },
            { event = luxl.EVENT_ATTR_VAL, text = "v1" },
            { event = luxl.EVENT_ATTR_NAME, text = "k2" },
            { event = luxl.EVENT_ATTR_VAL, text = "v2" },
            { event = luxl.EVENT_END, text = "/" },
        }, res)
    end)

    it("should lex nested tags", function()
        local res = lex("<parent><child>text</child></parent>")
        assert.is.same({
            { event = luxl.EVENT_START, text = "parent" },
            { event = luxl.EVENT_START, text = "child" },
            { event = luxl.EVENT_TEXT, text = "text" },
            { event = luxl.EVENT_END, text = "/child" },
            { event = luxl.EVENT_END, text = "/parent" },
        }, res)
    end)

    -- Documenting the quirk/limitation for self-closing tag without space
    it("documents limitation: self-closing tag without space behaves unexpectedly", function()
        local res = lex("<tag/>")
        -- Based on code analysis, we expect:
        -- 1. EVENT_END for "tag" (instead of EVENT_START)
        -- 2. End of document (no EVENT_START, and second EVENT_END is ignored because mark is 0)
        assert.is.same({
            { event = luxl.EVENT_END, text = "tag" },
        }, res)
    end)
end)
