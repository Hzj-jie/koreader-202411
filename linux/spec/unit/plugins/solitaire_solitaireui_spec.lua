describe("SolitaireUI plugin module", function()
  local SolitaireUI
  local Blitbuffer
  local UIManager

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    SolitaireUI = require("plugins/solitaire.koplugin/solitaireui")
    Blitbuffer = require("ffi/blitbuffer")
    UIManager = require("ui/uimanager")
  end)

  it("should instantiate SolitaireUI container", function()
    local inst = SolitaireUI:new({
      settings_path = os.tmpname(),
      save_path = os.tmpname(),
    })
    assert.is_table(inst)
    assert.is_table(inst.game)
    assert.is_table(inst.stats)

    os.remove(inst.settings_path)
    os.remove(inst.save_path)
  end)

  it("should load and save draw mode settings", function()
    local tmp_settings = os.tmpname()
    local inst = SolitaireUI:new({
      settings_path = tmp_settings,
      save_path = os.tmpname(),
    })

    inst.draw_mode_pref = 3
    inst:saveSettings()

    inst:loadSettings()
    assert.are.equal(3, inst.draw_mode_pref)

    os.remove(tmp_settings)
    os.remove(inst.save_path)
  end)

  it("should save, load, and delete game state", function()
    local tmp_save = os.tmpname()
    local inst = SolitaireUI:new({
      settings_path = os.tmpname(),
      save_path = tmp_save,
    })

    inst:saveGame()
    local loaded = inst:loadGame()
    assert.is_boolean(loaded)

    inst:deleteSave()

    os.remove(inst.settings_path)
  end)

  it("should handle new game and undo move operations", function()
    local inst = SolitaireUI:new({
      settings_path = os.tmpname(),
      save_path = os.tmpname(),
    })

    inst:newGame()
    assert.is_table(inst.game)

    inst:undoMove()

    os.remove(inst.settings_path)
    os.remove(inst.save_path)
  end)

  it("should render UI and all card types onto Blitbuffer", function()
    local inst = SolitaireUI:new({
      settings_path = os.tmpname(),
      save_path = os.tmpname(),
    })

    local bb = Blitbuffer.new(inst.screen_width or 600, inst.screen_height or 800)
    inst:paintTo(bb, 0, 0)

    -- Test individual drawing helpers
    inst:drawCard(bb, 10, 10, { rank = 1, suit = 1, face_up = true }, true, true, false)
    inst:drawCard(bb, 10, 50, { rank = 12, suit = 2, face_up = true }, false, false, true)
    inst:drawCard(bb, 10, 90, { rank = 5, suit = 3, face_up = false }, false, false, false)
    inst:drawEmptySlot(bb, 10, 130, "K")
    inst:drawCardBackPattern(bb, 10, 170)

    bb:free()
    os.remove(inst.settings_path)
    os.remove(inst.save_path)
  end)

  it("should render UI with Draw-3 waste fanning and empty tableau/foundation hints", function()
    local inst = SolitaireUI:new({
      settings_path = os.tmpname(),
      save_path = os.tmpname(),
    })

    inst.game.draw_mode = 3
    inst.game.waste = {
      { rank = 2, suit = 1, face_up = true },
      { rank = 3, suit = 2, face_up = true },
      { rank = 4, suit = 3, face_up = true },
    }
    inst.selected_source = { type = "waste" }
    inst.hint_highlight = {
      type = "waste_to_tableau",
      to = 2,
      card_idx = 1,
    }

    -- Set up tableau column 1 with cards, column 2 empty
    inst.game.tableau[1] = {
      { rank = 10, suit = 1, face_up = false },
      { rank = 9, suit = 2, face_up = true },
    }
    inst.game.tableau[2] = {}

    -- Set foundation 1 with card, foundation 2 empty
    inst.game.foundations[1] = {
      { rank = 1, suit = 1, face_up = true },
    }
    inst.game.foundations[2] = {}

    local bb = Blitbuffer.new(inst.screen_width or 600, inst.screen_height or 800)
    inst:paintTo(bb, 0, 0)

    -- Now test with empty waste
    inst.game.waste = {}
    inst.hint_highlight = {
      type = "tableau_to_tableau",
      from = 1,
      to = 2,
      card_idx = 2,
    }
    inst.selected_source = { type = "tableau", index = 1, card_pos = 2 }
    inst:paintTo(bb, 0, 0)

    bb:free()
    os.remove(inst.settings_path)
    os.remove(inst.save_path)
  end)

  it("should handle user taps and gestures across all zones", function()
    local inst = SolitaireUI:new({
      settings_path = os.tmpname(),
      save_path = os.tmpname(),
    })

    local bb = Blitbuffer.new(inst.screen_width or 600, inst.screen_height or 800)
    inst:paintTo(bb, 0, 0)

    -- Tap empty or outside
    inst:onTap(nil, { pos = { x = 0, y = 0 } })

    -- Find zones
    for _, zone in ipairs(inst.touch_zones) do
      local mid_x = zone.x + math.floor(zone.w / 2)
      local mid_y = zone.y + math.floor(zone.h / 2)
      inst:onTap(nil, { pos = { x = mid_x, y = mid_y } })
      inst:onHold(nil, { pos = { x = mid_x, y = mid_y } })
    end

    bb:free()
    os.remove(inst.settings_path)
    os.remove(inst.save_path)
  end)

  it("should handle drawing from stock and waste selection", function()
    local orig_show = UIManager.show
    UIManager.show = function() end

    local inst = SolitaireUI:new({
      settings_path = os.tmpname(),
      save_path = os.tmpname(),
    })

    local bb = Blitbuffer.new(inst.screen_width or 600, inst.screen_height or 800)

    -- 1. Tap stock to draw
    inst.game.stock = { { rank = 5, suit = 1, face_up = false } }
    inst.game.waste = {}
    inst:paintTo(bb, 0, 0)
    local stock_zone = nil
    for _, z in ipairs(inst.touch_zones) do
      if z.type == "stock" then stock_zone = z break end
    end
    assert.is_not_nil(stock_zone)
    inst:onTap(nil, { pos = { x = stock_zone.x + 5, y = stock_zone.y + 5 } })
    assert.are.equal(1, #inst.game.waste)

    -- 2. Tap waste to select
    inst:paintTo(bb, 0, 0)
    local waste_zone = nil
    for _, z in ipairs(inst.touch_zones) do
      if z.type == "waste" then waste_zone = z break end
    end
    assert.is_not_nil(waste_zone)
    inst:onTap(nil, { pos = { x = waste_zone.x + 5, y = waste_zone.y + 5 } })
    assert.is_table(inst.selected_source)
    assert.are.equal("waste", inst.selected_source.type)

    -- Tap waste again to deselect
    inst:onTap(nil, { pos = { x = waste_zone.x + 5, y = waste_zone.y + 5 } })
    assert.is_nil(inst.selected_source)

    bb:free()
    UIManager.show = orig_show
    os.remove(inst.settings_path)
    os.remove(inst.save_path)
  end)

  it("should handle waste to foundation and tableau to foundation moves", function()
    local orig_show = UIManager.show
    UIManager.show = function() end

    local inst = SolitaireUI:new({
      settings_path = os.tmpname(),
      save_path = os.tmpname(),
    })

    local bb = Blitbuffer.new(inst.screen_width or 600, inst.screen_height or 800)

    -- Waste to Foundation
    inst.game.waste = { { rank = 1, suit = 1, face_up = true } } -- Ace of Hearts
    inst.game.foundations[1] = {}
    inst:paintTo(bb, 0, 0)
    local waste_zone = nil
    for _, z in ipairs(inst.touch_zones) do
      if z.type == "waste" then waste_zone = z break end
    end
    local f1_zone = nil
    for _, z in ipairs(inst.touch_zones) do
      if z.type == "foundation" and z.index == 1 then f1_zone = z break end
    end

    inst:onTap(nil, { pos = { x = waste_zone.x + 5, y = waste_zone.y + 5 } })
    inst:paintTo(bb, 0, 0)
    inst:onTap(nil, { pos = { x = f1_zone.x + 5, y = f1_zone.y + 5 } })
    assert.are.equal(1, #inst.game.foundations[1])
    assert.are.equal(0, #inst.game.waste)

    -- Tableau to Foundation
    inst.game.tableau[1] = { { rank = 2, suit = 1, face_up = true } } -- 2 of Hearts
    inst:paintTo(bb, 0, 0)
    local t1_zone = nil
    for _, z in ipairs(inst.touch_zones) do
      if z.type == "tableau" and z.index == 1 then t1_zone = z break end
    end
    for _, z in ipairs(inst.touch_zones) do
      if z.type == "foundation" and z.index == 1 then f1_zone = z break end
    end

    inst:onTap(nil, { pos = { x = t1_zone.x + 5, y = t1_zone.y + 5 } })
    assert.is_table(inst.selected_source)
    assert.are.equal("tableau", inst.selected_source.type)
    inst:paintTo(bb, 0, 0)
    inst:onTap(nil, { pos = { x = f1_zone.x + 5, y = f1_zone.y + 5 } })
    assert.are.equal(2, #inst.game.foundations[1])

    bb:free()
    UIManager.show = orig_show
    os.remove(inst.settings_path)
    os.remove(inst.save_path)
  end)

  it("should handle waste to tableau and tableau to tableau moves", function()
    local orig_show = UIManager.show
    UIManager.show = function() end

    local inst = SolitaireUI:new({
      settings_path = os.tmpname(),
      save_path = os.tmpname(),
    })

    local bb = Blitbuffer.new(inst.screen_width or 600, inst.screen_height or 800)

    -- Waste to Tableau
    inst.game.waste = { { rank = 8, suit = 4, face_up = true } } -- Black 8 (Spades)
    inst.game.tableau[2] = { { rank = 9, suit = 2, face_up = true } } -- Red 9 (Diamonds)
    inst:paintTo(bb, 0, 0)
    local waste_zone = nil
    for _, z in ipairs(inst.touch_zones) do
      if z.type == "waste" then waste_zone = z break end
    end
    local t2_zone = nil
    for _, z in ipairs(inst.touch_zones) do
      if z.type == "tableau" and z.index == 2 then t2_zone = z break end
    end

    inst:onTap(nil, { pos = { x = waste_zone.x + 5, y = waste_zone.y + 5 } })
    inst:paintTo(bb, 0, 0)
    inst:onTap(nil, { pos = { x = t2_zone.x + 5, y = t2_zone.y + 5 } })
    assert.are.equal(2, #inst.game.tableau[2])

    -- Tableau to Tableau
    inst.game.tableau[3] = { { rank = 10, suit = 4, face_up = true } } -- Black 10 (Spades)
    inst:paintTo(bb, 0, 0)
    for _, z in ipairs(inst.touch_zones) do
      if z.type == "tableau" and z.index == 2 and z.card_pos == 1 then t2_zone = z break end
    end
    local t3_zone = nil
    for _, z in ipairs(inst.touch_zones) do
      if z.type == "tableau" and z.index == 3 then t3_zone = z break end
    end

    inst:onTap(nil, { pos = { x = t2_zone.x + 5, y = t2_zone.y + 5 } })
    inst:paintTo(bb, 0, 0)
    inst:onTap(nil, { pos = { x = t3_zone.x + 5, y = t3_zone.y + 5 } })
    assert.are.equal(3, #inst.game.tableau[3])

    -- Foundation to Tableau
    inst.game.foundations[1] = { { rank = 1, suit = 1, face_up = true }, { rank = 2, suit = 1, face_up = true } } -- Hearts (Red)
    inst.game.tableau[4] = { { rank = 3, suit = 4, face_up = true } } -- Spades 3 (Black)
    inst:paintTo(bb, 0, 0)
    local t4_zone = nil
    for _, z in ipairs(inst.touch_zones) do
      if z.type == "tableau" and z.index == 4 then t4_zone = z break end
    end
    inst.selected_source = { type = "foundation", index = 1 }
    inst:onTap(nil, { pos = { x = t4_zone.x + 5, y = t4_zone.y + 5 } })
    assert.are.equal(2, #inst.game.tableau[4])

    bb:free()
    UIManager.show = orig_show
    os.remove(inst.settings_path)
    os.remove(inst.save_path)
  end)

  it("should handle hold gestures on waste and tableau", function()
    local orig_show = UIManager.show
    UIManager.show = function() end

    local inst = SolitaireUI:new({
      settings_path = os.tmpname(),
      save_path = os.tmpname(),
    })

    local bb = Blitbuffer.new(inst.screen_width or 600, inst.screen_height or 800)

    inst.game.waste = { { rank = 1, suit = 2, face_up = true } } -- Ace of Diamonds
    inst.game.foundations[1] = { { rank = 1, suit = 1, face_up = true } } -- Hearts 1
    inst.game.foundations[2] = {}
    inst:paintTo(bb, 0, 0)
    local waste_zone = nil
    for _, z in ipairs(inst.touch_zones) do
      if z.type == "waste" then waste_zone = z break end
    end
    inst:onHold(nil, { pos = { x = waste_zone.x + 5, y = waste_zone.y + 5 } })
    assert.are.equal(1, #inst.game.foundations[2])

    inst.game.tableau[5] = { { rank = 1, suit = 3, face_up = true } } -- Ace of Clubs
    inst.game.foundations[3] = {}
    inst:paintTo(bb, 0, 0)
    local t5_zone = nil
    for _, z in ipairs(inst.touch_zones) do
      if z.type == "tableau" and z.index == 5 then t5_zone = z break end
    end
    inst:onHold(nil, { pos = { x = t5_zone.x + 5, y = t5_zone.y + 5 } })
    assert.are.equal(1, #inst.game.foundations[3])

    bb:free()
    UIManager.show = orig_show
    os.remove(inst.settings_path)
    os.remove(inst.save_path)
  end)

  it("should handle gameplay actions: hint, autoMove, toggleDrawMode, dialogs, win", function()
    local orig_show = UIManager.show
    local orig_schedule = UIManager.scheduleIn
    local orig_close = UIManager.close
    local shown_widgets = {}
    UIManager.show = function(self_uim, widget)
      table.insert(shown_widgets, widget)
    end
    UIManager.close = function() end
    UIManager.scheduleIn = function(self_uim, delay, fn) fn() end

    local inst = SolitaireUI:new({
      settings_path = os.tmpname(),
      save_path = os.tmpname(),
    })

    -- Test newGame recording loss when game was active
    inst.game_started = true
    inst.game.moves = 5
    inst:newGame()

    -- Test showHint when hint available vs not
    inst.game.tableau[1] = { { rank = 2, suit = 1, face_up = true } }
    inst.game.foundations[1] = { { rank = 1, suit = 1, face_up = true } }
    inst:showHint()

    inst.game.tableau = { {}, {}, {}, {}, {}, {}, {} }
    inst.game.stock = {}
    inst.game.waste = {}
    inst.game.foundations = { {}, {}, {}, {} }
    inst:showHint()

    -- Test autoMove with moves vs no moves
    inst:autoMove()

    inst.game.tableau[1] = { { rank = 1, suit = 1, face_up = true } }
    inst:autoMove()

    inst:toggleDrawMode()
    inst:toggleDrawMode()
    inst:showStats()
    inst:showLeaderboard()

    -- Test win message with new bests
    inst.stats.best_score = 0
    inst.stats.best_time = 10
    inst.stats.fewest_moves = 10
    inst.game.score = 500
    inst.game.moves = 10
    inst.game.getElapsedTime = function() return 10 end
    inst:showWinMessage()

    inst:confirmResetStats()
    inst:showMoreMenu()

    -- Trigger button dialog callbacks in confirmResetStats and showMoreMenu
    for _, w in ipairs(shown_widgets) do
      if w.buttons then
        for _, row in ipairs(w.buttons) do
          for _, btn in ipairs(row) do
            if btn.callback then
              pcall(btn.callback)
            end
          end
        end
      end
    end

    inst:onClose()
    inst:onCloseWidget()

    UIManager.show = orig_show
    UIManager.scheduleIn = orig_schedule
    UIManager.close = orig_close
    os.remove(inst.settings_path)
    os.remove(inst.save_path)
  end)
end)
