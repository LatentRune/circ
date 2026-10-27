-- Visiting a vendor with items members pay more for: the nudge lines in chat.
SHOT = { title = "Vendor nudge" }
dofile(SIM_DIR .. "fixtures.lua")
Setup()
FireEvent("MERCHANT_SHOW")
Advance(0.5)
