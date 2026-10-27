-- core/Settings.lua: the saved variables (CircDB), their defaults, and the per-ledger and
-- per-character tables inside them. Fires "Ready" once everything is loaded at login;
-- most files start their work from ns:Listen("Ready", ...).
--
-- Player settings live in CircDB.settings and are changed on the Settings tab
-- (settings/Panel.lua) or with slash commands (settings/Slash.lua):
--   showSelf   list my own crafts and requests in lookups        features/Lookup.lua
--   nudges     vendor and Auction House reminders                features/Nudges.lua
--   tooltip    ledger lines on item tooltips                     ui/Tooltip.lua
--   minimap    the minimap button (minimapAngle: where it sits)  ui/Minimap.lua
--   shareBags  share tradeable bag contents with the ledger      features/Bags.lua
--   advanced   Ledger management buttons and commands            ui/Ledger.lua
--   buyPct, margin  how suggested prices are worked out          features/Prices.lua
--
-- A saved setting that moves or is renamed gets a step in MIGRATIONS, so players keep
-- their setup. Code calls the ledger a "union"; the saved names keep that word.
local ADDON, ns = ...

local DEFAULTS = {
  union = nil,           -- { name, abbrev, migrations, boundAt, takeovers = {} }
  settings = { buyPct = 80, margin = 10, nudges = true, tooltip = true, minimap = true, showSelf = true, advanced = false, shareBags = true },
  guide = {},            -- getting-started progress: looked, prices, ledger, hidden, finished
  overrides = { buy = {}, sell = {} },
  wants = {},            -- [itemID] = { qty, price }
  recipes = {},          -- [recipeID] = { n = name, p = product itemID, c = count, prof, r = { [itemID] = count } }
  realms = {},           -- [realm-faction] = { ledgers = { [abbrev] = { players = {}, ledger = {} } } }
  chars = {},            -- [Name-Realm] = { professions = {}, recipes = {} } for this account
  debug = false,
}

-- One-time changes to older saved variables, in order. CircDB.schema is the number of
-- steps already applied. Add new steps at the end; never edit or remove one.
local MIGRATIONS = {
}

local function applyDefaults(dst, src)
  for k, v in pairs(src) do
    if dst[k] == nil then
      if type(v) == "table" then
        dst[k] = {}
        applyDefaults(dst[k], v)
      else
        dst[k] = v
      end
    elseif type(dst[k]) == "table" and type(v) == "table" then
      applyDefaults(dst[k], v)
    end
  end
end

local function migrate(db)
  if next(db) == nil then -- a first run starts with nothing to change
    if #MIGRATIONS > 0 then db.schema = #MIGRATIONS end
    return
  end
  for i = (db.schema or 0) + 1, #MIGRATIONS do
    MIGRATIONS[i](db)
    db.schema = i
  end
end

-- Data for this account's ledger on this realm and faction. Keyed by the ledger's
-- abbreviation so a move to a successor channel keeps members and ledger.
function ns:UnionDB()
  local key = (GetNormalizedRealmName() or GetRealmName()) .. "-" .. (UnitFactionGroup("player") or "?")
  local r = CircDB.realms[key]
  if not r then
    r = { unions = {} }
    CircDB.realms[key] = r
  end
  r.unions = r.unions or {}
  local abbrev = CircDB.union and CircDB.union.abbrev or "NONE"
  local u = r.unions[abbrev]
  if not u then
    u = { players = {}, ledger = {} }
    r.unions[abbrev] = u
  end
  return u
end

function ns:CharDB()
  local key = self:PlayerKey()
  local c = CircDB.chars[key]
  if not c then
    c = { professions = {}, recipes = {} }
    CircDB.chars[key] = c
  end
  c.stock = c.stock or {} -- [itemID] = { price }, items listed for sale
  return c
end

ns:On("ADDON_LOADED", function(name)
  if name ~= ADDON then return end
  CircDB = CircDB or {}
  migrate(CircDB)
  applyDefaults(CircDB, DEFAULTS)
end)

ns:On("PLAYER_LOGIN", function()
  ns:UnionDB()
  ns:CharDB()
  ns.ready = true
  ns:Fire("Ready")
end)
