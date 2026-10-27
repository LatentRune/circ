-- settings/Help.lua: the command list /circ help prints. Kept in one place so the README
-- and docs can quote it. {pct} and {margin} show the current settings; {dev} lists the
-- testing commands from dev/Debug.lua, when that file is in the build.
local _, ns = ...
local Help = {}
ns.Help = Help

Help.LINES = {
  "/circ - open or close the window",
  "/circ create SMITH - start a ledger (5 letters; needs Ledger management in Settings)",
  "/circ invite <player> - invite a player to your ledger (needs Ledger management)",
  "/circ leave - leave your ledger and go back to START (needs Ledger management)",
  "/circ reconnect - reconnect to your ledger channel",
  "/circ find <item> - look up an item",
  "/circ buy <item> <price|off|auto> - what you pay for a reagent",
  "/circ sell <item> <price|off|auto> - what you charge for a finished good",
  "/circ pct <n> - default reagent offer, % of market (now {pct})",
  "/circ margin <n> - default margin on finished goods, % (now {margin})",
  "/circ request <item> <qty> <price> - post a request; /circ unrequest <item>",
  "/circ shop <item> [qty] - shopping list: who in the ledger makes it and its reagents",
  "/circ nudges on|off, /circ tooltip on|off, /circ minimap on|off{dev}",
  "Prices: 1g20s, 35s, 80c or 1.5 (gold)",
}

-- Added to the {dev} line by dev/Debug.lua
Help.devCommands = ""

function Help:Print()
  for _, line in ipairs(Help.LINES) do
    line = line:gsub("{pct}", tostring(CircDB.settings.buyPct)):gsub("{margin}", tostring(CircDB.settings.margin))
      :gsub("{dev}", Help.devCommands)
    DEFAULT_CHAT_FRAME:AddMessage("  " .. line)
  end
end
