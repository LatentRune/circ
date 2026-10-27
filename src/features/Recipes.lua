-- features/Recipes.lua: what each recipe needs and makes, by recipe ID, and the reverse:
-- which recipes use or make an item. Every Classic Era recipe is bundled in
-- data/RecipeData.lua. This account's own scans (features/Scan.lua) override the bundle,
-- since they carry the client's own names, and members fill in recipes the bundle lacks
-- (RDEFREQ / RDEF messages). Always on.
local _, ns = ...
local R = {}
ns.Recipes = R

R.usedIn = {}   -- [itemID] = { [recipeID] = true }
R.madeBy = {}   -- [itemID] = { [recipeID] = true }

local bundled = {}  -- decoded RecipeData rows, by recipe ID

local function decode(id)
  local row = ns.RecipeData[id]
  if not row then return nil end
  local def = bundled[id]
  if not def then
    local r = {}
    for i = 1, #row[6], 2 do r[row[6][i]] = row[6][i + 1] end
    def = { prof = row[1], p = row[2], c = row[3], skill = row[4], n = row[5], r = r, season = row[7], bundled = true }
    bundled[id] = def
  end
  return def
end

local function setIndex(id, def, value)
  if def.p and def.p > 0 then
    R.madeBy[def.p] = R.madeBy[def.p] or {}
    R.madeBy[def.p][id] = value
  end
  for itemID in pairs(def.r or {}) do
    R.usedIn[itemID] = R.usedIn[itemID] or {}
    R.usedIn[itemID][id] = value
  end
end

local function indexOne(id, def) setIndex(id, def, true) end

function R:Rebuild()
  wipe(self.usedIn)
  wipe(self.madeBy)
  for id in pairs(ns.RecipeData) do
    if not CircDB.recipes[id] then indexOne(id, decode(id)) end
  end
  for id, def in pairs(CircDB.recipes) do
    indexOne(id, def)
  end
end

function R:Get(id)
  return CircDB.recipes[id] or decode(id)
end

-- Find a bundled recipe when the client gives no recipe link: by the item it makes,
-- then by its name. Returns the recipe ID or nil.
local byName
function R:FindID(name, product)
  if product and product > 0 and self.madeBy[product] then
    local id = next(self.madeBy[product]) -- any recipe that makes it
    if id then return id end
  end
  if type(name) ~= "string" then return nil end
  if not byName then
    byName = {}
    for id, row in pairs(ns.RecipeData) do byName[row[5]:lower()] = id end
  end
  return byName[name:lower()]
end

function R:IsBundled(id)
  return ns.RecipeData[id] ~= nil
end

function R:Count()
  local bundledCount, learned = 0, 0
  for _ in pairs(ns.RecipeData) do bundledCount = bundledCount + 1 end
  for id in pairs(CircDB.recipes) do
    if not ns.RecipeData[id] then learned = learned + 1 end
  end
  return bundledCount, learned
end

local function valid(def)
  if type(def) ~= "table" or type(def.r) ~= "table" then return false end
  if def.p ~= nil and type(def.p) ~= "number" then return false end
  local n = 0
  for k, v in pairs(def.r) do
    if type(k) ~= "number" or type(v) ~= "number" or v < 1 or v > 100 then return false end
    n = n + 1
  end
  return n > 0 and n <= 12
end

-- Store a definition. Definitions from this client's own scans always win; definitions
-- from other members are only added for recipes neither the bundle nor a scan covers.
function R:Add(id, def, fromScan)
  if type(id) ~= "number" or not valid(def) then return false end
  local existing = CircDB.recipes[id]
  if not fromScan and (ns.RecipeData[id] or (existing and existing.own)) then return false end
  local old = existing or decode(id)
  if old then setIndex(id, old, nil) end
  def.own = fromScan or (existing and existing.own) or nil
  CircDB.recipes[id] = def
  indexOne(id, def)
  return true
end

function R:Missing(idList)
  local missing = {}
  for _, id in ipairs(idList) do
    if not self:Get(id) then missing[#missing + 1] = id end
  end
  return missing
end

function R:DisplayName(id)
  local def = self:Get(id)
  if not def then return "Recipe " .. id end
  if def.p and def.p > 0 then
    local name = GetItemInfo(def.p)
    if name then return name end
  end
  return def.n or ("Recipe " .. id)
end

-- Answer definition requests from ledger members
ns:Listen("Msg:RDEFREQ", function(data, sender)
  if type(data) ~= "table" then return end
  local out, count = {}, 0
  for _, id in ipairs(data) do
    local def = R:Get(id)
    if def and count < 60 then
      out[id] = { n = def.n, p = def.p, c = def.c, prof = def.prof, r = def.r }
      count = count + 1
    end
  end
  if count > 0 then ns.Comm:Send("RDEF", out, sender) end
end)

ns:Listen("Msg:RDEF", function(data)
  if type(data) ~= "table" then return end
  local added = 0
  for id, def in pairs(data) do
    if R:Add(id, def, false) then added = added + 1 end
  end
  if added > 0 then ns:Fire("DataChanged") end
end)

ns:Listen("Ready", function() R:Rebuild() end)

-- Products and reagents of every recipe this character has scanned:
-- { [productID] = recipeID }, { [reagentID] = true }
function R:Mine()
  local products, reagents = {}, {}
  for _, p in pairs(ns:CharDB().professions) do
    for _, rid in ipairs(p.recipes or {}) do
      local def = R:Get(rid)
      if def then
        if def.p and def.p > 0 then products[def.p] = rid end
        for itemID in pairs(def.r or {}) do reagents[itemID] = true end
      end
    end
  end
  return products, reagents
end
