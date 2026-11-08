local gettext = require("gettext")

local Generator = {}

Generator.MODES = {
  {
    id = "add_sub_10",
    title = gettext("Addition & Subtraction within 10"),
    description = gettext("Add and subtract numbers up to 10"),
    type = "add_sub",
    max = 10,
  },
  {
    id = "add_sub_100",
    title = gettext("Addition & Subtraction within 100"),
    description = gettext("Add and subtract numbers up to 100"),
    type = "add_sub",
    max = 100,
  },
  {
    id = "add_sub_1000",
    title = gettext("Addition & Subtraction within 1,000"),
    description = gettext("Add and subtract numbers up to 1,000"),
    type = "add_sub",
    max = 1000,
  },
  {
    id = "add_sub_10000",
    title = gettext("Addition & Subtraction within 10,000"),
    description = gettext("Add and subtract numbers up to 10,000"),
    type = "add_sub",
    max = 10000,
  },
  {
    id = "mul_100",
    title = gettext("Multiplication within 100"),
    description = gettext("Multiplication table up to 10 × 10"),
    type = "mul",
    max = 100,
  },
  {
    id = "div_100",
    title = gettext("Division within 100"),
    description = gettext("Division with whole number results up to 100"),
    type = "div",
    max = 100,
  },
  {
    id = "mul_div_advanced",
    title = gettext("2-Digit × 1-Digit & Division within 1,000"),
    description = gettext("Multiplication and division with 2-digit numbers"),
    type = "mul_div_advanced",
  },
  {
    id = "mixed_100",
    title = gettext("Mixed Operations within 100"),
    description = gettext("Random +, -, ×, ÷ operations within 100"),
    type = "mixed",
    max = 100,
  },
  {
    id = "mixed_1000",
    title = gettext("Mixed Operations within 1,000"),
    description = gettext("Random +, -, ×, ÷ operations within 1,000"),
    type = "mixed",
    max = 1000,
  },
  {
    id = "missing_100_add_sub",
    title = gettext("Fill-in-the-Blank (+, -) within 100"),
    description = gettext(
      "Find the missing number in addition and subtraction equations"
    ),
    type = "missing",
    max = 100,
    ops = "add_sub",
  },
  {
    id = "missing_100",
    title = gettext("Fill-in-the-Blank within 100"),
    description = gettext("Find the missing number in equations"),
    type = "missing",
    max = 100,
  },
  {
    id = "squares_400",
    title = gettext("Square Numbers within 400"),
    description = gettext("Squares of numbers up to 20²"),
    type = "squares",
    max = 400,
  },
  {
    id = "three_term_100",
    title = gettext("3-Term Mental Math"),
    description = gettext("Order of operations with 3 numbers"),
    type = "three_term",
    max = 100,
    question_count = 5,
  },
  {
    id = "arithmetic_progression_30_entry",
    title = gettext("Arithmetic Progression within 30 (Entry Level)"),
    description = gettext("Alternating blanks, step up to 3, numbers up to 30"),
    type = "arithmetic_progression",
    max = 30,
    max_step = 3,
    alternating_blanks = true,
    question_count = 5,
    single_column = true,
  },
  {
    id = "arithmetic_progression_50_easy",
    title = gettext("Arithmetic Progression within 50 (Easy)"),
    description = gettext("Alternating blanks, step up to 4, numbers up to 50"),
    type = "arithmetic_progression",
    max = 50,
    max_step = 4,
    alternating_blanks = true,
    question_count = 5,
    single_column = true,
  },
  {
    id = "arithmetic_progression_50",
    title = gettext("Arithmetic Progression within 50"),
    description = gettext("Step up to 4, numbers up to 50"),
    type = "arithmetic_progression",
    max = 50,
    max_step = 4,
    question_count = 5,
    single_column = true,
  },
  {
    id = "arithmetic_progression_100",
    title = gettext("Arithmetic Progression within 100"),
    description = gettext("Step up to 10, numbers up to 100"),
    type = "arithmetic_progression",
    max = 100,
    max_step = 10,
    question_count = 5,
    single_column = true,
  },
  {
    id = "math_snake_100",
    title = gettext("Math Snake (+, -) within 100"),
    description = gettext("Chain addition and subtraction steps within 100"),
    type = "math_snake",
    max = 100,
    question_count = 11,
  },
}

function Generator.getModes()
  return Generator.MODES
end

function Generator.getModeById(mode_id)
  for _, mode in ipairs(Generator.MODES) do
    if mode.id == mode_id then
      return mode
    end
  end
  return Generator.MODES[2] -- default to add_sub_100
end

local function makeBinaryProblem(op, a, b, answer)
  return {
    op = op,
    a = a,
    b = b,
    answer = answer,
    text = string.format("%d %s %d =", a, op, b),
  }
end

local function makeMissingProblem(op, a, b, c, ans_is_first)
  if ans_is_first then
    return {
      op = op,
      answer = a,
      text = string.format("___ %s %d = %d", op, b, c),
    }
  end
  return {
    op = op,
    answer = b,
    text = string.format("%d %s ___ = %d", a, op, c),
  }
end

local function generateSingleProblem(mode)
  local mode_type = mode.type
  local max_val = mode.max

  if mode_type == "add_sub" then
    local is_addition = math.random(1, 2) == 1
    if is_addition then
      -- a + b <= max_val
      local a, b
      if max_val <= 10 then
        a = math.random(1, 9)
        b = math.random(1, 10 - a)
      elseif max_val <= 100 then
        -- Generate meaningful numbers
        a = math.random(2, max_val - 2)
        b = math.random(1, max_val - a)
      else
        local min_a = math.floor(max_val * 0.05)
        a = math.random(min_a, max_val - min_a)
        b = math.random(min_a, max_val - a)
      end
      return makeBinaryProblem("+", a, b, a + b)
    else
      -- a - b >= 0, a <= max_val
      local a, b
      if max_val <= 10 then
        a = math.random(2, 10)
        b = math.random(1, a)
      elseif max_val <= 100 then
        a = math.random(10, max_val)
        b = math.random(1, a)
      else
        local min_a = math.floor(max_val * 0.1)
        a = math.random(min_a, max_val)
        b = math.random(1, a)
      end
      return makeBinaryProblem("-", a, b, a - b)
    end
  elseif mode_type == "mul" then
    local a = math.random(2, 9)
    local b = math.random(2, 9)
    return makeBinaryProblem("×", a, b, a * b)
  elseif mode_type == "div" then
    local b = math.random(2, 9)
    local c = math.random(1, 9)
    return makeBinaryProblem("÷", b * c, b, c)
  elseif mode_type == "mul_div_advanced" then
    local is_mul = math.random(1, 2) == 1
    if is_mul then
      local a = math.random(11, 99)
      local b = math.random(2, 9)
      return makeBinaryProblem("×", a, b, a * b)
    else
      local b = math.random(2, 9)
      local c = math.random(11, 99)
      return makeBinaryProblem("÷", b * c, b, c)
    end
  elseif mode_type == "mixed" then
    local roll = math.random(1, 4)
    if roll == 1 then
      -- Addition
      local a = math.random(10, max_val - 10)
      local b = math.random(5, max_val - a)
      return makeBinaryProblem("+", a, b, a + b)
    elseif roll == 2 then
      -- Subtraction
      local a = math.random(15, max_val)
      local b = math.random(5, a - 1)
      return makeBinaryProblem("-", a, b, a - b)
    elseif roll == 3 then
      -- Multiplication
      local a = max_val <= 100 and math.random(2, 9) or math.random(11, 99)
      local b = math.random(2, 9)
      return makeBinaryProblem("×", a, b, a * b)
    else
      -- Division
      local b = math.random(2, 9)
      local c = max_val <= 100 and math.random(2, 9) or math.random(11, 99)
      return makeBinaryProblem("÷", b * c, b, c)
    end
  elseif mode_type == "missing" then
    local op_roll = mode.ops == "add_sub" and math.random(1, 2)
      or math.random(1, 4)
    if op_roll == 1 then
      -- a + b = c
      local a = math.random(5, 50)
      local b = math.random(5, 50)
      return makeMissingProblem("+", a, b, a + b, math.random(1, 2) == 1)
    elseif op_roll == 2 then
      -- a - b = c
      local a = math.random(20, 100)
      local b = math.random(5, a - 5)
      return makeMissingProblem("-", a, b, a - b, math.random(1, 2) == 1)
    elseif op_roll == 3 then
      -- a × b = c
      local a = math.random(2, 9)
      local b = math.random(2, 9)
      return makeMissingProblem("×", a, b, a * b, math.random(1, 2) == 1)
    else
      -- a ÷ b = c
      local b = math.random(2, 9)
      local c = math.random(2, 9)
      return makeMissingProblem("÷", b * c, b, c, math.random(1, 2) == 1)
    end
  elseif mode_type == "squares" then
    local n = math.random(2, 20)
    return {
      op = "²",
      answer = n * n,
      text = string.format("%d² =", n),
    }
  elseif mode_type == "three_term" then
    local pattern = math.random(1, 6)
    if pattern == 1 then
      -- a + b + c =
      local a = math.random(5, 30)
      local b = math.random(5, 30)
      local c = math.random(5, 30)
      return {
        op = "+",
        answer = a + b + c,
        text = string.format("%d + %d + %d =", a, b, c),
      }
    elseif pattern == 2 then
      -- a - b - c =
      local a = math.random(30, 90)
      local b = math.random(5, math.floor(a / 2))
      local c = math.random(1, a - b - 1)
      return {
        op = "-",
        answer = a - b - c,
        text = string.format("%d - %d - %d =", a, b, c),
      }
    elseif pattern == 3 then
      -- a + b - c =
      local a = math.random(10, 40)
      local b = math.random(10, 40)
      local c = math.random(5, a + b - 5)
      return {
        op = "+-",
        answer = a + b - c,
        text = string.format("%d + %d - %d =", a, b, c),
      }
    elseif pattern == 4 then
      -- a × b + c =
      local a = math.random(2, 9)
      local b = math.random(2, 9)
      local c = math.random(5, 30)
      return {
        op = "×+",
        answer = a * b + c,
        text = string.format("%d × %d + %d =", a, b, c),
      }
    elseif pattern == 5 then
      -- a × b - c =
      local a = math.random(3, 9)
      local b = math.random(3, 9)
      local c = math.random(1, a * b - 2)
      return {
        op = "×-",
        answer = a * b - c,
        text = string.format("%d × %d - %d =", a, b, c),
      }
    else
      -- a - b × c =
      local b = math.random(2, 9)
      local c = math.random(2, 9)
      local bc = b * c
      local a = math.random(bc + 2, bc + 40)
      return {
        op = "-×",
        answer = a - bc,
        text = string.format("%d - %d × %d =", a, b, c),
      }
    end
  elseif mode_type == "arithmetic_progression" then
    local terms_count = mode.terms_count or 8
    local is_addition = math.random(1, 2) == 1
    local max_d = mode.max_step or (max_val <= 50 and 4 or 10)
    local d = math.random(1, max_d)
    local span = (terms_count - 1) * d
    local terms = {}

    local step_dir = is_addition and d or -d
    local min_start = is_addition and 1 or span
    local start_val = math.random(
      min_start,
      math.max(min_start, is_addition and (max_val - span) or max_val)
    )
    for i = 1, terms_count do
      table.insert(terms, start_val + (i - 1) * step_dir)
    end

    local blanks = {}
    local blank_indices = {}

    if mode.alternating_blanks then
      -- Strictly in either 1 3 5 7 or 2 4 6 8 (one number one gap)
      local start_idx = math.random(1, 2)
      for i = start_idx, terms_count, 2 do
        blanks[i] = true
        table.insert(blank_indices, i)
      end
    else
      -- Randomly remove 4 or 5 numbers from the pattern
      local num_blanks = math.random(4, 5)

      -- Pick an adjacent pair (anchor, anchor+1) from 1..(terms_count-1) to remain visible, guaranteeing solvable pattern
      local anchor = math.random(1, terms_count - 1)
      local candidate_indices = {}
      for i = 1, terms_count do
        if i ~= anchor and i ~= (anchor + 1) then
          table.insert(candidate_indices, i)
        end
      end
      -- Fisher-Yates shuffle
      for i = #candidate_indices, 2, -1 do
        local j = math.random(1, i)
        candidate_indices[i], candidate_indices[j] = candidate_indices[j], candidate_indices[i]
      end

      for i = 1, num_blanks do
        local idx = candidate_indices[i]
        blanks[idx] = true
        table.insert(blank_indices, idx)
      end
      table.sort(blank_indices)
    end

    local answers = {}
    local user_answers = {}
    for _, idx in ipairs(blank_indices) do
      answers[idx] = terms[idx]
      user_answers[idx] = ""
    end

    local display_terms = {}
    for idx, val in ipairs(terms) do
      if blanks[idx] then
        table.insert(display_terms, "___")
      else
        table.insert(display_terms, tostring(val))
      end
    end

    return {
      step = d,
      terms = terms,
      blanks = blanks,
      blank_indices = blank_indices,
      answers = answers,
      user_answers = user_answers,
      text = table.concat(display_terms, ", "),
      inline_blanks = true,
    }
  end
end

local function generateMathSnakeProblems(mode, count)
  local max_val = mode.max
  assert(max_val >= 10)

  local cur = math.random(
    math.max(10, math.floor(max_val * 0.15)),
    math.floor(max_val * 0.85)
  )
  local problems = {}
  local prev_op
  local prev_b

  for i = 1, count do
    local up_room = max_val - cur
    local down_room = cur
    local can_add = up_room >= 5
    local can_sub = down_room >= 5
    assert(can_add or can_sub)

    local is_addition
    if can_add and can_sub then
      is_addition = math.random(1, 2) == 1
    else
      is_addition = can_add
    end

    local op = is_addition and "+" or "-"
    local hi = math.min(35, is_addition and up_room or down_room)
    assert(hi >= 5)

    local b
    if prev_op and op ~= prev_op and prev_b <= hi then
      b = math.random(2, hi - 1)
      if b >= prev_b then
        b = b + 1
      end
    else
      b = math.random(2, hi)
    end

    local next_val = is_addition and (cur + b) or (cur - b)
    assert(next_val >= 0 and next_val <= max_val)

    problems[i] = {
      id = i,
      op = op,
      a = cur,
      b = b,
      answer = next_val,
      user_answer = "",
      checked = false,
    }
    cur = next_val
    prev_op = op
    prev_b = b
  end

  return problems
end

function Generator.generateProblems(mode_id, count)
  local mode = type(mode_id) == "table" and mode_id
    or Generator.getModeById(mode_id)
  count = count or mode.question_count or 10
  if mode.type == "math_snake" then
    return generateMathSnakeProblems(mode, count)
  end
  local problems = {}
  local seen = {}

  for i = 1, count do
    local prob
    local attempts = 0
    while attempts < 20 do
      attempts = attempts + 1
      prob = generateSingleProblem(mode)
      if not seen[prob.text] or attempts >= 15 then
        seen[prob.text] = true
        break
      end
    end
    prob.id = i
    if not prob.inline_blanks then
      prob.user_answer = ""
    end
    prob.is_correct = nil
    prob.checked = false
    table.insert(problems, prob)
  end

  return problems
end

function Generator.checkAnswers(problems)
  local correct_count = 0

  for _, prob in ipairs(problems) do
    prob.checked = true
    if prob.inline_blanks then
      local all_blanks_correct = true
      for _, b_idx in ipairs(prob.blank_indices) do
        if tonumber(prob.user_answers[b_idx]) ~= prob.answers[b_idx] then
          all_blanks_correct = false
        end
      end
      if all_blanks_correct then
        prob.is_correct = true
        correct_count = correct_count + 1
      else
        prob.is_correct = false
      end
    else
      if tonumber(prob.user_answer) == prob.answer then
        prob.is_correct = true
        correct_count = correct_count + 1
      else
        prob.is_correct = false
      end
    end
  end

  return {
    total = #problems,
    correct_count = correct_count,
  }
end

return Generator
