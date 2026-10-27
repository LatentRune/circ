-- features/Lookup.lua: answers the Lookup tab's questions from members' records: who uses
-- an item and pays what, who makes it, who has it, everything one member offers, and the
-- names to suggest while typing. Also the best offer for an item (features/Nudges.lua).
-- Setting: showSelf ("Show me in lookups").
local _, ns = ...
local Lk = {}
ns.Lookup = Lk

-- Bundled BoE gear and recipe names (BoeData.lua), added to the bundled item names so
-- Lookup can suggest items nobody has listed yet
if type(ns.BoeData) == "string" then
  ns.ItemNames = ns.ItemNames or {}
  for id, name in ns.BoeData:gmatch("(%d+)\t([^\n]+)") do
    id = tonumber(id)
    if not ns.ItemNames[id] then ns.ItemNames[id] = name end
  end
  ns.BoeData = nil
end

local function sortRows(rows, highFirst)
  table.sort(rows, function(x, y)
    if x.online ~= y.online then return x.online end
    local px, py = x.price or 0, y.price or 0
    if px ~= py then
      if highFirst then return px > py end
      if px == 0 then return false end
      if py == 0 then return true end
      return px < py
    end
    return x.player < y.player
  end)
  return rows
end

-- Members who use the item as a reagent, plus members with a buy order for it
function Lk:UsedIn(itemID)
  local rows = {}
  local recipes = ns.Recipes.usedIn[itemID] or {}
  local hideSelf = CircDB.settings.showSelf == false and ns:PlayerKey()
  for player, p in pairs(ns.Records:All()) do
    if player == hideSelf then p = {} end
    local best
    for rid in pairs(recipes) do
      if p.recipes and p.recipes[rid] then best = best or rid end
    end
    if best then
      rows[#rows + 1] = {
        player = player, kind = "uses", recipeID = best, price = p.buy and p.buy[itemID],
        online = ns.Records:IsOnline(player) and true or false,
      }
    end
    local want = p.wants and p.wants[itemID]
    if want then
      rows[#rows + 1] = {
        player = player, kind = "wants", qty = want.qty, price = want.price,
        online = ns.Records:IsOnline(player) and true or false,
      }
    end
  end
  return sortRows(rows, true)
end

-- Members who can craft the item
function Lk:MadeBy(itemID)
  local rows = {}
  local recipes = ns.Recipes.madeBy[itemID] or {}
  local hideSelf = CircDB.settings.showSelf == false and ns:PlayerKey()
  for player, p in pairs(ns.Records:All()) do
    if player == hideSelf then p = {} end
    for rid in pairs(recipes) do
      if p.recipes and p.recipes[rid] then
        local def = ns.Recipes:Get(rid)
        rows[#rows + 1] = {
          player = player, kind = "makes", recipeID = rid, price = p.sell and p.sell[itemID],
          skill = def and p.profs and p.profs[def.prof],
          online = ns.Records:IsOnline(player) and true or false,
        }
        break
      end
    end
  end
  return sortRows(rows, false)
end

-- Members who have the item: listed for sale (kind "has", with a price) or just carried in
-- their bags (kind "bag"). Listings come first.
function Lk:HasIt(itemID)
  local rows, listed = {}, {}
  local hideSelf = CircDB.settings.showSelf == false and ns:PlayerKey()
  for player, p in pairs(ns.Records:All()) do
    local e = player ~= hideSelf and p.stock and p.stock[itemID]
    if e then
      listed[player] = true
      rows[#rows + 1] = { player = player, kind = "has", qty = e.qty, price = e.price,
        online = ns.Records:IsOnline(player) and true or false }
    end
  end
  local bagRows = {}
  for player, n in pairs(ns.Bags and ns.Bags:Holders(itemID) or {}) do
    if player ~= hideSelf and not listed[player] then
      bagRows[#bagRows + 1] = { player = player, kind = "bag", qty = n,
        online = ns.Records:IsOnline(player) and true or false }
    end
  end
  sortRows(rows, false)
  sortRows(bagRows, false)
  for _, r in ipairs(bagRows) do rows[#rows + 1] = r end
  return rows
end

-- Items members list for sale, which may not be in the bundled names
local function stockItems()
  local set = {}
  for _, p in pairs(ns.Records:All()) do
    for itemID in pairs(p.stock or {}) do set[itemID] = true end
  end
  return set
end

-- Best price another member pays for the item, for nudges and tooltips
function Lk:BestOffer(itemID, onlineOnly)
  local bestPrice, bestPlayer
  for _, row in ipairs(self:UsedIn(itemID)) do
    if row.player ~= ns:PlayerKey() and row.price and row.price > 0 and (row.online or not onlineOnly) then
      if not bestPrice or row.price > bestPrice then bestPrice, bestPlayer = row.price, row.player end
    end
  end
  return bestPrice, bestPlayer
end

-- Find an item ID from a link, an ID, or a (partial) name among items the ledger knows about
function Lk:Resolve(text)
  if not text or text == "" then return nil end
  local id = ns:ItemIDFromLink(text) or tonumber(text)
  if id then return id end
  local name = GetItemInfo(text)
  if name then
    local _, link = GetItemInfo(text)
    return ns:ItemIDFromLink(link)
  end
  -- Bundled names first (no item cache needed), then items only scans or members taught us
  local needle = text:lower()
  local partial
  local function try(itemID, n)
    if not n then return false end
    n = n:lower()
    if n == needle then return true end
    if n:find(needle, 1, true) and (not partial or n < partial[2]) then partial = { itemID, n } end
    return false
  end
  for itemID, n in pairs(ns.ItemNames) do
    if try(itemID, n) then return itemID end
  end
  for _, index in ipairs({ ns.Recipes.usedIn, ns.Recipes.madeBy, stockItems() }) do
    for itemID in pairs(index) do
      if not ns.ItemNames[itemID] and try(itemID, (GetItemInfo(itemID))) then return itemID end
    end
  end
  return partial and partial[1]
end

-- Autocomplete: item names (bundled and learned) and ledger member names.
-- Names starting with the text come first, then names containing it; shorter names first.
function Lk:Suggest(text, max)
  max = max or 8
  if type(text) ~= "string" then return {} end
  local needle = text:lower():gsub("^%s+", ""):gsub("%s+$", "")
  if #needle < 2 then return {} end
  local found, seen = {}, {}
  local function consider(kind, id, name)
    if not name or seen[kind .. id] then return end
    local lower = name:lower()
    local at = lower:find(needle, 1, true)
    if at then
      seen[kind .. id] = true
      found[#found + 1] = { kind = kind, id = id, label = name, rank = (at == 1 and 0 or 1), len = #name }
    end
  end
  for player in pairs(ns.Records:All()) do
    consider("player", player, ns:ShortName(player))
  end
  for itemID, name in pairs(ns.ItemNames or {}) do consider("item", itemID, name) end
  for _, index in ipairs({ ns.Recipes.usedIn, ns.Recipes.madeBy, stockItems() }) do
    for itemID in pairs(index) do
      if not (ns.ItemNames and ns.ItemNames[itemID]) then consider("item", itemID, (GetItemInfo(itemID))) end
    end
  end
  table.sort(found, function(a, b)
    if a.rank ~= b.rank then return a.rank < b.rank end
    if a.kind ~= b.kind then return a.kind == "player" end
    if a.len ~= b.len then return a.len < b.len end
    return a.label < b.label
  end)
  local out = {}
  for i = 1, math.min(max, #found) do out[i] = found[i] end
  return out
end

-- Everything one member makes, buys, wants and sells from their bags, for looking up a player
function Lk:Profile(player)
  local p = ns.Records:Get(player)
  if not p then return nil end
  local rows = {}
  for itemID, price in pairs(p.sell or {}) do rows[#rows + 1] = { kind = "makes", itemID = itemID, price = price } end
  for itemID, price in pairs(p.buy or {}) do rows[#rows + 1] = { kind = "buys", itemID = itemID, price = price } end
  for itemID, w in pairs(p.wants or {}) do rows[#rows + 1] = { kind = "wants", itemID = itemID, price = w.price, qty = w.qty } end
  for itemID, e in pairs(p.stock or {}) do rows[#rows + 1] = { kind = "has", itemID = itemID, price = e.price, qty = e.qty } end
  local order = { wants = 0, has = 1, makes = 2, buys = 3 }
  table.sort(rows, function(a, b)
    if a.kind ~= b.kind then return order[a.kind] < order[b.kind] end
    return ns:ItemName(a.itemID) < ns:ItemName(b.itemID)
  end)
  return rows
end
