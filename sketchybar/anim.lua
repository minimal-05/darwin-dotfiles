-- M3 Expressive motion vocabulary (end-4/Caelestia timings), mapped to sketchybar curves.
-- Durations in frames @60Hz. Rule: spatial for what moves, effect for what fades,
-- color for state sweeps. Hover NEVER resizes (resize = full bar relayout per frame).
local colors = require("colors")
local settings = require("settings")

local anim = {
  SPATIAL = 22, -- ~366ms unfold/moves
  EFFECT  = 10, -- ~166ms fades/content
  COLOR   = 16, -- ~266ms color sweeps
}

-- Popup close guard: `mouse.exited.global` is unreliable on macOS, so popups
-- close via plain exit events with a grace period — leaving any guarded part
-- schedules the close, touching any guarded part cancels it.
local guard_gen = {}
function anim.guard_cancel(owner)
  guard_gen[owner.name] = (guard_gen[owner.name] or 0) + 1
end
function anim.guard_close(owner, delay)
  guard_gen[owner.name] = (guard_gen[owner.name] or 0) + 1
  local my = guard_gen[owner.name]
  sbar.delay(delay or 1.0, function()
    if guard_gen[owner.name] ~= my then return end
    anim.popup_close(owner) -- fade out like the app menus, not a hard hide
  end)
end
-- attach guard hover to rows that have no other mouse subscriptions
function anim.guard(owner, items)
  for _, it in ipairs(items) do
    it:subscribe("mouse.entered", function() anim.guard_cancel(owner) end)
    it:subscribe("mouse.exited", function() anim.guard_close(owner) end)
  end
end

-- M3 state layer: color-only fade (8% onSurface overlay feel). No size change.
-- opts.owner: this item owns a popup — hovering keeps it open, leaving closes it.
function anim.hover(item, opts)
  local base = opts and opts.base or colors.pill
  local owner = opts and opts.owner
  item:subscribe("mouse.entered", function()
    if owner then anim.guard_cancel(owner) end
    sbar.animate("tanh", anim.EFFECT, function()
      item:set({ background = { color = colors.hover } })
    end)
  end)
  item:subscribe("mouse.exited", function()
    if owner then anim.guard_close(owner) end
    sbar.animate("tanh", anim.EFFECT, function()
      item:set({ background = { color = base } })
    end)
  end)
end

-- clickBounce: y_offset keyframes (no relayout), overshoot then settle
function anim.bounce(item)
  sbar.animate("sin", 16, function()
    item:set({ y_offset = 3 })
    item:set({ y_offset = 0 })
  end)
end

-- The app-menu vocabulary, applied to every popup: rows appear at their final
-- position and fade in with a light stagger; closing fades out, then hides.
function anim.cascade(rows)
  for i, r in ipairs(rows) do
    local ic = r.icon or colors.primary
    local lc = r.label or colors.muted
    r.item:set({
      y_offset = 0,
      icon = { color = colors.with_alpha(ic, 0.0) },
      label = { color = colors.with_alpha(lc, 0.0) },
    })
    sbar.animate("tanh", math.min(anim.EFFECT + i * 2, 26), function()
      r.item:set({ icon = { color = ic }, label = { color = lc } })
    end)
  end
end

local open_rows = {}
local close_gen = {}

function anim.popup_open(owner, rows)
  anim.popup_open_instant(owner, rows)
end

-- instant open: contents fully visible immediately (for content that is
-- pre-warmed and should never read as loading); close still fades
function anim.popup_open_instant(owner, rows)
  close_gen[owner.name] = (close_gen[owner.name] or 0) + 1
  open_rows[owner.name] = rows
  if rows then
    for _, r in ipairs(rows) do
      r.item:set({
        icon = { color = r.icon or colors.primary },
        label = { color = r.label or colors.muted },
      })
    end
  end
  owner:set({ popup = { drawing = true } })
end

-- fade the rows out, then hide — the same fold the app menus do
function anim.popup_close(owner)
  local rows = open_rows[owner.name]
  if not rows then
    owner:set({ popup = { drawing = false } })
    return
  end
  close_gen[owner.name] = (close_gen[owner.name] or 0) + 1
  local my = close_gen[owner.name]
  for _, r in ipairs(rows) do
    local ic = r.icon or colors.primary
    local lc = r.label or colors.muted
    sbar.animate("tanh", anim.EFFECT, function()
      r.item:set({
        icon = { color = colors.with_alpha(ic, 0.0) },
        label = { color = colors.with_alpha(lc, 0.0) },
      })
    end)
  end
  sbar.delay(0.2, function()
    if close_gen[owner.name] ~= my then return end -- reopened mid-fade
    owner:set({ popup = { drawing = false } })
  end)
end

-- Re-run fn every `secs` while owner's popup stays open (one live ticker per owner)
local tickers = {}
function anim.popup_ticker(owner, secs, fn)
  local gen = (tickers[owner.name] or 0) + 1
  tickers[owner.name] = gen
  local function tick()
    if tickers[owner.name] ~= gen then return end
    local p = owner:query().popup
    if p and p.drawing == "on" then
      fn()
      sbar.delay(secs, tick)
    end
  end
  sbar.delay(secs, tick)
end

-- M3 content swap: out up 150ms, swap, in from below 166ms
function anim.text_swap(item, new_label, color)
  color = color or colors.on_surface
  sbar.animate("tanh", 9, function()
    item:set({ label = { y_offset = 5, color = colors.with_alpha(color, 0.0) } })
  end)
  sbar.delay(0.12, function()
    item:set({ label = { string = new_label, y_offset = -5 } })
    sbar.animate("tanh", anim.EFFECT, function()
      item:set({ label = { y_offset = 0, color = color } })
    end)
  end)
end

function anim.row_hover(row, owner)
  row:subscribe("mouse.entered", function()
    if owner then anim.guard_cancel(owner) end
    -- color set here, NOT at creation: a background color auto-enables
    -- drawing, which left every row's hover pill permanently on
    row:set({ background = { drawing = true, color = colors.hover } })
  end)
  row:subscribe("mouse.exited", function()
    if owner then anim.guard_close(owner) end
    row:set({ background = { drawing = false } })
  end)
end

return anim
