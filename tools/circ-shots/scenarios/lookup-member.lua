-- A member's profile: type a member's name, press Enter on the suggestion.
SHOT = { title = "Lookup: a member" }
dofile(SIM_DIR .. "fixtures.lua")
Setup()
Slash("")
Advance(0.5)
Type(CircSearchBox, "Cara")
Advance(0.2)
PressEnter(CircSearchBox)
Advance(0.5)
