-- Who buys Linen Cloth: a crafter who uses it and a member's request, with prices.
SHOT = { title = "Lookup: who buys it" }
dofile(SIM_DIR .. "fixtures.lua")
Setup()
Slash("find Linen Cloth")
Advance(1)
