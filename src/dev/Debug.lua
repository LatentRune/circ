-- dev/Debug.lua: tools for testing, shipped in test builds and left out of the release
-- zip (tools/package.py). Adds /circ debug (gray debug lines in chat, also a checkbox in
-- Settings > Advanced) and /circ status (version, connection, message counts, scanned
-- professions, channels and the ledger channel's log). Works with settings/Slash.lua,
-- settings/Help.lua and settings/Panel.lua.
local _, ns = ...
local commands = ns.Slash.commands
ns.Dev = true

ns.Help.devCommands = ", /circ status, /circ debug"

ns.Panel.advancedRows[#ns.Panel.advancedRows + 1] = function()
  return { left = "Debug messages in chat", check = { on = CircDB.debug == true, fn = function(on)
    CircDB.debug = on
    ns.UI:Refresh()
  end } }
end

commands.debug = function()
  CircDB.debug = not CircDB.debug
  ns:Print("Debug", CircDB.debug and "on" or "off")
end

commands.status = function()
  ns:Print("Version", ns.version, "| ledger:", ns.Union:DisplayName(),
    "| connected:", ns.Union:ChannelID() and "yes" or ("no (" .. ns.Union.joinTries .. " join tries)"))
  local members = 0
  for _ in pairs(ns:UnionDB().players) do members = members + 1 end
  local bundled, learned = ns.Recipes:Count()
  local s = ns.Comm.stats
  ns:Print("Members known:", members, "| recipes:", bundled, "bundled,", learned, "learned",
    "| sent", s.sent, "received", s.received, "dropped", s.dropped, "| queue", ns.Comm:QueueLength())
  local profs = {}
  for prof, p in pairs(ns:CharDB().professions) do profs[#profs + 1] = prof .. " " .. #(p.recipes or {}) end
  ns:Print("Scanned here:", #profs > 0 and table.concat(profs, ", ") or "nothing yet - open your profession windows")
  if ns.newerVersionSeen then ns:Print("A member has a newer version of Circ.") end
  -- Channels the game reports, to compare with the ledger channel's name
  local chans = {}
  local list = { GetChannelList() }
  for i = 1, #list, 3 do
    local name = tostring(list[i + 1])
    chans[#chans + 1] = list[i] .. "." .. (ns.Union.Same(name, ns.Union:Name()) and "LEDGER" or (ns.Union.Normalize(name) and "other circ" or name))
  end
  ns:Print("Channels:", #chans > 0 and table.concat(chans, ", ") or "none")
  if #ns.Union.log > 0 then ns:Print("Ledger channel log:", table.concat(ns.Union.log, " | ")) end
end
