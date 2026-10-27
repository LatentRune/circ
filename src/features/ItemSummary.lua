-- features/ItemSummary.lua: a short summary of one item for its tooltip (ui/Tooltip.lua): how
-- many other members buy it, sell it, carry it or make it, and the best prices. Leaves
-- out this character. Uses features/Lookup.lua.
local _, ns = ...

-- { buyers, bestOffer, sellers, lowest, holders, makers, cheapest }; prices may be nil
function ns:ItemSummary(itemID)
  local me = ns:PlayerKey()
  local s = { buyers = 0, sellers = 0, holders = 0, makers = 0 }
  for _, r in ipairs(ns.Lookup:UsedIn(itemID)) do
    if r.player ~= me then
      s.buyers = s.buyers + 1
      if r.price and r.price > 0 and (not s.bestOffer or r.price > s.bestOffer) then s.bestOffer = r.price end
    end
  end
  for _, r in ipairs(ns.Lookup:MadeBy(itemID)) do
    if r.player ~= me then
      s.makers = s.makers + 1
      if r.price and r.price > 0 and (not s.cheapest or r.price < s.cheapest) then s.cheapest = r.price end
    end
  end
  for _, r in ipairs(ns.Lookup:HasIt(itemID)) do
    if r.player ~= me then
      if r.kind == "has" then
        s.sellers = s.sellers + 1
        if r.price and r.price > 0 and (not s.lowest or r.price < s.lowest) then s.lowest = r.price end
      else
        s.holders = s.holders + 1
      end
    end
  end
  return s
end
