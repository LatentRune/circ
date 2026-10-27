-- The game world a scenario describes: who you are, what is in your bags, which chat
-- channels exist, which price addon is installed, what the profession window shows. The
-- game's API functions below answer from it. Ledger members talk to you through
-- Member() in sim.lua, which speaks Circ's wire format the way another client would.

NOW = 1000
function GetTime() return NOW end
function time() return 1700000000 + math.floor(NOW) end
-- Dates are printed in UTC so a run looks the same on every machine.
function date(fmt, t) return os.date("!" .. (fmt or "%c"), t or time()) end
math.randomseed(42)

WORLD = {
  player = { name = "Alice", realm = "Realm", class = "WARLOCK", faction = "Horde" },
  items = {},       -- [itemID] = { name, quality, icon, vendor }
  bags = {},        -- { { id, count, bound, quality? }, ... } in slot order, bag 0 first
  channels = {},    -- [lower-case name] = channel number
  channelsWork = true,  -- false: joins are ignored, like right after login
  tradeskill = nil, -- { name, rank, max, recipes = { { name, kind, spell, product, made, reagents = { {id, n} } } } }
  priceAddon = nil, -- { [itemID] = copper } served as Auctionator
  sent = {},        -- addon messages Circ sent: { dist, target, text }
  chat = {},        -- lines printed to the chat window
  errors = {},      -- lines in the red/green text at the top of the screen
}

------------------------------------------------------------------------------
-- You
------------------------------------------------------------------------------

local CLASS_NAMES = { WARRIOR = "Warrior", MAGE = "Mage", ROGUE = "Rogue", DRUID = "Druid", HUNTER = "Hunter",
  SHAMAN = "Shaman", PRIEST = "Priest", WARLOCK = "Warlock", PALADIN = "Paladin" }
RAID_CLASS_COLORS = {}
for token, c in pairs({
  WARRIOR = { 0.78, 0.61, 0.43 }, MAGE = { 0.25, 0.78, 0.92 }, ROGUE = { 1, 0.96, 0.41 },
  DRUID = { 1, 0.49, 0.04 }, HUNTER = { 0.67, 0.83, 0.45 }, SHAMAN = { 0, 0.44, 0.87 },
  PRIEST = { 1, 1, 1 }, WARLOCK = { 0.53, 0.53, 0.93 }, PALADIN = { 0.96, 0.55, 0.73 },
}) do
  RAID_CLASS_COLORS[token] = { r = c[1], g = c[2], b = c[3],
    colorStr = string.format("ff%02x%02x%02x", math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5)) }
end
-- The game's class icon sheet: each class is a quarter-by-quarter cell.
CLASS_ICON_TCOORDS = {
  WARRIOR = { 0, 0.25, 0, 0.25 }, MAGE = { 0.25, 0.49609375, 0, 0.25 }, ROGUE = { 0.49609375, 0.7421875, 0, 0.25 },
  DRUID = { 0.7421875, 0.98828125, 0, 0.25 }, HUNTER = { 0, 0.25, 0.25, 0.5 }, SHAMAN = { 0.25, 0.49609375, 0.25, 0.5 },
  PRIEST = { 0.49609375, 0.7421875, 0.25, 0.5 }, WARLOCK = { 0.7421875, 0.98828125, 0.25, 0.5 },
  PALADIN = { 0, 0.25, 0.5, 0.75 },
}

function UnitName(u) if u == "player" then return WORLD.player.name end end
function UnitClass(u) if u == "player" then return CLASS_NAMES[WORLD.player.class], WORLD.player.class end end
function UnitFactionGroup() return WORLD.player.faction end
function GetRealmName() return WORLD.player.realm end
function GetNormalizedRealmName() return WORLD.player.realm end
function UnitIsPlayer() return WORLD.target ~= nil end
function GetUnitName(u)
  if u == "target" then return WORLD.target end
  if u == "NPC" then return WORLD.tradePartner end
end

------------------------------------------------------------------------------
-- Items and bags
------------------------------------------------------------------------------

local QUALITY_COLOR = { [0] = "ff9d9d9d", "ffffffff", "ff1eff00", "ff0070dd", "ffa335ee", "ffff8000" }

-- Item(id, name, quality, icon, vendor price): adds an item the game knows about.
function Item(id, name, quality, icon, vendor)
  WORLD.items[id] = { name = name, quality = quality or 1, icon = icon or "Interface\\Icons\\INV_Misc_QuestionMark", vendor = vendor or 0 }
end

local function link(id)
  local it = WORLD.items[id]
  return "|c" .. QUALITY_COLOR[it.quality] .. "|Hitem:" .. id .. "::::::::60:::::|h[" .. it.name .. "]|h|r"
end

function GetItemInfo(id)
  if type(id) == "string" then
    local n = tonumber(id:match("item:(%d+)"))
    if n then id = n else
      for k, it in pairs(WORLD.items) do if it.name == id then id = k; break end end
    end
  end
  local it = WORLD.items[id]
  if not it then return nil end
  return it.name, link(id), it.quality, 1, 1, "", "", 20, "", it.icon, it.vendor
end
function GetItemIcon(id) local it = WORLD.items[id]; return it and it.icon end

local function slotOf(bag, slot)
  local i = bag * 16 + slot
  return WORLD.bags[i]
end
C_Container = {
  GetContainerNumSlots = function(bag) return 16 end,
  GetContainerItemID = function(bag, slot) local s = slotOf(bag, slot); return s and s[1] end,
  GetContainerItemInfo = function(bag, slot)
    local s = slotOf(bag, slot)
    if not s then return nil end
    local it = WORLD.items[s[1]] or {}
    return { itemID = s[1], stackCount = s[2] or 1, isBound = s[3] or false, quality = it.quality or 1 }
  end,
}

------------------------------------------------------------------------------
-- Chat, channels and addon messages
------------------------------------------------------------------------------

DEFAULT_CHAT_FRAME = { AddMessage = function(_, text) WORLD.chat[#WORLD.chat + 1] = tostring(text) end }
UIErrorsFrame = { AddMessage = function(_, text) WORLD.errors[#WORLD.errors + 1] = tostring(text) end }
CHAT_FILTERS = {}
function ChatFrame_AddMessageEventFilter(event, fn)
  CHAT_FILTERS[event] = CHAT_FILTERS[event] or {}
  table.insert(CHAT_FILTERS[event], fn)
end

function GetChannelName(name)
  if type(name) ~= "string" then return 0 end
  local id = WORLD.channels[name:lower()]
  return id or 0, id and name or nil
end
function GetChannelList()
  local names = {}
  for n in pairs(WORLD.channels) do names[#names + 1] = n end
  table.sort(names, function(a, b) return WORLD.channels[a] < WORLD.channels[b] end)
  local t = {}
  for _, n in ipairs(names) do t[#t + 1] = WORLD.channels[n]; t[#t + 1] = n; t[#t + 1] = false end
  return unpack(t)
end
-- Channel numbers handed out in order, after the game's own General and Trade.
local nextChannel = 5
function JoinPermanentChannel(name)
  if not WORLD.channelsWork or type(name) ~= "string" then return end
  if not WORLD.channels[name:lower()] then
    WORLD.channels[name:lower()] = nextChannel
    nextChannel = nextChannel + 1
    local id = WORLD.channels[name:lower()]
    After(0.2, function()
      FireEvent("CHAT_MSG_CHANNEL_NOTICE", "YOU_JOINED", "", "", id .. ". " .. name, "", "", 0, id, name)
      FireEvent("CHANNEL_UI_UPDATE")
    end)
  end
end
JoinChannelByName = JoinPermanentChannel
function LeaveChannelByName(name)
  if type(name) == "string" then WORLD.channels[name:lower()] = nil end
end
function SetChannelOwner() end

C_ChatInfo = {
  RegisterAddonMessagePrefix = function() return true end,
  SendAddonMessage = function(prefix, text, dist, target)
    assert(#text <= 255, "addon message over 255 bytes")
    WORLD.sent[#WORLD.sent + 1] = { prefix = prefix, dist = dist, target = tostring(target), text = text }
    return true
  end,
}

------------------------------------------------------------------------------
-- The profession window, trading and vendors
------------------------------------------------------------------------------

local function ts() return WORLD.tradeskill end
function GetTradeSkillLine() local t = ts(); if t then return t.name, t.rank, t.max end return "UNKNOWN", 0, 0 end
function GetNumTradeSkills() return ts() and #ts().recipes or 0 end
function GetTradeSkillInfo(i) local r = ts().recipes[i]; return r.name, r.kind or "easy" end
function GetTradeSkillRecipeLink(i) local r = ts().recipes[i]; return r.spell and ("|cffffd000|Henchant:" .. r.spell .. "|h[" .. r.name .. "]|h|r") end
function GetTradeSkillItemLink(i) local r = ts().recipes[i]; return r.product and WORLD.items[r.product] and link(r.product) end
function GetTradeSkillNumMade(i) local r = ts().recipes[i]; return r.made or 1, r.made or 1 end
function GetTradeSkillNumReagents(i) return #(ts().recipes[i].reagents or {}) end
function GetTradeSkillReagentInfo(i, j) local g = ts().recipes[i].reagents[j]; return "", nil, g[2], 0 end
function GetTradeSkillReagentItemLink(i, j) local g = ts().recipes[i].reagents[j]; return WORLD.items[g[1]] and link(g[1]) end
function ExpandTradeSkillSubClass() end
function GetNumCrafts() return 0 end

function GetPlayerTradeMoney() return 0 end
function GetTargetTradeMoney() return 0 end
function GetTradePlayerItemLink() end
function GetTradeTargetItemLink() end
ERR_TRADE_COMPLETE = "Trade complete."

function GetAuctionSellItemInfo() return WORLD.auctionItem and WORLD.items[WORLD.auctionItem].name end

-- A price addon, when the scenario installs one.
function InstallAuctionator(prices)
  Auctionator = { API = { v1 = { GetAuctionPriceByItemID = function(_, id) return prices[id] end } } }
end

------------------------------------------------------------------------------
-- Money, popups, tooltips, links and the rest of the game's helpers Circ calls
------------------------------------------------------------------------------

-- Like the game: "1|T...GoldIcon:0:0:2:0|t 20|T...SilverIcon...|t".
function GetCoinTextureString(copper)
  copper = math.floor(copper)
  local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
  local parts = {}
  if g > 0 then parts[#parts + 1] = g .. "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t" end
  if s > 0 then parts[#parts + 1] = s .. "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t" end
  if c > 0 or #parts == 0 then parts[#parts + 1] = c .. "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t" end
  return table.concat(parts, " ")
end

FRIENDS_TEXTURE_ONLINE = "Interface\\FriendsFrame\\StatusIcon-Online"
FRIENDS_TEXTURE_OFFLINE = "Interface\\FriendsFrame\\StatusIcon-Offline"
OKAY, CANCEL, ACCEPT, DECLINE, YES, NO = "Okay", "Cancel", "Accept", "Decline", "Yes", "No"
UISpecialFrames = {}
BackdropTemplateMixin = {}
SlashCmdList = {}
StaticPopupDialogs = {}
SOUNDKIT = { IG_CHARACTER_INFO_TAB = 841 }
function PlaySound() end
function strjoin(sep, ...) return table.concat({ ... }, sep) end
function tostringall(...)
  local n = select("#", ...)
  local t = { ... }
  for i = 1, n do t[i] = tostring(t[i]) end
  return unpack(t, 1, n)
end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
tinsert, tremove = table.insert, table.remove
function hooksecurefunc(a, b, c)
  local tbl, name, fn = _G, a, b
  if type(a) == "table" then tbl, name, fn = a, b, c end
  local orig = tbl[name]
  tbl[name] = function(...) local r = { orig(...) }; fn(...); return unpack(r) end
end
function IsModifiedClick() return WORLD.shiftDown or false end
function HandleModifiedItemClick() return false end
function ChatEdit_InsertLink() return false end
function ChatEdit_GetActiveWindow() return nil end
function ChatFrame_SendTell(name) WORLD.tell = name end
function OpenStackSplitFrame() end

-- Popups, the way the game's StaticPopup_Show works: two text arguments formatted into
-- the dialog's text, then data, then an optional frame to insert.
function StaticPopup_Show(which, text1, text2, data, insertedFrame)
  local info = StaticPopupDialogs[which]
  if not info then error("Dialog " .. tostring(which) .. " does not exist.") end
  -- The game formats the text first, with only the two text arguments.
  local text = string.format(info.text, text1, text2)
  if insertedFrame ~= nil and type(insertedFrame) ~= "table" then
    error("insertedFrame must be a frame, got " .. type(insertedFrame))
  end
  local d = StaticPopup1
  if not d then
    d = CreateFrame("Frame", "StaticPopup1", UIParent, "BackdropTemplate")
    d:SetBackdrop({ insets = { left = 4 } })
    d:SetBackdropColor(0.04, 0.04, 0.06, 0.95)
    d:SetBackdropBorderColor(0.8, 0.8, 0.8, 1)
    d:SetFrameStrata("DIALOG")
    d:SetSize(320, 110)
    d:SetPoint("TOP", 0, -135)
    d.text = d:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    d.text:SetPoint("TOP", 0, -16)
    d.text:SetWidth(290)
    d.button1 = CreateFrame("Button", "StaticPopup1Button1", d, "UIPanelButtonTemplate")
    d.button1:SetSize(128, 21)
    d.button2 = CreateFrame("Button", "StaticPopup1Button2", d, "UIPanelButtonTemplate")
    d.button2:SetSize(128, 21)
    d.editBox = CreateFrame("EditBox", "StaticPopup1EditBox", d, "InputBoxTemplate")
    d.editBox:SetSize(130, 32)
    d.editBox:SetPoint("BOTTOM", 0, 45)
    d:Hide()
  end
  d:SetFrameStrata("DIALOG")
  d.which, d.data = which, data
  d.text:SetText(text)
  d.button1:SetText(info.button1 or "")
  d.button2:SetText(info.button2 or "")
  d.button1:ClearAllPoints(); d.button2:ClearAllPoints()
  if info.button2 then
    d.button1:SetPoint("BOTTOMRIGHT", d, "BOTTOM", -6, 16)
    d.button2:SetPoint("BOTTOMLEFT", d, "BOTTOM", 6, 16)
    d.button2:Show()
  else
    d.button1:SetPoint("BOTTOM", 0, 16)
    d.button2:Hide()
  end
  d.editBox:SetShown(info.hasEditBox and true or false)
  d:SetHeight(info.hasEditBox and 130 or 110)
  d:Show()
  if info.OnShow then info.OnShow(d, data) end
  WORLD.popup = which
  return d
end

-- The item tooltip: the item's name in its quality color, then whatever addons add.
local tipItem
function GameTooltip:SetHyperlink(l)
  local id = tonumber(tostring(l):match("item:(%d+)"))
  local it = id and WORLD.items[id]
  tipItem = id
  if it then
    local c = QUALITY_COLOR[it.quality]
    self:SetText(it.name, tonumber(c:sub(3, 4), 16) / 255, tonumber(c:sub(5, 6), 16) / 255, tonumber(c:sub(7, 8), 16) / 255)
  else
    self:SetText("Item " .. tostring(id), 1, 1, 1)
  end
  if self._scripts.OnTooltipSetItem then self._scripts.OnTooltipSetItem(self) end
end
function GameTooltip:GetItem()
  if tipItem and WORLD.items[tipItem] then return WORLD.items[tipItem].name, link(tipItem) end
end
ItemRefTooltip = CreateFrame("GameTooltip", "ItemRefTooltip", UIParent)
ItemRefTooltip._shown = false

Minimap = CreateFrame("Frame", "Minimap", UIParent)
Minimap:SetSize(140, 140)
Minimap:SetPoint("TOPRIGHT", -18, -24)
do
  local face = Minimap:CreateTexture(nil, "BACKGROUND")
  face:SetAllPoints()
  face:SetTexture("Interface\\Minimap\\MinimapFace")
end
function Minimap:GetEffectiveScale() return 1 end

------------------------------------------------------------------------------
-- Timers: C_Timer runs from the fake clock, in time order, so runs repeat exactly.
------------------------------------------------------------------------------

local timers, seq = {}, 0
function After(delay, fn)
  seq = seq + 1
  timers[#timers + 1] = { at = NOW + delay, fn = fn, seq = seq }
end
C_Timer = {
  After = After,
  NewTicker = function(every, fn, times)
    local t = { every = every, fn = fn, left = times }
    function t:Cancel() self.cancelled = true end
    function t:IsCancelled() return self.cancelled end
    local function tick()
      if t.cancelled then return end
      fn(t)
      if t.left then t.left = t.left - 1; if t.left <= 0 then return end end
      After(every, tick)
    end
    After(every, tick)
    return t
  end,
}

-- Runs every timer due by `target`, earliest first.
function RunTimers(target)
  while true do
    local best, bi
    for i, t in ipairs(timers) do
      if t.at <= target and (not best or t.at < best.at or (t.at == best.at and t.seq < best.seq)) then best, bi = t, i end
    end
    if not best then return end
    table.remove(timers, bi)
    if best.at > NOW then NOW = best.at end
    best.fn()
  end
end
