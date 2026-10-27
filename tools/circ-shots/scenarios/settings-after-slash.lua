-- Settings open while the player types /circ tooltip off: the checkbox should follow.
SHOT = { title = "Settings after /circ tooltip off" }
dofile(SIM_DIR .. "fixtures.lua")
Setup()
Slash("settings")
Advance(1)
Slash("tooltip off")
Advance(1)
