local colors = require("colors")
local settings = require("settings")
local anim = require("anim")

sbar.add("event", "media_update")

local ART = "/tmp/sketchybar_artwork.png"

-- fixed-width ⏮ ⏯ ⏭ pill: the bar NEVER resizes for media; all detail
-- (artwork, title, position) lives in the hover dropdown
local media_back = sbar.add("item", "media.back", {
  position = "center",
  icon = { string = "󰒮", color = colors.muted, width = 22, align = "center", padding_left = 6, padding_right = 0 },
  label = { drawing = false },
  background = { drawing = false },
  padding_left = 0, padding_right = 0,
  drawing = false,
  click_script = "media-control previous-track",
})

local media_icon = sbar.add("item", "media.icon", {
  position = "center",
  icon = { string = "󰝚", color = colors.primary, width = 24, align = "center", padding_left = 0, padding_right = 0 },
  label = { drawing = false },
  background = { drawing = false },
  padding_left = 0, padding_right = 0,
  drawing = false,
  click_script = "media-control toggle-play-pause",
})

local media_fwd = sbar.add("item", "media.fwd", {
  position = "center",
  icon = { string = "󰒭", color = colors.muted, width = 22, align = "center", padding_left = 0, padding_right = 6 },
  label = { drawing = false },
  background = { drawing = false },
  padding_left = 0, padding_right = 0,
  drawing = false,
  click_script = "media-control next-track",
})

local media_bracket = sbar.add("bracket", "media.bracket",
  { media_back.name, media_icon.name, media_fwd.name },
  {
    background = {
      color = colors.pill,
      corner_radius = settings.radius,
      height = settings.pill_height,
    },
    popup = { align = "center", horizontal = false },
  })

-- dropdown: artwork + track details
local art_row = sbar.add("item", "media.art", {
  position = "popup." .. media_bracket.name,
  icon = { drawing = false },
  label = { drawing = false },
  background = { image = { scale = 0.55 }, color = colors.transparent },
  width = 170,
})
-- text rows share the artwork's width with centered labels, so the whole
-- dropdown reads as one centered column
local function detail_row(name, color)
  return sbar.add("item", "media." .. name, {
    position = "popup.media.bracket",
    width = 170,
    icon = { drawing = false },
    label = {
      string = "",
      color = color,
      max_chars = 19,
      width = 170,
      align = "center",
      padding_left = 0,
      padding_right = 0,
    },
    background = { drawing = false },
  })
end
local title_row = detail_row("title", colors.on_surface)
local time_row = detail_row("time", colors.muted)

local function mmss(s)
  s = math.floor(tonumber(s) or 0)
  return string.format("%d:%02d", s // 60, s % 60)
end

local state = { playing = false, title = "", artist = "", has_art = false }
local last_art_title = nil

local function set_drawing(on)
  media_back:set({ drawing = on })
  media_icon:set({ drawing = on })
  media_fwd:set({ drawing = on })
end

-- decode + resize + round the corners in one python pass; exits silent on no art
local function fetch_artwork()
  sbar.exec("rm -f " .. ART .. "; media-control get | python3 -c '" ..
    "import json,sys,base64,io\n" ..
    "from PIL import Image, ImageDraw\n" ..
    "d=json.load(sys.stdin)\n" ..
    "a=d.get(\"artworkData\") if d else None\n" ..
    "if not a: sys.exit(1)\n" ..
    "im=Image.open(io.BytesIO(base64.b64decode(a))).convert(\"RGB\")\n" ..
    "s=min(im.size)\n" ..
    "im=im.crop(((im.size[0]-s)//2,(im.size[1]-s)//2,(im.size[0]+s)//2,(im.size[1]+s)//2)).resize((309,309))\n" ..
    "mask=Image.new(\"L\",im.size,0)\n" ..
    "ImageDraw.Draw(mask).rounded_rectangle([0,0,im.size[0]-1,im.size[1]-1],radius=26,fill=255)\n" ..
    "im=im.convert(\"RGBA\")\n" ..
    "im.putalpha(mask)\n" ..
    "im.save(\"" .. ART .. "\")\n" ..
    "print(\"done\")'",
  function(result)
    state.has_art = tostring(result):match("done") ~= nil
    if state.has_art then
      art_row:set({ drawing = true, background = { image = { string = ART, scale = 0.55 } } })
    else
      art_row:set({ drawing = false })
    end
  end)
end

local function update_time()
  sbar.exec("media-control get --no-artwork --now", function(d)
    if type(d) == "table" and d.duration then
      time_row:set({ label = mmss(d.elapsedTimeNow or d.elapsedTime) .. " / " .. mmss(d.duration), drawing = true })
    else
      time_row:set({ drawing = false })
    end
  end)
end

-- hover opens the dropdown; the guard closes it when the pointer leaves
local function open_popup()
  local p = media_bracket:query().popup
  if p and p.drawing == "on" then return end
  local text = state.title .. (state.artist ~= "" and ("  ·  " .. state.artist) or "")
  title_row:set({ label = text })
  fetch_artwork()
  update_time()
  anim.popup_open_instant(media_bracket, {
    { item = title_row, label = colors.on_surface },
    { item = time_row },
  })
  anim.popup_ticker(media_bracket, 1, update_time)
end

media_bracket:subscribe("media_update", function()
  sbar.exec("cat /tmp/sketchybar_media.json 2>/dev/null", function(result)
    local d = type(result) == "table" and (result.payload or result) or nil
    if not d or not d.title then
      state.title = ""
      state.playing = false
      media_bracket:set({ popup = { drawing = false } })
      set_drawing(false)
      return
    end
    set_drawing(true)
    state.title = d.title
    state.artist = d.artist or ""
    state.playing = d.playing == true
    media_icon:set({ icon = { string = state.playing and "󰏤" or "󰐊" } })
    -- refresh dropdown contents in place if it's open
    local p = media_bracket:query().popup
    if p and p.drawing == "on" then
      title_row:set({ label = state.title .. (state.artist ~= "" and ("  ·  " .. state.artist) or "") })
    end
    if state.title ~= last_art_title then -- only on actual track change
      last_art_title = state.title
      fetch_artwork() -- pre-warm so the first hover shows art instantly
    end
  end)
end)

-- hover intent: the dropdown only opens after the pointer settles for a beat,
-- so skimming across the pill never flashes it
local hover_gen = 0
for _, it in ipairs({ media_back, media_icon, media_fwd }) do
  it:subscribe("mouse.entered", function()
    anim.guard_cancel(media_bracket)
    hover_gen = hover_gen + 1
    local my = hover_gen
    sbar.delay(0.35, function()
      if hover_gen ~= my then return end
      open_popup()
    end)
  end)
  it:subscribe("mouse.exited", function()
    hover_gen = hover_gen + 1
    anim.guard_close(media_bracket)
  end)
end
anim.guard(media_bracket, { art_row, title_row, time_row })

media_icon:subscribe("mouse.clicked", function()
  anim.bounce(media_icon)
end)
