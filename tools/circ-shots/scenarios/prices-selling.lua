-- Selling from the bags: shift-click the gloves on the Prices tab, then the Selling view.
SHOT = { title = "Prices: selling" }
dofile(SIM_DIR .. "fixtures.lua")
Setup({ chars = { ["Alice-Realm"] = { professions = {}, recipes = {},
  stock = { [4306] = { price = 150 }, [12359] = { price = 2600, off = true } } } } })
Slash("prices")
Advance(0.5)
WORLD.shiftDown = true
HandleModifiedItemClick("|cff1eff00|Hitem:720::::::::60:::::|h[Brawler Gloves]|h|r")
WORLD.shiftDown = false
Advance(0.5)
Click(ButtonNamed("Selling"))
Advance(1)
