local colors = require("colors")
local anim = require("anim")

-- Control Center is a native grid panel (helpers/cc_panel, Swift) — Apple's CC
-- layout in the bar's M3 theme. The binary self-toggles: second launch closes it.
local PANEL = os.getenv("HOME") .. "/.config/sketchybar/helpers/cc_panel/bin/cc_panel"

local cc = sbar.add("item", "control_center", {
  position = "right",
  icon = { string = "󰕮", color = colors.secondary, padding_right = 10 },
  label = { drawing = false },
  click_script = PANEL,
})

cc:subscribe("mouse.clicked", function()
  anim.bounce(cc)
end)

anim.hover(cc)
