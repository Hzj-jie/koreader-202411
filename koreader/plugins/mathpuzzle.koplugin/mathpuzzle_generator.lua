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
