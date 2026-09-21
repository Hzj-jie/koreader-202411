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

  it("should generate valid missing operand problems for addition and subtraction only", function()
    local problems = Generator.generateProblems("missing_100_add_sub", 30)
    assert.are.equal(30, #problems)
    for _, prob in ipairs(problems) do
      assert.is_number(prob.answer)
      assert.is_true(prob.text:find("___") ~= nil)
      assert.is_true(prob.op == "+" or prob.op == "-")
      assert.is_nil(prob.text:find("×"))
      assert.is_nil(prob.text:find("÷"))
      assert.is_true(prob.answer >= 0 and prob.answer <= 100)
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

  it(
    "should generate valid arithmetic progression problems with addition and subtraction across four levels",
    function()
      local ap_entry = Generator.getModeById("arithmetic_progression_30_entry")
      assert.is_table(ap_entry)
      assert.are.equal("arithmetic_progression_30_entry", ap_entry.id)
      assert.are.equal(30, ap_entry.max)
      assert.are.equal(3, ap_entry.max_step)
      assert.is_true(ap_entry.alternating_blanks)
      assert.are.equal(5, ap_entry.question_count)
      assert.is_true(ap_entry.single_column)

      local ap_easy = Generator.getModeById("arithmetic_progression_50_easy")
      assert.is_table(ap_easy)
      assert.are.equal("arithmetic_progression_50_easy", ap_easy.id)
      assert.are.equal(50, ap_easy.max)
      assert.are.equal(4, ap_easy.max_step)
      assert.is_true(ap_easy.alternating_blanks)
      assert.are.equal(5, ap_easy.question_count)
      assert.is_true(ap_easy.single_column)

      local ap50 = Generator.getModeById("arithmetic_progression_50")
      assert.is_table(ap50)
      assert.are.equal("arithmetic_progression_50", ap50.id)
      assert.are.equal(50, ap50.max)
      assert.are.equal(4, ap50.max_step)
      assert.are.equal(5, ap50.question_count)
      assert.is_true(ap50.single_column)

      local ap100 = Generator.getModeById("arithmetic_progression_100")
      assert.is_table(ap100)
      assert.are.equal("arithmetic_progression_100", ap100.id)
      assert.are.equal(100, ap100.max)
      assert.are.equal(10, ap100.max_step)
      assert.are.equal(5, ap100.question_count)
      assert.is_true(ap100.single_column)

      -- Alias check
      assert.are.equal(ap_entry, Generator.getModeById("arithmetic_progression_entry"))
      assert.are.equal(ap_entry, Generator.getModeById("ap_entry"))
      assert.are.equal(ap_entry, Generator.getModeById("ap_30_entry"))
      assert.are.equal(ap_entry, Generator.getModeById("ap_30"))
      assert.are.equal(ap_entry, Generator.getModeById("arithmetic_progression_30"))
      assert.are.equal(ap_entry, Generator.getModeById("arithmetic_progression_30_easy"))
      assert.are.equal(ap_entry, Generator.getModeById("arithmetic_progression_20"))
      assert.are.equal(ap_entry, Generator.getModeById("ap_20"))
      assert.are.equal(ap_entry, Generator.getModeById("arithmetic_progression_20_entry"))
      assert.are.equal(ap_easy, Generator.getModeById("arithmetic_progression_easy"))
      assert.are.equal(ap_easy, Generator.getModeById("ap_easy"))
      assert.are.equal(ap_easy, Generator.getModeById("ap_50_easy"))
      assert.are.equal(ap100, Generator.getModeById("arithmetic_progression"))
      assert.are.equal(ap100, Generator.getModeById("ap_100"))
      assert.are.equal(ap50, Generator.getModeById("ap_50"))

      -- Test Entry Level (max 30, step up to 3, 8 terms, alternating blanks strictly at {1,3,5,7} or {2,4,6,8})
      local problems_entry = Generator.generateProblems("arithmetic_progression_30_entry", 20)
      assert.are.equal(20, #problems_entry)
      local saw_entry_odd_blanks = false
      local saw_entry_even_blanks = false
      local saw_entry_addition = false
      local saw_entry_subtraction = false

      for _, prob in ipairs(problems_entry) do
        assert.is_true(prob.step >= 1 and prob.step <= 3)
        assert.are.equal(8, #prob.terms)
        for _, term in ipairs(prob.terms) do
          assert.is_true(term >= 0 and term <= 30)
        end
        assert.are.equal(4, #prob.blank_indices)
        local indices_str = table.concat(prob.blank_indices, ",")
        assert.is_true(indices_str == "1,3,5,7" or indices_str == "2,4,6,8")
        if indices_str == "1,3,5,7" then
          saw_entry_odd_blanks = true
        elseif indices_str == "2,4,6,8" then
          saw_entry_even_blanks = true
        end
        for _, b_idx in ipairs(prob.blank_indices) do
          assert.is_true(prob.answers[b_idx] >= 0 and prob.answers[b_idx] <= 30)
          assert.are.equal(prob.terms[b_idx], prob.answers[b_idx])
        end
        if prob.op == "+" then
          saw_entry_addition = true
          for i = 1, #prob.terms - 1 do
            assert.are.equal(prob.step, prob.terms[i + 1] - prob.terms[i])
          end
        elseif prob.op == "-" then
          saw_entry_subtraction = true
          for i = 1, #prob.terms - 1 do
            assert.are.equal(prob.step, prob.terms[i] - prob.terms[i + 1])
          end
        end
      end
      assert.is_true(saw_entry_odd_blanks)
      assert.is_true(saw_entry_even_blanks)
      assert.is_true(saw_entry_addition)
      assert.is_true(saw_entry_subtraction)

      -- Test Easy Level (alternating blanks strictly at {1,3,5,7} or {2,4,6,8})
      local problems_easy = Generator.generateProblems("arithmetic_progression_50_easy", 20)
      assert.are.equal(20, #problems_easy)
      local saw_odd_blanks = false
      local saw_even_blanks = false

      for _, prob in ipairs(problems_easy) do
        assert.is_true(prob.step >= 1 and prob.step <= 4)
        assert.are.equal(8, #prob.terms)
        for _, term in ipairs(prob.terms) do
          assert.is_true(term >= 0 and term <= 50)
        end
        assert.are.equal(4, #prob.blank_indices)
        local indices_str = table.concat(prob.blank_indices, ",")
        assert.is_true(indices_str == "1,3,5,7" or indices_str == "2,4,6,8")
        if indices_str == "1,3,5,7" then
          saw_odd_blanks = true
        elseif indices_str == "2,4,6,8" then
          saw_even_blanks = true
        end
        for _, b_idx in ipairs(prob.blank_indices) do
          assert.is_true(prob.answers[b_idx] >= 0 and prob.answers[b_idx] <= 50)
        end
      end
      assert.is_true(saw_odd_blanks)
      assert.is_true(saw_even_blanks)

      -- Test Level 1 (max 50, step up to 4, random blanks)
      local problems_50 = Generator.generateProblems("arithmetic_progression_50", 20)
      assert.are.equal(20, #problems_50)
      for _, prob in ipairs(problems_50) do
        assert.is_true(prob.step >= 1 and prob.step <= 4)
        assert.are.equal(8, #prob.terms)
        for _, term in ipairs(prob.terms) do
          assert.is_true(term >= 0 and term <= 50)
        end
        for _, b_idx in ipairs(prob.blank_indices) do
          assert.is_true(prob.answers[b_idx] >= 0 and prob.answers[b_idx] <= 50)
        end
      end

      -- Test Level 2 (max 100, step up to 10, random blanks)
      local problems_100 = Generator.generateProblems("arithmetic_progression_100", 20)
      assert.are.equal(20, #problems_100)

      local saw_addition = false
      local saw_subtraction = false
      local saw_4_blanks = false
      local saw_5_blanks = false

      for _, prob in ipairs(problems_100) do
        assert.is_string(prob.text)
        assert.is_true(prob.text:find("___") ~= nil)
        assert.is_number(prob.step)
        assert.is_true(prob.step >= 1 and prob.step <= 10)
        assert.is_table(prob.terms)
        assert.are.equal(8, #prob.terms)
        assert.is_true(prob.inline_blanks)
        assert.is_table(prob.blank_indices)
        local num_blanks = #prob.blank_indices
        assert.is_true(num_blanks == 4 or num_blanks == 5)
        if num_blanks == 4 then
          saw_4_blanks = true
        elseif num_blanks == 5 then
          saw_5_blanks = true
        end

        for _, b_idx in ipairs(prob.blank_indices) do
          assert.is_true(prob.blanks[b_idx])
          assert.are.equal(prob.terms[b_idx], prob.answers[b_idx])
          assert.is_true(prob.answers[b_idx] >= 0 and prob.answers[b_idx] <= 100)
        end

        if prob.op == "+" then
          saw_addition = true
          for i = 1, #prob.terms - 1 do
            assert.are.equal(prob.step, prob.terms[i + 1] - prob.terms[i])
          end
        elseif prob.op == "-" then
          saw_subtraction = true
          for i = 1, #prob.terms - 1 do
            assert.are.equal(prob.step, prob.terms[i] - prob.terms[i + 1])
          end
        end
      end

      assert.is_true(saw_addition)
      assert.is_true(saw_subtraction)
      assert.is_true(saw_4_blanks)
      assert.is_true(saw_5_blanks)

      -- Verify checkAnswers with correct answers
      local test_problems = Generator.generateProblems("arithmetic_progression_50", 5)
      for _, p in ipairs(test_problems) do
        for _, b_idx in ipairs(p.blank_indices) do
          p.user_answers[b_idx] = tostring(p.answers[b_idx])
        end
      end
      local check_res = Generator.checkAnswers(test_problems)
      assert.are.equal(5, check_res.total)
      assert.are.equal(5, check_res.correct_count)
      assert.are.equal(5, check_res.answered_count)
      assert.is_true(check_res.all_correct)

      -- Verify checkAnswers with one wrong blank
      test_problems[1].user_answers[test_problems[1].blank_indices[1]] = "999"
      local check_res2 = Generator.checkAnswers(test_problems)
      assert.are.equal(4, check_res2.correct_count)
      assert.is_false(check_res2.all_correct)
    end
  )

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
