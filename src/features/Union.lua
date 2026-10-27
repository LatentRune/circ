-- features/Union.lua: which ledger this account is in, and moving between ledgers:
-- binding to a channel, creating a ledger, inviting players and answering invites,
-- leaving (back to START), and channels joined by hand with /join.
--
-- An account is in one ledger at a time. Joining or creating another asks first
-- (ns:Ask("SWITCH"), ui/Popups.lua), since the account leaves its current one. Every
-- channel other than the bound one is ignored, including Circ channels joined by hand.
-- Creating, inviting and leaving need Ledger management on (setting "advanced").
-- Works with features/Channel.lua (names) and features/Connection.lua (staying joined).
local _, ns = ...
local U = ns.Union

function U:Bind(name, reason)
  name = U.Normalize(name)
  if not name then return false end
  local abbrev = U.AbbrevOf(name)
  local old = CircDB.union
  local same = old and old.abbrev == abbrev
  CircDB.union = {
    name = name,
    abbrev = abbrev,
    migrations = same and old.migrations or 0,
    takeovers = same and old.takeovers or {},
    boundAt = time(),
  }
  ns:Print("This account is now in ledger", U.Display(name), reason and ("(" .. reason .. ")") or "")
  self:JoinBound()
  ns:Fire("UnionChanged", name)
  return true
end

-- Leave the current channel without rejoining anything
local function leaveCurrent()
  local name = U:Name()
  if not name then return end
  ns:Fire("UnionLeaving", name)
  U.leaving = true
  LeaveChannelByName(name)
  U.leaving = nil
  CircDB.union = nil
end

-- Switch to another ledger channel, asking first when that means leaving the current one
function U:SwitchTo(name, reason, confirmed)
  if self:Name() == name then
    ns:Print("Already in", U.Display(name))
    return
  end
  local function go()
    leaveCurrent()
    U:Bind(name, reason)
    if reason == "created" then U.createdAt = GetTime() end
  end
  if self:IsBound() and not confirmed then
    local what = (reason == "created" and "Create ledger " or "Join ledger ") .. U.Display(name) .. "?"
    if self:IsStart() then
      what = what .. "\n\nYou will leave the starter ledger, START."
    end
    if not ns:Ask("SWITCH", what, U.Display(self:Name()), go) then
      ns:Print("Close the open popup and try again.")
    end
  else
    go()
  end
end

-- Create a ledger from its 5-letter name; a random number goes into the hidden channel name
function U:Create(text)
  local abbrev, err = U.Validate(text)
  if not abbrev then
    ns:Print(err)
    return false, err
  end
  self:SwitchTo(U.NewName(abbrev), "created")
  return true
end

function U:JoinStart()
  self:SwitchTo(U.START, "starter ledger")
end

-- Invite another player. Their addon receives the hidden channel name and asks them to join.
function U:Invite(player)
  if not self:IsBound() or self:IsStart() then
    ns:Print("Create or join your own ledger before inviting.")
    return
  end
  if type(player) ~= "string" or player == "" then
    ns:Print("Usage: /circ invite <player>, or target a player and press Invite")
    return
  end
  local target = ns:FullName((player:gsub("^%l", string.upper)))
  if target == ns:PlayerKey() then
    ns:Print("You can't invite yourself. Invite another player; your alts join your ledger automatically.")
    return
  end
  U.pendingInvites = U.pendingInvites or {}
  U.pendingInvites[target] = GetTime()
  ns.Comm:Send("INVITE", { c = self:Name() }, target, true)
  ns:Print("Invite sent to", ns:ShortName(target) .. "...")
  -- Their addon answers right away; no answer means no Circ, offline, or the other faction
  ns:After(10, function()
    if U.pendingInvites[target] then
      U.pendingInvites[target] = nil
      ns:Print("No answer from", ns:ShortName(target) .. ". They need Circ installed, must be online, and on your faction.")
    end
  end)
end

-- Invite answers: "shown" when the popup appears, then "accepted", "declined" or "already"
local ANSWERS = {
  shown = "got your invite",
  accepted = "joined your ledger",
  declined = "declined your invite",
  already = "is already in your ledger",
  busy = "couldn't see your invite (another popup was open)",
}
ns:Listen("Msg:INVACK", function(data, sender)
  if type(data) ~= "table" or not ANSWERS[data.s] then return end
  if U.pendingInvites then U.pendingInvites[sender] = nil end
  ns:Print(ns:ShortName(sender), ANSWERS[data.s] .. ".")
end)

-- The player's answer to an invite popup
function U:AcceptInvite(inviter, name)
  ns.Comm:Send("INVACK", { s = "accepted" }, inviter, true)
  U:SwitchTo(name, "invited", true)
end
function U:DeclineInvite(inviter)
  ns.Comm:Send("INVACK", { s = "declined" }, inviter, true)
end

local lastInvite = 0
ns:Listen("Msg:INVITE", function(data, sender)
  if type(data) ~= "table" or not U.ValidName(data.c) then return end
  local name = U.Normalize(data.c)
  if U.Same(name, U.START) then return end
  if name == U:Name() then
    ns.Comm:Send("INVACK", { s = "already" }, sender, true)
    return
  end
  if GetTime() - lastInvite < 10 then return end
  lastInvite = GetTime()
  local warn = ""
  if U:IsStart() then
    warn = "\n\nYou will leave the starter ledger, START."
  elseif U:IsBound() then
    warn = "\n\nYou will leave " .. U:DisplayName() .. "."
  end
  if ns:Ask("INVITE", sender, name, warn) then
    ns.Comm:Send("INVACK", { s = "shown" }, sender, true)
  else
    ns.Comm:Send("INVACK", { s = "busy" }, sender, true)
  end
end)

-- Leaving a ledger returns the account to the starter ledger; leaving the starter ledger opts out
function U:Leave()
  local name = self:Name()
  if not name then ns:Print("Not in a ledger") return end
  if self:IsStart() then
    ns:Print("You're in START, the starter ledger. Create a ledger or accept an invite to move.")
    return
  end
  leaveCurrent()
  ns:Print("Left ledger", U.Display(name))
  self:Bind(U.START, "back to the starter ledger")
end

-- A CIRC channel joined by hand: bind if unbound, offer to switch if in the starter ledger,
-- otherwise ignore it
local function onNotice(kind, _, _, _, _, _, _, _, chanName)
  if type(chanName) ~= "string" then return end
  local name = U.Normalize(chanName) or chanName
  if kind == "YOU_LEFT" then
    -- A /leave by hand counts as leaving the ledger, unless a kick or ban caused it.
    -- Wait a moment, since the kick notice can arrive after the leave notice.
    if name ~= U:Name() or U.leaving then return end
    ns:After(1, function()
      local kicked = ns.Protection and ns.Protection.lastKickAt and GetTime() - ns.Protection.lastKickAt < 10
      if name == U:Name() and not kicked and not U:ChannelID() then
        ns:Print("You left the ledger channel by hand.")
        U:Leave()
      end
    end)
    return
  end
  if kind ~= "YOU_JOINED" and kind ~= "YOU_CHANGED" then return end
  if not U.ValidName(name) or name == U:Name() then return end
  if not U:IsBound() then
    U:Bind(name, "first ledger channel joined")
  elseif U:IsStart() then
    U:SwitchTo(name, "joined")
  else
    ns:Print("Ignoring that channel - this account's ledger is", U:DisplayName())
  end
end
ns:On("CHAT_MSG_CHANNEL_NOTICE", onNotice)
