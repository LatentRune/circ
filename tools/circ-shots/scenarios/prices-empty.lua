-- Prices with no price addon and nothing scanned yet.
SHOT = { title = "Prices, nothing scanned" }
dofile(SIM_DIR .. "fixtures.lua")
Setup(nil, { noScan = true, noPrices = true })
Slash("prices")
Advance(1)
