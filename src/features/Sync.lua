-- features/Sync.lua: keeps every member's record current.
-- HELLO carries a record version. Anyone holding an older copy asks the owner (REQ),
-- and the owner answers with its record (REC). Records are only accepted first-hand,
-- except for the catch-up a newcomer gets about offline members (DIRREQ / DIR / RREQ /
-- RRELAY), which are marked as relayed. Always on; talks through core/Comm.lua.
local _, ns = ...
local Sync = {}
ns.Sync = Sync

local lastHello = 0
local announced = 0      -- record version last announced to the whole ledger
local requested = {}     -- [owner] = time of last REQ
local reqFrom = {}       -- [requester] = true, waiting for my REC
local deferred = {}      -- [owner] = newest version heard while a REQ waits out the 30-second limit
local recScheduled = false

local function jitter(minS, maxS) return minS + math.random() * (maxS - minS) end

-- joining = true right after login or a ledger switch: everyone answers with their version,
-- since I may have none of their records yet
function Sync:Hello(target, joining)
  ns.Comm:Send("HELLO", { v = ns.Records:MyVersion(), ver = ns.version, j = joining and 1 or nil,
    bv = ns.Bags and ns.Bags:Version() or nil }, target or "UNION", true)
  if not target then
    lastHello = GetTime()
    announced = ns.Records:MyVersion()
  end
end

-- Rebuild my record, keep a local copy for my own lookups, announce if it changed
local rebuildPending = false
function Sync:Rebuild()
  if rebuildPending then return end
  rebuildPending = true
  ns:After(3, function()
    rebuildPending = false
    -- Compare with the last announced version: other messages also rebuild the record
    local rec = ns.Records:BuildMine()
    ns.Records:Store(ns:PlayerKey(), rec, true)
    ns:Fire("RecordsUpdated")
    if rec.v ~= announced and ns.Union:ChannelID() then Sync:Hello() end
  end)
end
ns:Listen("DataChanged", function() Sync:Rebuild() end)

-- Send my record to everyone who asked, as one channel message when many asked
local function sendRecord()
  recScheduled = false
  local rec = ns.Records:BuildMine()
  local askers = {}
  for name in pairs(reqFrom) do askers[#askers + 1] = name end
  wipe(reqFrom)
  if #askers >= 3 then
    ns.Comm:Send("REC", rec, "UNION")
  else
    for _, name in ipairs(askers) do ns.Comm:Send("REC", rec, name) end
  end
end

ns:Listen("Msg:HELLO", function(data, sender, dist)
  if type(data) ~= "table" then return end
  if ns.Union.createdAt and GetTime() - ns.Union.createdAt < 15 and dist == "UNION" then
    ns:Print("Another group is already using this ledger. Leave it and create it again.")
    ns.Union.createdAt = nil
  end
  local known = ns.Records:Get(sender)
  local wasAway = not known or not known.lastSeen or (time() - known.lastSeen) > 20 * 60
  if (data.v or 0) > ns.Records:Version(sender) then
    local last = requested[sender] or 0
    if GetTime() - last > 30 then
      requested[sender] = GetTime()
      ns:After(jitter(0.5, 3), function() ns.Comm:Send("REQ", {}, sender) end)
    elseif deferred[sender] then
      deferred[sender] = math.max(deferred[sender], data.v)
    else
      -- Asked too recently: ask again once the wait is over, if still behind
      deferred[sender] = data.v
      ns:After(30 - (GetTime() - last) + jitter(0.5, 3), function()
        local v = deferred[sender]
        deferred[sender] = nil
        if v and v > ns.Records:Version(sender) then
          requested[sender] = GetTime()
          ns.Comm:Send("REQ", {}, sender)
        end
      end)
    end
  end
  -- A member just arrived: tell them my version so they can fetch my record
  if dist == "UNION" and (wasAway or data.j) then
    ns:After(jitter(2, 10), function() Sync:Hello(sender) end)
  end
end)

ns:Listen("Msg:REQ", function(_, sender)
  reqFrom[sender] = true
  if not recScheduled then
    recScheduled = true
    ns:After(jitter(1, 4), sendRecord)
  end
end)

-- Fetch definitions for recipes I have never seen, from the member who sent the record
local function fetchDefs(owner, from)
  local ids = {}
  for id in pairs(ns.Records:Get(owner).recipes) do ids[#ids + 1] = id end
  local missing = ns.Recipes:Missing(ids)
  for i = 1, #missing, 60 do
    local batch = {}
    for j = i, math.min(i + 59, #missing) do batch[#batch + 1] = missing[j] end
    ns.Comm:Send("RDEFREQ", batch, from)
  end
end

ns:Listen("Msg:REC", function(rec, sender)
  if not ns.Records:Store(sender, rec) then return end
  fetchDefs(sender, sender)
end)

-- Directory catch-up: a member who just arrived learns about members who are offline.
-- One online member answers with the versions it holds (the others stand down), and
-- relays the records the newcomer is missing. Relayed records are marked as such.
local pendingDir = {}
ns:Listen("Msg:DIRREQ", function(data, sender)
  if type(data) ~= "table" then return end
  local key = sender .. ":" .. (data.n or 0)
  pendingDir[key] = true
  ns:After(jitter(1, 6), function()
    if not pendingDir[key] then return end
    pendingDir[key] = nil
    local versions, count = {}, 0
    for owner, p in pairs(ns:UnionDB().players) do
      if owner ~= sender and p.raw and count < 200 then
        versions[owner] = p.v
        count = count + 1
      end
    end
    ns.Comm:Send("DIR", { to = sender, n = data.n, v = versions }, "UNION")
  end)
end)

ns:Listen("Msg:DIR", function(data, sender)
  if type(data) ~= "table" then return end
  pendingDir[(data.to or "") .. ":" .. (data.n or 0)] = nil
  if data.to ~= ns:PlayerKey() or type(data.v) ~= "table" then return end
  local want = {}
  for owner, v in pairs(data.v) do
    if type(v) == "number" and owner ~= ns:PlayerKey() and v > ns.Records:Version(owner) then
      want[#want + 1] = owner
    end
  end
  for i = 1, #want, 8 do
    local batch = {}
    for j = i, math.min(i + 7, #want) do batch[#batch + 1] = want[j] end
    ns.Comm:Send("RREQ", batch, sender)
  end
end)

ns:Listen("Msg:RREQ", function(data, sender)
  if type(data) ~= "table" then return end
  local out = {}
  for _, owner in ipairs(data) do
    local p = ns.Records:Get(owner)
    if type(owner) == "string" and p and p.raw then out[owner] = p.raw end
  end
  if next(out) then ns.Comm:Send("RRELAY", out, sender) end
end)

ns:Listen("Msg:RRELAY", function(data, sender)
  if type(data) ~= "table" then return end
  for owner, rec in pairs(data) do
    if type(owner) == "string" and owner ~= ns:PlayerKey() and owner ~= sender
      and ns.Records:Store(owner, rec, true, true) then
      fetchDefs(owner, sender)
    end
  end
  ns:Fire("DataChanged")
end)

function Sync:CatchUp()
  ns.Comm:Send("DIRREQ", { n = math.random(1, 99999) }, "UNION")
end

ns:Listen("UnionChanged", function(name)
  wipe(requested)
  wipe(reqFrom)
  wipe(deferred)
  Sync:Rebuild()
  if name then
    ns:After(4, function() Sync:Hello(nil, true) end)
    ns:After(15, function() Sync:CatchUp() end)
  end
end)

ns:Listen("Ready", function()
  Sync:Rebuild()
  ns:After(10, function() if ns.Union:ChannelID() then Sync:Hello(nil, true) end end)
  ns:After(20, function() if ns.Union:ChannelID() then Sync:CatchUp() end end)
  -- Heartbeat so members show as online
  ns:Every(600, function()
    if ns.Union:ChannelID() and GetTime() - lastHello > 500 then Sync:Hello() end
  end)
end)
