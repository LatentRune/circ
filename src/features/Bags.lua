-- features/Bags.lua: what each member carries, so "Who has it" finds items nobody has
-- listed for sale. Only tradeable items count, gray junk is left out, and sharing can be
-- turned off. Setting: shareBags ("Share my bags with my ledger").
-- Each character keeps a numbered snapshot. Changes go out as a diff against the previous
-- number at most once a minute; anyone whose copy is out of step asks for the full snapshot.
local _, ns = ...
local B = {}
ns.Bags = B

local To36, From36 = ns.To36, ns.From36
local SEND_DELAY = 60

local function pack(map)
  local out = {}
  for id, n in pairs(map) do out[#out + 1] = To36(id) .. ":" .. To36(n) end
  table.sort(out)
  return table.concat(out, ",")
end

local function unpackMap(s)
  local t = {}
  for k, v in (type(s) == "string" and s or ""):gmatch("(%w+):(%w+)") do
    local id, n = From36(k), From36(v)
    if id and n then t[id] = n end
  end
  return t
end

function B:Enabled() return CircDB.settings.shareBags ~= false end

-- My snapshot { v = number, i = { [itemID] = count } }
local function mine()
  local c = ns:CharDB()
  c.bags = c.bags or { v = 0, i = {} }
  return c.bags
end
function B:Version() return mine().v end

-- Bags of other members in this ledger: { [owner] = { v, i } }
local function others()
  local u = ns:UnionDB()
  u.bags = u.bags or {}
  return u.bags
end

-- Everyone's bag counts for one item, me included: { [owner] = count }
function B:Holders(itemID)
  local out = {}
  for owner, b in pairs(others()) do
    if b.i and b.i[itemID] then out[owner] = b.i[itemID] end
  end
  local n = mine().i[itemID]
  if n and self:Enabled() then out[ns:PlayerKey()] = n end
  return out
end

-- Diff waiting to go out: base number and changed counts (0 = gone)
local pending
local function flush()
  if not pending then return end
  local p = pending
  pending = nil
  if ns.Union:ChannelID() then
    ns.Comm:Send("BAGD", { b = p.base, v = mine().v, i = pack(p.changes) }, "UNION")
  end
end

-- Compare the bags with my snapshot and queue the changes
function B:Update()
  local snap = mine()
  local now = self:Enabled() and ns.Stock:BagCounts(true) or {}
  local changes, any = {}, false
  for id, n in pairs(now) do
    if snap.i[id] ~= n then changes[id] = n; any = true end
  end
  for id in pairs(snap.i) do
    if not now[id] then changes[id] = 0; any = true end
  end
  if not any then return end
  local base = snap.v
  snap.i = now
  snap.v = math.max(time(), base + 1)
  if not pending then
    pending = { base = base, changes = {} }
    ns:After(SEND_DELAY, flush)
  end
  for id, n in pairs(changes) do pending.changes[id] = n end
end

-- Ask an owner for their full snapshot, at most every 30 seconds each
local asked = {}
local function ask(owner)
  if GetTime() - (asked[owner] or 0) < 30 then return end
  asked[owner] = GetTime()
  ns.Comm:Send("BAGREQ", {}, owner)
end

ns:Listen("Msg:BAGD", function(data, sender)
  if type(data) ~= "table" or type(data.v) ~= "number" then return end
  local have = others()[sender]
  if have and have.v == data.b then
    for id, n in pairs(unpackMap(data.i)) do have.i[id] = n > 0 and n or nil end
    have.v = data.v
    ns:Fire("BagsChanged")
  elseif not have or have.v < data.v then
    ask(sender)
  end
end)

ns:Listen("Msg:BAGS", function(data, sender)
  if type(data) ~= "table" or type(data.v) ~= "number" then return end
  local have = others()[sender]
  if have and have.v >= data.v then return end
  others()[sender] = { v = data.v, i = unpackMap(data.i) }
  ns:Fire("BagsChanged")
end)

-- Answer requests for my snapshot; one channel message when several ask at once
local askers, answerQueued = {}, false
ns:Listen("Msg:BAGREQ", function(_, sender)
  askers[sender] = true
  if answerQueued then return end
  answerQueued = true
  ns:After(2, function()
    answerQueued = false
    local list = {}
    for name in pairs(askers) do list[#list + 1] = name end
    wipe(askers)
    local snap = mine()
    local msg = { v = snap.v, i = B:Enabled() and pack(snap.i) or "" }
    if #list >= 3 then
      ns.Comm:Send("BAGS", msg, "UNION")
    else
      for _, name in ipairs(list) do ns.Comm:Send("BAGS", msg, name) end
    end
  end)
end)

-- HELLO carries my snapshot number; fetch a member's bags when theirs is newer than mine
ns:Listen("Msg:HELLO", function(data, sender)
  if type(data) ~= "table" or type(data.bv) ~= "number" then return end
  local have = others()[sender]
  if data.bv > 0 and (not have or have.v < data.bv) then ask(sender) end
end)

ns:Listen("UnionChanged", function() wipe(asked) end)
