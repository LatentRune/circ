-- Typing in the search box: item and member suggestions under it.
SHOT = { title = "Search suggestions" }
dofile(SIM_DIR .. "fixtures.lua")
Setup()
Slash("")
Advance(0.5)
Type(CircSearchBox, "lin")
Advance(0.5)
