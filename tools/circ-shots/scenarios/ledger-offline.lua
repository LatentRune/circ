-- The Ledger tab while the channel can't be reached: a Connect row at the top.
SHOT = { title = "Ledger, not connected" }
dofile(SIM_DIR .. "fixtures.lua")
WORLD.channelsWork = false
StockBags()
Boot(Returning())
Advance(10)
Slash("ledger")
Advance(1)
