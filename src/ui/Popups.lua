-- ui/Popups.lua: the questions features/ asks the player with ns:Ask(kind, ...):
--   SWITCH    join or create another ledger, leaving this one    features/Union.lua
--   INVITE    a member invites you to their ledger                features/Union.lua
--   TAKEOVER  move the ledger to a fresh channel after a takeover features/Protection.lua
-- Each returns the popup, or nil when another popup is in the way.
local _, ns = ...
local U = ns.Union

StaticPopupDialogs["CIRC_SWITCH"] = {
  text = "%s\n\nThis account will leave %s. Only one ledger at a time.",
  button1 = OKAY or "OK",
  button2 = CANCEL or "Cancel",
  OnAccept = function(_, data) data() end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
}

StaticPopupDialogs["CIRC_INVITE"] = {
  text = "%s invites you to the ledger %s.%s",
  button1 = ACCEPT or "Accept",
  button2 = DECLINE or "Decline",
  OnAccept = function(self, data) U:AcceptInvite(self.inviter, data) end,
  OnCancel = function(self) U:DeclineInvite(self.inviter) end,
  timeout = 60,
  whileDead = true,
  hideOnEscape = true,
}

StaticPopupDialogs["CIRC_TAKEOVER"] = {
  text = "Your ledger %s looks taken over (%s).\n\nMove %s to a fresh channel? Its trades and members are kept, and other members move the same way.",
  button1 = YES,
  button2 = NO,
  OnAccept = function() ns.Protection:Migrate() end,
  OnCancel = function() ns.Protection:Declined() end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
}

local ASK = {}

-- what: the question; current: the ledger being left; go: runs on OK
function ASK.SWITCH(what, current, go)
  return ns:ShowPopup("CIRC_SWITCH", what, current, go)
end

-- sender invites to the channel name; warn says which ledger is left, or ""
function ASK.INVITE(sender, name, warn)
  local dialog = ns:ShowPopup("CIRC_INVITE", ns:ShortName(sender), U.Display(name), warn, name)
  if type(dialog) == "table" then dialog.inviter = sender end
  return dialog
end

-- name: the ledger's channel now; nextName: where it would move
function ASK.TAKEOVER(name, reason, nextName)
  return ns:ShowPopup("CIRC_TAKEOVER", U.Display(name), reason, U.Display(nextName))
end

function ns:Ask(kind, ...)
  return ASK[kind](...)
end
