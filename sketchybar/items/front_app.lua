local colors = require("colors")
local settings = require("settings")
local anim = require("anim")
local app_icons = require("helpers.app_icons")

local function sh_quote(s)
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

local front_app = sbar.add("item", "front_app", {
  position = "left",
  icon = {
    font = settings.app_font_big,
    string = app_icons["Default"] or ":default:",
    color = colors.primary,
    padding_right = 10, -- symmetric: icon-only pill
  },
  label = { drawing = false },
})

front_app:subscribe("front_app_switched", function(env)
  front_app:set({ icon = { string = app_icons[env.INFO] or app_icons["Default"] or ":default:" } })
end)

-- left-click: slide the app menus out/in; right-click: app switcher popup
local opening = false
front_app:subscribe("mouse.clicked", function(env)
  if env.BUTTON ~= "right" then
    anim.bounce(front_app)
    sbar.trigger("toggle_menus")
    return
  end
  local p = front_app:query().popup
  if opening or (p and p.drawing == "on") then
    opening = false
    anim.popup_close(front_app)
    return
  end
  opening = true
  sbar.remove("/front_app.app\\..*/")
  -- linefeed delimiter: app names can contain commas, never newlines
  sbar.exec([[osascript -e 'set text item delimiters to linefeed' -e 'tell application "System Events" to get (name of processes where background only is false) as text']], function(result)
    if not opening then return end
    opening = false
    local rows = {}
    local i = 0
    for raw in string.gmatch(tostring(result), "([^\n]+)") do
      local app = raw:gsub("^%s+", ""):gsub("%s+$", "")
      if app ~= "" then
        i = i + 1
        local row = sbar.add("item", "front_app.app." .. i, {
          position = "popup.front_app",
          icon = {
            font = settings.app_font,
            string = app_icons[app] or app_icons["Default"] or ":default:",
            color = colors.primary,
            width = 28,
          },
          label = { string = app, color = colors.muted },
          background = {
            drawing = false,
            corner_radius = 10,
            height = settings.popup_row_height,
          },
        })
        anim.row_hover(row, front_app)
        local as_escaped = app:gsub("\\", "\\\\"):gsub('"', '\\"')
        row:subscribe("mouse.clicked", function()
          sbar.exec("osascript -e " .. sh_quote('tell application "' .. as_escaped .. '" to activate'))
          front_app:set({ popup = { drawing = false } })
        end)
        rows[#rows + 1] = { item = row }
      end
    end
    anim.popup_open(front_app, rows)
  end)
end)
anim.hover(front_app, { owner = front_app })
