local colors = require("colors")
local anim = require("anim")

-- M3 workspace dots, dead-center: the active space stretches into a lavender
-- pill. Slots are pre-created; visibility tracks yabai's real space count live
-- (yabai signals trigger spaces_refresh on create/destroy).
local MAX = 10
local GAP = 24 -- breathing room between the dot cluster and its neighbors
local selected_sid = 1
local space_count = 0
local spaces = {}

sbar.add("event", "spaces_refresh")

local function add_space(sid)
  local space = sbar.add("space", "space." .. sid, {
    space = sid,
    position = "center",
    drawing = false,
    icon = { drawing = false },
    -- size via label.width: item-level width on space items desyncs layout
    label = { string = "", width = 14, padding_left = 0, padding_right = 0 },
    background = { color = colors.outline, height = 10, corner_radius = 5 },
    padding_left = 3,
    padding_right = 3,
  })

  local was_selected = false
  space:subscribe("space_change", function(env)
    local selected = env.SELECTED == "true"
    if selected == was_selected then return end -- 8 of 10 dots: no-op, no redraw
    was_selected = selected
    if selected then selected_sid = sid end
    -- animated morph: the instant width snap shifted the whole center band
    -- ~20px mid-swipe, which read as a hitch (refresh churn that once
    -- corrupted animated widths is gone, so this is safe again)
    sbar.animate("tanh", anim.SPATIAL, function()
      space:set({
        label = { width = selected and 34 or 14 },
        background = { color = selected and colors.primary or colors.outline },
      })
    end)
  end)

  space:subscribe("mouse.clicked", function(env)
    if env.BUTTON == "right" then
      sbar.exec("open -b com.apple.exposelauncher")
    else
      sbar.exec("yabai -m space --focus " .. sid .. " 2>/dev/null")
    end
  end)

  space:subscribe("mouse.scrolled", function(env)
    local delta = env.INFO and tonumber(env.INFO.delta) or 0
    if delta > 0 then
      sbar.exec("yabai -m space --focus prev 2>/dev/null || yabai -m space --focus last 2>/dev/null")
    elseif delta < 0 then
      sbar.exec("yabai -m space --focus next 2>/dev/null || yabai -m space --focus first 2>/dev/null")
    end
  end)

  space:subscribe("mouse.entered", function()
    if selected_sid ~= sid then
      sbar.animate("tanh", anim.EFFECT, function()
        space:set({ background = { color = colors.muted } })
      end)
    end
  end)
  space:subscribe("mouse.exited", function()
    if selected_sid ~= sid then
      sbar.animate("tanh", anim.EFFECT, function()
        space:set({ background = { color = colors.outline } })
      end)
    end
  end)

  return space
end

for sid = 1, MAX do spaces[sid] = add_space(sid) end

-- always re-asserts full geometry (a corrective pass, not just a diff) and
-- forces a relayout — sketchybar space items drift out of sync otherwise
local function refresh_count()
  sbar.exec("yabai -m query --spaces", function(list)
    local count = type(list) == "table" and #list or 0
    if count == 0 then return end
    space_count = count
    for sid = 1, MAX do
      spaces[sid]:set({
        drawing = sid <= count,
        label = { width = sid == selected_sid and 34 or 14 },
        padding_left = sid == 1 and GAP or 3,
        padding_right = sid == count and GAP or 3,
      })
    end
  end)
end

-- NOTE: never subscribe this to "forced" — refresh_count runs --update,
-- which fires "forced", which would loop the event thread into a hang
local observer = sbar.add("item", "spaces.count_observer", { drawing = false, updates = true })
observer:subscribe({ "spaces_refresh", "system_woke" }, refresh_count)
refresh_count()
