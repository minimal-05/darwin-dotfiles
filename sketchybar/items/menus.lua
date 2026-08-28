local colors = require("colors")
local settings = require("settings")
local anim = require("anim")

-- The frontmost app's real menus, collapsed by default: clicking the app name
-- slides them out (label-width animation) and folds them back. Each menu opens
-- OUR popup (entries via the AX helper); the native bar never drops down.
local MENUS_BIN = os.getenv("HOME") .. "/.config/sketchybar/helpers/menus/bin/menus"
local MAX = 10
local MAX_ENTRIES = 18

sbar.add("event", "toggle_menus")
sbar.add("event", "menus_opened")
sbar.add("event", "menus_closed")

local expanded = false
local menu_items = {}
local menu_ids = {} -- bar slot -> real AX menu index (slots skip title-like entries)

local function close_all_popups()
  for j = 1, MAX do
    anim.popup_close(menu_items[j])
  end
end

local function open_menu(i)
  local id = menu_ids[i] or i
  sbar.remove("/menu.entry\\..*/")
  sbar.exec(MENUS_BIN .. " -i " .. id, function(out)
    local rows = {}
    local k = 0
    for line in tostring(out):gmatch("([^\n]+)") do
      local idx, title, shortcut = line:match("^(%d+)\t([^\t]+)\t?(.*)$")
      if idx and k < MAX_ENTRIES then
        k = k + 1
        local text = title
        if shortcut and shortcut ~= "" then
          text = title .. "   " .. shortcut
        end
        local row = sbar.add("item", "menu.entry." .. k, {
          position = "popup.menu." .. i,
          icon = { drawing = false },
          label = { string = text, color = colors.muted, max_chars = 36 },
          background = {
            drawing = false,
            corner_radius = 10,
            height = settings.popup_row_height,
          },
        })
        anim.row_hover(row, menu_items[i])
        local entry_id = tonumber(idx)
        row:subscribe("mouse.clicked", function()
          sbar.exec(MENUS_BIN .. " -p " .. id .. " " .. entry_id)
          close_all_popups()
        end)
        rows[#rows + 1] = { item = row }
      end
    end
    if k == 0 then
      -- lazily-built menu: fall back to dropping the native one
      sbar.exec(MENUS_BIN .. " -s " .. id)
      return
    end
    anim.popup_open(menu_items[i], rows)
  end)
end

for i = 1, MAX do
  local menu = sbar.add("item", "menu." .. i, {
    position = "left",
    drawing = false,
    icon = { drawing = false },
    label = {
      string = "",
      color = colors.muted,
      font = { family = settings.font, size = 12.0 }, -- native menu bar density
      padding_left = 5,
      padding_right = 5,
    },
    background = { drawing = false },
    padding_left = 0,
    padding_right = 0,
    popup = { align = "left" },
  })
  menu:subscribe("mouse.entered", function()
    anim.guard_cancel(menu)
    sbar.animate("tanh", anim.EFFECT, function()
      menu:set({ label = { color = colors.on_surface } })
    end)
    -- Apple behavior: sliding along open menus moves the open dropdown
    for j = 1, MAX do
      if j ~= i then
        local p = menu_items[j]:query().popup
        if p and p.drawing == "on" then
          menu_items[j]:set({ popup = { drawing = false } })
          open_menu(i)
          break
        end
      end
    end
  end)
  menu:subscribe("mouse.exited", function()
    anim.guard_close(menu)
    sbar.animate("tanh", anim.EFFECT, function()
      menu:set({ label = { color = i == 1 and colors.primary or colors.muted } })
    end)
  end)
  menu:subscribe("mouse.clicked", function()
    local p = menu:query().popup
    if p and p.drawing == "on" then
      anim.popup_close(menu)
      return
    end
    close_all_popups()
    open_menu(i)
  end)
  menu_items[i] = menu
end

-- reveal: one layout pass (drawing + final width immediately), then staggered
-- color fade-ins — animating width forced a full bar relayout per item per
-- frame, which is what made the slide feel rough
local function update_menus()
  sbar.exec(MENUS_BIN .. " -l", function(list)
    if not expanded then return end
    local oi = 0
    local i = 0
    for line in tostring(list):gmatch("([^\n]+)") do
      oi = oi + 1
      -- skip window-title impostors some apps publish into the menu bar
      if #line <= 32 and not line:match("^::") and not line:match("✳") then
        i = i + 1
        if i <= MAX then
          menu_ids[i] = oi
          local item = menu_items[i]
          local target = i == 1 and colors.primary or colors.muted
          item:set({
            drawing = true,
            label = {
              string = line,
              width = "dynamic",
              color = colors.with_alpha(target, 0.0),
              font = { style = i == 1 and "Bold" or "Regular" },
            },
          })
          sbar.animate("tanh", math.min(anim.EFFECT + i * 2, 26), function()
            item:set({ label = { color = target } })
          end)
        end
      end
    end
    if i == 0 then
      -- AX permission missing: reading menus needs sketchybar in Accessibility
      menu_items[1]:set({
        drawing = true,
        label = { string = "󰍜 grant Accessibility to sketchybar (click)", width = "dynamic", color = colors.yellow },
        click_script = [[open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"]],
      })
      i = 1
    else
      menu_items[1]:set({ click_script = "" })
    end
    for j = i + 1, MAX do menu_items[j]:set({ drawing = false }) end
  end)
end

local function fold_menus()
  close_all_popups()
  for i = 1, MAX do
    local target = i == 1 and colors.primary or colors.muted
    sbar.animate("tanh", anim.EFFECT, function()
      menu_items[i]:set({ label = { color = colors.with_alpha(target, 0.0) } })
    end)
  end
  sbar.delay(0.22, function()
    if expanded then return end -- reopened mid-fold
    for i = 1, MAX do menu_items[i]:set({ drawing = false }) end
  end)
end

local controller = sbar.add("item", "menus.controller", { drawing = false, updates = true })
controller:subscribe("toggle_menus", function()
  expanded = not expanded
  if expanded then
    sbar.trigger("menus_opened") -- media pill yields the space
    update_menus()
  else
    fold_menus()
    sbar.trigger("menus_closed")
  end
end)
controller:subscribe("front_app_switched", function()
  -- collapsed menus can't have open popups: skip the 10-item close storm
  -- that was firing on every workspace swipe
  if not expanded then return end
  close_all_popups()
  update_menus()
end)
