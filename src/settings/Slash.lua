-- settings/Slash.lua: the /circ command and everything after it: open the window or a tab,
-- look up an item, set prices and requests, shopping lists, turn parts on and off, and
-- (with Ledger management on) create, invite and leave. /circ help lists them
-- (settings/Help.lua); dev/Debug.lua adds the testing commands. Every command also tries
-- to join the ledger channel if it's missing (features/Connection.lua).
--
-- Also opens the window on the getting-started guide the first time an account logs in,
-- so a new player needs no command at all.
local _, ns = ...
local Slash = {}
ns.Slash = Slash

-- Split "<item> <a> <b>" where the item is a link or a name of several words
local function splitItemArgs(rest, nArgs)
  local link = rest:match("(|c%x+|Hitem:.-|h|r)")
  local args = {}
  local item
  if link then
    item = link
    local after = rest:gsub("|c%x+|Hitem:.-|h|r", "", 1)
    for w in after:gmatch("%S+") do args[#args + 1] = w end
  else
    local words = {}
    for w in rest:gmatch("%S+") do words[#words + 1] = w end
    for _ = 1, nArgs do
      if #words > 0 then table.insert(args, 1, table.remove(words)) end
    end
    item = table.concat(words, " ")
  end
  return item, args
end

local function priceArg(text)
  if not text then return nil, false end
  if text:lower() == "auto" then return nil, true end
  local v = ns:ParseMoney(text)
  if v == nil then return nil, false end
  return v, true
end

-- [name] = function(rest); dev/Debug.lua adds to it
local commands = {}
Slash.commands = commands

commands.help = function() ns.Help:Print() end
-- Creating and leaving ledgers is off until Ledger management is turned on in Settings
local function advanced()
  if CircDB.settings.advanced then return true end
  ns:Print("Turn on Ledger management in Settings (/circ settings) first.")
  return false
end
commands.create = function(rest) if advanced() then ns.Union:Create(rest) end end
commands.invite = function(rest) if advanced() then ns.Union:Invite(rest) end end
commands.start = function() if advanced() then ns.Union:JoinStart() end end
commands.leave = function() if advanced() then ns.Union:Leave() end end
commands.reconnect = function() ns.Union:EnsureConnected() end -- the Nudge above joins right away
commands.find = function(rest) ns.UI:LookupItem(rest) end
commands.requests = function() ns.UI:Show("requests") end
commands.settings = function() ns.UI:Show("settings") end
commands.ledger = function() ns.UI:Show("ledger") end
commands.prices = function() ns.UI:Show("prices") end

local function setPrice(kind, rest)
  local item, args = splitItemArgs(rest, 1)
  local itemID = ns.Lookup:Resolve(item)
  local value, ok = priceArg(args[1])
  if not itemID or not ok then
    ns:Print("Usage: /circ " .. kind .. " <item> <price|off|auto>")
    return
  end
  if kind == "buy" then ns.Prices:SetBuy(itemID, value) else ns.Prices:SetSell(itemID, value) end
  ns:Print(kind, ns:ItemName(itemID), "->", value == nil and "auto" or (value == false and "off" or ns:Money(value)))
end
commands.buy = function(rest) setPrice("buy", rest) end
commands.sell = function(rest) setPrice("sell", rest) end

commands.pct = function(rest)
  local n = tonumber(rest)
  if not n or n < 1 or n > 200 then ns:Print("Usage: /circ pct 80") return end
  CircDB.settings.buyPct = n
  ns:Fire("DataChanged")
  ns:Print("Default reagent offer is now", n .. "% of market")
end
commands.margin = function(rest)
  local n = tonumber(rest)
  if not n or n < 0 or n > 500 then ns:Print("Usage: /circ margin 10") return end
  CircDB.settings.margin = n
  ns:Fire("DataChanged")
  ns:Print("Default margin is now", n .. "%")
end

commands.request = function(rest)
  local item, args = splitItemArgs(rest, 2)
  local itemID = ns.Lookup:Resolve(item)
  local qty = tonumber(args[1] or "")
  local price = ns:ParseMoney(args[2] or "")
  if not itemID or not qty or not price then
    ns:Print("Usage: /circ request <item> <qty> <price each>")
    return
  end
  CircDB.wants[itemID] = { qty = qty, price = price }
  ns:Fire("DataChanged")
  ns:Print("Request:", qty, "x", ns:ItemName(itemID), "at", ns:Money(price))
end
commands.unrequest = function(rest)
  local itemID = ns.Lookup:Resolve(rest)
  if itemID and CircDB.wants[itemID] then
    CircDB.wants[itemID] = nil
    ns:Fire("DataChanged")
    ns:Print("Removed request for", ns:ItemName(itemID))
  end
end

-- Shopping list for an item: the cheapest ledger crafter for it, and for each of its reagents
local function cheapestMaker(itemID)
  for _, r in ipairs(ns.Lookup:MadeBy(itemID)) do
    if r.player ~= ns:PlayerKey() then return r end
  end
end
commands.shop = function(rest)
  local item, args = splitItemArgs(rest, 1)
  local qty = tonumber(args[1] or "")
  if not qty then item = rest; qty = 1 end
  local itemID = ns.Lookup:Resolve(item)
  if not itemID then ns:Print("Usage: /circ shop <item> [qty]") return end
  local _, link = GetItemInfo(itemID)
  ns:Print("Shopping list for", qty, "x", link or ns:ItemName(itemID))
  local maker = cheapestMaker(itemID)
  if maker then
    DEFAULT_CHAT_FRAME:AddMessage("  Buy finished: " .. ns:ShortName(maker.player) ..
      (maker.price and (" charges " .. ns:Money(maker.price * qty)) or " (ask)"))
  end
  local rid = next(ns.Recipes.madeBy[itemID] or {})
  local def = rid and ns.Recipes:Get(rid)
  if not def then
    if not maker then DEFAULT_CHAT_FRAME:AddMessage("  No ledger crafter or known recipe for this item.") end
    return
  end
  DEFAULT_CHAT_FRAME:AddMessage("  Or bring the reagents:")
  for reagent, count in pairs(def.r) do
    local need = math.ceil(count * qty / math.max(def.c or 1, 1))
    local _, rlink = GetItemInfo(reagent)
    local src = cheapestMaker(reagent)
    local where
    if src then
      where = ns:ShortName(src.player) .. (src.price and (" " .. ns:Money(src.price * need)) or " (ask)")
    else
      local m = ns.Prices:Market(reagent)
      where = m and ("AH about " .. ns:Money(m * need)) or "no ledger source"
    end
    DEFAULT_CHAT_FRAME:AddMessage("    " .. need .. " x " .. (rlink or ns:ItemName(reagent)) .. " - " .. where)
  end
end

local function toggle(key, rest, label)
  CircDB.settings[key] = rest ~= "off"
  ns:Print(label, CircDB.settings[key] and "on" or "off")
  ns.UI:Refresh() -- the Settings tab's checkbox follows, if it's open
end
commands.nudges = function(rest) toggle("nudges", rest, "Vendor and AH nudges") end
commands.tooltip = function(rest) toggle("tooltip", rest, "Tooltip lines") end
commands.minimap = function(rest) toggle("minimap", rest, "Minimap button"); ns.Minimap:Update() end

SLASH_CIRC1 = "/circ"
SlashCmdList.CIRC = function(msg)
  ns.Union:Nudge()
  msg = msg or ""
  local cmd, rest = msg:match("^(%S+)%s*(.-)$")
  if not cmd then ns.UI:Toggle() return end
  local fn = commands[cmd:lower()]
  if fn then fn(rest or "") else commands.help() end
end

ns:Listen("Ready", function()
  -- First time on this account: open the window on the getting-started list
  if not CircDB.seenIntro then
    CircDB.seenIntro = true
    ns:After(8, function() ns.UI:Show("lookup") end)
    return
  end
  if next(ns:CharDB().professions) == nil then
    ns:Print("Open each of your profession windows once so your ledger can find you. Type /circ to open Circ.")
  end
end)

-- Old names still work
commands.want = commands.request
commands.unwant = commands.unrequest
commands.wants = commands.requests
