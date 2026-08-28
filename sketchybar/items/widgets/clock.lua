local colors = require("colors")
local settings = require("settings")
local anim = require("anim")

local clock = sbar.add("item", "clock", {
  position = "center",
  update_freq = 10,
  icon = { string = "󰥔", color = colors.tertiary },
  label = { string = "…" },
  popup = { align = "center" },
})

local last_clock = ""
clock:subscribe({ "routine", "forced", "system_woke" }, function()
  local s = os.date("%H:%M · %A, ") .. (os.date("%m/%d"):gsub("^0", ""):gsub("/0", "/"))
  if s ~= last_clock then -- skip no-op redraws (fires every 10s, changes per minute)
    last_clock = s
    clock:set({ label = s })
  end
end)

-- calendar dropdown, generated in lua: banner, week/day meta, year progress,
-- moon phase, and a grid with today inline-marked (•26)
local function popup_row(name, size, color)
  return sbar.add("item", "clock." .. name, {
    position = "popup.clock",
    icon = { drawing = false },
    label = {
      string = "",
      font = { family = settings.font, size = size },
      color = color,
      padding_left = 14,
      padding_right = 14,
    },
    background = { drawing = false },
  })
end

local banner = sbar.add("item", "clock.banner", {
  position = "popup.clock",
  icon = { string = "󰃭", color = colors.tertiary, width = 28, font = { size = 15.0 } },
  label = {
    string = "",
    color = colors.on_surface,
    font = { family = settings.font, style = "Bold", size = 13.0 },
  },
  background = { drawing = false },
})
local meta_row = popup_row("meta", 11.0, colors.secondary)
local year_row = popup_row("year", 11.0, colors.teal)
local moon_row = popup_row("moon", 11.0, colors.yellow)
local head_row = popup_row("head", 13.0, colors.secondary)
local week_rows = {}
for i = 1, 6 do
  week_rows[i] = popup_row("week." .. i, 13.0, colors.muted)
end

local MOONS = { "🌑", "🌒", "🌓", "🌔", "🌕", "🌖", "🌗", "🌘" }
local MOON_NAMES = {
  "New moon", "Waxing crescent", "First quarter", "Waxing gibbous",
  "Full moon", "Waning gibbous", "Last quarter", "Waning crescent",
}

local function build_rows()
  local t = os.date("*t")
  banner:set({ label = os.date("%A, %B %d") })

  -- meta: ISO week + day-of-year
  local doy = tonumber(os.date("%j"))
  local ylen = (t.year % 4 == 0 and (t.year % 100 ~= 0 or t.year % 400 == 0)) and 366 or 365
  meta_row:set({ label = string.format("week %d  ·  day %d of %d", tonumber(os.date("%V")), doy, ylen) })

  -- year progress bar
  local pct = doy / ylen
  local filled = math.floor(pct * 12 + 0.5)
  year_row:set({ label = t.year .. "  " .. string.rep("█", filled) .. string.rep("░", 12 - filled) ..
    string.format("  %d%%", math.floor(pct * 100 + 0.5)) })

  -- moon phase (synodic approximation from the 2000-01-06 new moon)
  local days_since = (os.time() - 947182440) / 86400
  local phase = (days_since % 29.53059) / 29.53059
  local idx = (math.floor(phase * 8 + 0.5) % 8) + 1
  moon_row:set({ label = MOONS[idx] .. "  " .. MOON_NAMES[idx] })

  head_row:set({ label = "Su Mo Tu We Th Fr Sa" })

  -- month grid, today marked inline as •N (3-char cells keep columns aligned)
  local first_wd = tonumber(os.date("%w", os.time({ year = t.year, month = t.month, day = 1, hour = 12 })))
  local days_in_month = os.date("*t", os.time({ year = t.year, month = t.month + 1, day = 0, hour = 12 })).day
  local rows = {
    { item = banner, icon = colors.tertiary, label = colors.on_surface },
    { item = meta_row, label = colors.secondary },
    { item = year_row, label = colors.teal },
    { item = moon_row, label = colors.yellow },
    { item = head_row, label = colors.secondary },
  }
  local day = 1
  for w = 1, 6 do
    if day > days_in_month then
      week_rows[w]:set({ drawing = false })
    else
      local cells = {}
      local has_today = false
      for wd = 0, 6 do
        if (w == 1 and wd < first_wd) or day > days_in_month then
          cells[#cells + 1] = "   "
        else
          if day == t.day then
            cells[#cells + 1] = string.format("•%2d", day)
            has_today = true
          else
            cells[#cells + 1] = string.format(" %2d", day)
          end
          day = day + 1
        end
      end
      week_rows[w]:set({ drawing = true, label = table.concat(cells) })
      rows[#rows + 1] = { item = week_rows[w], label = has_today and colors.primary or colors.muted }
    end
  end
  return rows
end

clock:subscribe("mouse.clicked", function()
  local p = clock:query().popup
  if p and p.drawing == "on" then
    anim.popup_close(clock)
    return
  end
  anim.bounce(clock)
  anim.popup_open(clock, build_rows())
end)

anim.hover(clock, { owner = clock })
anim.guard(clock, { banner, meta_row, year_row, moon_row, head_row })
anim.guard(clock, week_rows)
