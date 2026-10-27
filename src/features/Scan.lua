-- features/Scan.lua: reads the recipes this character knows while a profession window is
-- open, and saves them with the profession's skill level. Trade skills use the TradeSkill
-- API; Enchanting in Classic Era uses the Craft API. Shows every recipe while scanning
-- (expands headers, drops the "have materials" filter) and puts the filter back after.
-- Feeds features/Recipes.lua and features/Records.lua. Always on.
local _, ns = ...
local Scan = {}
ns.Scan = Scan

local function recipeIDFromLink(link)
  if type(link) ~= "string" then return nil end
  local id = link:match("enchant:(%d+)") or link:match("spell:(%d+)")
  return id and tonumber(id)
end

local scanning = false
local stats

-- Recipe ID from the recipe link; when the client gives none, match the bundled
-- recipe database by the item made or by the recipe's name
local function resolveID(link, name, product)
  local id = recipeIDFromLink(link)
  if id then stats.link = stats.link + 1 return id end
  id = ns.Recipes:FindID(name, product)
  if id then stats.matched = stats.matched + 1 return id end
  stats.unknown = stats.unknown + 1
  ns:Debug("could not identify recipe", name, "link:", tostring(link), "product:", tostring(product))
  return nil
end

local function finish(profName, rank, maxRank, found)
  local char = ns:CharDB()
  local list = {}
  for id in pairs(found) do list[#list + 1] = id end
  char.professions[profName] = { rank = rank, max = maxRank, recipes = list, scannedAt = time() }
  ns:Debug("scanned", profName .. ":", #list, "recipes (" .. stats.link .. " by link, " .. stats.matched ..
    " matched by name or item, " .. stats.unknown .. " unknown)")
  ns:Fire("ScanDone", profName, #list)
  ns:Fire("DataChanged")
end

function Scan:TradeSkill()
  if scanning then return end
  local profName, rank, maxRank = GetTradeSkillLine()
  if not profName or profName == "UNKNOWN" then return end
  scanning = true
  local makeableBox = TradeSkillFrameAvailableFilterCheckButton
  local wasMakeable = makeableBox and makeableBox:GetChecked()
  -- Show everything: expand headers and drop the "have materials" filter
  pcall(ExpandTradeSkillSubClass, 0)
  if TradeSkillOnlyShowMakeable then pcall(TradeSkillOnlyShowMakeable, false) end
  if SetTradeSkillSubClassFilter then pcall(SetTradeSkillSubClassFilter, 0, 1, 1) end
  if SetTradeSkillInvSlotFilter then pcall(SetTradeSkillInvSlotFilter, 0, 1, 1) end

  local found = {}
  stats = { link = 0, matched = 0, unknown = 0 }
  for i = 1, GetNumTradeSkills() do
    local name, kind = GetTradeSkillInfo(i)
    if name and kind ~= "header" then
      local product = ns:ItemIDFromLink(GetTradeSkillItemLink(i))
      local id = resolveID(GetTradeSkillRecipeLink and GetTradeSkillRecipeLink(i), name, product)
      if id then
        local minMade = GetTradeSkillNumMade(i)
        local reagents = {}
        for j = 1, GetTradeSkillNumReagents(i) do
          local _, _, count = GetTradeSkillReagentInfo(i, j)
          local itemID = ns:ItemIDFromLink(GetTradeSkillReagentItemLink(i, j))
          if itemID and count then reagents[itemID] = count end
        end
        ns.Recipes:Add(id, { n = name, p = product or 0, c = minMade or 1, prof = profName, r = reagents }, true)
        found[id] = true
      end
    end
  end
  scanning = false
  if wasMakeable and TradeSkillOnlyShowMakeable then pcall(TradeSkillOnlyShowMakeable, true) end
  finish(profName, rank, maxRank, found)
end

function Scan:Craft()
  if scanning then return end
  local profName, rank, maxRank = GetCraftDisplaySkillLine()
  if not profName then return end
  scanning = true
  local makeableBox = CraftFrameAvailableFilterCheckButton
  local wasMakeable = makeableBox and makeableBox:GetChecked()
  if CraftOnlyShowMakeable then pcall(CraftOnlyShowMakeable, false) end
  local found = {}
  stats = { link = 0, matched = 0, unknown = 0 }
  for i = 1, GetNumCrafts() do
    local name, _, kind = GetCraftInfo(i)
    if name and kind ~= "header" then
      local link = (GetCraftRecipeLink and GetCraftRecipeLink(i)) or GetCraftItemLink(i)
      local product = ns:ItemIDFromLink(GetCraftItemLink(i)) -- nil for enchants
      local id = resolveID(link, name, product)
      if id then
        local reagents = {}
        for j = 1, GetCraftNumReagents(i) do
          local _, _, count = GetCraftReagentInfo(i, j)
          local itemID = ns:ItemIDFromLink(GetCraftReagentItemLink(i, j))
          if itemID and count then reagents[itemID] = count end
        end
        ns.Recipes:Add(id, { n = name, p = product or 0, c = 1, prof = profName, r = reagents }, true)
        found[id] = true
      end
    end
  end
  scanning = false
  if wasMakeable and CraftOnlyShowMakeable then pcall(CraftOnlyShowMakeable, true) end
  finish(profName, rank, maxRank, found)
end

-- Debounce: the window fires many update events while it fills
local pending = {}
local function schedule(kind)
  if pending[kind] then return end
  pending[kind] = true
  ns:After(0.5, function()
    pending[kind] = nil
    if kind == "trade" then
      if TradeSkillFrame and TradeSkillFrame:IsShown() or GetNumTradeSkills() > 0 then Scan:TradeSkill() end
    else
      if GetNumCrafts and GetNumCrafts() > 0 then Scan:Craft() end
    end
  end)
end

ns:On("TRADE_SKILL_SHOW", function() schedule("trade") end)
ns:On("CRAFT_SHOW", function() schedule("craft") end)
ns:On("NEW_RECIPE_LEARNED", function() schedule("trade"); schedule("craft") end)
