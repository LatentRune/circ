-- The guide part way: professions scanned and an item looked up; the arrows step back
-- to look at step 2 again.
SHOT = { title = "Guide, looking back" }
dofile(SIM_DIR .. "fixtures.lua")
StockBags()
Boot({ seenIntro = true, union = Returning().union, guide = { looked = true } })
Advance(5)
OpenProfession(TAILORING)
Slash("")
Advance(0.5)
for _, f in ipairs(ALL_FRAMES) do
  if f._normalPath and f._normalPath:find("PrevPage") and f:IsVisible() then Click(f) end
end
Advance(0.5)
