-- Helpers scenarios use: start the addon, add ledger members, open windows, click and
-- type, and let time pass.

NS = {}

-- Runs the game for a while: timers in order, and OnUpdate on visible frames at 30 fps.
function Advance(seconds)
  local dt = 1 / 30
  local target = NOW + seconds
  while NOW < target - 1e-9 do
    local step = math.min(dt, target - NOW)
    RunTimers(NOW + step)
    NOW = NOW + step
    for _, f in ipairs(ALL_FRAMES) do
      local fn = f._scripts.OnUpdate
      if fn and f:IsVisible() then fn(f, step) end
    end
  end
  RunTimers(NOW)
end

-- Loads the addon the way the game does: saved variables first (nil on a first run),
-- then every file in .toc order, each given the addon's name and its shared table.
function Boot(db)
  CircDB = db
  local files = {}
  for line in io.lines(ADDON_DIR .. "Circ.toc") do
    local f = line:match("^%s*([^#%s][^%s]*%.lua)%s*$")
    if f then files[#files + 1] = (f:gsub("\\", "/")) end  -- the game writes folders as core\File.lua
  end
  for _, f in ipairs(files) do
    local chunk = assert(loadfile(ADDON_DIR .. f))
    chunk("Circ", NS)
  end
  FireEvent("ADDON_LOADED", "Circ")
  FireEvent("PLAYER_LOGIN")
  FireEvent("PLAYER_ENTERING_WORLD", true, false)
  Advance(0.5)
end

-- Saved variables for a player who has used Circ before: in a ledger, guide finished.
function Returning(extra)
  local db = {
    union = { name = "circQ7K2smith", abbrev = "SMITH", migrations = 0, takeovers = {}, boundAt = 1699990000 },
    seenIntro = true,
    guide = { looked = true, prices = true, ledger = true, finished = true, hidden = true },
  }
  for k, v in pairs(extra or {}) do db[k] = v end
  return db
end

------------------------------------------------------------------------------
-- Other members, speaking Circ's wire format (Serialize.lua and Comm.lua): a message
-- is "S" plus the encoded { t = kind, d = data, p = 1 }, or "M<id>:<i>:<n>|" chunks.
------------------------------------------------------------------------------

local function encode(v, out)
  local t = type(v)
  if t == "string" then out[#out + 1] = "s" .. #v .. ":" .. v
  elseif t == "number" then out[#out + 1] = "n" .. tostring(v) .. ";"
  elseif t == "boolean" then out[#out + 1] = v and "T" or "F"
  elseif t == "table" then
    out[#out + 1] = "{"
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, k in ipairs(keys) do encode(k, out); encode(v[k], out) end
    out[#out + 1] = "}"
  else out[#out + 1] = "N" end
end

local B36 = "0123456789abcdefghijklmnopqrstuvwxyz"
function To36(n)
  if n == 0 then return "0" end
  local s = ""
  while n > 0 do local r = n % 36; s = B36:sub(r + 1, r + 1) .. s; n = math.floor(n / 36) end
  return s
end
local function packList(ids) local t = {}; for i, id in ipairs(ids) do t[i] = To36(id) end; return table.concat(t, ",") end
local function packMap(m)
  local t = {}
  for k, v in pairs(m) do t[#t + 1] = To36(k) .. ":" .. To36(v) end
  table.sort(t)
  return table.concat(t, ",")
end
local function packTriples(m)
  local t = {}
  for id, e in pairs(m) do t[#t + 1] = To36(id) .. ":" .. To36(e[1]) .. ":" .. To36(e[2]) end
  table.sort(t)
  return table.concat(t, ",")
end

-- The ledger channel this account is bound to, as the game names it.
local function channelName() return CircDB and CircDB.union and CircDB.union.name or "" end

local msgId = 0
-- One addon message from `sender`, to the ledger channel or whispered to you.
function Send(sender, kind, data, whisper)
  local out = {}
  encode({ t = kind, d = data, p = 1 }, out)
  local body = table.concat(out)
  local texts = {}
  if #body <= 240 then texts[1] = "S" .. body
  else
    msgId = msgId + 1
    local n = math.ceil(#body / 240)
    for i = 1, n do texts[i] = "M" .. To36(msgId) .. ":" .. i .. ":" .. n .. "|" .. body:sub((i - 1) * 240 + 1, i * 240) end
  end
  local chan = channelName()
  local id = GetChannelName(chan)
  for _, text in ipairs(texts) do
    if whisper then
      FireEvent("CHAT_MSG_ADDON", "CIRC", text, "WHISPER", sender, WORLD.player.name, 0, 0, "")
    else
      FireEvent("CHAT_MSG_ADDON", "CIRC", text, "CHANNEL", sender, "", 0, id, chan)
    end
  end
end

-- A ledger member and the record their client publishes.
-- m = { name, class, profs = { Tailoring = 150 }, recipes = { spellID, ... },
--       buy = { [itemID] = copper }, sell = { [itemID] = copper },
--       wants = { [itemID] = { qty, copper } }, stock = { [itemID] = { qty, copper } },
--       bags = { [itemID] = count }, v = record version }
function Member(m)
  local sender = m.name .. "-" .. WORLD.player.realm
  local ids = {}
  for i, id in ipairs(m.recipes or {}) do ids[i] = id end
  table.sort(ids)
  local rec = { v = m.v or 1699999000, cls = m.class, profs = m.profs or {}, r = packList(ids),
    b = packMap(m.buy or {}), s = packMap(m.sell or {}), w = packTriples(m.wants or {}), h = packTriples(m.stock or {}) }
  Send(sender, "REC", rec)
  if m.bags then Send(sender, "BAGS", { v = rec.v, i = packMap(m.bags) }) end
  return sender
end

-- A trade between two members, reported by both, so it shows as confirmed.
-- t = { a = "Bob", b = "Cara", aPaid = copper, bPaid = copper, ago = seconds, oneSided = true }
function Trade(t)
  local a, b = t.a .. "-" .. WORLD.player.realm, t.b .. "-" .. WORLD.player.realm
  if a > b then a, b, t.aPaid, t.bPaid = b, a, t.bPaid, t.aPaid end
  local e = { a = a, b = b, ma = t.aPaid or 0, mb = t.bPaid or 0, ia = t.aItems or "", ib = t.bItems or "", t = time() - (t.ago or 0) }
  Send(a, "LEDG", e)
  if not t.oneSided then Send(b, "LEDG", e) end
end

------------------------------------------------------------------------------
-- Things the player does
------------------------------------------------------------------------------

-- Opens a profession window and waits for Circ's scan.
function OpenProfession(t)
  WORLD.tradeskill = t
  FireEvent("TRADE_SKILL_SHOW")
  Advance(1)
end

function Slash(text) SlashCmdList.CIRC(text or "") end

-- Clicks a button the way the mouse does.
function Click(button, which)
  if button._disabled then return end
  local fn = button._scripts.OnClick or button._scripts.OnMouseUp
  if fn then fn(button, which or "LeftButton") end
end

-- Types into an edit box, as if from the keyboard (OnTextChanged sees user input).
function Type(box, text)
  box:SetFocus()
  box:SetText(text, true)
end

-- Points the mouse at an item and shows its tooltip, as hovering it in the bags does.
function HoverItem(id)
  MOUSE = { x = 900, y = 420 }
  GameTooltip:SetOwner(UIParent, "ANCHOR_CURSOR")
  GameTooltip:SetHyperlink("item:" .. id)
  GameTooltip:Show()
end

-- Finds a visible button by its text, for clicks a player would make.
function ButtonNamed(text)
  for _, f in ipairs(ALL_FRAMES) do
    if f._label and f._label:GetText() == text and f:IsVisible() then return f end
  end
  error("no visible button says " .. text)
end

-- A member who is offline now: another member relays their record, as Circ's catch-up does.
function OfflineMember(m, via)
  local owner = m.name .. "-" .. WORLD.player.realm
  local ids = {}
  for i, id in ipairs(m.recipes or {}) do ids[i] = id end
  table.sort(ids)
  local rec = { v = m.v or 1699990000, cls = m.class, profs = m.profs or {}, r = packList(ids),
    b = packMap(m.buy or {}), s = packMap(m.sell or {}), w = packTriples(m.wants or {}), h = packTriples(m.stock or {}) }
  Send(via .. "-" .. WORLD.player.realm, "RRELAY", { [owner] = rec }, true)
  return owner
end

-- Presses Enter in an edit box.
function PressEnter(box)
  local fn = box._scripts.OnEnterPressed
  if fn then fn(box) end
end
