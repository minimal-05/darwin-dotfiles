-- tail spacer for the centering loop (see balance.lua); must be the LAST
-- center item so it can push the band leftward
sbar.add("item", "balance.tail", {
  position = "center",
  width = 0,
  icon = { drawing = false },
  label = { drawing = false },
  background = { drawing = false },
})
