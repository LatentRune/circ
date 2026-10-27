-- Who makes Linen Cloak: Cara (online) and Alice herself, with skill and price.
SHOT = { title = "Lookup: who makes it" }
dofile(SIM_DIR .. "fixtures.lua")
Setup()
Slash("find Linen Cloak")
Advance(0.5)
Click(ButtonNamed("Who makes it"))
Advance(1)
