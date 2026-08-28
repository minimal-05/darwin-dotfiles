local colors = require("colors")
local settings = require("settings")
local anim = require("anim")

-- Apple menu, styled identically to the app-menu dropdowns: plain rows,
-- shortcut hints appended inline, hover pill, content-hugging width.
local apple = sbar.add("item", "apple", {
  position = "left",
  icon = { string = "󰀵", color = colors.primary, font = { size = 16.0 }, padding_right = 10 },
  label = { drawing = false },
  popup = { align = "left" },
})

local n_rows = 0
local all_rows = {}
local function menu_row(text)
  n_rows = n_rows + 1
  local row = sbar.add("item", "apple.menu." .. n_rows, {
    position = "popup.apple",
    icon = { drawing = false },
    label = { string = text, color = colors.muted, max_chars = 36 },
    background = {
      drawing = false,
      corner_radius = 10,
      height = settings.popup_row_height,
    },
  })
  anim.row_hover(row, apple)
  all_rows[#all_rows + 1] = { item = row }
  return row
end

local about = menu_row("About This Mac")
local sys_settings = menu_row("System Settings…")
local app_store = menu_row("App Store…")
local force_quit = menu_row("Force Quit…   ⌥⌘⎋")
local sleep = menu_row("Sleep")
local restart = menu_row("Restart…")
local shutdown = menu_row("Shut Down…")
local lock = menu_row("Lock Screen   ⌃⌘Q")
local logout = menu_row("Log Out…   ⇧⌘Q")
local dark = menu_row("Toggle Dark Mode")
local reload = menu_row("Reload Bar")

-- personalize: front app in Force Quit, full name in Log Out
sbar.exec("id -F", function(name)
  local full = tostring(name):gsub("%s+$", "")
  if full ~= "" then logout:set({ label = "Log Out " .. full .. "…   ⇧⌘Q" }) end
end)
-- store only; the label is applied lazily at open so app switches (and
-- workspace swipes) never trigger a bar redraw here
local current_app = nil
apple:subscribe("front_app_switched", function(env)
  current_app = env.INFO
end)

local function close()
  anim.popup_close(apple)
end

local actions = {
  -- About This Mac panel moved into an extension on modern macOS
  { about, [[open "x-apple.systempreferences:com.apple.SystemProfiler.AboutExtension"]] },
  { sys_settings, [[open -a "System Settings"]] },
  { app_store, [[open -a "App Store"]] },
  -- ⌥⌘⎋ opens the Force Quit dialog
  { force_quit, [[osascript -e 'tell application "System Events" to key code 53 using {command down, option down}']] },
  { sleep, "pmset sleepnow" },
  { restart, [[osascript -e 'tell application "System Events" to restart']] },
  { shutdown, [[osascript -e 'tell application "System Events" to shut down']] },
  { lock, [[osascript -e 'tell application "System Events" to keystroke "q" using {command down, control down}']] },
  { logout, [[osascript -e 'tell application "System Events" to log out']] },
  { dark, [[osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to not dark mode']] },
  { reload, "sketchybar --reload" },
}
for _, a in ipairs(actions) do
  a[1]:subscribe("mouse.clicked", function()
    close()
    sbar.exec(a[2])
  end)
end

apple:subscribe("mouse.clicked", function()
  local p = apple:query().popup
  if p and p.drawing == "on" then
    close()
  else
    if current_app then
      force_quit:set({ label = "Force Quit " .. current_app .. "…   ⌥⌘⎋" })
    end
    anim.popup_open(apple, all_rows)
  end
end)
anim.hover(apple, { owner = apple })
