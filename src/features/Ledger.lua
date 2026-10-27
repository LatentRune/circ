-- features/Ledger.lua: the trade ledger. Records completed trades between members: the
-- gold and items each side gave. Both sides report the same trade; an entry is confirmed
-- once both reports match. Every member can see the ledger, and members who were offline
-- catch up (LREQ / LDUMP). Shown on the Ledger tab (ui/Ledger.lua). Always on.
local _, ns = ...
local L = {}
ns.Ledger = L

local MATCH_WINDOW = 300

local function entries() return ns:UnionDB().ledger end

-- Items as "id36x qty" joined by ";" sorted, so both sides produce the same text
local function packItems(list)
  local out = {}
  for id, qty in pairs(list) do out[#out + 1] = ns.To36(id) .. "x" .. qty end
  table.sort(out)
  return table.concat(out, ";")
end

function L.Canonical(me, partner, myMoney, theirMoney, myItems, theirItems, t)
  local e
  if me < partner then
    e = { a = me, b = partner, ma = myMoney, mb = theirMoney, ia = packItems(myItems), ib = packItems(theirItems) }
  else
    e = { a = partner, b = me, ma = theirMoney, mb = myMoney, ia = packItems(theirItems), ib = packItems(myItems) }
  end
  e.t = t
  return e
end

function L.Key(e)
  return table.concat({ e.a, e.b, e.ma, e.mb, e.ia, e.ib }, "|")
end

-- Merge a report into the ledger. Returns the stored entry.
function L:Add(e, reporters)
  local key = L.Key(e)
  local db = entries()
  for _, x in pairs(db) do
    if L.Key(x) == key and math.abs((x.t or 0) - e.t) <= MATCH_WINDOW then
      for name in pairs(reporters) do x.rep[name] = true end
      x.confirmed = x.rep[x.a] and x.rep[x.b] or nil
      return x
    end
  end
  local id = ns.To36(ns.Hash(key .. ":" .. e.t))
  local stored = { a = e.a, b = e.b, ma = e.ma, mb = e.mb, ia = e.ia, ib = e.ib, t = e.t, rep = {} }
  for name in pairs(reporters) do stored.rep[name] = true end
  stored.confirmed = stored.rep[stored.a] and stored.rep[stored.b] or nil
  db[id] = stored
  return stored
end

function L:Sorted()
  local list = {}
  for _, e in pairs(entries()) do list[#list + 1] = e end
  table.sort(list, function(x, y) return x.t > y.t end)
  return list
end

function L:CountFor(name)
  local n = 0
  for _, e in pairs(entries()) do
    if e.confirmed and (e.a == name or e.b == name) then n = n + 1 end
  end
  return n
end

-- Gold in and out per member, and total gold circulated, over the last `days`
function L:Totals(days)
  local cutoff = time() - days * 86400
  local per, total = {}, 0
  for _, e in pairs(entries()) do
    if e.confirmed and e.t >= cutoff then
      per[e.a] = per[e.a] or { inGold = 0, outGold = 0, trades = 0 }
      per[e.b] = per[e.b] or { inGold = 0, outGold = 0, trades = 0 }
      per[e.a].outGold = per[e.a].outGold + e.ma
      per[e.b].inGold = per[e.b].inGold + e.ma
      per[e.b].outGold = per[e.b].outGold + e.mb
      per[e.a].inGold = per[e.a].inGold + e.mb
      per[e.a].trades = per[e.a].trades + 1
      per[e.b].trades = per[e.b].trades + 1
      total = total + e.ma + e.mb
    end
  end
  return per, total
end

-- Trade window capture --------------------------------------------------------------
local trade

local function snapshot()
  if not trade then return end
  trade.myMoney = GetPlayerTradeMoney() or 0
  trade.theirMoney = GetTargetTradeMoney() or 0
  trade.myItems, trade.theirItems = {}, {}
  for i = 1, 6 do -- slot 7 is "will not be traded"
    local id = ns:ItemIDFromLink(GetTradePlayerItemLink(i))
    if id then
      local _, _, qty = GetTradePlayerItemInfo(i)
      trade.myItems[id] = (trade.myItems[id] or 0) + (qty or 1)
    end
    id = ns:ItemIDFromLink(GetTradeTargetItemLink(i))
    if id then
      local _, _, qty = GetTradeTargetItemInfo(i)
      trade.theirItems[id] = (trade.theirItems[id] or 0) + (qty or 1)
    end
  end
end

ns:On("TRADE_SHOW", function()
  local partner = GetUnitName("NPC", true)
  trade = partner and { partner = ns:FullName(partner) } or nil
  snapshot()
end)
for _, ev in ipairs({ "TRADE_PLAYER_ITEM_CHANGED", "TRADE_TARGET_ITEM_CHANGED", "TRADE_MONEY_CHANGED" }) do
  ns:On(ev, snapshot)
end
-- Keep what was on the table when someone pressed Trade; slots may clear as the trade completes
ns:On("TRADE_ACCEPT_UPDATE", function(playerAccepted, targetAccepted)
  snapshot()
  if trade and (playerAccepted == 1 or targetAccepted == 1) then
    trade.final = { myMoney = trade.myMoney, theirMoney = trade.theirMoney, myItems = trade.myItems, theirItems = trade.theirItems }
  end
end)

ns:On("UI_INFO_MESSAGE", function(_, msg)
  if not trade or msg ~= ERR_TRADE_COMPLETE then return end
  local t = trade.final or trade
  t.partner = trade.partner
  trade = nil
  if not ns.Records:Get(t.partner) then
    ns:Debug("trade with non-member", t.partner, "not logged")
    return
  end
  local me = ns:PlayerKey()
  local e = L.Canonical(me, t.partner, t.myMoney, t.theirMoney, t.myItems, t.theirItems, time())
  if e.ma == 0 and e.mb == 0 and e.ia == "" and e.ib == "" then return end
  L:Add(e, { [me] = true })
  ns.Comm:Send("LEDG", e, "UNION")
  ns:Fire("LedgerChanged")
end)
ns:On("TRADE_CLOSED", function()
  -- TRADE_CLOSED fires before UI_INFO_MESSAGE on success, so clear a little later
  ns:After(2, function() trade = nil end)
end)

-- Network ------------------------------------------------------------------------------
local function validEntry(e)
  return type(e) == "table" and type(e.a) == "string" and type(e.b) == "string"
    and type(e.ma) == "number" and type(e.mb) == "number" and type(e.t) == "number"
    and type(e.ia) == "string" and type(e.ib) == "string"
end

ns:Listen("Msg:LEDG", function(e, sender)
  if not validEntry(e) then return end
  if sender ~= e.a and sender ~= e.b then return end -- only a party to the trade may report it
  L:Add(e, { [sender] = true })
  ns:Fire("LedgerChanged")
end)

-- Catch-up for members who were offline: one member answers, the rest stand down
local pendingDump = {}
ns:Listen("Msg:LREQ", function(data, sender)
  if type(data) ~= "table" then return end
  local key = sender .. ":" .. (data.n or 0)
  pendingDump[key] = true
  ns:After(1 + math.random() * 5, function()
    if not pendingDump[key] then return end
    pendingDump[key] = nil
    local out = {}
    for _, e in ipairs(L:Sorted()) do
      if e.t > (data.since or 0) and #out < 150 then
        local reps = {}
        for name in pairs(e.rep) do reps[#reps + 1] = name end
        out[#out + 1] = { a = e.a, b = e.b, ma = e.ma, mb = e.mb, ia = e.ia, ib = e.ib, t = e.t, rep = reps }
      end
    end
    ns.Comm:Send("LDUMP", { to = sender, n = data.n, e = out }, "UNION")
  end)
end)

ns:Listen("Msg:LDUMP", function(data)
  if type(data) ~= "table" then return end
  pendingDump[(data.to or "") .. ":" .. (data.n or 0)] = nil
  if data.to ~= ns:PlayerKey() or type(data.e) ~= "table" then return end
  for _, e in ipairs(data.e) do
    if validEntry(e) and type(e.rep) == "table" then
      local reps = {}
      for _, name in ipairs(e.rep) do
        if name == e.a or name == e.b then reps[name] = true end
      end
      L:Add(e, reps)
    end
  end
  ns:Fire("LedgerChanged")
end)

function L:CatchUp()
  local newest = 0
  for _, e in pairs(entries()) do if e.t > newest then newest = e.t end end
  ns.Comm:Send("LREQ", { since = newest - MATCH_WINDOW, n = math.random(1, 99999) }, "UNION")
end

ns:Listen("UnionChanged", function(name) if name then ns:After(20, function() L:CatchUp() end) end end)
ns:Listen("Ready", function()
  ns:After(25, function() if ns.Union:ChannelID() then L:CatchUp() end end)
end)
