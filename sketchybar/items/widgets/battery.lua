local colors = require("colors")
local settings = require("settings")
local anim = require("anim")

local battery = sbar.add("item", "battery", {
  position = "center",
  update_freq = 60,
  icon = { string = "󰁹", color = colors.green },
  label = { string = "…" },
  padding_left = 8, -- even 8px gap to the zero-padding media pill
  popup = { align = "right" },
})

local rows = {}
for i = 1, 3 do
  rows[i] = sbar.add("item", "battery.detail." .. i, {
    position = "popup.battery",
    icon = { drawing = false },
    label = { string = "", color = colors.muted },
    background = { drawing = false },
  })
end

local was_charging = nil

battery:subscribe({ "routine", "power_source_change", "system_woke", "forced" }, function()
  sbar.exec("pmset -g batt", function(result)
    local out = tostring(result)
    local pct = tonumber(out:match("(%d+)%%"))
    if not pct then
      battery:set({ drawing = false })
      return
    end
    local charging = out:match("AC Power") ~= nil

    local icon, color
    if charging then icon, color = "󰂄", colors.primary
    elseif pct > 80 then icon, color = "󰁹", colors.green
    elseif pct > 60 then icon, color = "󰂀", colors.green
    elseif pct > 40 then icon, color = "󰁾", colors.yellow
    elseif pct > 20 then icon, color = "󰁻", colors.yellow
    else icon, color = "󰁺", colors.red end

    sbar.animate("tanh", anim.COLOR, function()
      battery:set({ icon = { string = icon, color = color }, label = pct .. "%" })
    end)
    if was_charging ~= nil and charging ~= was_charging then
      anim.bounce(battery) -- little jolt when the cable state flips
    end
    was_charging = charging
    if pct <= 15 and not charging then
      -- low-battery heartbeat: one dim-and-recover pulse per tick
      sbar.animate("sin", 40, function()
        battery:set({ icon = { color = colors.with_alpha(colors.red, 0.35) } })
        battery:set({ icon = { color = colors.red } })
      end)
    end
  end)
end)

local function fill_details(open_after)
  sbar.exec("pmset -g batt", function(result)
    local out = tostring(result)
    local pct = out:match("(%d+)%%") or "?"
    local time = out:match("(%d+:%d+) remaining")
    local charging = out:match("AC Power") ~= nil
    rows[1]:set({ label = charging and "󰚥  On AC power" or "󰁹  On battery" })
    rows[2]:set({ label = "󱐋  Charge: " .. pct .. "%" .. (time and ("  ·  " .. time .. " left") or "") })
    sbar.exec("system_profiler SPPowerDataType 2>/dev/null | awk '/Cycle Count/{c=$3} /Condition/{cond=$2} END{print c\" \"cond}'", function(hw)
      local cycles, cond = tostring(hw):match("(%d+)%s+(%S+)")
      rows[3]:set({ label = "󰁪  Cycles: " .. (cycles or "?") .. "  ·  " .. (cond or "") })
      if open_after then
        anim.popup_open(battery, { { item = rows[1] }, { item = rows[2] }, { item = rows[3] } })
      end
    end)
  end)
end

battery:subscribe("mouse.clicked", function()
  local p = battery:query().popup
  if p and p.drawing == "on" then
    anim.popup_close(battery)
    return
  end
  anim.bounce(battery)
  fill_details(true)
  anim.popup_ticker(battery, 10, function() fill_details(false) end) -- live time-remaining
end)
anim.hover(battery, { owner = battery })
anim.guard(battery, rows)
fill_details(false) -- pre-warm (system_profiler takes ~2s on first open otherwise)
