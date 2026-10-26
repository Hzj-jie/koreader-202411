describe("Sokoban Settings widget", function()
  local SettingsWidget, UIManager

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))
    UIManager = require("ui/uimanager")

    SettingsWidget = require("plugins/sokoban.koplugin/sokoban_settings")
  end)

  before_each(function()
    UIManager.setDirty = function() end
  end)

  local function findWidget(widget, predicate)
    if predicate(widget) then
      return widget
    end
    if type(widget) == "table" then
      for _, child in ipairs(widget) do
        local found = findWidget(child, predicate)
        if found then
          return found
        end
      end
    end
    return nil
  end

  it("should initialize Sokoban SettingsWidget instance", function()
    local widget = SettingsWidget:new({
      level_sets = {
        { name = "Easy", count = 10 },
        { name = "Hard", count = 5 },
      },
      current_set = "Easy",
      current_level = 1,
      furthest_reached = { Easy = 3 },
      best_moves = { Easy = { [1] = 12 } },
    })
    assert.is_table(widget)
    assert.are.equal("Easy", widget.current_set)
    assert.are.equal(1, widget.current_level)
    assert.is_table(widget.dimen)
  end)

  it(
    "should handle level-set selection and switch current_set and current_level",
    function()
      local shown_widget
      local old_close = UIManager.close
      local old_show = UIManager.show
      UIManager.close = function() end
      UIManager.show = function(self, w)
        shown_widget = w
      end

      local widget = SettingsWidget:new({
        level_sets = {
          { name = "Easy", count = 10 },
          { name = "Hard", count = 5 },
        },
        current_set = "Easy",
        current_level = 3,
        last_played_levels = { Easy = 3, Hard = 2 },
        furthest_reached = { Easy = 5, Hard = 4 },
      })

      -- Find set_table
      local set_table = findWidget(widget, function(w)
        return type(w) == "table"
          and w.buttons
          and #w.buttons == 2
          and w.buttons[1][1]
          and w.buttons[1][1].text:find("Easy")
      end)
      assert.is_not_nil(set_table)
      assert.is_true(set_table.buttons[1][1].bold)
      assert.is_false(set_table.buttons[2][1].bold)

      -- Clicking the already selected set does nothing
      shown_widget = nil
      set_table.buttons[1][1].callback()
      assert.is_nil(shown_widget)

      -- Clicking Hard switches current_set and loads last_played_levels
      set_table.buttons[2][1].callback()
      assert.is_not_nil(shown_widget)
      assert.are.equal("Hard", shown_widget.current_set)
      assert.are.equal(2, shown_widget.current_level)

      UIManager.close = old_close
      UIManager.show = old_show
    end
  )

  it(
    "should handle level navigation ◀ and ▶ buttons within allowed boundaries",
    function()
      local shown_widget
      local old_close = UIManager.close
      local old_show = UIManager.show
      UIManager.close = function() end
      UIManager.show = function(self, w)
        shown_widget = w
      end

      local widget = SettingsWidget:new({
        level_sets = {
          { name = "Set1", count = 10 },
        },
        current_set = "Set1",
        current_level = 2,
        furthest_reached = { Set1 = 3 },
      })

      local nav_table = findWidget(widget, function(w)
        return type(w) == "table"
          and w.buttons
          and w.buttons[1]
          and #w.buttons[1] == 3
          and w.buttons[1][1].text == "◀"
      end)
      assert.is_not_nil(nav_table)

      -- Decrement: 2 -> 1
      shown_widget = nil
      nav_table.buttons[1][1].callback()
      assert.is_not_nil(shown_widget)
      assert.are.equal(1, shown_widget.current_level)

      -- At level 1, decrement should not decrement below 1
      widget.current_level = 1
      shown_widget = nil
      nav_table.buttons[1][1].callback()
      assert.is_nil(shown_widget)

      -- Increment: 2 -> 3 (allowed since furthest_reached = 3)
      widget.current_level = 2
      shown_widget = nil
      nav_table.buttons[1][3].callback()
      assert.is_not_nil(shown_widget)
      assert.are.equal(3, shown_widget.current_level)

      -- Increment at furthest_reached limit (3): cannot exceed 3
      widget.current_level = 3
      shown_widget = nil
      nav_table.buttons[1][3].callback()
      assert.is_nil(shown_widget)

      UIManager.close = old_close
      UIManager.show = old_show
    end
  )

  it(
    "should display solved checkmark ✓ when level has been solved",
    function()
      local solved_widget = SettingsWidget:new({
        level_sets = {
          { name = "Set1", count = 10 },
        },
        current_set = "Set1",
        current_level = 1,
        furthest_reached = { Set1 = 3 },
        best_moves = { Set1 = { [1] = 15 } },
      })

      local nav_table = findWidget(solved_widget, function(w)
        return type(w) == "table"
          and w.buttons
          and w.buttons[1]
          and #w.buttons[1] == 3
          and w.buttons[1][1].text == "◀"
      end)
      assert.is_not_nil(nav_table)
      local label_text = nav_table.buttons[1][2].text
      assert.is_not_nil(label_text:find("✓ 1 / 10"))

      local unsolved_widget = SettingsWidget:new({
        level_sets = {
          { name = "Set1", count = 10 },
        },
        current_set = "Set1",
        current_level = 2,
        furthest_reached = { Set1 = 3 },
        best_moves = { Set1 = { [1] = 15 } },
      })

      local un_nav = findWidget(unsolved_widget, function(w)
        return type(w) == "table"
          and w.buttons
          and w.buttons[1]
          and #w.buttons[1] == 3
          and w.buttons[1][1].text == "◀"
      end)
      assert.is_not_nil(un_nav)
      local un_text = un_nav.buttons[1][2].text
      assert.is_nil(un_text:find("✓"))
      assert.is_not_nil(un_text:find("2 / 10"))
    end
  )

  it(
    "should detect at_frontier and toggle between Play and Skip Level callbacks",
    function()
      local closed_widget
      local old_close = UIManager.close
      UIManager.close = function(self, w)
        closed_widget = w
      end

      local played_set_idx, played_level
      local skipped_set_idx, skipped_level

      -- Frontier level (unsolved, playing == current_level, furthest_reached)
      local frontier_widget = SettingsWidget:new({
        level_sets = {
          { name = "Set1", count = 10 },
          { name = "Set2", count = 5 },
        },
        current_set = "Set2",
        current_level = 2,
        playing_set = "Set2",
        playing_level = 2,
        furthest_reached = { Set2 = 2 },
        best_moves = { Set2 = { [1] = 10 } },
        on_play_cb = function(s, l)
          played_set_idx = s
          played_level = l
        end,
        on_skip_cb = function(s, l)
          skipped_set_idx = s
          skipped_level = l
        end,
      })

      local frontier_play_btn = findWidget(frontier_widget, function(w)
        return type(w) == "table"
          and w.buttons
          and #w.buttons == 1
          and w.buttons[1][1]
          and (
            w.buttons[1][1].text == "Skip Level"
            or w.buttons[1][1].text == "Play"
          )
      end)
      assert.is_not_nil(frontier_play_btn)
      assert.are.equal("Skip Level", frontier_play_btn.buttons[1][1].text)

      frontier_play_btn.buttons[1][1].callback()
      assert.are.equal(frontier_widget, closed_widget)
      assert.are.equal(2, skipped_set_idx)
      assert.are.equal(2, skipped_level)
      assert.is_nil(played_set_idx)

      -- Normal Play button (already solved or looking back at previous level)
      local normal_widget = SettingsWidget:new({
        level_sets = {
          { name = "Set1", count = 10 },
        },
        current_set = "Set1",
        current_level = 1,
        playing_set = "Set1",
        playing_level = 2,
        furthest_reached = { Set1 = 2 },
        best_moves = { Set1 = { [1] = 10 } },
        on_play_cb = function(s, l)
          played_set_idx = s
          played_level = l
        end,
        on_skip_cb = function(s, l)
          skipped_set_idx = s
          skipped_level = l
        end,
      })

      local normal_play_btn = findWidget(normal_widget, function(w)
        return type(w) == "table"
          and w.buttons
          and #w.buttons == 1
          and w.buttons[1][1]
          and (
            w.buttons[1][1].text == "Skip Level"
            or w.buttons[1][1].text == "Play"
          )
      end)
      assert.is_not_nil(normal_play_btn)
      assert.are.equal("Play", normal_play_btn.buttons[1][1].text)

      played_set_idx = nil
      played_level = nil
      skipped_set_idx = nil
      skipped_level = nil
      normal_play_btn.buttons[1][1].callback()
      assert.are.equal(normal_widget, closed_widget)
      assert.are.equal(1, played_set_idx)
      assert.are.equal(1, played_level)
      assert.is_nil(skipped_set_idx)
      assert.is_nil(skipped_level)

      UIManager.close = old_close
    end
  )

  it(
    "should handle lifecycle methods onShow, onClose, onTapClose, onCloseWidget",
    function()
      local closed_widget
      local old_close = UIManager.close
      UIManager.close = function(self, w)
        closed_widget = w
      end

      local widget = SettingsWidget:new({
        level_sets = {
          { name = "Default", count = 5 },
        },
        current_set = "Default",
        current_level = 1,
      })
      widget:onShow()
      widget:onCloseWidget()
      assert.is_true(widget:onTapClose())
      assert.are.equal(widget, closed_widget)

      UIManager.close = old_close
    end
  )
end)
