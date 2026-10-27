-- Every getting-started step done: no guide bar, so the list shows 18 rows.
SHOT = { title = "Guide finished" }
dofile(SIM_DIR .. "fixtures.lua")
local db = Returning({ wants = { [2320] = { qty = 20, price = 28 } } })
db.guide = { looked = true, prices = true, ledger = true }
StockBags()
InstallAuctionator(AH)
Boot(db)
Advance(5)
OpenProfession(TAILORING)
Member(BOB); Member(CARA); Member(EIRA)
Advance(3)
Slash("requests")
Advance(1)
