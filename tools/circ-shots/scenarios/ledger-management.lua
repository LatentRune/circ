-- Ledger management on: invite and create boxes, with a name that's too short.
SHOT = { title = "Ledger management" }
dofile(SIM_DIR .. "fixtures.lua")
Setup({ settings = { advanced = true } })
Slash("ledger")
Advance(0.5)
Type(CircUnionBox, "SMI")
Advance(0.5)
