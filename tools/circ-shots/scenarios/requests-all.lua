-- Requests, all lists: Alice's own (one taken off the market), others', and materials.
SHOT = { title = "Requests" }
dofile(SIM_DIR .. "fixtures.lua")
Setup({ wants = { [2320] = { qty = 20, price = 28 }, [14047] = { qty = 5, price = 0, off = true } } })
Slash("requests")
Advance(1)
