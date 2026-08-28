local colors = require("colors")
local settings = require("settings")
local anim = require("anim")

-- Open-Meteo (auto-selects the best national model, e.g. JMA in Japan) with
-- IP geolocation; wttr.in was consistently a few degrees off.
local weather = sbar.add("item", "weather", {
  position = "center",
  update_freq = 900,
  icon = { string = "󰖐", color = colors.teal },
  label = { string = "…" },
  padding_right = 8, -- even 8px gap to the zero-padding media pill
  popup = { align = "center" },
  drawing = false, -- shown on first successful fetch
})

local WMO_ICON = {
  [0] = "󰖙", [1] = "󰖕", [2] = "󰖕", [3] = "󰖐",
  [45] = "󰖑", [48] = "󰖑",
  [51] = "󰖗", [53] = "󰖗", [55] = "󰖗", [56] = "󰖗", [57] = "󰖗",
  [61] = "󰖖", [63] = "󰖖", [65] = "󰖖", [66] = "󰖖", [67] = "󰖖",
  [71] = "󰖘", [73] = "󰖘", [75] = "󰖘", [77] = "󰖘", [85] = "󰖘", [86] = "󰖘",
  [80] = "󰖖", [81] = "󰖖", [82] = "󰖖",
  [95] = "󰖓", [96] = "󰖓", [99] = "󰖓",
}
local WMO_NAME = {
  [0] = "Clear", [1] = "Mostly clear", [2] = "Partly cloudy", [3] = "Overcast",
  [45] = "Fog", [48] = "Fog",
  [51] = "Drizzle", [53] = "Drizzle", [55] = "Drizzle", [56] = "Drizzle", [57] = "Drizzle",
  [61] = "Rain", [63] = "Rain", [65] = "Heavy rain", [66] = "Freezing rain", [67] = "Freezing rain",
  [71] = "Snow", [73] = "Snow", [75] = "Heavy snow", [77] = "Snow", [85] = "Snow showers", [86] = "Snow showers",
  [80] = "Showers", [81] = "Showers", [82] = "Heavy showers",
  [95] = "Thunderstorm", [96] = "Thunderstorm", [99] = "Thunderstorm",
}

local rows = {}
for i = 1, 5 do
  rows[i] = sbar.add("item", "weather.detail." .. i, {
    position = "popup.weather",
    icon = { drawing = false },
    label = { string = "", color = colors.muted },
    background = { drawing = false },
  })
end

local city = nil
local data = nil

local function render_popup_rows()
  if not data then return {} end
  local cur = data.current
  local code = math.floor(tonumber(cur.weather_code) or 0)
  local d = data.daily
  local lines = {
    { (city or "Here") .. "  ·  " .. (WMO_NAME[code] or "—"), colors.teal },
    { string.format("feels %.0f°  ·  %d%% humidity", cur.apparent_temperature, cur.relative_humidity_2m), colors.muted },
    { string.format("wind %.0f km/h", cur.wind_speed_10m), colors.muted },
    { string.format("today  %.0f° / %.0f°  ·  rain %d%%",
        d.temperature_2m_min[1], d.temperature_2m_max[1], d.precipitation_probability_max[1] or 0), colors.muted },
    { string.format("tomorrow  %.0f° / %.0f°  ·  rain %d%%",
        d.temperature_2m_min[2], d.temperature_2m_max[2], d.precipitation_probability_max[2] or 0), colors.muted },
  }
  local out = {}
  for i, l in ipairs(lines) do
    rows[i]:set({ label = l[1], drawing = true })
    out[#out + 1] = { item = rows[i], label = l[2] }
  end
  return out
end

local function refresh()
  sbar.exec("curl -sm 5 ipinfo.io", function(info)
    local lat, lon
    if type(info) == "table" and info.loc then
      lat, lon = tostring(info.loc):match("([%-%d%.]+),([%-%d%.]+)")
      city = info.city
    end
    if not lat then
      weather:set({ drawing = false })
      return
    end
    local url = "https://api.open-meteo.com/v1/forecast?latitude=" .. lat .. "&longitude=" .. lon ..
      "&current=temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m" ..
      "&daily=temperature_2m_max,temperature_2m_min,precipitation_probability_max&timezone=auto&forecast_days=2"
    sbar.exec("curl -sm 8 '" .. url .. "'", function(result)
      if type(result) ~= "table" or not result.current then
        weather:set({ drawing = false }) -- offline: vanish quietly
        return
      end
      data = result
      local code = math.floor(tonumber(result.current.weather_code) or 0)
      weather:set({ drawing = true })
      sbar.animate("tanh", anim.EFFECT, function()
        weather:set({
          icon = { string = WMO_ICON[code] or "󰖐" },
          label = string.format("%.0f°C", result.current.temperature_2m),
        })
      end)
      -- keep the popup fresh if it's open
      local p = weather:query().popup
      if p and p.drawing == "on" then render_popup_rows() end
    end)
  end)
end

weather:subscribe({ "routine", "forced", "system_woke" }, refresh)

weather:subscribe("mouse.clicked", function()
  local p = weather:query().popup
  if p and p.drawing == "on" then
    anim.popup_close(weather)
    return
  end
  anim.bounce(weather)
  local prow = render_popup_rows()
  if #prow > 0 then anim.popup_open(weather, prow) end
end)

anim.hover(weather, { owner = weather })
anim.guard(weather, rows)
refresh()
