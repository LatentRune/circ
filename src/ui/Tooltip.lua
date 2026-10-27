-- ui/Tooltip.lua: up to four "Ledger:" lines on every item tooltip: who buys it and the
-- best offer, who sells it and from what price, whose bags hold it, and who makes it.
-- Setting: tooltip ("Ledger lines on item tooltips"). The numbers come from
-- features/ItemSummary.lua; core/Compat.lua hooks the tooltips.
local _, ns = ...

local function addLines(tooltip, itemID)
  if not itemID or not CircDB or not CircDB.settings.tooltip then return end
  local s = ns:ItemSummary(itemID)
  if s.buyers > 0 then
    tooltip:AddLine("|cff33ff99Ledger:|r bought by " .. s.buyers .. (s.bestOffer and (", best offer " .. ns:Money(s.bestOffer)) or ""), 1, 1, 1)
  end
  if s.sellers > 0 then
    tooltip:AddLine("|cff33ff99Ledger:|r for sale by " .. s.sellers .. (s.lowest and (", from " .. ns:Money(s.lowest)) or ""), 1, 1, 1)
  end
  if s.holders > 0 then
    tooltip:AddLine("|cff33ff99Ledger:|r in the bags of " .. s.holders, 1, 1, 1)
  end
  if s.makers > 0 then
    tooltip:AddLine("|cff33ff99Ledger:|r made by " .. s.makers .. (s.cheapest and (", from " .. ns:Money(s.cheapest)) or ""), 1, 1, 1)
  end
end

local function fromTooltip(tooltip)
  local _, link = tooltip:GetItem()
  addLines(tooltip, ns:ItemIDFromLink(link))
end

ns:Listen("Ready", function() ns.Compat.HookItemTooltips(fromTooltip) end)
