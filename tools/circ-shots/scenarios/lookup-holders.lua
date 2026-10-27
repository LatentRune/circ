-- Who has Brawler Gloves: Cara lists it for sale; Eira and Alice only carry one.
SHOT = { title = "Lookup: who has it" }
dofile(SIM_DIR .. "fixtures.lua")
Setup()
Slash("find Brawler Gloves")
Advance(0.5)
Click(ButtonNamed("Who has it"))
Advance(1)
