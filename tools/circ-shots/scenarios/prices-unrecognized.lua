-- A profession window whose recipes Circ can't identify (no recipe links, nothing in the
-- bundled list): the Prices tab says so and where to report it.
SHOT = { title = "Prices, recipes not recognized" }
dofile(SIM_DIR .. "fixtures.lua")
Setup(nil, { noScan = true })
OpenProfession({ name = "Tailoring", rank = 10, max = 75, recipes = {
  { name = "Mystery Weave" }, { name = "Odd Stitching" },
} })
Slash("prices")
Advance(1)
