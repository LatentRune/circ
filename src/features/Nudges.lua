-- features/Nudges.lua: finds ledger members who pay more than a vendor or the Auction House
-- at the two places gold usually leaks out: selling to a vendor and posting an auction.
-- Setting: nudges ("Vendor and Auction House reminders"). Fires "VendorOffers" and
-- "AuctionOffer"; ui/Nudges.lua says them in chat.
local _, ns = ...

-- A merchant window opened: every bag item a member pays more for than the vendor does
ns:On("MERCHANT_SHOW", function()
  if not CircDB.settings.nudges then return end
  local seen, offers = {}, {}
  for bag = 0, 4 do
    for slot = 1, (ns.Compat.NumSlots(bag) or 0) do
      local itemID = ns.Compat.ItemIDAt(bag, slot)
      if itemID and not seen[itemID] then
        seen[itemID] = true
        local price, player = ns.Lookup:BestOffer(itemID, false)
        if price then
          local vendor = select(11, GetItemInfo(itemID)) or 0
          if price > vendor then offers[#offers + 1] = { itemID = itemID, price = price, player = player, vendor = vendor } end
        end
      end
    end
  end
  if #offers > 0 then ns:Fire("VendorOffers", offers) end
end)

-- An item was put in the auction slot: the best member offer for it, against the market
ns:On("NEW_AUCTION_UPDATE", function()
  if not CircDB.settings.nudges then return end
  local name = GetAuctionSellItemInfo()
  if not name then return end
  local _, link = GetItemInfo(name)
  local itemID = ns:ItemIDFromLink(link)
  if not itemID then return end
  local price, player = ns.Lookup:BestOffer(itemID, false)
  if price then
    ns:Fire("AuctionOffer", { itemID = itemID, price = price, player = player, market = ns.Prices:Market(itemID) })
  end
end)
