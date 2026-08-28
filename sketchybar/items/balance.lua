local anim = require("anim")

-- Closed-loop centering: sketchybar centers the whole center band, not the
-- dots. Two invisible spacers — head (created here, first in the band) and
-- tail (balance_tail.lua, last in the band) — are resized until the measured
-- midpoint of the workspace dots sits on the screen's midline.
local pad = sbar.add("item", "balance.pad", {
  position = "center",
  width = 0,
  update_freq = 6,
  icon = { drawing = false },
  label = { drawing = false },
  background = { drawing = false },
})

local head_w, tail_w = 0, 0
local MAX_PAD = 700
local W_cache = nil
local w_ticks = 0

local function measure(W)
    local first, last
    for sid = 1, 16 do
      local ok, q = pcall(sbar.query, "space." .. sid)
      if not ok or type(q) ~= "table" or not q.bounding_rects then break end
      local r = q.bounding_rects["display-1"]
      -- hidden slots park at -9999 and must not poison the measurement
      if r and q.geometry and q.geometry.drawing == "on" and r.origin[1] > -1000 then
        local x, w = r.origin[1], r.size[1]
        if not first or x < first then first = x end
        if not last or x + w > last then last = x + w end
      end
    end
    if not first then return end
    local err = ((first + last) / 2) - (W / 2)
    if math.abs(err) < 3 then return end -- deadband against jitter

    if err > 0 then -- dots too far right: shrink head, then grow tail
      local delta = math.floor(2 * err + 0.5)
      local dec = math.min(head_w, delta)
      head_w = head_w - dec
      tail_w = math.min(MAX_PAD, tail_w + (delta - dec))
    else -- dots too far left: shrink tail, then grow head
      local delta = math.floor(-2 * err + 0.5)
      local dec = math.min(tail_w, delta)
      tail_w = tail_w - dec
      head_w = math.min(MAX_PAD, head_w + (delta - dec))
    end
    -- INSTANT set: animating the correction made the loop re-measure its own
    -- motion and oscillate forever (dots visibly sliding around)
    pad:set({ width = head_w })
    sbar.set("balance.tail", { width = tail_w })
end

local function rebalance()
  -- the display width almost never changes: cache it, re-fetch rarely
  w_ticks = w_ticks + 1
  if W_cache and w_ticks % 20 ~= 1 then
    measure(W_cache)
    return
  end
  sbar.exec("sketchybar --query displays", function(displays)
    if type(displays) ~= "table" or not displays[1] or not displays[1].frame then return end
    W_cache = displays[1].frame.w
    measure(W_cache)
  end)
end

pad:subscribe({ "routine", "forced" }, rebalance)
-- react quickly to the things that change cluster widths
pad:subscribe({ "media_update", "menus_opened", "menus_closed", "space_change", "spaces_refresh", "front_app_switched" }, function()
  sbar.delay(0.8, rebalance)
end)
