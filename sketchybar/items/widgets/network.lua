local colors = require("colors")
local settings = require("settings")
local anim = require("anim")

-- stacked up/down speeds (two labels sharing one slot), fed by the network_load C provider
local net_up = sbar.add("item", "network.up", {
  position = "center",
  icon = {
    string = "󰕒",
    color = colors.teal,
    font = { family = settings.font, size = 10.0 },
    padding_left = 8,
    padding_right = 2,
  },
  label = {
    string = "??",
    color = colors.muted,
    font = { family = settings.font, size = 10.0 },
    padding_right = 8,
  },
  y_offset = 5,
  width = 0,
  padding_left = 0, padding_right = 0,
  background = { drawing = false }, -- the bracket draws the pill
})

local net_down = sbar.add("item", "network.down", {
  position = "center",
  icon = {
    string = "󰇚",
    color = colors.primary,
    font = { family = settings.font, size = 10.0 },
    padding_left = 8,
    padding_right = 2,
  },
  label = {
    string = "??",
    color = colors.muted,
    font = { family = settings.font, size = 10.0 },
    padding_right = 8,
  },
  y_offset = -5,
  padding_left = 0, padding_right = 0,
  background = { drawing = false },
  popup = { align = "left" },
})

local net_bracket = sbar.add("bracket", "network.bracket",
  { net_up.name, net_down.name },
  { background = { color = colors.pill, corner_radius = settings.radius, height = settings.pill_height } })

net_up:subscribe("network_update", function(env)
  net_up:set({ label = env.upload })
  net_down:set({ label = env.download })
end)

-- popup: IP (click copies), router, SSID when macOS will reveal it
local ip_row = sbar.add("item", "network.ip", {
  position = "popup." .. net_down.name,
  icon = { string = "󰩟", color = colors.primary, width = 26 },
  label = { string = "…", color = colors.muted },
  background = { drawing = false, corner_radius = 10, height = settings.popup_row_height },
})
local router_row = sbar.add("item", "network.router", {
  position = "popup." .. net_down.name,
  icon = { string = "󰑩", color = colors.primary, width = 26 },
  label = { string = "…", color = colors.muted },
  background = { drawing = false },
})
local ssid_row = sbar.add("item", "network.ssid", {
  position = "popup." .. net_down.name,
  icon = { string = "󰖩", color = colors.primary, width = 26 },
  label = { string = "Wi-Fi", color = colors.muted },
  background = { drawing = false },
})
anim.row_hover(ip_row, net_down)

local current_ip = ""
ip_row:subscribe("mouse.clicked", function()
  if current_ip == "" then return end
  sbar.exec("printf '%s' '" .. current_ip .. "' | pbcopy")
  anim.text_swap(ip_row, "copied!", colors.green)
  sbar.delay(1.2, function()
    anim.text_swap(ip_row, current_ip, colors.muted)
  end)
end)

local function open_popup()
  sbar.exec("ipconfig getifaddr en0 || echo offline", function(ip)
    current_ip = tostring(ip):gsub("%s+$", "")
    ip_row:set({ label = current_ip })
    sbar.exec([[networksetup -getinfo Wi-Fi | awk -F ': ' '/^Router/ {print $2}']], function(router)
      local r = tostring(router):gsub("%s+$", "")
      router_row:set({ label = r ~= "" and r or "no router" })
      anim.popup_open(net_down, {
        { item = ip_row }, { item = router_row }, { item = ssid_row },
      })
      -- SSID is slow + often redacted on Sequoia; fill it in when it arrives
      sbar.exec([[system_profiler SPAirPortDataType 2>/dev/null | awk '/Current Network Information:/{getline; gsub(/^ +| +:.*/,""); sub(/:$/,""); print; exit}']], function(ssid)
        local s = tostring(ssid):gsub("%s+$", "")
        if s ~= "" then ssid_row:set({ label = s }) end
      end)
    end)
  end)
end

net_down:subscribe("mouse.clicked", function()
  local p = net_down:query().popup
  if p and p.drawing == "on" then
    anim.popup_close(net_down)
  else
    open_popup()
    anim.popup_ticker(net_down, 5, function()
      sbar.exec("ipconfig getifaddr en0 || echo offline", function(ip)
        current_ip = tostring(ip):gsub("%s+$", "")
        ip_row:set({ label = current_ip })
      end)
    end)
  end
end)
net_up:subscribe("mouse.clicked", function()
  local p = net_down:query().popup
  if p and p.drawing == "on" then
    anim.popup_close(net_down)
  else
    open_popup()
  end
end)
anim.guard(net_down, { router_row, ssid_row })

-- pre-warm the popup's IP/router rows at load
sbar.exec("ipconfig getifaddr en0 || echo offline", function(ip)
  current_ip = tostring(ip):gsub("%s+$", "")
  ip_row:set({ label = current_ip })
end)
sbar.exec([[networksetup -getinfo Wi-Fi | awk -F ': ' '/^Router/ {print $2}']], function(router)
  local r = tostring(router):gsub("%s+$", "")
  router_row:set({ label = r ~= "" and r or "no router" })
end)

-- hover on the shared pill
for _, it in ipairs({ net_up, net_down }) do
  it:subscribe("mouse.entered", function()
    anim.guard_cancel(net_down)
    sbar.animate("tanh", anim.EFFECT, function()
      net_bracket:set({ background = { color = colors.hover } })
    end)
  end)
  it:subscribe("mouse.exited", function()
    anim.guard_close(net_down)
    sbar.animate("tanh", anim.EFFECT, function()
      net_bracket:set({ background = { color = colors.pill } })
    end)
  end)
end
