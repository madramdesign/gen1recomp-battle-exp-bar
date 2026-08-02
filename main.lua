-- Gen 3+ style battle EXP bar under the player's HP chrome.
-- Uses the official battle.overlay hook (Cookbook R39 pattern).

return function(mod)
  local Growth = require("src.pokemon.Growth")
  local Font = require("src.render.Font")
  local HudTiles = require("src.render.HudTiles")
  local PaletteFX = require("src.render.PaletteFX")

  local EXP_X, EXP_Y, EXP_W = 80, 89, 67
  local WIDE_EXP_X, WIDE_EXP_Y, WIDE_SEGS = 208, 88, 10
  local HOLD_FRAMES = 30
  local BLUE = { 56 / 255, 144 / 255, 240 / 255, 1 }
  local BLACK = { 0, 0, 0, 1 }

  -- Tiny "XP" glyph (8x8), same idea as later-gen HUD chrome.
  local XP_ROWS = {
    "oooooooo",
    "oooooooo",
    "oxxoxoxx",
    "ooxxooxx",
    "ooxxooxx",
    "oxoxxoxx",
    "oooooooo",
    "oooooooo",
  }

  mod.options:define({
    {
      key = "style",
      label = "EXP BAR STYLE",
      type = "choice",
      default = "blue",
      choices = {
        { "BLUE", "blue" },
        { "BLACK", "black" },
        { "OFF", "off" },
      },
      description = "Color of the battle experience bar (or hide it).",
    },
  })

  local function styleColor()
    local style = mod.options:get("style")
    if style == "black" then return BLACK end
    if style == "blue" then return BLUE end
    return nil
  end

  local function targetPixels(battle)
    local mon = battle.player and battle.player.mon
    local def = mon and battle.data.pokemon[mon.species]
    if not def then return 0 end
    local cap = (battle.data.constants and battle.data.constants.levelCap) or 100
    if mon.level >= cap then return EXP_W end
    local cur = Growth.expForLevel(def.growthRate, mon.level, battle.data.growth_rates)
    local nxt = Growth.expForLevel(def.growthRate, mon.level + 1, battle.data.growth_rates)
    local need = nxt - cur
    if need <= 0 then return 0 end
    local progress = math.max(0, math.min(need, (mon.exp or 0) - cur))
    return math.floor(progress * EXP_W / need)
  end

  -- Per-battle animation state (weak keys so finished battles GC).
  local states = setmetatable({}, { __mode = "k" })

  local function animatedPixels(battle)
    local mon = battle.player and battle.player.mon
    local target = targetPixels(battle)
    local state = states[battle]
    if not state then
      state = {
        mon = mon,
        pixels = target,
        level = mon and mon.level,
        phase = nil,
        cycles = 0,
        frame = battle.frame,
      }
      states[battle] = state
      return target
    end

    if state.mon ~= mon or state.pixels == nil then
      state.mon = mon
      state.pixels = target
      state.level = mon and mon.level
      state.phase = nil
      state.cycles = 0
      state.frame = battle.frame
      return target
    end

    if state.frame == battle.frame then return state.pixels end
    state.frame = battle.frame

    local level = mon and mon.level or state.level
    if level and state.level and level > state.level then
      state.cycles = (state.cycles or 0) + (level - state.level)
      state.level = level
      if not state.phase then state.phase = "fill_level" end
    elseif level and level ~= state.level then
      state.level = level
    end

    if state.phase == "fill_level" then
      state.pixels = math.min(EXP_W, state.pixels + 1)
      if state.pixels == EXP_W then
        state.phase = "hold_level"
        state.hold = HOLD_FRAMES
      end
    elseif state.phase == "hold_level" then
      if state.hold and state.hold > 0 then
        state.hold = state.hold - 1
      else
        state.cycles = math.max(0, (state.cycles or 1) - 1)
        local cap = (battle.data.constants and battle.data.constants.levelCap) or 100
        if mon and mon.level >= cap then
          state.phase = nil
          state.pixels = EXP_W
          state.cycles = 0
        else
          state.pixels = 0
          state.phase = state.cycles > 0 and "fill_level" or "after_level"
        end
      end
    elseif state.phase == "after_level" then
      state.pixels = math.min(target, state.pixels + 1)
      if state.pixels >= target then state.phase = nil end
    elseif state.pixels < target then
      state.pixels = math.min(target, state.pixels + 1)
    elseif state.pixels > target then
      state.pixels = math.max(target, state.pixels - 1)
    end

    return state.pixels
  end

  local xpImage
  local function drawXpTile(x, y)
    local g = love.graphics
    if xpImage == nil then
      xpImage = false
      if love.image and love.image.newImageData and g.newImage then
        local data = love.image.newImageData(8, 8)
        for py, row in ipairs(XP_ROWS) do
          for px = 1, 8 do
            if row:sub(px, px) == "x" then
              data:setPixel(px - 1, py - 1, 0, 0, 0, 1)
            end
          end
        end
        xpImage = g.newImage(data)
        xpImage:setFilter("nearest", "nearest")
      end
    end
    if xpImage then
      g.setColor(1, 1, 1, 1)
      g.draw(xpImage, x, y)
      return
    end
    g.setColor(0, 0, 0, 1)
    for py, row in ipairs(XP_ROWS) do
      for px = 1, 8 do
        if row:sub(px, px) == "x" then
          g.rectangle("fill", x + px - 1, y + py - 1, 1, 1)
        end
      end
    end
  end

  local function clipForMenu(phase, x, width, origin)
    local nativeEnd = phase == "moveSelect" and 88
      or phase == "mimicSelect" and 128
    if not nativeEnd then return x, width end
    local coverEnd = origin + nativeEnd
    if x < coverEnd then
      width = width - (coverEnd - x)
      x = coverEnd
    end
    return x, width
  end

  local function drawWide(px, color, sx, sy)
    local g = love.graphics
    sx, sy = sx or 0, sy or 0
    g.setShader()
    g.setColor(1, 1, 1, 1)
    g.rectangle("fill", 184 + sx, 88 + sy, 120, 16)

    local border = Font.BORDER
    Font.drawCode(border.v, 184 + sx, 88 + sy)
    Font.drawCode(border.v, 296 + sx, 88 + sy)
    Font.drawCode(border.bl, 184 + sx, 96 + sy)
    Font.drawCode(border.br, 296 + sx, 96 + sy)
    for x = 192, 288, 8 do
      Font.drawCode(border.h, x + sx, 96 + sy)
    end

    g.setColor(0, 0, 0, 1)
    drawXpTile(192 + sx, WIDE_EXP_Y + sy)
    HudTiles.tile(0x62, 200 + sx, WIDE_EXP_Y + sy)

    local fill = math.floor(px * WIDE_SEGS * 8 / EXP_W)
    for i = 0, WIDE_SEGS - 1 do
      local segment = math.min(8, math.max(0, fill - i * 8))
      HudTiles.tile(segment >= 8 and 0x6B or 0x63 + segment,
        WIDE_EXP_X + i * 8 + sx, WIDE_EXP_Y + sy)
    end
    HudTiles.tile(HudTiles.capTile(),
      WIDE_EXP_X + WIDE_SEGS * 8 + sx, WIDE_EXP_Y + sy)

    if fill > 0 then
      g.setColor(color[1], color[2], color[3], color[4])
      g.rectangle("fill", WIDE_EXP_X + sx, WIDE_EXP_Y + 3 + sy, fill, 2)
      if PaletteFX.markTrueColor then
        PaletteFX.markTrueColor(WIDE_EXP_X + sx, WIDE_EXP_Y + 3 + sy, fill, 2)
      end
    end
  end

  local function shakeOffset(battle)
    local fx = battle.fx
    local sx = fx and fx.shakeX or 0
    local sy = fx and fx.shakeY or 0
    if sx == 0 and sy == 0 and fx and fx.shake and fx.shake > 0 then
      sx = battle.frame % 4 < 2 and 2 or -2
    end
    return sx, sy
  end

  mod.hooks:wrap("battle.overlay", function(next, battle)
    next(battle)

    local color = styleColor()
    if not color or not battle then return end
    if battle.safari or battle.demo or battle.showPlayerBack then return end
    if battle.blankForAskName then return end
    if (battle.introSlide or 0) ~= 0 then return end
    if not battle.player or not battle.player.mon then return end

    local px = animatedPixels(battle)
    local sx, sy = shakeOffset(battle)

    if battle.wideLayout and battle:wideLayout() then
      drawWide(px, color, sx, sy)
      return
    end

    if px <= 0 then return end
    local x = EXP_X + EXP_W - px + sx
    local y = EXP_Y + sy
    x, px = clipForMenu(battle.phase, x, px, sx)
    if px <= 0 then return end

    love.graphics.setShader()
    love.graphics.setColor(color[1], color[2], color[3], color[4])
    love.graphics.rectangle("fill", x, y, px, 2)
    if PaletteFX.markTrueColor then
      PaletteFX.markTrueColor(x, y, px, 2)
    end
  end)

  mod.log:info("battle EXP bar ready (style=%s)", tostring(mod.options:get("style")))
end
