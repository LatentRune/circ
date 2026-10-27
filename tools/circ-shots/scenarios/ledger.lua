-- The Ledger tab, connected: members by class, gold traded this week, and trades, one of
-- them reported by one side only.
SHOT = { title = "Ledger" }
dofile(SIM_DIR .. "fixtures.lua")
Setup()
Trade({ a = "Bob", b = "Cara", aPaid = 62000, ago = 3600 })
Trade({ a = "Cara", b = "Eira", bPaid = 4500, ago = 86400 })
Trade({ a = "Bob", b = "Eira", aPaid = 1200, ago = 600, oneSided = true })
Advance(1)
Slash("ledger")
Advance(1)
