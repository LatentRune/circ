-- ui/widgets/Text.lua: how Circ writes things in its window: item links and icons, player
-- names in class color with an online dot, "5m ago", plurals, and the text colors.
-- Shared by every tab (ui/Lookup.lua, ui/Requests.lua, ui/Ledger.lua, ui/Prices.lua).
local _, ns = ...
local T = {}
ns.Text = T

T.QUESTION_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
T.GRAY, T.GOLD, T.GREEN = "|cff8a8a8a", "|cffffd100", "|cff40ff40"

function T.ItemText(itemID)
  local _, link = GetItemInfo(itemID)
  return link or ns:ItemName(itemID)
end

function T.ItemIcon(itemID)
  return ns.Compat.ItemIcon(itemID) or T.QUESTION_ICON
end

function T.ClassOf(player)
  if player == ns:PlayerKey() then return select(2, UnitClass("player")) end
  local p = ns.Records:Get(player)
  return p and p.cls
end

function T.ClassColor(cls)
  local c = cls and RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls]
  if not c then return "|cffffffff" end
  if c.colorStr then return "|c" .. c.colorStr end
  return string.format("|cff%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255)
end

-- A member's name in class color with an online or offline dot
function T.PlayerText(name, online)
  local short = ns:ShortName(name)
  if name == ns:PlayerKey() then short = short .. " (you)" end
  local dot = online and (FRIENDS_TEXTURE_ONLINE or "Interface\\FriendsFrame\\StatusIcon-Online")
    or (FRIENDS_TEXTURE_OFFLINE or "Interface\\FriendsFrame\\StatusIcon-Offline")
  local color = online and T.ClassColor(T.ClassOf(name)) or T.GRAY
  return "|T" .. dot .. ":12|t " .. color .. short .. "|r"
end

function T.Ago(t)
  if not t then return "?" end
  local d = time() - t
  if d < 120 then return "now" end
  if d < 7200 then return math.floor(d / 60) .. "m ago" end
  if d < 172800 then return math.floor(d / 3600) .. "h ago" end
  return math.floor(d / 86400) .. "d ago"
end

function T.Trim(text)
  if type(text) ~= "string" then return "" end
  return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- { { itemID, value }, ... } sorted by item name
function T.SortedByName(set)
  local list = {}
  for itemID, v in pairs(set) do list[#list + 1] = { itemID, v } end
  table.sort(list, function(a, b) return ns:ItemName(a[1]) < ns:ItemName(b[1]) end)
  return list
end

function T.CountKeys(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

function T.Plural(n, one, many)
  return n .. " " .. (n == 1 and one or many)
end
