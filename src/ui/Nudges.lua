-- ui/Nudges.lua: says in chat what features/Nudges.lua found: members who pay more than
-- the vendor, when a merchant window opens, and the best member offer, when an item goes
-- into the Auction House slot (also shown in the middle of the screen).
-- Setting: nudges ("Vendor and Auction House reminders").
local _, ns = ...

local function offerLine(o, compareLabel, compare)
  local _, link = GetItemInfo(o.itemID)
  local line = (link or ns:ItemName(o.itemID)) .. ": " .. ns:ShortName(o.player) .. " pays " .. ns:Money(o.price)
  if compare and compare > 0 then line = line .. " (" .. compareLabel .. " " .. ns:Money(compare) .. ")" end
  return line
end

ns:Listen("VendorOffers", function(offers)
  ns:Print("Before you vendor, ledger members buy:")
  for i = 1, math.min(#offers, 6) do DEFAULT_CHAT_FRAME:AddMessage("   " .. offerLine(offers[i], "vendor", offers[i].vendor)) end
  if #offers > 6 then DEFAULT_CHAT_FRAME:AddMessage("   ...and " .. (#offers - 6) .. " more (/circ)") end
end)

ns:Listen("AuctionOffer", function(o)
  local line = "Ledger: " .. offerLine(o, "AH", o.market)
  UIErrorsFrame:AddMessage(line, 0.2, 1, 0.6)
  ns:Print(line)
end)
