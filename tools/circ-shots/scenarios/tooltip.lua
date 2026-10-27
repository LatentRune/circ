-- Hovering Linen Cloth in the bags: the ledger lines Circ adds to the item tooltip.
SHOT = { title = "Item tooltip", chat = false }
dofile(SIM_DIR .. "fixtures.lua")
Setup()
HoverItem(2589)
Advance(0.2)
