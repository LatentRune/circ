-- ui/Ledger.lua: the Ledger tab. The members (online first, with professions and recipe
-- counts), the gold traded with each over the last 7 days, and every trade, marked
-- confirmed once both sides reported it (features/Ledger.lua). With Ledger management on
-- (setting "advanced"), a toolbar to invite a player, create a ledger or leave this one
-- (features/Union.lua).
local _, ns = ...
local UI = ns.UI
local W, T = ns.Widgets, ns.Text
local GRAY, GREEN = T.GRAY, T.GREEN

function UI.builders.ledger()
  local u = CircDB.union
  local names = {}
  for name in pairs(ns.Records:All()) do names[#names + 1] = name end
  local online = 0
  for _, name in ipairs(names) do if ns.Records:IsOnline(name) then online = online + 1 end end
  if UI.unionHint then
    UI:SetHeader("Ledger " .. ns.Union:DisplayName(), UI.unionHint)
  elseif not u then
    UI:SetHeader("No ledger", "Accept an invite to join a ledger.")
  elseif not ns.Union:ChannelID() then
    UI:SetHeader("Ledger " .. ns.Union:DisplayName(), "|cffffff00Connecting...|r")
  else
    UI:SetHeader("Ledger " .. ns.Union:DisplayName(),
      T.Plural(#names, "member", "members") .. ", " .. online .. " online." ..
      (CircDB.settings.advanced and "  Invite a player by name, or target them and press Invite." or ""))
  end
  if not u then return {} end
  local out = {}
  if not ns.Union:ChannelID() then
    out[#out + 1] = { left = "|cffffff00Not connected to your ledger's channel yet.|r",
      tip = "Circ keeps trying by itself. Press Connect to try right now.",
      action = { label = "Connect", fn = function() ns.Union:Nudge() end } }
  end

  out[#out + 1] = { header = true, left = "Members", right = GRAY .. "recipes|r" }
  table.sort(names, function(a, b)
    local oa, ob = ns.Records:IsOnline(a) and 1 or 0, ns.Records:IsOnline(b) and 1 or 0
    if oa ~= ob then return oa > ob end
    return a < b
  end)
  for _, name in ipairs(names) do
    local p = ns.Records:Get(name)
    local profs = {}
    for prof, rank in pairs(p.profs or {}) do profs[#profs + 1] = prof .. " " .. rank end
    table.sort(profs)
    local isOnline = ns.Records:IsOnline(name)
    out[#out + 1] = { cls = p.cls or T.ClassOf(name), left = T.PlayerText(name, isOnline) .. GRAY .. "  " .. table.concat(profs, ", ") .. "|r",
      right = T.CountKeys(p.recipes or {}) .. (isOnline and "" or (GRAY .. "  " .. (p.relayed and "relayed" or ("seen " .. T.Ago(p.lastSeen))) .. "|r")),
      onClick = function() UI:LookupPlayer(name) end, tip = "Click to see what " .. ns:ShortName(name) .. " makes and buys.",
      whisper = name ~= ns:PlayerKey() and name or nil }
  end

  local per, total = ns.Ledger:Totals(7)
  out[#out + 1] = { header = true, left = "Gold traded, last 7 days: " .. ns:Money(total), right = GRAY .. "in / out|r" }
  local flow = {}
  for name in pairs(per) do flow[#flow + 1] = name end
  table.sort(flow, function(a, b) return per[a].inGold + per[a].outGold > per[b].inGold + per[b].outGold end)
  for _, name in ipairs(flow) do
    out[#out + 1] = { cls = T.ClassOf(name), left = T.PlayerText(name, ns.Records:IsOnline(name)) .. GRAY .. "  " .. T.Plural(per[name].trades, "trade", "trades") .. "|r",
      right = ns:Money(per[name].inGold) .. " / " .. ns:Money(per[name].outGold) }
  end
  if #flow == 0 then out[#out + 1] = { left = GRAY .. "No gold traded between members yet.|r" } end

  local list = ns.Ledger:Sorted()
  if #list > 0 then
    out[#out + 1] = { header = true, left = "Trades" }
    for _, e in ipairs(list) do
      local parts = {}
      if e.ma > 0 then parts[#parts + 1] = ns:ShortName(e.a) .. " paid " .. ns:Money(e.ma) end
      if e.mb > 0 then parts[#parts + 1] = ns:ShortName(e.b) .. " paid " .. ns:Money(e.mb) end
      if e.ia ~= "" then parts[#parts + 1] = ns:ShortName(e.a) .. " gave items" end
      if e.ib ~= "" then parts[#parts + 1] = ns:ShortName(e.b) .. " gave items" end
      out[#out + 1] = { left = GRAY .. date("%m-%d %H:%M", e.t) .. "|r  " .. table.concat(parts, ", "),
        right = e.confirmed and (GREEN .. "confirmed|r") or "|cffffff00one side|r" }
    end
  end
  return out
end

-- Invite a player by name; create a ledger from 5 letters; leave
function UI:BuildLedgerToolbar(frame)
  local y = UI.TOOLBAR_Y
  local playerBox = W.EditBox(frame, "CircInviteBox", 22, y, 150, 40)
  W.Placeholder(playerBox, "Player name")
  local inviteButton = W.Button(frame, "Invite", 178, y, 70)
  local nameBox = W.EditBox(frame, "CircUnionBox", 290, y, 70, 5)
  W.Placeholder(nameBox, "NAME")
  local createButton = W.Button(frame, "Create", 364, y, 70)
  local leaveButton = W.Button(frame, "Leave", 508, y, 70)

  local function validate()
    local text = nameBox:GetText()
    local ok, err = ns.Union.Validate(text)
    if ok then
      UI.unionHint = GREEN .. "Press Create to start the ledger " .. ok .. "|r"
      createButton:Enable()
    else
      UI.unionHint = (type(text) == "string" and text ~= "") and ("|cffff5050" .. err .. "|r") or nil
      createButton:Disable()
    end
    if UI.current == "ledger" then UI:Refresh() end
  end
  local function create()
    if ns.Union.Validate(nameBox:GetText()) then
      ns.Union:Create(nameBox:GetText())
      nameBox:SetText("")
      nameBox:ClearFocus()
    end
  end
  local function invite()
    local who = playerBox:GetText()
    if type(who) ~= "string" or who == "" then
      who = UnitIsPlayer("target") and GetUnitName("target", true) or ""
    end
    ns.Union:Invite(who)
    playerBox:SetText("")
    playerBox:ClearFocus()
  end
  nameBox:SetScript("OnTextChanged", validate)
  nameBox:SetScript("OnEnterPressed", create)
  createButton:SetScript("OnClick", create)
  playerBox:SetScript("OnEnterPressed", invite)
  inviteButton:SetScript("OnClick", invite)
  leaveButton:SetScript("OnClick", function() ns.Union:Leave() end)
  createButton:Disable()
  W.Tip(nameBox, "Name for a new ledger: exactly 5 letters.")
  W.Tip(createButton, "Start a new ledger. You'll leave your current one.")
  W.Tip(playerBox, "Player to invite. Leave empty to invite your target.")
  W.Tip(inviteButton, "Invite a player. They need Circ installed.")
  W.Tip(leaveButton, "Leave this ledger and go back to START.")
  UI.toolbars.ledger = {}
  UI.toolbars.ledgerAdvanced = { playerBox, inviteButton, nameBox, createButton, leaveButton }

end
