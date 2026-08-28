local colors = require("colors")
local settings = require("settings")
local anim = require("anim")

local volume = sbar.add("item", "volume", {
  position = "right",
  icon = { string = "󰕾", color = colors.blue },
  label = { string = "…" },
  popup = { align = "right" },
})

-- sliders need click_script: the lua subscribe path does not deliver drag events
local slider = sbar.add("slider", "volume.slider", 160, {
  position = "popup.volume",
  slider = {
    highlight_color = colors.primary,
    percentage = 50,
    background = { height = 8, corner_radius = 4, color = colors.outline },
    knob = { string = "󰝥", color = colors.primary, drawing = true },
  },
  icon = { drawing = false },
  label = { drawing = false },
  background = { drawing = false },
  click_script = [[osascript -e "set volume output volume $PERCENTAGE"]],
})

local function icon_for(vol, muted)
  if muted or vol == 0 then return "󰝟"
  elseif vol < 50 then return "󰖀"
  else return "󰕾" end
end

volume:subscribe("volume_change", function(env)
  local vol = tonumber(env.INFO) or 0
  sbar.animate("tanh", anim.EFFECT, function()
    volume:set({ icon = icon_for(vol, false), label = vol .. "%" })
    slider:set({ slider = { percentage = vol } })
  end)
end)

volume:subscribe("mouse.scrolled", function(env)
  local delta = env.INFO and tonumber(env.INFO.delta) or 0
  sbar.exec("osascript -e 'set volume output volume (output volume of (get volume settings)) " ..
    (delta > 0 and "+ " or "- ") .. math.min(math.abs(delta) * 4, 20) .. "'")
end)

-- output device list: rebuilds in place, popup stays open after switching
local function build_devices(open_after)
  sbar.exec("SwitchAudioSource -t output -c", function(current)
    current = tostring(current):gsub("%s+$", "")
    sbar.exec("SwitchAudioSource -a -t output", function(available)
      sbar.remove("/volume.device\\..*/")
      local rows = { { item = slider, label = colors.primary } }
      local i = 0
      for device in tostring(available):gmatch("([^\n]+)") do
        i = i + 1
        local is_current = device == current
        local row = sbar.add("item", "volume.device." .. i, {
          position = "popup.volume",
          icon = {
            string = is_current and "󰓃" or "",
            color = colors.primary,
            width = 24,
          },
          label = { string = device, color = is_current and colors.primary or colors.muted },
          background = {
            drawing = false,
            corner_radius = 10,
            height = settings.popup_row_height,
          },
        })
        anim.row_hover(row, volume)
        row:subscribe("mouse.clicked", function()
          -- single-quote so $/backticks in device names never expand
          sbar.exec("SwitchAudioSource -s '" .. device:gsub("'", "'\\''") .. "'", function()
            build_devices(false) -- refresh in place, keep the popup open
          end)
        end)
        rows[#rows + 1] = { item = row, label = is_current and colors.primary or colors.muted }
      end
      if open_after then anim.popup_open(volume, rows) end
    end)
  end)
end

local opening = false
volume:subscribe("mouse.clicked", function()
  local p = volume:query().popup
  if opening or (p and p.drawing == "on") then
    opening = false
    anim.popup_close(volume)
    return
  end
  opening = true
  anim.bounce(volume)
  build_devices(true)
  sbar.delay(0.5, function() opening = false end)
end)
anim.hover(volume, { owner = volume })
anim.guard(volume, { slider })

-- initial state
sbar.exec("osascript -e 'output volume of (get volume settings)'", function(vol)
  vol = tonumber(tostring(vol):match("%d+")) or 0
  volume:set({ icon = icon_for(vol, false), label = vol .. "%" })
  slider:set({ slider = { percentage = vol } })
end)
