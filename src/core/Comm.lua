-- core/Comm.lua: addon messages between members. Splits long messages into chunks, sends
-- through a queue that stays under the server's limit, and puts chunks back together.
-- Only the ledger channel and whispers are read; guild, party and other channels are not.
--
--   ns.Comm:Send(kind, data, target, prio)   target is "UNION" (the ledger channel) or a
--                                            player; data goes through core/Serialize.lua
--   ns:Listen("Msg:KIND", fn(data, sender, dist))   one per message kind received
--
-- features/Channel.lua tells Comm which channel is the ledger's (Comm:UseChannel).
local _, ns = ...
local Comm = {}
ns.Comm = Comm

local PREFIX = "CIRC"
local MAX_BODY = 240        -- 255 byte limit minus chunk header
local BURST = 6             -- tokens available at once
local REFILL = 1.25         -- seconds per token (server allows roughly 1 per second per prefix)

local queue = {}
local tokens = BURST
local lastRefill = 0
local nextMsgId = math.random(1, 1000)
local partial = {}          -- [sender .. id] = { n, parts = {}, got, at }

Comm.stats = { sent = 0, received = 0, dropped = 0 }

-- The ledger channel's name and its number in this session, or nil when not in one
local channelName, channelID = function() return nil end, function() return nil end
function Comm:UseChannel(nameFn, idFn) channelName, channelID = nameFn, idFn end

local function refill()
  local now = GetTime()
  local add = (now - lastRefill) / REFILL
  if add >= 1 then
    tokens = math.min(BURST, tokens + math.floor(add))
    lastRefill = now
  end
end

local function rawSend(item)
  local status, err
  if item.target == "UNION" then
    local id = channelID()
    if not id then return true end -- not in a ledger; drop silently
    status, err = ns.Compat.SendAddonMessage(PREFIX, item.text, "CHANNEL", tostring(id))
  else
    status, err = ns.Compat.SendAddonMessage(PREFIX, item.text, "WHISPER", item.target)
  end
  if status == "error" then
    ns:Debug("send failed", err)
    Comm.stats.dropped = Comm.stats.dropped + 1
    return true
  end
  if status == "throttled" then return false end -- retry later
  if status == "refused" then Comm.stats.dropped = Comm.stats.dropped + 1 end
  Comm.stats.sent = Comm.stats.sent + 1
  return true
end

local function pump()
  refill()
  while tokens >= 1 and #queue > 0 do
    local item = queue[1]
    if rawSend(item) then
      table.remove(queue, 1)
      tokens = tokens - 1
    else
      tokens = 0
      break
    end
  end
end

function Comm:QueueLength() return #queue end

-- Send a message. target is "UNION" or a player name. prio puts small control messages first.
function Comm:Send(kind, data, target, prio)
  local body = ns.Serialize.Encode({ t = kind, d = data, p = ns.protocol })
  local chunks = {}
  if #body <= MAX_BODY then
    chunks[1] = "S" .. body
  else
    nextMsgId = nextMsgId % 46000 + 1
    local id = ns.To36(nextMsgId)
    local n = math.ceil(#body / MAX_BODY)
    for i = 1, n do
      chunks[i] = "M" .. id .. ":" .. i .. ":" .. n .. "|" .. body:sub((i - 1) * MAX_BODY + 1, i * MAX_BODY)
    end
  end
  for i = 1, #chunks do
    local item = { text = chunks[i], target = target }
    if prio and #chunks == 1 then
      table.insert(queue, 1, item)
    else
      queue[#queue + 1] = item
    end
  end
  ns:Debug("queued", kind, "to", target, #chunks, "chunk(s), queue", #queue)
end

local function deliver(body, sender, dist)
  local msg, err = ns.Serialize.Decode(body)
  if not msg or type(msg) ~= "table" or type(msg.t) ~= "string" then
    ns:Debug("bad message from", sender, err)
    return
  end
  if (msg.p or 0) > ns.protocol then
    ns.newerVersionSeen = true
  end
  Comm.stats.received = Comm.stats.received + 1
  ns:Debug("recv", msg.t, "from", sender, dist)
  ns:Fire("Msg:" .. msg.t, msg.d, sender, dist)
end

local function onAddonMessage(prefix, text, channel, sender, target, _, localID, chanName)
  if prefix ~= PREFIX then return end
  sender = ns:FullName(sender)
  if sender == ns:PlayerKey() then return end

  local dist
  if channel == "WHISPER" then
    dist = "WHISPER"
  elseif channel == "CHANNEL" then
    if not channelName() then return end
    local bound = channelName():lower()
    local myId = channelID()
    local named = (type(chanName) == "string" and chanName ~= "" and chanName)
      or (type(target) == "string" and target ~= "" and target)
    if named then
      if not named:lower():find(bound, 1, true) then return end
    elseif localID and myId and tonumber(localID) ~= myId then
      return
    end
    dist = "UNION"
  else
    return -- guild, party and other channels are ignored on purpose
  end

  ns:Fire("Seen", sender)

  local kind = text:sub(1, 1)
  if kind == "S" then
    deliver(text:sub(2), sender, dist)
  elseif kind == "M" then
    local id, i, n, chunk = text:match("^M(%w+):(%d+):(%d+)|(.*)$")
    if not id then return end
    i, n = tonumber(i), tonumber(n)
    local key = sender .. id
    local p = partial[key]
    if not p then
      p = { n = n, parts = {}, got = 0, at = GetTime() }
      partial[key] = p
    end
    if not p.parts[i] then
      p.parts[i] = chunk
      p.got = p.got + 1
    end
    if p.got == p.n then
      partial[key] = nil
      deliver(table.concat(p.parts), sender, dist)
    end
  end
end

ns:On("CHAT_MSG_ADDON", onAddonMessage)

ns:Listen("Ready", function()
  C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
  lastRefill = GetTime()
  ns:Every(0.2, pump)
  -- Forget half-received messages after two minutes
  ns:Every(60, function()
    local now = GetTime()
    for k, p in pairs(partial) do
      if now - p.at > 120 then partial[k] = nil end
    end
  end)
end)
