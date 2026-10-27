-- features/Connection.lua: keeps this account in its ledger's channel. Joins it after
-- login and every loading screen, keeps trying while the server isn't ready, rejoins when
-- the channel drops, and keeps the channel's chat lines out of the chat windows.
-- Fires "UnionConnected" once the channel is there.
--
-- Keeps a short log of why the channel came and went, for /circ status (dev/Debug.lua).
-- Works with features/Channel.lua (which channel) and features/Union.lua (switching).
local _, ns = ...
local U = ns.Union

-- Keep the ledger channel's chat lines and join/leave notices out of the chat windows.
-- This filters the lines instead of removing the channel from the chat windows, which may
-- make the game drop the channel itself.
local function isLedgerChannel(chanName)
  return U:IsBound() and U.Same(chanName, U:Name())
end
if ChatFrame_AddMessageEventFilter then
  local function filter(_, _, _, _, _, _, _, _, _, _, chanName)
    return isLedgerChannel(chanName)
  end
  for _, event in ipairs({ "CHAT_MSG_CHANNEL", "CHAT_MSG_CHANNEL_JOIN", "CHAT_MSG_CHANNEL_LEAVE",
    "CHAT_MSG_CHANNEL_NOTICE", "CHAT_MSG_CHANNEL_NOTICE_USER" }) do
    ChatFrame_AddMessageEventFilter(event, filter)
  end
end

-- Connection log: why the ledger channel came and went, for /circ status
U.log = {}
local function logEvent(text)
  table.insert(U.log, date("%H:%M:%S") .. " " .. text)
  while #U.log > 12 do table.remove(U.log, 1) end
  ns:Debug("ledger channel:", text)
end
U.LogEvent = logEvent
local function noticeLog(kind, _, _, _, _, _, _, _, chanName)
  if isLedgerChannel(chanName) then logEvent(tostring(kind)) end
end
ns:On("CHAT_MSG_CHANNEL_NOTICE", noticeLog)
ns:On("CHAT_MSG_CHANNEL_NOTICE_USER", noticeLog)

-- Watch the connection and say so when the channel drops, with the last notice seen
local wasConnected
ns:Listen("UnionChanged", function() wasConnected = nil end)
local function watch()
  if not U:IsBound() then wasConnected = nil return end
  local now = U:ChannelID() ~= nil
  if wasConnected == true and not now then
    logEvent("channel lost")
    ns:Print("Lost the ledger channel. Last events:", table.concat(U.log, " | ", math.max(1, #U.log - 3)))
    U:EnsureConnected()
  elseif wasConnected == false and now then
    logEvent("connected")
  end
  wasConnected = now
end

local lastJoinTry = 0
-- retry = true for repeated attempts (Ledger tab), which are limited to one every 5 seconds
function U:JoinBound(retry)
  local name = self:Name()
  if not name then return end
  if not self:ChannelID() and (not retry or GetTime() - lastJoinTry > 5) then
    lastJoinTry = GetTime()
    JoinPermanentChannel(name)
  end
end

-- Join the ledger channel from a click or a typed command. The game may ignore channel joins
-- that don't come from the player's own input, so every Circ click and slash command tries
-- again while the channel is missing.
U.joinTries = 0
local lastNudge = 0
function U:Nudge()
  if not self:IsBound() or self:ChannelID() or GetTime() - lastNudge < 2 then return end
  lastNudge = GetTime()
  U.joinTries = U.joinTries + 1
  logEvent("join from a click")
  JoinPermanentChannel(self:Name())
  ns:After(1.5, function()
    if U:ChannelID() then
      ns:Fire("UnionConnected", U:Name())
    end
  end)
end

-- Rejoin the bound channel on every character, or put new accounts in the starter ledger.
-- Channels can take a while to become available after login or a game restart, and a join
-- sent too early is dropped, so keep trying every few seconds until the channel is there.
local reconnect
local function stopReconnect()
  if reconnect then reconnect:Cancel() reconnect = nil end
end
function U:EnsureConnected()
  stopReconnect()
  local tries = 0
  local function try()
    if not U:IsBound() then
      stopReconnect()
      U:Bind(U.START, "starter ledger for new users")
      return
    end
    if U:ChannelID() then
      stopReconnect()
      ns:Fire("UnionConnected", U:Name())
      return
    end
    tries = tries + 1
    U.joinTries = U.joinTries + 1
    logEvent("join try " .. tries)
    if tries > 30 then
      stopReconnect()
      ns:Print("Could not reach the ledger channel. Open Circ and press Connect on the Ledger tab.")
      return
    end
    lastJoinTry = GetTime()
    JoinPermanentChannel(U:Name())
  end
  ns:After(3, function()
    try()
    if U:IsBound() and not U:ChannelID() then
      reconnect = ns:Every(4, try)
    end
  end)
end

ns:Listen("Ready", function()
  ns:Every(3, watch)
  -- Old channel names with digits and underscores can't be joined; convert them
  local u = CircDB.union
  if u and type(u.name) == "string" and U.Normalize(u.name) and U.Normalize(u.name) ~= u.name then
    u.name = U.Normalize(u.name)
    ns:Print("Moved your ledger", U.Display(u.name), "to a channel name the server accepts.")
  end
  if not U:IsBound() then
    ns:After(5, function()
      if not U:IsBound() then
        U:Bind(U.START, "starter ledger for new users")
      end
    end)
    return
  end
  U:EnsureConnected()
end)

-- Loading screens can drop custom channels for a moment; check again after each one
ns:On("PLAYER_ENTERING_WORLD", function()
  if ns.ready and U:IsBound() and not U:ChannelID() then U:EnsureConnected() end
end)
ns:On("CHANNEL_UI_UPDATE", function()
  if U:IsBound() and U:ChannelID() then ns:Fire("UnionConnected", U:Name()) end
end)
