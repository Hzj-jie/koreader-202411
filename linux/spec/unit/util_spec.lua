describe("util module", function()
  local DataStorage, util
  setup(function()
    require("commonrequire")
    DataStorage = require("datastorage")
    util = require("util")
  end)

  it("should strip punctuation marks around word", function()
    assert.is_equal("hello world", util.stripPunctuation('"hello world"'))
    assert.is_equal("hello world", util.stripPunctuation('"hello world?"'))
    assert.is_equal("hello, world", util.stripPunctuation('"hello, world?"'))
    assert.is_equal("你好", util.stripPunctuation("“你好“"))
    assert.is_equal("你好", util.stripPunctuation("“你好?“"))
    assert.is_equal("", util.stripPunctuation(""))
    assert.is_nil(util.stripPunctuation(nil))
  end)

  describe("gsplit()", function()
    it("should split string with patterns", function()
      local sentence = "Hello world, welcome to KOReader!"
      local words = {}
      for word in util.gsplit(sentence, "%s+", false) do
        table.insert(words, word)
      end
      assert.are_same(
        { "Hello", "world,", "welcome", "to", "KOReader!" },
        words
      )
    end)
    it("should split command line arguments with quotation", function()
      local command =
        './sdcv -nj "words" "a lot" \'more or less\' --data-dir=dict'
      local argv = {}
      for arg1 in util.gsplit(command, "[\"'].-[\"']", true) do
        for arg2 in util.gsplit(arg1, "^[^\"'].-%s+", true) do
          for arg3 in util.gsplit(arg2, "[\"']", false) do
            local trimmed = util.trim(arg3)
            if trimmed ~= "" then
              table.insert(argv, trimmed)
            end
          end
        end
      end
      assert.are_same(
        { "./sdcv", "-nj", "words", "a lot", "more or less", "--data-dir=dict" },
        argv
      )
    end)
    it("should split string with dashes", function()
      local words = {}
      for word in util.gsplit("a-b-c-d", "-", false) do
        table.insert(words, word)
      end
      assert.are_same({ "a", "b", "c", "d" }, words)
    end)
    it("should split string with dashes with final dash", function()
      local words = {}
      for word in util.gsplit("a-b-c-d-", "-", false) do
        table.insert(words, word)
      end
      assert.are_same({ "a", "b", "c", "d" }, words)
    end)
  end)

  describe("splitToWords()", function()
    it("should split line into words", function()
      local words = util.splitToWords("one two,three  four . five")
      assert.are_same({
        "one",
        " ",
        "two",
        ",",
        "three",
        "  ",
        "four",
        " . ",
        "five",
      }, words)
    end)
    it("should split ancient greek words", function()
      local words = util.splitToWords(
        "Λαρισαῖος Λευκοθέα Λιγυαστάδης."
      )
      assert.are_same({
        "Λαρισαῖος",
        " ",
        "Λευκοθέα",
        " ",
        "Λιγυαστάδης",
        ".",
      }, words)
    end)
    it("should split Chinese words", function()
      local words =
        util.splitToWords("彩虹是通过太阳光的折射引起的。")
      assert.are_same({
        "彩",
        "虹",
        "是",
        "通",
        "过",
        "太",
        "阳",
        "光",
        "的",
        "折",
        "射",
        "引",
        "起",
        "的",
        "。",
      }, words)
    end)
    it("should split Japanese words", function()
      local words = util.splitToWords(
        "色は匂へど散りぬるを我が世誰ぞ常ならむ"
      )
      assert.are_same({
        "色",
        "は",
        "匂",
        "へ",
        "ど",
        "散",
        "り",
        "ぬ",
        "る",
        "を",
        "我",
        "が",
        "世",
        "誰",
        "ぞ",
        "常",
        "な",
        "ら",
        "む",
      }, words)
    end)
    it("should split Korean words", function()
      -- Technically splitting on spaces is correct but we treat Korean
      -- as if it were any other CJK text.
      local words = util.splitToWords(
        "대한민국의 국기는 대한민국 국기법에 따라 태극기"
      )
      assert.are_same({
        "대",
        "한",
        "민",
        "국",
        "의",
        " ",
        "국",
        "기",
        "는",
        " ",
        "대",
        "한",
        "민",
        "국",
        " ",
        "국",
        "기",
        "법",
        "에",
        " ",
        "따",
        "라",
        " ",
        "태",
        "극",
        "기",
      }, words)
    end)
    it("should split words of multilingual text", function()
      local words = util.splitToWords("BBC纪录片")
      assert.are_same({ "BBC", "纪", "录", "片" }, words)
    end)
  end)

  describe("splitToChars()", function()
    it("should split text to line - unicode", function()
      local text =
        "Pójdźże, chmurność glück schließen Štěstí neštěstí. Uñas gavilán"
      local word = ""
      local table_of_words = {}
      local c
      local table_chars = util.splitToChars(text)
      for i = 1, #table_chars do
        c = table_chars[i]
        word = word .. c
        if util.isSplittable(c) then
          table.insert(table_of_words, word)
          word = ""
        end
        if i == #table_chars and word ~= "" then
          table.insert(table_of_words, word)
        end
      end
      assert.are_same({
        "Pójdźże, ",
        "chmurność ",
        "glück ",
        "schließen ",
        "Štěstí ",
        "neštěstí. ",
        "Uñas ",
        "gavilán",
      }, table_of_words)
    end)
    it("should split text to line - CJK Chinese", function()
      local text = "彩虹是通过太阳光的折射引起的。"
      local word = ""
      local table_of_words = {}
      local c
      local table_chars = util.splitToChars(text)
      for i = 1, #table_chars do
        c = table_chars[i]
        word = word .. c
        if util.isSplittable(c) then
          table.insert(table_of_words, word)
          word = ""
        end
        if i == #table_chars and word ~= "" then
          table.insert(table_of_words, word)
        end
      end
      assert.are_same({
        "彩",
        "虹",
        "是",
        "通",
        "过",
        "太",
        "阳",
        "光",
        "的",
        "折",
        "射",
        "引",
        "起",
        "的",
        "。",
      }, table_of_words)
    end)
    it("should split text to line - CJK Japanese", function()
      local text = "色は匂へど散りぬるを我が世誰ぞ常ならむ"
      local word = ""
      local table_of_words = {}
      local c
      local table_chars = util.splitToChars(text)
      for i = 1, #table_chars do
        c = table_chars[i]
        word = word .. c
        if util.isSplittable(c) then
          table.insert(table_of_words, word)
          word = ""
        end
        if i == #table_chars and word ~= "" then
          table.insert(table_of_words, word)
        end
      end
      assert.are_same({
        "色",
        "は",
        "匂",
        "へ",
        "ど",
        "散",
        "り",
        "ぬ",
        "る",
        "を",
        "我",
        "が",
        "世",
        "誰",
        "ぞ",
        "常",
        "な",
        "ら",
        "む",
      }, table_of_words)
    end)
    it("should split text to line - CJK Korean", function()
      local text =
        "대한민국의 국기는 대한민국 국기법에 따라 태극기"
      local word = ""
      local table_of_words = {}
      local c
      local table_chars = util.splitToChars(text)
      for i = 1, #table_chars do
        c = table_chars[i]
        word = word .. c
        if util.isSplittable(c) then
          table.insert(table_of_words, word)
          word = ""
        end
        if i == #table_chars and word ~= "" then
          table.insert(table_of_words, word)
        end
      end
      assert.are_same({
        "대",
        "한",
        "민",
        "국",
        "의",
        " ",
        "국",
        "기",
        "는",
        " ",
        "대",
        "한",
        "민",
        "국",
        " ",
        "국",
        "기",
        "법",
        "에",
        " ",
        "따",
        "라",
        " ",
        "태",
        "극",
        "기",
      }, table_of_words)
    end)
    it("should split text to line - mixed CJK and latin", function()
      local text =
        "This is Russian: русский язык, Chinese: 汉语, Japanese: 日本語、 Korean: 한국어。"
      local word = ""
      local table_of_words = {}
      local c
      local table_chars = util.splitToChars(text)
      for i = 1, #table_chars do
        c = table_chars[i]
        word = word .. c
        if util.isSplittable(c) then
          table.insert(table_of_words, word)
          word = ""
        end
        if i == #table_chars and word ~= "" then
          table.insert(table_of_words, word)
        end
      end
      assert.are_same({
        "This ",
        "is ",
        "Russian: ",
        "русский ",
        "язык, ",
        "Chinese: ",
        "汉",
        "语",
        ", ",
        "Japanese: ",
        "日",
        "本",
        "語",
        "、",
        " ",
        "Korean: ",
        "한",
        "국",
        "어",
        "。",
      }, table_of_words)
    end)
    it("should split text to line with next_c - unicode", function()
      local text =
        "Ce test : 1) est très simple ; 2 ) simple comme ( 2/2 ) > 50 % ? ok."
      local word = ""
      local table_of_words = {}
      local c, next_c
      local table_chars = util.splitToChars(text)
      for i = 1, #table_chars do
        c = table_chars[i]
        next_c = i < #table_chars and table_chars[i + 1] or nil
        word = word .. c
        if util.isSplittable(c, next_c) then
          table.insert(table_of_words, word)
          word = ""
        end
        if i == #table_chars and word ~= "" then
          table.insert(table_of_words, word)
        end
      end
      assert.are_same({
        "Ce ",
        "test : ",
        "1) ",
        "est ",
        "très ",
        "simple ; ",
        "2 ) ",
        "simple ",
        "comme ",
        "( ",
        "2/2 ) > ",
        "50 % ? ",
        "ok.",
      }, table_of_words)
    end)
    it("should split text to line with next_c and prev_c - unicode", function()
      local text =
        "Ce test : 1) est « très simple » ; 2 ) simple comme ( 2/2 ) > 50 % ? ok."
      local word = ""
      local table_of_words = {}
      local c, next_c, prev_c
      local table_chars = util.splitToChars(text)
      for i = 1, #table_chars do
        c = table_chars[i]
        next_c = i < #table_chars and table_chars[i + 1] or nil
        prev_c = i > 1 and table_chars[i - 1] or nil
        word = word .. c
        if util.isSplittable(c, next_c, prev_c) then
          table.insert(table_of_words, word)
          word = ""
        end
        if i == #table_chars and word ~= "" then
          table.insert(table_of_words, word)
        end
      end
      assert.are_same({
        "Ce ",
        "test : ",
        "1) ",
        "est ",
        "« très ",
        "simple » ; ",
        "2 ) ",
        "simple ",
        "comme ",
        "( 2/2 ) > 50 % ? ",
        "ok.",
      }, table_of_words)
    end)
  end)

  it("should split file path and name", function()
    local test = function(full, path, name)
      local p, n = util.splitFilePathName(full)
      assert.are_same(p, path)
      assert.are_same(n, name)
    end
    test("/a/b/c.txt", "/a/b/", "c.txt")
    test("/a/b////c.txt", "/a/b////", "c.txt")
    test("/a/b/", "/a/b/", "")
    test("c.txt", "", "c.txt")
    test("", "", "")
    test(nil, "", "")
    test("a/b", "a/", "b")
    test("/b", "/", "b")
    assert.are_same("/a/b/", util.splitFilePathName("/a/b/c.txt"))
  end)

  it("should split file name and suffix", function()
    local test = function(full, name, suffix)
      local n, s = util.splitFileNameSuffix(full)
      assert.are_same(n, name)
      assert.are_same(s, suffix)
    end
    test("a.txt", "a", "txt")
    test("/a/b.txt", "/a/b", "txt")
    test("a", "a", "")
    test("/a/b", "/a/b", "")
    test("/a/", "/a/", "")
    test("/a/.txt", "/a/", "txt")
    test(nil, "", "")
    test("", "", "")
    assert.are_same("a", util.splitFileNameSuffix("a.txt"))
  end)

  describe("getSafeFileName()", function()
    it("should replace unsafe characters", function()
      assert.is_equal("___", util.getSafeFilename("|||"))
    end)
    it("should truncate any characters beyond the limit", function()
      assert.is_equal(
        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        util.getSafeFilename(
          "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        )
      )
    end)
    it("should truncate extension beyond the limit", function()
      assert.is_equal(
        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        util.getSafeFilename(
          "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        )
      )
    end)
    it("should strip HTML from the filename", function()
      assert.is_equal("lalala", util.getSafeFilename("<span>lalala</span>"))
    end)
  end)

  describe("partialMD5()", function()
    it("should calculate partial md5 hash of pdf file", function()
      assert.is_equal(
        util.partialMD5("spec/front/unit/data/tall.pdf"),
        "41cce710f34e5ec21315e19c99821415"
      )
    end)
    it("should calculate partial md5 hash of epub file", function()
      assert.is_equal(
        util.partialMD5("spec/front/unit/data/leaves.epub"),
        "59d481d168cca6267322f150c5f6a2a3"
      )
    end)
  end)

  describe("fixUtf8()", function()
    it("should replace invalid UTF-8 characters with an underscore", function()
      assert.is_equal("\127 _ _\127 ", util.fixUtf8("\127 \128 \194\127 ", "_"))
    end)

    it(
      "should replace invalid UTF-8 characters with multiple characters",
      function()
        assert.is_equal(
          "\127 __ __\127 ",
          util.fixUtf8("\127 \128 \194\127 ", "__")
        )
      end
    )

    it("should replace invalid UTF-8 characters with empty char", function()
      assert.is_equal("\127  \127 ", util.fixUtf8("\127 \128 \194\127 ", ""))
    end)

    it("should not replace valid UTF-8 � character", function()
      assert.is_equal(
        "�valid � char �",
        util.fixUtf8("�valid � char �", "__")
      )
    end)

    it("should not replace valid UTF-8 characters", function()
      assert.is_equal(
        "\99 \244\129\130\190",
        util.fixUtf8("\99 \244\129\130\190", "_")
      )
    end)

    it("should not replace valid UTF-8 characters Polish chars", function()
      assert.is_equal(
        "Pójdźże źółć",
        util.fixUtf8("Pójdźże źółć", "_")
      )
    end)

    it("should not replace valid UTF-8 characters German chars", function()
      assert.is_equal(
        "glück schließen",
        util.fixUtf8("glück schließen", "_")
      )
    end)
  end)

  describe("splitToArray()", function()
    it("should split input to array", function()
      assert.are_same(
        { "100", "abc", "", "def", "ghi200" },
        util.splitToArray("100\tabc\t\tdef\tghi200\t", "\t", true)
      )
    end)

    it("should also split input to array", function()
      assert.are_same(
        { "", "bc", "bc", "bc", "bc" },
        util.splitToArray("abcabcabcabca", "a", true)
      )
    end)

    it("should split input to array without empty entities", function()
      assert.are_same(
        { "100", "abc", "def", "ghi200" },
        util.splitToArray("100  abc   def ghi200  ", " ", false)
      )
    end)
  end)

  describe("htmlToPlainTextIfHtml()", function()
    it("should guess it is not HTML and let is as is", function()
      local s = "if (i < 0 && j < 0) j = i&amp;"
      assert.is_equal(s, util.htmlToPlainTextIfHtml(s))
    end)
    it("should guess it is HTML and convert it to text", function()
      assert.is_equal(
        "Making unit tests is fun & nécéssaire",
        util.htmlToPlainTextIfHtml(
          "<div> <br> Making <b>unit&nbsp;tests</b> is <i class='notreally'>fun &amp; n&#xE9;c&#233;ssaire</i><br/> </div>"
        )
      )
    end)
    it(
      "should guess it is double encoded HTML and convert it to text",
      function()
        assert.is_equal(
          "Deux parties.\nPrologue.Désespérée, elle le tue...\nPremière partie. Sur la route & dans la nuit",
          util.htmlToPlainTextIfHtml(
            "Deux parties.&lt;br&gt;Prologue.Désespérée, elle le tue...&lt;br&gt;Première partie. Sur la route &amp;amp; dans la nuit"
          )
        )
      end
    )
  end)

  describe("isEmptyDir()", function()
    it("should return true on empty dir", function()
      assert.is_true(util.isEmptyDir(DataStorage:getDataDir() .. "/history")) -- should be empty during unit tests
    end)
    it("should return false on non-empty dir", function()
      assert.is_false(util.isEmptyDir(DataStorage:getDataDir())) -- should contain subdirectories
    end)
    it("should return nil on non-existent dir", function()
      assert.is_nil(
        util.isEmptyDir(
          "/this/is/just/some/nonsense/really/this/should/not/exist"
        )
      )
    end)
  end)

  describe("getFriendlySize()", function()
    describe("should convert bytes to friendly size as string", function()
      it("to 100.0 GB", function()
        assert.is_equal(
          "100.0 GB",
          util.getFriendlySize(100 * 1000 * 1000 * 1000)
        )
      end)
      it("to 1.0 GB", function()
        assert.is_equal("1.0 GB", util.getFriendlySize(1000 * 1000 * 1000 + 1))
      end)
      it("to 1.0 MB", function()
        assert.is_equal("1.0 MB", util.getFriendlySize(1000 * 1000 + 1))
      end)
      it("to 1.0 kB", function()
        assert.is_equal("1.0 kB", util.getFriendlySize(1000 + 1))
      end)
      it("to B", function()
        assert.is_equal("10 B", util.getFriendlySize(10))
      end)
      it("to 100.0 GB with minimum field width alignment", function()
        assert.is_equal(
          " 100.0 GB",
          util.getFriendlySize(100 * 1000 * 1000 * 1000, true)
        )
      end)
      it("to 1.0 GB with minimum field width alignment", function()
        assert.is_equal(
          "   1.0 GB",
          util.getFriendlySize(1000 * 1000 * 1000 + 1, true)
        )
      end)
      it("to 1.0 MB with minimum field width alignment", function()
        assert.is_equal(
          "   1.0 MB",
          util.getFriendlySize(1000 * 1000 + 1, true)
        )
      end)
      it("to 1.0 kB with minimum field width alignment", function()
        assert.is_equal("   1.0 kB", util.getFriendlySize(1000 + 1, true))
      end)
      it("to B with minimum field width alignment", function()
        assert.is_equal("    10 B", util.getFriendlySize(10, true))
      end)
    end)
    it("should return nil when input is nil or false", function()
      assert.is_nil(util.getFriendlySize(nil))
      assert.is_nil(util.getFriendlySize(false))
    end)
    it("should return nil when input is not a number", function()
      assert.is_nil(util.getFriendlySize("a string"))
    end)
  end)

  describe("urlEncode() and urlDecode", function()
    it("should encode string", function()
      assert.is_equal(
        "Secret_Password123",
        util.urlEncode("Secret_Password123")
      )
      assert.is_equal(
        "Secret%20Password123",
        util.urlEncode("Secret Password123")
      )
      assert.is_equal(
        "S*cret%3DP%40%24%24word*!%23%3F",
        util.urlEncode("S*cret=P@$$word*!#?")
      )
      assert.is_equal(
        "~%5E-_%5C%25!*'()%3B%3A%40%26%3D%2B%24%2C%2F%3F%23%5B%5D",
        util.urlEncode("~^-_\\%!*'();:@&=+$,/?#[]")
      )
    end)
    it("should decode string", function()
      assert.is_equal(
        "Secret_Password123",
        util.urlDecode("Secret_Password123")
      )
      assert.is_equal(
        "Secret Password123",
        util.urlDecode("Secret%20Password123")
      )
      assert.is_equal(
        "S*cret=P@$$word*!#?",
        util.urlDecode("S*cret%3DP%40%24%24word*!%23%3F")
      )
      assert.is_equal(
        "~^-_\\%!*'();:@&=+$,/?#[]",
        util.urlDecode(
          "~%5E-_%5C%25!*'()%3B%3A%40%26%3D%2B%24%2C%2F%3F%23%5B%5D"
        )
      )
    end)
    it("should encode and back decode string", function()
      assert.is_equal(
        "Secret_Password123",
        util.urlDecode(util.urlEncode("Secret_Password123"))
      )
      assert.is_equal(
        "Secret Password123",
        util.urlDecode(util.urlEncode("Secret Password123"))
      )
      assert.is_equal(
        "S*cret=P@$$word*!#?",
        util.urlDecode(util.urlEncode("S*cret=P@$$word*!#?"))
      )
      assert.is_equal(
        "~^-_%!*'();:@&=+$,/?#[]",
        util.urlDecode(util.urlEncode("~^-_%!*'();:@&=+$,/?#[]"))
      )
    end)
  end)

  describe("arrayIsEmpty()", function()
    it("should return true when input is nil", function()
      assert.is_true(util.arrayIsEmpty(nil))
    end)
    it("should return true when array is empty", function()
      assert.is_true(util.arrayIsEmpty({}))
    end)
    it("should return false when array has elements", function()
      assert.is_false(util.arrayIsEmpty({ 1, 2, 3 }))
    end)
  end)

  describe("utf8Reverse()", function()
    it("should reverse ASCII and UTF-8 strings correctly", function()
      assert.is_equal("olleh", util.utf8Reverse("hello"))
      assert.is_equal("界世好你", util.utf8Reverse("你好世界"))
    end)
  end)

  describe("arrayReverse()", function()
    it("should reverse array in-place", function()
      local arr = { 1, 2, 3, 4, 5 }
      util.arrayReverse(arr)
      assert.are_same({ 5, 4, 3, 2, 1 }, arr)
    end)
  end)

  describe("arrayDfSearch()", function()
    it("should find nested elements using depth-first search", function()
      local nested = { { "target" } }
      local found, depth = util.arrayDfSearch(nested, "target")
      assert.is_true(found)
      assert.is_equal(3, depth)

      local not_found = util.arrayDfSearch(nested, "missing")
      assert.is_false(not_found)
    end)
  end)

  describe("ltrim() and rtrim()", function()
    it("should trim whitespace from ends", function()
      assert.is_equal("hello", util.ltrim("   hello"))
      assert.is_equal("hello", util.rtrim("hello   "))
    end)
  end)

  describe("getFormattedSize()", function()
    it("should format bytes into human readable string", function()
      assert.is_equal("500", util.getFormattedSize(500))
      assert.is_equal("1,024", util.getFormattedSize(1024))
      assert.is_equal("1,048,576", util.getFormattedSize(1024 * 1024))
    end)
  end)

  describe("functionFingerprint()", function()
    it("should raise error for non-functions", function()
      assert.has_error(function()
        util.functionFingerprint("hello")
      end)
      assert.has_error(function()
        util.functionFingerprint(123)
      end)
      assert.has_error(function()
        util.functionFingerprint(nil)
      end)
    end)

    it(
      "should distinguish functions with different bytecode implementations",
      function()
        local f1 = function()
          return 1
        end
        local f2 = function()
          return 2
        end
        assert.is_not_equal(
          util.functionFingerprint(f1),
          util.functionFingerprint(f2)
        )
      end
    )

    it(
      "should generate identical fingerprints for closures capturing identical upvalues",
      function()
        local function makeClosure(x, y)
          return function()
            return x + y
          end
        end
        local c1 = makeClosure(10, 20)
        local c2 = makeClosure(10, 20)
        assert.is_equal(
          util.functionFingerprint(c1),
          util.functionFingerprint(c2)
        )
      end
    )

    it("should distinguish closures capturing different upvalues", function()
      local function makeClosure(doc)
        return function()
          return doc
        end
      end
      local c1 = makeClosure("book1.epub")
      local c2 = makeClosure("book2.epub")
      assert.is_not_equal(
        util.functionFingerprint(c1),
        util.functionFingerprint(c2)
      )
    end)

    it("should handle closures capturing tables with name property", function()
      local obj1 = { name = "PluginA", id = 1 }
      local obj2 = { name = "PluginB", id = 2 }

      local function makeAction(target)
        return function()
          return target.name
        end
      end

      local a1 = makeAction(obj1)
      local a2 = makeAction(obj2)
      assert.is_not_equal(
        util.functionFingerprint(a1),
        util.functionFingerprint(a2)
      )
    end)

    it("should handle nested closures recursively", function()
      local function makeCurried(a)
        return function(b)
          return function()
            return a + b
          end
        end
      end

      local nested1 = makeCurried(1)(2)
      local nested2 = makeCurried(1)(2)
      local nested3 = makeCurried(1)(3)

      assert.is_equal(
        util.functionFingerprint(nested1),
        util.functionFingerprint(nested2)
      )
      assert.is_not_equal(
        util.functionFingerprint(nested1),
        util.functionFingerprint(nested3)
      )
    end)
  end)

  describe("isDirRW()", function()
    it("returns false on nil or empty path", function()
      assert.is_false(util.isDirRW(nil))
      assert.is_false(util.isDirRW(""))
    end)

    it("returns false for non-existent path without create", function()
      assert.is_false(util.isDirRW("/nonexistent_dir_rw_xyz_123"))
    end)

    it("returns true for existing writable directory like /tmp", function()
      assert.is_true(util.isDirRW("/tmp"))
    end)

    it("creates and verifies new directory when create is true", function()
      local test_dir = "/tmp/koreader_test_isdirrw_" .. tostring(os.time())
      assert.is_true(util.isDirRW(test_dir, true))
      os.remove(test_dir)
    end)
  end)
end)
