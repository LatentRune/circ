-- Minimal WoW API mock for offline tests
__clock = 1000
__outbox = {}
__timers = {}
__printed = {}
__events = {}  -- registered frames by event
local stubMeta
stubMeta = { __index = function(t, k)
  return function(...) return t end
end }
local function stub(extra)
  local o = extra or {}
  return setmetatable(o, stubMeta)
end

local frames = {}
function CreateFrame(kind, name, parent, template)
  local f = stub({})
  f.scripts = {}
  f.events = {}
  f.SetScript = function(self, s, fn) self.scripts[s] = fn end
  f.RegisterEvent = function(self, e) __events[e] = __events[e] or {}; table.insert(__events[e], self) end
  f.IsShown = function() return false end
  f.HasFocus = function() return false end
  f.CreateFontString = function() return stub({}) end
  f.SetText = function(self, t) self._text = t end
  f.GetText = function(self) return self._text or "" end
  if name then _G[name] = f end
  return f
end
function __fire(event, ...)
  for _, f in ipairs(__events[event] or {}) do f.scripts.OnEvent(f, event, ...) end
end

function GetTime() return __clock end
function time() return math.floor(__clock) + 1700000000 end
date = os.date
C_Timer = {
  After = function(d, fn) table.insert(__timers, { at = __clock + d, fn = fn }) end,
  NewTicker = function(d, fn)
    local t = { at = __clock + d, fn = fn, every = d }
    t.Cancel = function(self)
      for i, x in ipairs(__timers) do if x == self then table.remove(__timers, i) return end end
    end
    table.insert(__timers, t)
    return t
  end,
}
function __advance(sec)
  local target = __clock + sec
  while true do
    local nextT, idx
    for i, t in ipairs(__timers) do
      if t.at <= target and (not nextT or t.at < nextT.at) then nextT, idx = t, i end
    end
    if not nextT then break end
    __clock = nextT.at
    if nextT.every then nextT.at = nextT.at + nextT.every else table.remove(__timers, idx) end
    nextT.fn()
  end
  __clock = target
end

C_ChatInfo = {
  RegisterAddonMessagePrefix = function() return true end,
  SendAddonMessage = function(prefix, text, dist, target)
    assert(#text <= 255, "message too long: " .. #text)
    table.insert(__outbox, { prefix = prefix, text = text, dist = dist, target = target })
    return true
  end,
}

__me = "Alice"
function UnitName() return __me end
function GetUnitName() return __tradePartner end
function GetNormalizedRealmName() return "Realm" end
function GetRealmName() return "Realm" end
function UnitFactionGroup() return "Horde" end
function UnitClass() return "Warlock", "WARLOCK" end
__channels = {}
function GetChannelName(name) return __channels[name] or 0 end
function GetChannelList()
  local t = {}
  for n, id in pairs(__channels) do t[#t + 1] = id; t[#t + 1] = n; t[#t + 1] = false end
  return unpack(t)
end
function JoinPermanentChannel(name) __channels[name] = 5 end
function LeaveChannelByName(name) __channels[name] = nil end
function ChatFrame_RemoveChannel() end
function SetChannelOwner(c, n) __ownerHandoff = n end
NUM_CHAT_WINDOWS = 1
function strjoin(sep, ...) return table.concat({ ... }, sep) end
function tostringall(...) local t = { ... }; for i = 1, select("#", ...) do t[i] = tostring(t[i]) end; return unpack(t, 1, select("#", ...)) end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
tinsert = table.insert
UISpecialFrames = {}
__items = { [2589] = "Linen Cloth", [2996] = "Bolt of Linen Cloth", [2320] = "Coarse Thread", [2570] = "Linen Cloak", [990002] = "Test Widget" }
function GetItemInfo(id)
  if type(id) == "string" then
    for k, v in pairs(__items) do if v == id then return v, "|cffffffff|Hitem:" .. k .. "::|h[" .. v .. "]|h|r" end end
    return nil
  end
  local n = __items[id]
  if not n then return nil end
  return n, "|cffffffff|Hitem:" .. id .. "::|h[" .. n .. "]|h|r", 1, 1, 1, "", "", 20, "", "", 5
end
function GetCoinTextureString(c) return tostring(c) .. "c" end
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) table.insert(__printed, m) end }
UIErrorsFrame = { AddMessage = function() end }
StaticPopupDialogs = {}
function StaticPopup_Show(name, a, b, c, d) __popup = { name, a, b, c, d }; __dialog = {}; return __dialog end
function UnitIsPlayer() return false end
ACCEPT, DECLINE = "Accept", "Decline"
OKAY, CANCEL = "OK", "Cancel"
YES, NO = "Yes", "No"
function hooksecurefunc(a, b, c)
  local tbl, name, fn = _G, a, b
  if type(a) == "table" then tbl, name, fn = a, b, c end
  local orig = tbl[name]
  tbl[name] = function(...) local r = orig and orig(...); fn(...); return r end
end
function ChatEdit_InsertLink() return false end
Minimap = CreateFrame("Frame")
function GetCursorPosition() return 0, 0 end
function ChatEdit_GetActiveWindow() return nil end
function HandleModifiedItemClick() end
function IsModifiedClick() return true end
SlashCmdList = {}
GameTooltip = stub({}); ItemRefTooltip = stub({})
ERR_TRADE_COMPLETE = "Trade complete."

-- Tailoring window with two bundled recipes and one the bundle lacks
__trade = {
  { name = "Tailoring", kind = "header" },
  { name = "Bolt of Linen Cloth", kind = "optimal", spell = 2963, product = 2996, reagents = { { 2589, 2 } } },
  { name = "Linen Cloak", kind = "easy", spell = 2387, product = 2570, reagents = { { 2996, 1 }, { 2320, 1 } } },
  { name = "Test Widget", kind = "easy", spell = 990001, product = 990002, reagents = { { 2589, 3 } } },
}
function GetTradeSkillLine() return "Tailoring", 75, 150 end
function GetNumTradeSkills() return #__trade end
function GetTradeSkillInfo(i) return __trade[i].name, __trade[i].kind end
function GetTradeSkillRecipeLink(i) return __trade[i].spell and ("|cffffd000|Henchant:" .. __trade[i].spell .. "|h[x]|h|r") end
function GetTradeSkillItemLink(i) return "|cffffffff|Hitem:" .. __trade[i].product .. "::|h[x]|h|r" end
function GetTradeSkillNumMade() return 1, 1 end
function GetTradeSkillNumReagents(i) return #__trade[i].reagents end
function GetTradeSkillReagentInfo(i, j) return "r", nil, __trade[i].reagents[j][2], 0 end
function GetTradeSkillReagentItemLink(i, j) return "|cffffffff|Hitem:" .. __trade[i].reagents[j][1] .. "::|h[x]|h|r" end
function ExpandTradeSkillSubClass() end

-- Trade window
__tradeMoney = { me = 0, them = 0 }
function GetPlayerTradeMoney() return __tradeMoney.me end
function GetTargetTradeMoney() return __tradeMoney.them end
function GetTradePlayerItemLink() return nil end
function GetTradeTargetItemLink(i) if i == 1 and __tradeTargetItem then return "|cffffffff|Hitem:" .. __tradeTargetItem .. "::|h[x]|h|r" end end
function GetTradePlayerItemInfo() return nil end
function GetTradeTargetItemInfo(i) return "x", nil, 20 end

-- Price source
Auctionator = { API = { v1 = { GetAuctionPriceByItemID = function(_, id)
  local p = { [2589] = 50, [2996] = 150, [2320] = 30, [2570] = 400 }
  return p[id]
end } } }

function __load(path, ns)
  local chunk = assert(loadfile(path))
  chunk("Circ", ns)
end
