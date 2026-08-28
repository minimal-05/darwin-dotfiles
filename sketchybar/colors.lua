-- Material 3 dark baseline tokens (matches kitty theme)
local colors = {
  bar          = 0xf0141218, -- surface, translucent
  popup_bg     = 0xff211F26, -- surface container low
  pill         = 0xff2B2930, -- surface container
  hover        = 0xff3B3846, -- pill + 8% onSurface state layer
  primary      = 0xffD0BCFF,
  on_primary   = 0xff381E72,
  secondary    = 0xffCCC2DC,
  sec_container= 0xff4A4458,
  tertiary     = 0xffEFB8C8, -- clock accent (caelestia color-codes groups)
  on_surface   = 0xffE6E0E9,
  muted        = 0xffCAC4D0, -- on surface variant
  outline      = 0xff49454F,
  red          = 0xffF2B8B5,
  green        = 0xffA8D5A2,
  yellow       = 0xffE8C48A,
  blue         = 0xffA8C7FA,
  teal         = 0xff8FD5CB,
  transparent  = 0x00000000,
}

function colors.with_alpha(color, alpha) -- alpha 0.0..1.0
  return (color & 0x00ffffff) | (math.floor(alpha * 255.0 + 0.5) << 24)
end

function colors.blend(a, b, t) -- rgb lerp, t 0.0..1.0
  t = math.max(0, math.min(1, t))
  local function ch(x, shift) return (x >> shift) & 0xff end
  local function mix(shift)
    return math.floor(ch(a, shift) + (ch(b, shift) - ch(a, shift)) * t + 0.5)
  end
  return 0xff000000 | (mix(16) << 16) | (mix(8) << 8) | mix(0)
end

return colors
