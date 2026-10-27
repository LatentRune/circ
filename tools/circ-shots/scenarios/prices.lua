-- Prices with Auctionator: suggested prices in gray, highest first.
SHOT = { title = "Prices" }
dofile(SIM_DIR .. "fixtures.lua")
Setup({ overrides = { buy = {}, sell = { [2570] = 500 } } })
Slash("prices")
Advance(1)
