-- features/Records.lua: this character's record (professions, recipes, prices, requests
-- and items for sale, packed short in base 36) and the records received from other
-- members, unpacked for lookups. features/Sync.lua decides when records go out.
local _, ns = ...
local Rec = {}
ns.Records = Rec

local To36, From36 = ns.To36, ns.From36

local function packList(ids)
  local out = {}
  for i = 1, #ids do out[i] = To36(ids[i]) end
  return table.concat(out, ",")
end

local function packMap(map)
  local out = {}
  for k, v in pairs(map) do out[#out + 1] = To36(k) .. ":" .. To36(v) end
  table.sort(out)
  return table.concat(out, ",")
end

local function unpackList(s)
  local t = {}
  for part in (s or ""):gmatch("[^,]+") do
    local n = From36(part)
    if n then t[n] = true end
  end
  return t
end

local function unpackMap(s)
  local t = {}
  for k, v in (s or ""):gmatch("(%w+):(%w+)") do
    local kn, vn = From36(k), From36(v)
    if kn and vn then t[kn] = vn end
  end
  return t
end

-- Build this character's record from scans, prices and wants
function Rec:BuildMine()
  local char = ns:CharDB()
  local ids, profs, reagents = {}, {}, {}
  local buy, sell = {}, {}
  for prof, p in pairs(char.professions) do
    profs[prof] = p.rank or 0
    for _, id in ipairs(p.recipes or {}) do
      ids[#ids + 1] = id
      local def = ns.Recipes:Get(id)
      if def then
        for itemID in pairs(def.r) do reagents[itemID] = true end
        local price = ns.Prices:Sell(id)
        if price and def.p and def.p > 0 then sell[def.p] = price end
      end
    end
  end
  table.sort(ids)
  for itemID in pairs(reagents) do
    local price = ns.Prices:Buy(itemID)
    if price then buy[itemID] = price end
  end
  local wants = {}
  for itemID, w in pairs(CircDB.wants) do
    if not w.off then wants[#wants + 1] = To36(itemID) .. ":" .. To36(w.qty or 1) .. ":" .. To36(w.price or 0) end
  end
  table.sort(wants)
  local stock = {}
  for itemID, e in pairs(ns.Stock:Published()) do
    stock[#stock + 1] = To36(itemID) .. ":" .. To36(e.qty) .. ":" .. To36(e.price)
  end
  table.sort(stock)

  local _, class = UnitClass("player")
  local rec = {
    cls = class,
    profs = profs,
    r = packList(ids),
    b = packMap(buy),
    s = packMap(sell),
    w = table.concat(wants, ","),
    h = table.concat(stock, ","),
  }
  local hash = ns.Hash(ns.Serialize.Encode({ rec.profs, rec.r, rec.b, rec.s, rec.w, rec.h }))
  if char.recordHash ~= hash then
    char.recordHash = hash
    char.recordVersion = time()
  end
  rec.v = char.recordVersion
  return rec
end

function Rec:MyVersion()
  return ns:CharDB().recordVersion or 0
end

-- Unpack a record. First-hand records come from their owner; relayed ones come from another
-- member on behalf of an offline owner, are marked as relayed, and never replace a newer copy.
function Rec:Store(owner, rec, silent, relayed)
  if type(rec) ~= "table" or type(rec.v) ~= "number" then return false end
  local players = ns:UnionDB().players
  if relayed and players[owner] and (players[owner].v or 0) >= rec.v then return false end
  local p = players[owner] or { firstSeen = time() }
  p.raw = { v = rec.v, cls = rec.cls, profs = rec.profs, r = rec.r, b = rec.b, s = rec.s, w = rec.w, h = rec.h }
  p.relayed = relayed or nil
  p.v = rec.v
  p.cls = type(rec.cls) == "string" and rec.cls or nil
  p.profs = type(rec.profs) == "table" and rec.profs or {}
  p.recipes = unpackList(rec.r)
  p.buy = unpackMap(rec.b)
  p.sell = unpackMap(rec.s)
  p.wants = {}
  for id, qty, price in (rec.w or ""):gmatch("(%w+):(%w+):(%w+)") do
    local itemID = From36(id)
    if itemID then p.wants[itemID] = { qty = From36(qty) or 1, price = From36(price) or 0 } end
  end
  p.stock = {}
  for id, qty, price in (type(rec.h) == "string" and rec.h or ""):gmatch("(%w+):(%w+):(%w+)") do
    local itemID = From36(id)
    if itemID then p.stock[itemID] = { qty = From36(qty) or 1, price = From36(price) or 0 } end
  end
  if not relayed then p.lastSeen = time() end
  players[owner] = p
  if not silent then ns:Fire("DataChanged") end
  return true
end

function Rec:Get(owner) return ns:UnionDB().players[owner] end

function Rec:Version(owner)
  local p = ns:UnionDB().players[owner]
  return p and p.v or 0
end

-- Any message from a member counts as being seen online
ns:Listen("Seen", function(sender)
  local p = ns:UnionDB().players[sender]
  if p then p.lastSeen = time() end
end)

function Rec:IsOnline(owner)
  if owner == ns:PlayerKey() then return true end
  local p = ns:UnionDB().players[owner]
  return p and p.lastSeen and (time() - p.lastSeen) < 20 * 60
end

-- Drop members not seen for 30 days
function Rec:Prune()
  local players = ns:UnionDB().players
  local cutoff = time() - 30 * 86400
  for k, p in pairs(players) do
    if (p.lastSeen or 0) < cutoff then players[k] = nil end
  end
end

-- Iterate my record plus everyone else's, so lookups include myself
function Rec:All()
  local list = {}
  for k, p in pairs(ns:UnionDB().players) do list[k] = p end
  return list
end

ns:Listen("Ready", function() Rec:Prune() end)
