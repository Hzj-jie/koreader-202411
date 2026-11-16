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

  local function assertValidMissingEquation(prob)
    local eq = (prob.text:gsub("___", tostring(prob.answer)))
    local lhs, op, rhs, expected =
      eq:match("^(%d+)%s+(%S+)%s+(%d+)%s*=%s*(%d+)$")
    local a, b, c = tonumber(lhs), tonumber(rhs), tonumber(expected)
    assert.is_number(a)
    assert.is_number(b)
    assert.is_number(c)
    if op == "+" then
      assert.are.equal(a + b, c)
    elseif op == "-" then
      assert.are.equal(a - b, c)
    elseif op == "×" then
      assert.are.equal(a * b, c)
    elseif op == "÷" then
      assert.is_true(b > 0 and a % b == 0)
      assert.are.equal(a / b, c)
    else
      error("Unexpected operator: " .. tostring(op))
    end
  end

  it("should generate valid missing operand problems", function()
    local missing_problems = Generator.generateProblems("missing_100", 20)
    assert.are.equal(20, #missing_problems)
    for _, prob in ipairs(missing_problems) do
      assert.is_number(prob.answer)
      assert.is_true(prob.text:find("___") ~= nil)
      assertValidMissingEquation(prob)
    end
  end)

  it(
    "should generate valid missing operand problems for addition and subtraction only",
    function()
      local problems = Generator.generateProblems("missing_100_add_sub", 30)
      assert.are.equal(30, #problems)
      for _, prob in ipairs(problems) do
        assert.is_number(prob.answer)
        assert.is_true(prob.text:find("___") ~= nil)
        assert.is_true(prob.op == "+" or prob.op == "-")
        assert.is_nil(prob.text:find("×"))
        assert.is_nil(prob.text:find("÷"))
        assert.is_true(prob.answer >= 0 and prob.answer <= 100)
        assertValidMissingEquation(prob)
      end
    end
  )

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
        if prob.terms[2] > prob.terms[1] then
          saw_entry_addition = true
          for i = 1, #prob.terms - 1 do
            assert.are.equal(prob.step, prob.terms[i + 1] - prob.terms[i])
          end
        elseif prob.terms[2] < prob.terms[1] then
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

        assert.is_nil(prob.op)
        assert.is_nil(prob.answer)
        assert.is_nil(prob.user_answer)
        if prob.terms[2] > prob.terms[1] then
          saw_addition = true
          for i = 1, #prob.terms - 1 do
            assert.are.equal(prob.step, prob.terms[i + 1] - prob.terms[i])
          end
        elseif prob.terms[2] < prob.terms[1] then
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
      assert.is_nil(check_res.answered_count)
      assert.is_nil(check_res.all_correct)

      -- Verify checkAnswers with one wrong blank
      test_problems[1].user_answers[test_problems[1].blank_indices[1]] = "999"
      local check_res2 = Generator.checkAnswers(test_problems)
      assert.are.equal(4, check_res2.correct_count)
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
  end)

  it("should verify when all problems are answered correctly", function()
    local problems = Generator.generateProblems("add_sub_100", 10)
    for _, prob in ipairs(problems) do
      prob.user_answer = tostring(prob.answer)
    end
    local result_all = Generator.checkAnswers(problems)
    assert.are.equal(10, result_all.correct_count)
    for _, prob in ipairs(problems) do
      assert.is_true(prob.is_correct)
    end
  end)

  it(
    "should handle incorrect answers and whitespace trimming in checkAnswers",
    function()
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
    end
  )

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
        if prob.inline_blanks then
          assert.is_nil(prob.answer)
          assert.is_nil(prob.user_answer)
          assert.is_nil(prob.op)
          for _, b_idx in ipairs(prob.blank_indices) do
            assert.is_number(prob.answers[b_idx])
            assert.are.equal("", prob.user_answers[b_idx])
          end
        else
          assert.is_number(prob.answer)
          assert.are.equal("", prob.user_answer)
        end
        if mode.type ~= "math_snake" and mode.type ~= "math_equato" then
          assert.is_string(prob.text)
        end
        assert.is_false(prob.checked)
        assert.is_nil(prob.is_correct)
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

  it(
    "should handle non-numeric or invalid input gracefully in checkAnswers",
    function()
      local problems = Generator.generateProblems("add_sub_100", 4)
      problems[1].user_answer = "abc"
      problems[2].user_answer = nil
      problems[3].user_answer = "12/34"
      problems[4].user_answer = tostring(problems[4].answer)

      local res = Generator.checkAnswers(problems)
      assert.are.equal(4, res.total)
      assert.are.equal(1, res.correct_count)
      assert.is_false(problems[1].is_correct)
      assert.is_false(problems[2].is_correct)
      assert.is_false(problems[3].is_correct)
      assert.is_true(problems[4].is_correct)
    end
  )

  it("should expose math_snake_100 mode configuration", function()
    local snake_mode = Generator.getModeById("math_snake_100")
    assert.is_table(snake_mode)
    assert.are.equal("math_snake_100", snake_mode.id)
    assert.are.equal("math_snake", snake_mode.type)
    assert.are.equal(100, snake_mode.max)
    assert.are.equal(11, snake_mode.question_count)
  end)

  it("should generate valid connected math snake chains within 100", function()
    local saw_free_addition = false
    local saw_free_subtraction = false

    for _ = 1, 200 do
      local probs = Generator.generateProblems("math_snake_100")
      assert.are.equal(11, #probs)
      assert.is_true(probs[1].a >= 15 and probs[1].a <= 85)

      for i, prob in ipairs(probs) do
        assert.are.equal(i, prob.id)
        assert.is_nil(prob.text)
        assert.is_nil(prob.snake_start)
        assert.is_true(prob.op == "+" or prob.op == "-")
        assert.is_true(prob.a >= 0 and prob.a <= 100)
        assert.is_true(prob.answer >= 0 and prob.answer <= 100)
        assert.is_true(prob.b >= 2 and prob.b <= 35)
        assert.are.equal("", prob.user_answer)
        assert.is_false(prob.checked)
        assert.is_nil(prob.is_correct)

        if i > 1 then
          assert.are.equal(probs[i - 1].answer, prob.a)
          if prob.op ~= probs[i - 1].op then
            assert.are_not.equal(probs[i - 1].b, prob.b)
          end
        end

        if prob.op == "+" then
          if prob.a >= 5 then
            saw_free_addition = true
          end
          assert.are.equal(prob.a + prob.b, prob.answer)
          assert.is_true(100 - prob.a >= 5)
        else
          if 100 - prob.a >= 5 then
            saw_free_subtraction = true
          end
          assert.are.equal(prob.a - prob.b, prob.answer)
          assert.is_true(prob.a >= 5)
        end
      end
    end

    assert.is_true(saw_free_addition)
    assert.is_true(saw_free_subtraction)
  end)

  it(
    "should terminate and enforce boundary constraints under constant min/max random stubs",
    function()
      local active_stub
      finally(function()
        if active_stub then
          active_stub:revert()
        end
      end)

      local function verifySnakeInvariants(probs, expected_count)
        assert.are.equal(expected_count, #probs)
        assert.is_true(probs[1].a >= 15 and probs[1].a <= 85)
        local hit_boundary_force = false
        for i, prob in ipairs(probs) do
          assert.is_true(prob.op == "+" or prob.op == "-")
          assert.is_true(prob.a >= 0 and prob.a <= 100)
          assert.is_true(prob.answer >= 0 and prob.answer <= 100)
          assert.is_true(prob.b >= 2 and prob.b <= 35)
          if i > 1 then
            assert.are.equal(probs[i - 1].answer, prob.a)
            if prob.op ~= probs[i - 1].op then
              assert.are_not.equal(probs[i - 1].b, prob.b)
            end
          end
          if prob.op == "+" then
            assert.are.equal(prob.a + prob.b, prob.answer)
            assert.is_true(100 - prob.a >= 5)
            if prob.a < 5 then
              hit_boundary_force = true
            end
          else
            assert.are.equal(prob.a - prob.b, prob.answer)
            assert.is_true(prob.a >= 5)
            if 100 - prob.a < 5 then
              hit_boundary_force = true
            end
          end
        end
        return hit_boundary_force
      end

      -- Lower-bound stub forces headroom wall near 100 and anti-cancel shift on reversal
      active_stub = stub(math, "random", function(lo)
        if lo then
          return lo
        end
        return 0
      end)
      local min_hit = verifySnakeInvariants(
        Generator.generateProblems("math_snake_100", 50),
        50
      )
      assert.is_true(min_hit)
      active_stub:revert()
      active_stub = nil

      -- Upper-bound stub drives chain down to 0 and forces addition back up
      active_stub = stub(math, "random", function(lo, hi)
        if hi then
          return hi
        elseif lo then
          return lo
        end
        return 1
      end)
      local max_hit = verifySnakeInvariants(
        Generator.generateProblems("math_snake_100", 15),
        15
      )
      assert.is_true(max_hit)
      active_stub:revert()
      active_stub = nil
    end
  )

  it("should grade math_snake_100 steps strictly in checkAnswers", function()
    local probs = Generator.generateProblems("math_snake_100")
    local empty_res = Generator.checkAnswers(probs)
    assert.are.equal(11, empty_res.total)
    assert.are.equal(0, empty_res.correct_count)

    for _, prob in ipairs(probs) do
      prob.user_answer = tostring(prob.answer)
    end
    local full_res = Generator.checkAnswers(probs)
    assert.are.equal(11, full_res.total)
    assert.are.equal(11, full_res.correct_count)

    probs[4].user_answer = tostring(probs[4].answer + 1)
    local partial_res = Generator.checkAnswers(probs)
    assert.are.equal(11, partial_res.total)
    assert.are.equal(10, partial_res.correct_count)
    assert.is_false(probs[4].is_correct)
    assert.is_true(probs[3].is_correct)
    assert.is_true(probs[5].is_correct)
  end)

  describe("math_equato_100", function()
    local function evalEquatoLine(a, s1, s2, b, c)
      if s1 == "+" and s2 == "=" then
        return a + b == c, "+", 2
      elseif s1 == "−" and s2 == "=" then
        return a - b == c, "−", 2
      elseif s1 == "=" and s2 == "+" then
        return a == b + c, "+", 1
      elseif s1 == "=" and s2 == "−" then
        return a == b - c, "−", 1
      end
      return false, nil, nil
    end

    local function verifyEquatoPuzzle(probs)
      assert.are.equal(5, #probs)
      assert.is_nil(probs.bank)
      assert.is_table(probs.grid)
      assert.is_table(probs.row_ops)
      assert.is_table(probs.col_ops)
      assert.are.equal(3, #probs.grid)
      assert.are.equal(3, #probs.row_ops)
      assert.are.equal(3, #probs.col_ops)

      local vals = { {}, {}, {} }
      local given_count = 0
      local row_blanks = { 0, 0, 0 }
      local col_blanks = { 0, 0, 0 }
      for r = 1, 3 do
        assert.are.equal(3, #probs.grid[r])
        for c = 1, 3 do
          local v = probs.grid[r][c]
          if v ~= false then
            assert.is_number(v)
            assert.are.equal(math.floor(v), v)
            assert.is_true(v >= 1 and v <= 100)
            vals[r][c] = v
            given_count = given_count + 1
          else
            row_blanks[r] = row_blanks[r] + 1
            col_blanks[c] = col_blanks[c] + 1
          end
        end
      end
      assert.are.equal(4, given_count)
      for k = 1, 3 do
        assert.is_true(row_blanks[k] >= 1 and row_blanks[k] <= 2)
        assert.is_true(col_blanks[k] >= 1 and col_blanks[k] <= 2)
      end

      local prev_key = 0
      local seen_vals = {}
      for i, prob in ipairs(probs) do
        assert.are.equal(i, prob.id)
        assert.is_nil(prob.text)
        assert.is_number(prob.row)
        assert.is_number(prob.col)
        assert.is_true(prob.row >= 1 and prob.row <= 3)
        assert.is_true(prob.col >= 1 and prob.col <= 3)
        assert.is_false(probs.grid[prob.row][prob.col])
        local key = prob.row * 10 + prob.col
        assert.is_true(key > prev_key)
        prev_key = key

        assert.is_number(prob.answer)
        assert.are.equal(math.floor(prob.answer), prob.answer)
        assert.is_true(prob.answer >= 1 and prob.answer <= 100)
        assert.are.equal("", prob.user_answer)
        assert.is_false(prob.checked)
        assert.is_nil(prob.is_correct)
        vals[prob.row][prob.col] = prob.answer
      end

      for r = 1, 3 do
        for c = 1, 3 do
          local v = vals[r][c]
          assert.is_number(v)
          assert.is_nil(seen_vals[v])
          seen_vals[v] = true
        end
      end

      local plus_count = 0
      local minus_count = 0
      local eq_pos = {}
      local forms = {}

      for r = 1, 3 do
        local s1, s2 = probs.row_ops[r][1], probs.row_ops[r][2]
        assert.are_not.equal("-", s1)
        assert.are_not.equal("-", s2)
        local ok, op, eq_slot =
          evalEquatoLine(vals[r][1], s1, s2, vals[r][2], vals[r][3])
        assert.is_true(ok)
        if op == "+" then
          plus_count = plus_count + 1
        else
          minus_count = minus_count + 1
        end
        eq_pos[eq_slot] = true
        forms[s1 .. s2] = true
      end

      for c = 1, 3 do
        local s1, s2 = probs.col_ops[c][1], probs.col_ops[c][2]
        assert.are_not.equal("-", s1)
        assert.are_not.equal("-", s2)
        local ok, op, eq_slot =
          evalEquatoLine(vals[1][c], s1, s2, vals[2][c], vals[3][c])
        assert.is_true(ok)
        if op == "+" then
          plus_count = plus_count + 1
        else
          minus_count = minus_count + 1
        end
        eq_pos[eq_slot] = true
        forms[s1 .. s2] = true
      end

      assert.is_true(plus_count >= 1)
      assert.is_true(minus_count >= 1)
      return eq_pos, forms
    end

    it(
      "should expose math_equato_100 at the end of registered modes",
      function()
        local modes = Generator.getModes()
        local eq_mode = Generator.getModeById("math_equato_100")
        assert.is_table(eq_mode)
        assert.are.equal("math_equato_100", modes[#modes].id)
        assert.are.equal("math_equato", eq_mode.type)
        assert.are.equal(100, eq_mode.max)
        assert.are.equal(5, eq_mode.question_count)
        assert.is_string(eq_mode.title)
        assert.is_string(eq_mode.description)
      end
    )

    it(
      "should assert when math_equato_100 is requested with count ~= 5",
      function()
        assert.has_error(function()
          Generator.generateProblems("math_equato_100", 3)
        end)
      end
    )

    it(
      "should generate valid 3x3 equato grids with distinct values, mixed ops, and movable equals",
      function()
        local seen_eq_1 = false
        local seen_eq_2 = false
        local seen_forms = {}
        for _ = 1, 200 do
          local probs = Generator.generateProblems("math_equato_100")
          local eq_pos, forms = verifyEquatoPuzzle(probs)
          if eq_pos[1] then
            seen_eq_1 = true
          end
          if eq_pos[2] then
            seen_eq_2 = true
          end
          for f in pairs(forms) do
            seen_forms[f] = true
          end
        end
        assert.is_true(seen_eq_1)
        assert.is_true(seen_eq_2)
        assert.is_true(seen_forms["+="])
        assert.is_true(seen_forms["−="])
        assert.is_true(seen_forms["=+"])
        assert.is_true(seen_forms["=−"])
      end
    )

    it(
      "should have a unique 5! bank permutation solution and be peel-solvable line by line",
      function()
        for _ = 1, 30 do
          local probs = Generator.generateProblems("math_equato_100")
          verifyEquatoPuzzle(probs)

          -- Brute-force all 5! = 120 assignments of the bank
          local bank = {}
          for i = 1, 5 do
            bank[i] = probs[i].answer
          end

          local candidate = { {}, {}, {} }
          for r = 1, 3 do
            for c = 1, 3 do
              candidate[r][c] = probs.grid[r][c]
            end
          end

          local function checkCandidate()
            for r = 1, 3 do
              if
                not evalEquatoLine(
                  candidate[r][1],
                  probs.row_ops[r][1],
                  probs.row_ops[r][2],
                  candidate[r][2],
                  candidate[r][3]
                )
              then
                return false
              end
            end
            for c = 1, 3 do
              if
                not evalEquatoLine(
                  candidate[1][c],
                  probs.col_ops[c][1],
                  probs.col_ops[c][2],
                  candidate[2][c],
                  candidate[3][c]
                )
              then
                return false
              end
            end
            return true
          end

          local valid_count = 0
          local used = {}
          local function permute(idx)
            if idx > 5 then
              if checkCandidate() then
                valid_count = valid_count + 1
              end
              return
            end
            local blank = probs[idx]
            for b = 1, 5 do
              if not used[b] then
                used[b] = true
                candidate[blank.row][blank.col] = bank[b]
                permute(idx + 1)
                used[b] = false
              end
            end
          end
          permute(1)
          assert.are.equal(1, valid_count)

          -- Line-by-line peel solver starting from only the 4 givens
          local solved = { {}, {}, {} }
          for r = 1, 3 do
            for c = 1, 3 do
              if probs.grid[r][c] ~= false then
                solved[r][c] = probs.grid[r][c]
              end
            end
          end

          local function solveOneMissing(a, b, c, s1, s2, unknown_idx)
            if s1 == "+" and s2 == "=" then
              if unknown_idx == 1 then
                return c - b
              elseif unknown_idx == 2 then
                return c - a
              else
                return a + b
              end
            elseif s1 == "−" and s2 == "=" then
              if unknown_idx == 1 then
                return b + c
              elseif unknown_idx == 2 then
                return a - c
              else
                return a - b
              end
            elseif s1 == "=" and s2 == "+" then
              if unknown_idx == 1 then
                return b + c
              elseif unknown_idx == 2 then
                return a - c
              else
                return a - b
              end
            elseif s1 == "=" and s2 == "−" then
              if unknown_idx == 1 then
                return b - c
              elseif unknown_idx == 2 then
                return a + c
              else
                return b - a
              end
            end
          end

          local solved_count = 0
          while solved_count < 5 do
            local progressed = false
            for r = 1, 3 do
              local missing_idx
              local missing_n = 0
              for c = 1, 3 do
                if not solved[r][c] then
                  missing_n = missing_n + 1
                  missing_idx = c
                end
              end
              if missing_n == 1 then
                solved[r][missing_idx] = solveOneMissing(
                  solved[r][1],
                  solved[r][2],
                  solved[r][3],
                  probs.row_ops[r][1],
                  probs.row_ops[r][2],
                  missing_idx
                )
                solved_count = solved_count + 1
                progressed = true
              end
            end
            for c = 1, 3 do
              local missing_idx
              local missing_n = 0
              for r = 1, 3 do
                if not solved[r][c] then
                  missing_n = missing_n + 1
                  missing_idx = r
                end
              end
              if missing_n == 1 then
                solved[missing_idx][c] = solveOneMissing(
                  solved[1][c],
                  solved[2][c],
                  solved[3][c],
                  probs.col_ops[c][1],
                  probs.col_ops[c][2],
                  missing_idx
                )
                solved_count = solved_count + 1
                progressed = true
              end
            end
            assert.is_true(progressed)
          end

          for _, prob in ipairs(probs) do
            assert.are.equal(prob.answer, solved[prob.row][prob.col])
          end
        end
      end
    )

    it(
      "should terminate and enforce invariants under constant min/max random stubs",
      function()
        local active_stub
        finally(function()
          if active_stub then
            active_stub:revert()
          end
        end)

        active_stub = stub(math, "random", function(lo)
          if lo then
            return lo
          end
          return 0
        end)
        verifyEquatoPuzzle(Generator.generateProblems("math_equato_100"))
        active_stub:revert()
        active_stub = nil

        active_stub = stub(math, "random", function(lo, hi)
          if hi then
            return hi
          elseif lo then
            return lo
          end
          return 1
        end)
        verifyEquatoPuzzle(Generator.generateProblems("math_equato_100"))
        active_stub:revert()
        active_stub = nil
      end
    )

    it("should grade math_equato_100 blanks in checkAnswers", function()
      local probs = Generator.generateProblems("math_equato_100")
      local empty_res = Generator.checkAnswers(probs)
      assert.are.equal(5, empty_res.total)
      assert.are.equal(0, empty_res.correct_count)

      for _, prob in ipairs(probs) do
        prob.user_answer = tostring(prob.answer)
      end
      local full_res = Generator.checkAnswers(probs)
      assert.are.equal(5, full_res.total)
      assert.are.equal(5, full_res.correct_count)

      probs[3].user_answer = tostring(probs[3].answer + 1)
      local partial_res = Generator.checkAnswers(probs)
      assert.are.equal(5, partial_res.total)
      assert.are.equal(4, partial_res.correct_count)
      assert.is_false(probs[3].is_correct)
      assert.is_true(probs[2].is_correct)
      assert.is_true(probs[4].is_correct)
    end)
  end)
end)
