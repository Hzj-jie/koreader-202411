local gettext = require("gettext")
local _ = gettext

local Generator = {}

Generator.MODES = {
  {
    id = "add_sub_10",
    title = _("Addition & Subtraction within 10"),
    description = _("Add and subtract numbers up to 10"),
    type = "add_sub",
    max = 10,
  },
  {
    id = "add_sub_100",
    title = _("Addition & Subtraction within 100"),
    description = _("Add and subtract numbers up to 100"),
    type = "add_sub",
    max = 100,
  },
  {
    id = "add_sub_1000",
    title = _("Addition & Subtraction within 1,000"),
    description = _("Add and subtract numbers up to 1,000"),
    type = "add_sub",
    max = 1000,
  },
  {
    id = "add_sub_10000",
    title = _("Addition & Subtraction within 10,000"),
    description = _("Add and subtract numbers up to 10,000"),
    type = "add_sub",
    max = 10000,
  },
  {
    id = "mul_100",
    title = _("Multiplication within 100"),
    description = _("Multiplication table up to 10 × 10"),
    type = "mul",
    max = 100,
  },
  {
    id = "div_100",
    title = _("Division within 100"),
    description = _("Division with whole number results up to 100"),
    type = "div",
    max = 100,
  },
  {
    id = "mul_div_advanced",
    title = _("2-Digit × 1-Digit & Division within 1,000"),
    description = _("Multiplication and division with 2-digit numbers"),
    type = "mul_div_advanced",
  },
  {
    id = "mixed_100",
    title = _("Mixed Operations within 100"),
    description = _("Random +, -, ×, ÷ operations within 100"),
    type = "mixed",
    max = 100,
  },
  {
    id = "mixed_1000",
    title = _("Mixed Operations within 1,000"),
    description = _("Random +, -, ×, ÷ operations within 1,000"),
    type = "mixed",
    max = 1000,
  },
  {
    id = "missing_100",
    title = _("Fill-in-the-Blank within 100"),
    description = _("Find the missing number in equations"),
    type = "missing",
    max = 100,
  },
  {
    id = "squares_400",
    title = _("Square Numbers within 400"),
    description = _("Squares of numbers up to 20²"),
    type = "squares",
    max = 400,
  },
  {
    id = "three_term_100",
    title = _("3-Term Mental Math"),
    description = _("Order of operations with 3 numbers"),
    type = "three_term",
    max = 100,
    question_count = 5,
  },
  {
    id = "arithmetic_progression_50_easy",
    title = _("Arithmetic Progression within 50 (Easy)"),
    description = _("Alternating blanks, step up to 4, numbers up to 50"),
    type = "arithmetic_progression",
    max = 50,
    max_step = 4,
    alternating_blanks = true,
    question_count = 5,
    single_column = true,
  },
  {
    id = "arithmetic_progression_50",
    title = _("Arithmetic Progression within 50"),
    description = _("Step up to 4, numbers up to 50"),
    type = "arithmetic_progression",
    max = 50,
    max_step = 4,
    question_count = 5,
    single_column = true,
  },
  {
    id = "arithmetic_progression_100",
    title = _("Arithmetic Progression within 100"),
    description = _("Step up to 10, numbers up to 100"),
    type = "arithmetic_progression",
    max = 100,
    max_step = 10,
    question_count = 5,
    single_column = true,
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
  if mode_id == "arithmetic_progression_50_easy" or mode_id == "arithmetic_progression_easy" or mode_id == "ap_easy" or mode_id == "ap_50_easy" then
    return Generator.getModeById("arithmetic_progression_50_easy")
  end
  if mode_id == "arithmetic_progression" or mode_id == "arithmetic_progression_100" or mode_id == "ap_100" then
    return Generator.getModeById("arithmetic_progression_100")
  end
  if mode_id == "arithmetic_progression_50" or mode_id == "ap_50" then
    return Generator.getModeById("arithmetic_progression_50")
  end
  return Generator.MODES[2] -- default to add_sub_100
end

local function generateSingleProblem(mode)
  local mode_type = mode.type or "add_sub"
  local max_val = mode.max or 100

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
      return {
        op = "+",
        a = a,
        b = b,
        answer = a + b,
        text = string.format("%d + %d =", a, b),
      }
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
      return {
        op = "-",
        a = a,
        b = b,
        answer = a - b,
        text = string.format("%d - %d =", a, b),
      }
    end
  elseif mode_type == "mul" then
    local a = math.random(2, 9)
    local b = math.random(2, 9)
    return {
      op = "×",
      a = a,
      b = b,
      answer = a * b,
      text = string.format("%d × %d =", a, b),
    }
  elseif mode_type == "div" then
    local b = math.random(2, 9)
    local c = math.random(1, 9)
    local a = b * c
    return {
      op = "÷",
      a = a,
      b = b,
      answer = c,
      text = string.format("%d ÷ %d =", a, b),
    }
  elseif mode_type == "mul_div_advanced" then
    local is_mul = math.random(1, 2) == 1
    if is_mul then
      local a = math.random(11, 99)
      local b = math.random(2, 9)
      return {
        op = "×",
        a = a,
        b = b,
        answer = a * b,
        text = string.format("%d × %d =", a, b),
      }
    else
      local b = math.random(2, 9)
      local c = math.random(11, 99)
      local a = b * c
      return {
        op = "÷",
        a = a,
        b = b,
        answer = c,
        text = string.format("%d ÷ %d =", a, b),
      }
    end
  elseif mode_type == "mixed" then
    local roll = math.random(1, 4)
    if roll == 1 then
      -- Addition
      local a = math.random(10, max_val - 10)
      local b = math.random(5, max_val - a)
      return {
        op = "+",
        a = a,
        b = b,
        answer = a + b,
        text = string.format("%d + %d =", a, b),
      }
    elseif roll == 2 then
      -- Subtraction
      local a = math.random(15, max_val)
      local b = math.random(5, a - 1)
      return {
        op = "-",
        a = a,
        b = b,
        answer = a - b,
        text = string.format("%d - %d =", a, b),
      }
    elseif roll == 3 then
      -- Multiplication
      if max_val <= 100 then
        local a = math.random(2, 9)
        local b = math.random(2, 9)
        return {
          op = "×",
          a = a,
          b = b,
          answer = a * b,
          text = string.format("%d × %d =", a, b),
        }
      else
        local a = math.random(11, 99)
        local b = math.random(2, 9)
        return {
          op = "×",
          a = a,
          b = b,
          answer = a * b,
          text = string.format("%d × %d =", a, b),
        }
      end
    else
      -- Division
      if max_val <= 100 then
        local b = math.random(2, 9)
        local c = math.random(2, 9)
        local a = b * c
        return {
          op = "÷",
          a = a,
          b = b,
          answer = c,
          text = string.format("%d ÷ %d =", a, b),
        }
      else
        local b = math.random(2, 9)
        local c = math.random(11, 99)
        local a = b * c
        return {
          op = "÷",
          a = a,
          b = b,
          answer = c,
          text = string.format("%d ÷ %d =", a, b),
        }
      end
    end
  elseif mode_type == "missing" then
    local op_roll = math.random(1, 4)
    if op_roll == 1 then
      -- a + b = c
      local a = math.random(5, 50)
      local b = math.random(5, 50)
      local c = a + b
      if math.random(1, 2) == 1 then
        return {
          op = "+",
          answer = a,
          text = string.format("___ + %d = %d", b, c),
        }
      else
        return {
          op = "+",
          answer = b,
          text = string.format("%d + ___ = %d", a, c),
        }
      end
    elseif op_roll == 2 then
      -- a - b = c
      local a = math.random(20, 100)
      local b = math.random(5, a - 5)
      local c = a - b
      if math.random(1, 2) == 1 then
        return {
          op = "-",
          answer = a,
          text = string.format("___ - %d = %d", b, c),
        }
      else
        return {
          op = "-",
          answer = b,
          text = string.format("%d - ___ = %d", a, c),
        }
      end
    elseif op_roll == 3 then
      -- a × b = c
      local a = math.random(2, 9)
      local b = math.random(2, 9)
      local c = a * b
      if math.random(1, 2) == 1 then
        return {
          op = "×",
          answer = a,
          text = string.format("___ × %d = %d", b, c),
        }
      else
        return {
          op = "×",
          answer = b,
          text = string.format("%d × ___ = %d", a, c),
        }
      end
    else
      -- a ÷ b = c
      local b = math.random(2, 9)
      local c = math.random(2, 9)
      local a = b * c
      if math.random(1, 2) == 1 then
        return {
          op = "÷",
          answer = a,
          text = string.format("___ ÷ %d = %d", b, c),
        }
      else
        return {
          op = "÷",
          answer = b,
          text = string.format("%d ÷ ___ = %d", a, c),
        }
      end
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
    local terms_count = 8
    local is_addition = math.random(1, 2) == 1
    local max_d = mode.max_step or (max_val <= 50 and 4 or 10)
    local d = math.random(1, max_d)
    local span = (terms_count - 1) * d
    local terms = {}

    if is_addition then
      local min_start = 1
      local max_start = math.max(1, max_val - span)
      local start_val = math.random(min_start, max_start)
      for i = 1, terms_count do
        table.insert(terms, start_val + (i - 1) * d)
      end
    else
      local min_start = span
      local max_start = math.max(min_start, max_val)
      local start_val = math.random(min_start, max_start)
      for i = 1, terms_count do
        table.insert(terms, start_val - (i - 1) * d)
      end
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
      op = is_addition and "+" or "-",
      step = d,
      terms = terms,
      blanks = blanks,
      blank_indices = blank_indices,
      answers = answers,
      user_answers = user_answers,
      answer = answers[blank_indices[1]],
      user_answer = "",
      text = table.concat(display_terms, ", "),
      inline_blanks = true,
    }
  end
end

function Generator.generateProblems(mode_id, count)
  local mode = type(mode_id) == "table" and mode_id
    or Generator.getModeById(mode_id)
  count = count or (mode and mode.question_count) or 10
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
    prob.user_answer = ""
    prob.is_correct = nil
    prob.checked = false
    table.insert(problems, prob)
  end

  return problems
end

function Generator.checkAnswers(problems)
  local total = #problems
  local correct_count = 0
  local answered_count = 0

  for _, prob in ipairs(problems) do
    prob.checked = true
    if prob.inline_blanks or prob.user_answers then
      local all_blanks_correct = true
      local any_answered = false
      for _, b_idx in ipairs(prob.blank_indices) do
        local uans_str = tostring(prob.user_answers[b_idx] or ""):gsub("^%s*(.-)%s*$", "%1")
        local uans = tonumber(uans_str)
        if uans_str ~= "" then
          any_answered = true
        end
        if uans == nil or uans ~= prob.answers[b_idx] then
          all_blanks_correct = false
        end
      end
      if any_answered then
        answered_count = answered_count + 1
      end
      if all_blanks_correct then
        prob.is_correct = true
        correct_count = correct_count + 1
      else
        prob.is_correct = false
      end
    else
      local uans_str = tostring(prob.user_answer or ""):gsub("^%s*(.-)%s*$", "%1")
      local uans = tonumber(uans_str)
      if uans_str ~= "" then
        answered_count = answered_count + 1
      end
      if uans ~= nil and uans == prob.answer then
        prob.is_correct = true
        correct_count = correct_count + 1
      else
        prob.is_correct = false
      end
    end
  end

  return {
    total = total,
    correct_count = correct_count,
    answered_count = answered_count,
    all_correct = (correct_count == total),
  }
end

return Generator
