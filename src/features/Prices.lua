-- features/Prices.lua: market values from an installed price addon (Auctionator, TSM or
-- Aux), and this crafter's own prices:
--   buy  = what I pay for a reagent    (default: buyPct% of market)
--   sell = what I charge for a product (default: reagent market cost plus margin%, else market)
-- Prices the player sets on the Prices tab (ui/Prices.lua) are kept in CircDB.overrides.
-- Settings: buyPct and margin (Settings tab, or /circ pct and /circ margin).
local _, ns = ...
local P = {}
ns.Prices = P

-- Market value in copper, or nil. Tries Auctionator, TSM, then Aux.
function P:Market(itemID)
  if Auctionator and Auctionator.API and Auctionator.API.v1 and Auctionator.API.v1.GetAuctionPriceByItemID then
    local ok, v = pcall(Auctionator.API.v1.GetAuctionPriceByItemID, "Circ", itemID)
    if ok and v and v > 0 then return v, "Auctionator" end
  end
  if TSM_API and TSM_API.GetCustomPriceValue then
    local ok, v = pcall(TSM_API.GetCustomPriceValue, "DBMarket", "i:" .. itemID)
    if ok and v and v > 0 then return v, "TSM" end
  end
  if aux and aux.history and aux.history.value then
    local ok, v = pcall(aux.history.value, itemID .. ":0")
    if ok and v and v > 0 then return v, "Aux" end
  end
  return nil
end

function P:Source()
  if Auctionator and Auctionator.API then return "Auctionator" end
  if TSM_API then return "TSM" end
  if aux then return "Aux" end
  return nil
end

local function round(copper)
  -- Round to the silver above 1 gold, to the copper below
  if copper >= 10000 then return math.floor(copper / 100 + 0.5) * 100 end
  return math.floor(copper + 0.5)
end

function P:Buy(itemID)
  local o = CircDB.overrides.buy[itemID]
  if o ~= nil then return o or nil, "set" end
  local m = self:Market(itemID)
  if m then return round(m * CircDB.settings.buyPct / 100), "auto" end
  return nil
end

function P:Sell(recipeID)
  local def = ns.Recipes:Get(recipeID)
  if not def or not def.p or def.p == 0 then return nil end
  local o = CircDB.overrides.sell[def.p]
  if o ~= nil then return o or nil, "set" end
  local cost, complete = 0, true
  for itemID, count in pairs(def.r) do
    local m = self:Market(itemID)
    if not m then complete = false break end
    cost = cost + m * count
  end
  if complete and cost > 0 then
    return round(cost * (1 + CircDB.settings.margin / 100) / math.max(def.c or 1, 1)), "auto"
  end
  local m = self:Market(def.p)
  if m then return round(m), "auto" end
  return nil
end

-- Override a price. value = copper, false = "not buying/selling", nil = back to automatic
function P:SetBuy(itemID, value) CircDB.overrides.buy[itemID] = value; ns:Fire("DataChanged") end
function P:SetSell(itemID, value) CircDB.overrides.sell[itemID] = value; ns:Fire("DataChanged") end
