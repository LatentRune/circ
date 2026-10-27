-- Settings with a price addon installed: checkboxes and the two percentages.
SHOT = { title = "Settings" }
dofile(SIM_DIR .. "fixtures.lua")
Setup({ settings = { buyPct = 80, margin = 10, nudges = true, tooltip = true, minimap = true,
  showSelf = true, advanced = false, shareBags = false } })
Slash("settings")
Advance(1)
