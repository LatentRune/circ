-- settings/Panel.lua: the Settings tab in Circ's window. One checkbox per setting
-- (core/Settings.lua lists them all), the suggested-price percentages, and the Advanced
-- section. Changes apply right away. The same settings can be changed with slash commands
-- (settings/Slash.lua). dev/ files add their own rows to the Advanced section.
local _, ns = ...
local UI = ns.UI
local Panel = {}
ns.Panel = Panel

-- Rows other files add at the end of the Advanced section: functions returning a row
Panel.advancedRows = {}

function UI.builders.settings()
  UI:SetHeader("Settings", "Changes apply right away.")
  local st = CircDB.settings
  local function setting(key, label, tipText, after)
    return { left = label, tip = tipText, check = { on = st[key] ~= false, fn = function(on)
      st[key] = on
      if after then after() end
      UI:Refresh()
    end } }
  end
  local out = {
    { header = true, left = "General" },
    setting("showSelf", "Show me in lookups", "List your own crafts and requests when you look up an item.", function() ns:Fire("DataChanged") end),
    setting("nudges", "Vendor and Auction House reminders", "When you visit a vendor or the Auction House, mention ledger members who pay more."),
    setting("tooltip", "Ledger lines on item tooltips", "Add who buys or makes an item to its tooltip."),
    setting("minimap", "Minimap button", nil, function() if ns.Minimap then ns.Minimap:Update() end end),
    setting("shareBags", "Share my bags with my ledger", "Members can find tradeable items you carry under Lookup > Who has it. Gray junk and soulbound items are never shared.",
      function() if ns.Bags then ns.Bags:Update() end end),
    { left = "Getting-started guide", tip = "Show the guide at the bottom of this window again.",
      check = { on = not CircDB.guide.hidden and not CircDB.guide.finished, fn = function(on)
        CircDB.guide.hidden = not on
        if on then
          ns.Guide:Restart()
          UI:ResetGuide()
        end
        UI:Refresh()
      end } },
  }
  local src = ns.Prices:Source()
  if src then
    out[#out + 1] = { header = true, left = "Suggested prices (from " .. src .. ")" }
    out[#out + 1] = { left = "Materials: " .. st.buyPct .. "% of the Auction House price",
      action = { label = "Change", fn = function() ns:EditNumber("buyPct", "Suggested buying price, % of the Auction House price", 1, 200) end } }
    out[#out + 1] = { left = "Crafts: cost of materials + " .. st.margin .. "%",
      action = { label = "Change", fn = function() ns:EditNumber("margin", "Suggested selling price, % added to the cost of materials", 0, 500) end } }
  end
  out[#out + 1] = { header = true, left = "Advanced" }
  out[#out + 1] = setting("advanced", "Ledger management", "Show buttons on the Ledger tab to invite players, create a new ledger or leave this one.")
  for _, row in ipairs(Panel.advancedRows) do out[#out + 1] = row() end
  return out
end

