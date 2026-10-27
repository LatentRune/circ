-- core/Namespace.lua: the table every Circ file shares, and small helpers they all use:
-- chat output, player names, item names, money text and parsing, and the hash and base-36
-- helpers that keep messages short.
--
-- Every file starts with `local ADDON, ns = ...`; the game hands each one the same `ns`.
-- Files share through `ns` only and add no globals of their own (see .luacheckrc for the
-- few the game requires). Loaded first; see Circ.toc for the order.
local ADDON, ns = ...
ns.name = ADDON
ns.version = "0.13.2-test"
ns.protocol = 1
ns.Dev = false -- true when the testing tools in dev/ are in this build (dev/Debug.lua)

function ns:Print(...)
  local msg = strjoin(" ", tostringall(...))
  DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99Circ|r: " .. msg)
end

-- Gray lines in chat, only while debug messages are on (Settings, or /circ debug)
function ns:Debug(...)
  if CircDB and CircDB.debug then
    local msg = strjoin(" ", tostringall(...))
    DEFAULT_CHAT_FRAME:AddMessage("|cff999999Circ debug|r: " .. msg)
  end
end

-- Player identity, always Name-Realm
function ns:PlayerKey()
  if not self.playerKey then
    local name = UnitName("player")
    local realm = GetNormalizedRealmName() or GetRealmName():gsub("%s", "")
    self.playerKey = name .. "-" .. realm
  end
  return self.playerKey
end

function ns:FullName(name)
  if not name or name == "" then return nil end
  if name:find("-", 1, true) then return name end
  local realm = GetNormalizedRealmName() or GetRealmName():gsub("%s", "")
  return name .. "-" .. realm
end

function ns:ShortName(full)
  return (full or "?"):match("^[^-]+") or full
end

function ns:ItemIDFromLink(link)
  if type(link) ~= "string" then return nil end
  local id = link:match("item:(%d+)")
  return id and tonumber(id)
end

-- The game's name for an item, else the bundled name (data/BoeData.lua), else "item:123"
function ns:ItemName(itemID)
  local name = GetItemInfo(itemID) or (ns.ItemNames and ns.ItemNames[itemID])
  return name or ("item:" .. itemID)
end

function ns:Money(copper)
  if not copper or copper <= 0 then return "-" end
  return GetCoinTextureString(math.floor(copper + 0.5))
end

-- Parse "1g20s5c", "12s", "1.5" (gold) into copper. "off" returns false.
function ns:ParseMoney(text)
  if not text then return nil end
  text = text:lower():gsub("%s", "")
  if text == "off" or text == "none" then return false end
  local total, matched = 0, false
  for amount, unit in text:gmatch("([%d%.]+)([gsc])") do
    matched = true
    local n = tonumber(amount) or 0
    if unit == "g" then total = total + n * 10000
    elseif unit == "s" then total = total + n * 100
    else total = total + n end
  end
  if not matched then
    local n = tonumber(text)
    if not n then return nil end
    total = n * 10000
  end
  return math.floor(total + 0.5)
end

-- Hash used for successor channel names and ledger ids (djb2, no bit ops needed)
function ns.Hash(s)
  local h = 5381
  for i = 1, #s do
    h = (h * 33 + s:byte(i)) % 4294967296
  end
  return h
end

-- Base-36 helpers keep messages short
local digits = "0123456789abcdefghijklmnopqrstuvwxyz"
function ns.To36(n)
  n = math.floor(n)
  if n == 0 then return "0" end
  local s = ""
  while n > 0 do
    local r = n % 36
    s = digits:sub(r + 1, r + 1) .. s
    n = math.floor(n / 36)
  end
  return s
end
function ns.From36(s)
  return tonumber(s, 36)
end

-- Ask the player a question in a popup: ns:Ask(kind, ...) returns the popup, or nil when
-- it couldn't be shown. ui/Popups.lua fills this in with the questions and their texts,
-- so features/ can ask without drawing anything.
function ns:Ask() return nil end
