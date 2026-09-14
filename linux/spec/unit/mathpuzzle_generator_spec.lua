describe("MathPuzzle Generator module", function()
  local Generator

  setup(function()
    require("commonrequire")
    Generator = require("plugins/mathpuzzle.koplugin/mathpuzzle_generator")
  end)

  it("should list available modes", function()
    local modes = Generator.getModes()
    assert.is_table(modes)
    assert.is_true(#modes >= 4)
    local mode_100 = Generator.getModeById("add_sub_100")
    assert.is_table(mode_100)
    assert.are.equal("add_sub_100", mode_100.id)
    assert.are.equal(100, mode_100.max)
  end)

  it(
    "should generate 10 valid problems for addition and subtraction within 10",
    function()
      local problems = Generator.generateProblems("add_sub_10", 10)
      assert.are.equal(10, #problems)
      for _, prob in ipairs(problems) do
        assert.is_number(prob.a)
        assert.is_number(prob.b)
        assert.is_number(prob.answer)
        assert.is_string(prob.text)
        assert.is_true(prob.answer >= 0)
        assert.is_true(prob.answer <= 10)
        if prob.op == "+" then
          assert.are.equal(prob.a + prob.b, prob.answer)
        elseif prob.op == "-" then
          assert.are.equal(prob.a - prob.b, prob.answer)
          assert.is_true(prob.a >= prob.b)
        end
      end
    end
  )

  it(
    "should generate valid problems for addition and subtraction within 100, 1000, 10000",
    function()
      for _, mode_id in ipairs({
        "add_sub_100",
        "add_sub_1000",
        "add_sub_10000",
      }) do
        local mode = Generator.getModeById(mode_id)
        local problems = Generator.generateProblems(mode_id, 10)
        assert.are.equal(10, #problems)
        for _, prob in ipairs(problems) do
          assert.is_true(prob.answer >= 0)
          assert.is_true(prob.answer <= mode.max)
          if prob.op == "+" then
            assert.are.equal(prob.a + prob.b, prob.answer)
          elseif prob.op == "-" then
            assert.are.equal(prob.a - prob.b, prob.answer)
          end
        end
      end
    end
  )

  it("should generate valid multiplication and division problems", function()
    local mul_problems = Generator.generateProblems("mul_100", 10)
    assert.are.equal(10, #mul_problems)
    for _, prob in ipairs(mul_problems) do
      assert.are.equal("×", prob.op)
      assert.are.equal(prob.a * prob.b, prob.answer)
      assert.is_true(prob.answer <= 100)
    end

    local div_problems = Generator.generateProblems("div_100", 10)
    assert.are.equal(10, #div_problems)
    for _, prob in ipairs(div_problems) do
      assert.are.equal("÷", prob.op)
      assert.are.equal(prob.a / prob.b, prob.answer)
      assert.are.equal(0, prob.a % prob.b)
    end
  end)

  it(
    "should generate valid problems for advanced multiplication and division",
    function()
      local adv_problems = Generator.generateProblems("mul_div_advanced", 10)
      assert.are.equal(10, #adv_problems)
      for _, prob in ipairs(adv_problems) do
        assert.is_number(prob.answer)
        assert.is_string(prob.text)
        assert.is_true(prob.answer > 0)
      end
    end
  )

  it("should generate valid problems for mixed operations", function()
    local mixed_problems = Generator.generateProblems("mixed_100", 10)
    assert.are.equal(10, #mixed_problems)
    for _, prob in ipairs(mixed_problems) do
      assert.is_number(prob.answer)
      assert.is_string(prob.text)
    end
  end)

  it("should generate valid problems for squares", function()
    local squares_problems = Generator.generateProblems("squares_400", 10)
    assert.are.equal(10, #squares_problems)
    for _, prob in ipairs(squares_problems) do
      assert.is_number(prob.answer)
      assert.is_true(prob.answer >= 4 and prob.answer <= 400)
    end
  end)

  it("should generate valid missing operand problems", function()
    local missing_problems = Generator.generateProblems("missing_100", 10)
    assert.are.equal(10, #missing_problems)
    for _, prob in ipairs(missing_problems) do
      assert.is_number(prob.answer)
      assert.is_true(prob.text:find("___") ~= nil)
    end
  end)

  it("should generate valid 3-term mental math problems", function()
    local three_mode = Generator.getModeById("three_term_100")
    assert.are.equal(5, three_mode.question_count)
    local three_problems =
      Generator.generateProblems(three_mode, three_mode.question_count)
    assert.are.equal(5, #three_problems)
    for _, prob in ipairs(three_problems) do
      assert.is_number(prob.answer)
      assert.is_true(prob.answer >= 0)
    end
  end)

  it("should calculate score when all problems are unanswered", function()
    local problems = Generator.generateProblems("add_sub_100", 10)
    for _, prob in ipairs(problems) do
      prob.user_answer = ""
    end
    local result = Generator.checkAnswers(problems)
    assert.are.equal(10, result.total)
    assert.are.equal(0, result.correct_count)
    assert.are.equal(0, result.answered_count)
    assert.is_false(result.all_correct)
  end)

  it("should verify when all problems are answered correctly", function()
    local problems = Generator.generateProblems("add_sub_100", 10)
    for _, prob in ipairs(problems) do
      prob.user_answer = tostring(prob.answer)
    end
    local result_all = Generator.checkAnswers(problems)
    assert.are.equal(10, result_all.correct_count)
    assert.are.equal(10, result_all.answered_count)
    assert.is_true(result_all.all_correct)
    for _, prob in ipairs(problems) do
      assert.is_true(prob.is_correct)
    end
  end)

  it("should handle incorrect answers and whitespace trimming in checkAnswers", function()
    local problems = Generator.generateProblems("add_sub_100", 10)
    for _, prob in ipairs(problems) do
      prob.user_answer = tostring(prob.answer)
    end
    problems[1].user_answer = "  " .. tostring(problems[1].answer) .. "  "
    problems[2].user_answer = tostring(problems[2].answer + 1)
    problems[3].user_answer = ""
    local result_mixed = Generator.checkAnswers(problems)
    assert.is_true(problems[1].is_correct)
    assert.is_false(problems[2].is_correct)
    assert.is_false(problems[3].is_correct)
    assert.are.equal(8, result_mixed.correct_count)
  end)

  it("should fallback to default mode when mode ID is unknown", function()
    local fallback_mode = Generator.getModeById("non_existent_mode_xyz")
    assert.is_table(fallback_mode)
    assert.are.equal("add_sub_100", fallback_mode.id)
  end)

  it("should generate valid problems for all registered modes", function()
    for _, mode in ipairs(Generator.getModes()) do
      local count = mode.question_count or 10
      local problems = Generator.generateProblems(mode.id, count)
      assert.are.equal(count, #problems)
      for i, prob in ipairs(problems) do
        assert.are.equal(i, prob.id)
        assert.is_number(prob.answer)
        assert.is_string(prob.text)
        assert.is_false(prob.checked)
        assert.is_nil(prob.is_correct)
        assert.are.equal("", prob.user_answer)
      end
    end
  end)

  it("should generate valid problems for mixed_1000 mode", function()
    local mixed_1000 = Generator.generateProblems("mixed_1000", 20)
    assert.are.equal(20, #mixed_1000)
    for _, prob in ipairs(mixed_1000) do
      assert.is_number(prob.answer)
      assert.is_string(prob.text)
    end
  end)

  it("should handle non-numeric or invalid input gracefully in checkAnswers", function()
    local problems = Generator.generateProblems("add_sub_100", 4)
    problems[1].user_answer = "abc"
    problems[2].user_answer = nil
    problems[3].user_answer = "12/34"
    problems[4].user_answer = tostring(problems[4].answer)

    local res = Generator.checkAnswers(problems)
    assert.are.equal(4, res.total)
    assert.are.equal(1, res.correct_count)
    assert.are.equal(3, res.answered_count)
    assert.is_false(res.all_correct)
    assert.is_false(problems[1].is_correct)
    assert.is_false(problems[2].is_correct)
    assert.is_false(problems[3].is_correct)
    assert.is_true(problems[4].is_correct)
  end)
end)
