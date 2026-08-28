local colors = require("colors")

-- starts off-screen; init.lua animates y_offset to 8 after config loads
sbar.bar({
  height = 38,
  color = colors.bar,
  corner_radius = 18,
  margin = 12,
  y_offset = -60,
  blur_radius = 0, -- live blur re-renders every frame of a space swipe: hitches
  padding_left = 10,
  padding_right = 10,
  sticky = "on",
})
