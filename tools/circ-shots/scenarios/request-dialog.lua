-- Looking up Runecloth and pressing Request opens the request dialog, prefilled.
SHOT = { title = "Request dialog" }
dofile(SIM_DIR .. "fixtures.lua")
Setup()
Slash("find Runecloth")
Advance(0.5)
Click(ButtonNamed("Request"))
Advance(0.5)
