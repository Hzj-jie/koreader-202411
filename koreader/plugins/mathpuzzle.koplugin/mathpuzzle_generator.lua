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
    title = _("3-Term Mental Math (5 problems)"),
    description = _("Order of operations with 3 numbers (5 problems)"),
    type = "three_term",
    max = 100,
    question_count = 5,
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
  end
end

function Generator.generateProblems(mode_id, count)
  count = count or 10
  local mode = type(mode_id) == "table" and mode_id
    or Generator.getModeById(mode_id)
  local problems = {}
  local seen = {}

  for i = 1, count do
    local prob
    local attempts = 0
    while attempts < 20 do
      attempts = attempts + 1
      prob = generateSingleProblem(mode)
      local key = prob.text
      if not seen[key] or attempts >= 15 then
        seen[key] = true
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
    local uans_str = tostring(prob.user_answer or ""):gsub("^%s*(.-)%s*$", "%1")
    local uans = tonumber(uans_str)
    prob.checked = true
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

  return {
    total = total,
    correct_count = correct_count,
    answered_count = answered_count,
    all_correct = (correct_count == total),
  }
end

return Generator
