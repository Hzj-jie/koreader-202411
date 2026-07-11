describe("TermInputText widget module", function()
  local TermInputText
  local equals
  setup(function()
    require("commonrequire")
    TermInputText = require("plugins/terminal.koplugin/terminputtext")
    equals = require("util").tableEquals
  end)

  describe("wrapping logic", function()
    it("should wrap text properly without extra newlines or spaces", function()
      local term = TermInputText:new({
        maxc = 10,
        maxr = 3,
        wrap = true,
      })
      -- 10 columns, 3 rows.
      -- Write 9 chars -> stays on row 1
      term:addChars("123456789")
      assert.is_true(
        equals({ "1", "2", "3", "4", "5", "6", "7", "8", "9" }, term.charlist)
      )

      -- Write 1 more -> 10 chars, fits row 1
      term:addChars("0")
      assert.is_true(
        equals(
          { "1", "2", "3", "4", "5", "6", "7", "8", "9", "0" },
          term.charlist
        )
      )

      -- Write 1 more -> 11th char, should wrap to row 2!
      term:addChars("a")
      local expected = {
        "1",
        "2",
        "3",
        "4",
        "5",
        "6",
        "7",
        "8",
        "9",
        "0",
        "\n",
        "a",
        " ",
        " ",
        " ",
        " ",
        " ",
        " ",
        " ",
        " ",
        " ",
        "\n",
      }
      assert.is_true(equals(expected, term.charlist))

      -- Now write "b". Since "a" was at 12, "b" should go to 13 (no wrap!).
      term:addChars("b")
      expected[13] = "b"
      assert.is_true(equals(expected, term.charlist))
    end)

    it(
      "should not delete characters from next line when overwriting newline",
      function()
        local term = TermInputText:new({
          maxc = 10,
          maxr = 3,
          wrap = true,
        })
        -- Setup: two lines of text
        term.charlist = {
          "1",
          "2",
          "3",
          "\n",
          "a",
          "b",
          "c",
          "\n",
        }
        -- "123\nabc\n"
        -- indices: 1="1", 2="2", 3="3", 4="\n", 5="a", 6="b", 7="c", 8="\n"
        term.charpos = 4
        term:addChars("x")

        local expected = {
          "1",
          "2",
          "3",
          "x",
          "\n",
          "a",
          "b",
          "c",
          "\n",
        }
        assert.are.same(expected, term.charlist)
      end
    )

    it("should handle typing with long prompt and maxc=65", function()
      local term = TermInputText:new({
        maxc = 65,
        maxr = 19,
        wrap = true,
      })
      local prompt =
        "zijiehe@zijiehe09:~/data/git/koreader-202411/koreader/plugins/terminal.koplugin$ "
      term:addChars(prompt)

      -- Type "l", "s", " ", "-"
      term:addChars("l")
      term:addChars("s")
      term:addChars(" ")
      term:addChars("-")

      local expected = {}
      for i = 1, 65 do
        table.insert(expected, prompt:sub(i, i))
      end
      table.insert(expected, "\n")
      for i = 66, 81 do
        table.insert(expected, prompt:sub(i, i))
      end
      table.insert(expected, "l")
      table.insert(expected, "s")
      table.insert(expected, " ")
      table.insert(expected, "-")
      -- Pad Row 2 to maxc (65)
      for _ = 1, 45 do
        table.insert(expected, " ")
      end
      table.insert(expected, "\n")

      assert.are.same(expected, term.charlist)
    end)
  end)
end)
