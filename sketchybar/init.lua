sbar = require("sketchybar")

local CONFIG = os.getenv("HOME") .. "/.config/sketchybar"

sbar.begin_config()
require("bar")
require("default")

-- left: apple, app button, slide-out menus
require("items.apple")
require("items.front_app")
require("items.menus")

-- center band hugging the dots: [balancer][cpu][network][media][DOTS][clock][weather][battery]
-- the balancer spacer keeps the dots measured-centered on the screen
require("items.balance")
require("items.widgets.cpu")
-- rigid gap between the two bracket pills (neither can carry outer padding)
sbar.add("item", "sep.cpu.net", {
  position = "center",
  width = 8,
  icon = { drawing = false },
  label = { drawing = false },
  background = { drawing = false },
})
require("items.widgets.network")
require("items.spaces")
require("items.widgets.clock")
require("items.widgets.weather")
require("items.media")
require("items.widgets.battery")
require("items.balance_tail")

-- far right: just the control center gear
require("items.widgets.control_center")
sbar.end_config()

-- daemons: cpu + network event providers, media stream (media_change is broken on macOS 15.4+)
sbar.exec("killall cpu_load >/dev/null 2>&1; " .. CONFIG .. "/helpers/event_providers/cpu_load/bin/cpu_load cpu_update 3.0")
sbar.exec("killall network_load >/dev/null 2>&1; " .. CONFIG .. "/helpers/event_providers/network_load/bin/network_load en0 network_update 3.0")
sbar.exec(CONFIG .. "/helpers/media_stream.sh")
sbar.exec(CONFIG .. "/helpers/cc_panel/bin/cc_panel --daemon") -- pre-warm, hidden

-- bar entrance: slide down from above the screen edge
sbar.animate("tanh", 30, function()
  sbar.bar({ y_offset = 8 })
end)

sbar.event_loop()
