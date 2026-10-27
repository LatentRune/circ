-- The minimap button moved to another spot, and /circ help and /circ status in chat.
SHOT = { title = "Minimap button and /circ status", chatLines = 26 }
dofile(SIM_DIR .. "fixtures.lua")
Setup({ settings = { minimapAngle = 120, buyPct = 80, margin = 10, minimap = true } })
WORLD.chat = {}
Slash("help")
Slash("status")
Advance(0.5)
