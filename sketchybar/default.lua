local colors = require("colors")
local settings = require("settings")

sbar.default({
  background = {
    color = colors.pill,
    corner_radius = settings.radius,
    height = settings.pill_height,
  },
  icon = {
    font = { family = settings.font, style = "Regular", size = 14.0 },
    color = colors.on_surface,
    padding_left = 10,
    padding_right = 4,
  },
  label = {
    font = { family = settings.font, style = "Regular", size = 13.0 },
    color = colors.on_surface,
    padding_left = 4,
    padding_right = 10,
  },
  padding_left = settings.paddings,
  padding_right = settings.paddings,
  popup = {
    background = {
      color = colors.popup_bg,
      corner_radius = 16,
      border_width = 2,
      border_color = colors.outline,
      shadow = { drawing = true },
    },
    blur_radius = 30,
    y_offset = 6,
    height = 30, -- compact rows; without this popup lines inherit a huge default
  },
})
