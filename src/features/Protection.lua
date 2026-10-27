-- features/Protection.lua: notices when someone takes over the ledger's channel (a stranger
-- becomes owner, sets a password, or kicks members) and offers to move the ledger to a
-- successor channel that every member's client works out the same way, so members follow
-- without talking. Asks first (ns:Ask("TAKEOVER"), ui/Popups.lua); after two takeovers in
-- a day it only explains what to do. Also hands channel ownership to an established member
-- when the owner logs out. Works with features/Channel.lua (U.Successor) and
-- features/Union.lua (Bind).
local _, ns = ...
local Prot = {}
ns.Protection = Prot

local KICK_WINDOW, KICK_LIMIT = 300, 3
local recentKicks = {}
local prompted = false

local function isUnionChannel(chanName)
  return ns.Union:IsBound() and ns.Union.Same(chanName, ns.Union:Name())
end

local function isKnownMember(name)
  local full = ns:FullName(name)
  if full == ns:PlayerKey() then return true end
  local p = ns.Records:Get(full)
  return p ~= nil and (time() - (p.firstSeen or time())) > 86400
end

local function takeoversToday()
  local list = CircDB.union and CircDB.union.takeovers or {}
  local n, cutoff = 0, time() - 86400
  for _, t in ipairs(list) do if t > cutoff then n = n + 1 end end
  return n
end

function Prot:Migrate()
  local u = CircDB.union
  if not u then return end
  local nextName = ns.Union.Successor(u.name, (u.migrations or 0) + 1)
  local old = u.name
  table.insert(u.takeovers, time())
  LeaveChannelByName(old)
  CircDB.union = nil
  ns.Union:Bind(nextName, "moved to a fresh channel after a takeover")
  CircDB.union.migrations = (u.migrations or 0) + 1
  CircDB.union.takeovers = u.takeovers
  prompted = false
end

-- The player said no to moving (ui/Popups.lua); ask again on the next takeover sign
function Prot:Declined() prompted = false end

local lastWarned
function Prot:Takeover(reason)
  if prompted or not ns.Union:IsBound() then return end
  local u = CircDB.union
  if takeoversToday() >= 2 then
    -- Say so at most every 5 minutes; once a day has passed since the takeovers, ask again
    if lastWarned and GetTime() - lastWarned < 300 then return end
    lastWarned = GetTime()
    ns:Print("Ledger taken over again (" .. reason .. "). Automatic moving is not safe after two takeovers.",
      "One member should create a new ledger and invite everyone (Ledger tab).")
    return
  end
  prompted = true
  local nextName = ns.Union.Successor(u.name, (u.migrations or 0) + 1)
  ns:Print("Takeover detected:", reason)
  ns:Ask("TAKEOVER", u.name, reason, nextName)
end

-- Channel events about other users: password, owner, kicks, bans
ns:On("CHAT_MSG_CHANNEL_NOTICE_USER", function(kind, target, _, _, actor, _, _, _, chanName)
  if not isUnionChannel(chanName) then return end
  if kind == "OWNER_CHANGED" or kind == "CHANNEL_OWNER" then
    CircDB.union.owner = ns:FullName(target)
    if kind == "OWNER_CHANGED" and not isKnownMember(target) then
      Prot:Takeover("ownership went to " .. tostring(target) .. ", who is not a known member")
    end
  elseif kind == "PASSWORD_CHANGED" or kind == "SET_PASSWORD" then
    Prot:Takeover("a password was set by " .. tostring(target or actor))
  elseif kind == "PLAYER_KICKED" or kind == "PLAYER_BANNED" then
    local now = time()
    table.insert(recentKicks, now)
    while recentKicks[1] and recentKicks[1] < now - KICK_WINDOW do table.remove(recentKicks, 1) end
    if #recentKicks >= KICK_LIMIT then
      Prot:Takeover(#recentKicks .. " members kicked or banned in 5 minutes")
    end
  end
end)

-- Events about me: kicked, banned, or refused by a password
ns:On("CHAT_MSG_CHANNEL_NOTICE", function(kind, _, _, _, _, _, _, _, chanName)
  if not isUnionChannel(chanName) then return end
  if kind == "WRONG_PASSWORD" or kind == "BANNED" or kind == "PLAYER_BANNED" then
    Prot.lastKickAt = GetTime()
    Prot:Takeover("you were refused or banned from the channel")
  end
end)

ns:On("CHAT_MSG_CHANNEL_NOTICE_USER", function(kind, target, _, _, _, _, _, _, chanName)
  if not isUnionChannel(chanName) then return end
  if (kind == "PLAYER_KICKED" or kind == "PLAYER_BANNED") and ns:FullName(target) == ns:PlayerKey() then
    Prot.lastKickAt = GetTime()
    Prot:Takeover("you were kicked or banned")
  end
end)

-- Hand ownership to the most established online member before this owner leaves
function Prot:HandOff()
  local u = CircDB.union
  if not u or u.owner ~= ns:PlayerKey() then return end
  local best, bestScore
  for name, p in pairs(ns:UnionDB().players) do
    if name ~= ns:PlayerKey() and ns.Records:IsOnline(name) then
      local score = ns.Ledger and ns.Ledger:CountFor(name) or 0
      score = score * 1e10 + (time() - (p.firstSeen or time()))
      if not bestScore or score > bestScore then best, bestScore = name, score end
    end
  end
  if best then
    local ok = pcall(SetChannelOwner, u.name, ns:ShortName(best))
    ns:Debug("ownership handoff to", best, ok)
  end
end

ns:On("PLAYER_CAMPING", function() Prot:HandOff() end)
ns:Listen("UnionLeaving", function() Prot:HandOff() end)
