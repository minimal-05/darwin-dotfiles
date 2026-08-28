local colors = require("colors")
local settings = require("settings")
local anim = require("anim")

-- self-rendered graph (helpers/cpu_graph.py): sketchybar's graph item can't
-- stay inside the pill or color per-sample; a PIL-drawn image can do both
-- (btop-style green->yellow->red ramp per column)
local GRAPH_IMGS = { "/tmp/sketchybar_cpu_a.png", "/tmp/sketchybar_cpu_b.png" }
local cpu = sbar.add("item", "cpu", {
  position = "center",
  icon = { drawing = false },
  label = { drawing = false },
  width = 44,
  padding_left = 6,
  padding_right = 0,
  background = { drawing = false },
  popup = { align = "left" },
})
local cpu_pct = sbar.add("item", "cpu.pct", {
  position = "center",
  icon = { drawing = false },
  label = {
    string = "?%",
    font = { family = settings.font, size = 10.0 },
    color = colors.muted,
    width = 32, -- fixed: digits never change the pill's size
    align = "right",
    padding_left = 4,
    padding_right = 10,
  },
  padding_left = 0,
  padding_right = 0,
  background = { drawing = false },
})
local cpu_bracket = sbar.add("bracket", "cpu.bracket", { cpu.name, cpu_pct.name }, {
  background = { color = colors.pill, corner_radius = settings.radius, height = settings.pill_height },
})

-- system monitor popup: CPU / GPU / RAM / SSD / uptime + top processes
local stat_rows = {}
local STAT_DEFS = {
  { key = "cpu", icon = "󰻠", color = colors.blue },
  { key = "gpu", icon = "󰢮", color = colors.teal },
  { key = "ram", icon = "󰍛", color = colors.primary },
  { key = "swp", icon = "󰾴", color = colors.secondary },
  { key = "ssd", icon = "󰋊", color = colors.yellow },
  { key = "up",  icon = "󰔟", color = colors.tertiary },
}
for _, def in ipairs(STAT_DEFS) do
  stat_rows[def.key] = sbar.add("item", "cpu.stat." .. def.key, {
    position = "popup.cpu",
    icon = { string = def.icon, color = def.color, width = 26 },
    label = { string = "…", color = colors.on_surface },
    background = { drawing = false },
  })
end
local proc_header = sbar.add("item", "cpu.prochdr", {
  position = "popup.cpu",
  icon = { drawing = false },
  label = { string = "TOP PROCESSES", color = colors.secondary, font = { size = 10.0 }, padding_left = 4 },
  background = { drawing = false },
})
local proc_rows = {}
for i = 1, 3 do
  proc_rows[i] = sbar.add("item", "cpu.proc." .. i, {
    position = "popup.cpu",
    icon = { drawing = false },
    label = {
      string = "",
      font = { family = settings.font, size = 11.0 },
      color = colors.muted,
    },
    background = { drawing = false },
  })
end

local last_load = 0
local hist = {}
local flip = false

local function refresh_popup(open_after)
  stat_rows.cpu:set({ label = "CPU  " .. math.floor(last_load) .. "%" })
  sbar.exec([[ioreg -r -d 1 -w0 -c IOAccelerator 2>/dev/null | grep -o '"Device Utilization %"=[0-9]*' | head -1 | grep -o '[0-9]*$']], function(gpu)
    local g = tostring(gpu):match("%d+")
    stat_rows.gpu:set({ label = "GPU  " .. (g or "?") .. "%" })
  end)
  sbar.exec([[vm_stat | awk -v total=$(sysctl -n hw.memsize) -v ps=$(sysctl -n hw.pagesize) '/Pages active/{a=$NF} /Pages wired down/{w=$NF} /occupied by compressor/{c=$NF} END{gsub(/\./,"",a); gsub(/\./,"",w); gsub(/\./,"",c); used=(a+w+c)*ps; printf "RAM  %.1f / %.0f GB", used/1073741824, total/1073741824}']], function(ram)
    stat_rows.ram:set({ label = tostring(ram):gsub("%s+$", "") })
  end)
  sbar.exec([[sysctl -n vm.swapusage | awk '{gsub(/M/,"",$3); gsub(/M/,"",$6); printf "Swap  %.1f / %.1f GB", $6/1024, $3/1024}']], function(swp)
    stat_rows.swp:set({ label = tostring(swp):gsub("%s+$", "") })
  end)
  sbar.exec([[df -h / | awk 'NR==2 {print "SSD  "$4" free of "$2}']], function(ssd)
    stat_rows.ssd:set({ label = tostring(ssd):gsub("%s+$", "") })
  end)
  sbar.exec("uptime | sed 's/.*up /up /;s/, *[0-9]* users*.*//'", function(up)
    stat_rows.up:set({ label = tostring(up):gsub("%s+$", "") })
  end)
  sbar.exec("ps -Arco %cpu,comm | sed -n '2,4p'", function(result)
    local rows = {}
    for _, def in ipairs(STAT_DEFS) do
      rows[#rows + 1] = { item = stat_rows[def.key], icon = def.color, label = colors.on_surface }
    end
    rows[#rows + 1] = { item = proc_header, label = colors.secondary }
    local i = 0
    for line in tostring(result):gmatch("([^\n]+)") do
      i = i + 1
      if proc_rows[i] then
        proc_rows[i]:set({ label = line, drawing = true })
        rows[#rows + 1] = { item = proc_rows[i] }
      end
    end
    for j = i + 1, 3 do proc_rows[j]:set({ drawing = false }) end
    if open_after then anim.popup_open(cpu, rows) end
  end)
end

cpu:subscribe("cpu_update", function(env)
  local load = math.min(100, tonumber(env.total_load) or 0)
  last_load = load
  if #hist == 0 then -- seed on reload so the graph starts full, not empty
    for _ = 1, 24 do hist[#hist + 1] = math.floor(load) end
  end
  hist[#hist + 1] = math.floor(load)
  if #hist > 24 then table.remove(hist, 1) end
  -- alternate output files so the image cache never shows a stale frame
  flip = not flip
  local path = GRAPH_IMGS[flip and 1 or 2]
  sbar.exec(os.getenv("HOME") .. "/.config/sketchybar/helpers/cpu_graph/bin/cpu_graph " ..
    path .. " " .. table.concat(hist, " "), function(ok)
    if tostring(ok):match("ok") then
      cpu:set({ background = { drawing = true, color = colors.transparent, image = { string = path, scale = 0.5 } } })
    end
  end)
  local color = colors.blend(colors.blue, colors.red, load / 100.0)
  cpu_pct:set({ label = { string = math.floor(load) .. "%", color = color } })
end)

local function toggle_popup()
  local p = cpu:query().popup
  if p and p.drawing == "on" then
    anim.popup_close(cpu)
    return
  end
  refresh_popup(true)
  anim.popup_ticker(cpu, 3, function() refresh_popup(false) end)
end
for _, it in ipairs({ cpu, cpu_pct }) do
  it:subscribe("mouse.clicked", toggle_popup)
  it:subscribe("mouse.entered", function()
    anim.guard_cancel(cpu)
    sbar.animate("tanh", anim.EFFECT, function()
      cpu_bracket:set({ background = { color = colors.hover } })
    end)
  end)
  it:subscribe("mouse.exited", function()
    anim.guard_close(cpu)
    sbar.animate("tanh", anim.EFFECT, function()
      cpu_bracket:set({ background = { color = colors.pill } })
    end)
  end)
end
local guard_list = { proc_header }
for _, def in ipairs(STAT_DEFS) do guard_list[#guard_list + 1] = stat_rows[def.key] end
for i = 1, 3 do guard_list[#guard_list + 1] = proc_rows[i] end
anim.guard(cpu, guard_list)
refresh_popup(false) -- pre-warm the system monitor so its first open is instant
