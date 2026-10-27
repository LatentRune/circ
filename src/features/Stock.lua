-- features/Stock.lua: items this character lists for sale, such as BoE gear or spare
-- materials. A listing is just an item and a price; the quantity is however many tradeable
-- copies are in the bags right now, so a listing drops out of the ledger once the item is
-- gone. Also counts the bags for features/Bags.lua. Listed from the Prices tab.
local _, ns = ...
local S = {}
ns.Stock = S

-- Tradeable (not soulbound) copies of every item in the bags: { [itemID] = count }.
-- noJunk leaves out gray (poor quality) items.
function S:BagCounts(noJunk)
  local counts = {}
  for bag = 0, 4 do
    for slot = 1, (ns.Compat.NumSlots(bag) or 0) do
      local itemID, count, bound, quality = ns.Compat.SlotInfo(bag, slot)
      if itemID and not bound and not (noJunk and quality == 0) then
        counts[itemID] = (counts[itemID] or 0) + count
      end
    end
  end
  return counts
end

function S:List() return ns:CharDB().stock end

function S:Count(itemID) return self.counts and self.counts[itemID] or 0 end

-- List an item. Fails when there is no tradeable copy in the bags.
function S:Add(itemID)
  self.counts = self:BagCounts()
  if self:Count(itemID) == 0 then
    ns:Print("No tradeable", ns:ItemName(itemID), "in your bags. Soulbound items can't be sold.")
    return false
  end
  local list = self:List()
  if not list[itemID] then
    -- Start from my price for a craft, else the Auction House price, else "ask"
    list[itemID] = { price = CircDB.overrides.sell[itemID] or ns.Prices:Market(itemID) or 0 }
    ns:Print("Selling", ns:ItemName(itemID), "- set the price on the Prices tab.")
  end
  ns:Fire("DataChanged")
  return true
end

function S:Remove(itemID)
  self:List()[itemID] = nil
  ns:Fire("DataChanged")
end

function S:SetPrice(itemID, copper)
  local entry = self:List()[itemID]
  if entry then
    entry.price = copper or 0
    ns:Fire("DataChanged")
  end
end

-- Listings with copies in the bags, as published in my record: { [itemID] = { qty, price } }
function S:Published()
  local out = {}
  for itemID, entry in pairs(self:List()) do
    local n = self:Count(itemID)
    if n > 0 and not entry.off then out[itemID] = { qty = n, price = entry.price or 0 } end
  end
  return out
end

-- Recount after bag changes; publish only when a listed item's count changed
local function recount()
  local before = S.counts or {}
  S.counts = S:BagCounts()
  if ns.Bags then ns.Bags:Update() end
  for itemID in pairs(S:List()) do
    if (before[itemID] or 0) ~= S:Count(itemID) then
      ns:Fire("DataChanged")
      return
    end
  end
end

local pending = false
ns:On("BAG_UPDATE_DELAYED", function()
  if pending then return end
  pending = true
  ns:After(1, function() pending = false; recount() end)
end)
ns:Listen("Ready", function() ns:After(2, recount) end)
