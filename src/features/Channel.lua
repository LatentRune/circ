-- features/Channel.lua: the ledger's hidden chat channel and the rules for its name.
-- Players only ever type and see the 5-letter ledger name, like SMITH. The channel behind
-- it is "circ", 4 hidden capitals or digits, then the name in lower case: circQ7K2smith.
-- Nobody can guess the hidden part, so other ledgers are joined by invite. The starter
-- ledger every new account joins is circ0000start (START).
--
-- Also answers "which ledger is this account in" for every other file (ns.Union:Name()
-- and friends), and tells core/Comm.lua which channel to read and send on.
-- Works with features/Union.lua (joining and leaving) and features/Connection.lua
-- (staying connected). Code calls a ledger a "union"; players see "ledger".
local _, ns = ...
local U = {}
ns.Union = U

U.START = "circ0000start"
local ID = "[%u%d][%u%d][%u%d][%u%d]"
local UPPER_PATTERN = "^CIRC(" .. ID .. ")(%u%u%u%u%u)$"   -- any letter case, after :upper()
local OLD_PATTERN = "^CIRC_(%d%d%d%d)_(%u%u%u%u%u)$"
local ALNUM = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"

-- The one spelling of a ledger channel name: "circ", the hidden ID in capitals, then the
-- ledger name in lower case, like circQ7K2smith. Channel names match regardless of case, so
-- this only changes how the name reads. Also converts older forms: CIRC_1234_SMITH (servers
-- refuse underscores) becomes circ1234smith, and the starter ledger is always circ0000start.
-- Returns nil for anything that isn't a ledger channel name.
function U.Normalize(name)
  if type(name) ~= "string" then return nil end
  local up = name:upper()
  local id, abbrev = up:match(OLD_PATTERN)
  if not id then id, abbrev = up:match(UPPER_PATTERN) end
  if not id then return nil end
  if abbrev == "START" then id = "0000" end
  return "circ" .. id .. abbrev:lower()
end

-- Same ledger channel? Compares any spelling.
function U.Same(a, b)
  local na = U.Normalize(a)
  return na ~= nil and na == U.Normalize(b)
end

-- Four capitals or digits for the hidden part of a channel name (36^4 = 1,679,616 choices)
local function hiddenID(n)
  local out = ""
  for _ = 1, 4 do
    local k = n % 36
    out = out .. ALNUM:sub(k + 1, k + 1)
    n = math.floor(n / 36)
  end
  return out
end

-- A new channel name for a ledger name, with a random hidden part
function U.NewName(abbrev)
  return "circ" .. hiddenID(math.random(0, 36 ^ 4 - 1)) .. abbrev:lower()
end

-- The ledger name inside a channel name, in capitals, or nil
function U.AbbrevOf(name)
  local _, abbrev = (U.Normalize(name) or ""):upper():match(UPPER_PATTERN)
  return abbrev
end

function U:IsBound() return CircDB.union ~= nil end
function U:Name() return CircDB.union and CircDB.union.name end
function U:Abbrev() return CircDB.union and CircDB.union.abbrev end
function U:IsStart() return CircDB.union ~= nil and CircDB.union.abbrev == "START" end

-- Check a 5-letter ledger name typed by the player. Returns it cleaned, or nil and why not.
function U.Validate(text)
  if type(text) ~= "string" then text = "" end
  text = text:gsub("%s", ""):upper()
  if text == "" then return nil, "Enter a 5-letter ledger name" end
  if text:find("[^%a]") then return nil, "Letters only" end
  if #text ~= 5 then return nil, "Exactly 5 letters (" .. #text .. " so far)" end
  if text == "START" then return nil, "START is the starter ledger" end
  return text
end

function U.ValidName(name)
  return U.Normalize(name) ~= nil
end

-- What players see for a channel name
function U.Display(name)
  local abbrev = U.AbbrevOf(name)
  if not abbrev then return "?" end
  if abbrev == "START" then return "START (starter ledger)" end
  return abbrev
end
function U:DisplayName() return self:IsBound() and U.Display(self:Name()) or "none" end

function U:ChannelID()
  local name = self:Name()
  if not name then return nil end
  local id = GetChannelName(name)
  if id and id > 0 then return id end
  return nil
end

-- Successor channel every client derives the same way, so no message is needed to agree on it
function U.Successor(name, migration)
  name = U.Normalize(name)
  if not name then return nil end
  local id, abbrev = name:upper():match(UPPER_PATTERN)
  local h = ns.Hash(name:upper() .. ":" .. migration) % (36 ^ 4)
  if hiddenID(h) == id then h = (h + 1) % (36 ^ 4) end
  return "circ" .. hiddenID(h) .. abbrev:lower()
end

ns.Comm:UseChannel(function() return U:Name() end, function() return U:ChannelID() end)
