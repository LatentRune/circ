-- ui/Lookup.lua: the Lookup tab. A search box for items and members, then who in the
-- ledger buys the item, makes it, or has it in their bags, or everything one member
-- makes, sells, buys and requests. Shift-clicking an item (ui/Window.lua) looks it up.
-- The answers come from features/Lookup.lua.
local _, ns = ...
local UI = ns.UI
local W, T = ns.Widgets, ns.Text
local GRAY = T.GRAY
local itemText, itemIcon, classOf, playerText, plural = T.ItemText, T.ItemIcon, T.ClassOf, T.PlayerText, T.Plural

UI.mode = "used" -- which list shows for an item: used (who buys it), made, has

function UI.builders.lookup()
  local out = {}
  local lookupPlayer, lookupItem, mode = UI.lookupPlayer, UI.lookupItem, UI.mode
  if lookupPlayer then
    local profile = ns.Lookup:Profile(lookupPlayer)
    local online = ns.Records:IsOnline(lookupPlayer)
    UI:SetHeader(T.ClassColor(classOf(lookupPlayer)) .. ns:ShortName(lookupPlayer) .. "|r",
      "What " .. ns:ShortName(lookupPlayer) .. " makes, sells, buys and requests" .. (online and "  (online)" or ""))
    if not profile or #profile == 0 then return W.EmptyRows({ "No prices shared by this member yet." }) end
    local labels = { makes = "Makes", buys = "Buys", wants = "Requests", has = "Selling from bags" }
    local last
    for _, r in ipairs(profile) do
      if r.kind ~= last then
        out[#out + 1] = { header = true, left = labels[r.kind] or r.kind }
        last = r.kind
      end
      out[#out + 1] = { icon = r.itemID, left = itemText(r.itemID) .. (r.qty and (GRAY .. "  x" .. r.qty .. "|r") or ""),
        right = r.price and r.price > 0 and ns:Money(r.price) or (GRAY .. "ask|r"),
        onClick = function() UI:LookupItem(r.itemID) end,
        whisper = lookupPlayer ~= ns:PlayerKey() and online ~= nil and lookupPlayer or nil }
    end
    return out
  end
  if not lookupItem then
    UI:SetHeader("Lookup", "Find who in your ledger buys, makes or sells an item.")
    return W.EmptyRows({ "Type an item or member name above.", GRAY .. "Or shift-click an item in your bags.|r" })
  end
  local used, made, has = ns.Lookup:UsedIn(lookupItem), ns.Lookup:MadeBy(lookupItem), ns.Lookup:HasIt(lookupItem)
  local sub = plural(#used, "member buys it", "members buy it") .. ",  " .. plural(#made, "member makes it", "members make it")
    .. ",  " .. plural(#has, "member has it", "members have it")
  UI:SetHeader(itemText(lookupItem), sub, itemIcon(lookupItem))
  if mode == "used" then
    for _, r in ipairs(used) do
      local what = r.kind == "wants" and ("requested " .. (r.qty or 1)) or ("for " .. ns.Recipes:DisplayName(r.recipeID))
      out[#out + 1] = { cls = classOf(r.player), left = playerText(r.player, r.online) .. GRAY .. "  " .. what .. "|r",
        right = r.price and r.price > 0 and ("pays " .. ns:Money(r.price)) or (GRAY .. "whisper for price|r"),
        whisper = r.player ~= ns:PlayerKey() and r.player or nil }
    end
    if #out == 0 then return W.EmptyRows({ "Nobody in your ledger uses or requested this item yet." }) end
  elseif mode == "has" then
    local lastKind
    for _, r in ipairs(has) do
      if r.kind ~= lastKind then
        out[#out + 1] = { header = true, left = r.kind == "has" and "Listed for sale" or "In their bags, not listed" }
        lastKind = r.kind
      end
      local right
      if r.kind == "has" then
        right = r.price and r.price > 0 and ("asks " .. ns:Money(r.price)) or (GRAY .. "whisper for price|r")
      else
        right = GRAY .. "whisper to ask|r"
      end
      out[#out + 1] = { cls = classOf(r.player), left = playerText(r.player, r.online) .. GRAY .. "  has " .. (r.qty or 1) .. "|r",
        right = right, whisper = r.player ~= ns:PlayerKey() and r.player or nil }
    end
    if #out == 0 then return W.EmptyRows({ "Nobody in your ledger has this item right now.",
      GRAY .. "Only members who share their bags (Settings) show up here.|r" }) end
  else
    for _, r in ipairs(made) do
      out[#out + 1] = { cls = classOf(r.player), left = playerText(r.player, r.online) .. (r.skill and (GRAY .. "  skill " .. r.skill .. "|r") or ""),
        right = r.price and r.price > 0 and ("charges " .. ns:Money(r.price)) or (GRAY .. "whisper for price|r"),
        whisper = r.player ~= ns:PlayerKey() and r.player or nil }
    end
    if #out == 0 then return W.EmptyRows({ "Nobody in your ledger can make this item yet." }) end
  end
  return out
end

function UI:LookupPlayer(player)
  UI.lookupPlayer = player
  UI.lookupItem = nil
  UI:SelectTab("lookup")
  if UI.search then UI.search:SetText(ns:ShortName(player)) end
  self:Show()
  self:Refresh()
end

function UI:LookupItem(text)
  local id = ns.Lookup:Resolve(text)
  if not id then
    ns:Print("No item found for", text)
    return
  end
  UI.lookupItem = id
  UI.lookupPlayer = nil
  CircDB.guide.looked = true
  UI:SelectTab("lookup")
  self:Show()
  if UI.search then UI.search:SetText(ns:ItemName(id)) end
  self:Refresh()
end

-- Search box with item and member suggestions, then Who buys / Who makes / Who has / Request
function UI:BuildLookupToolbar(frame)
  local y = UI.TOOLBAR_Y
  local search = W.EditBox(frame, "CircSearchBox", 22, y, 200)
  UI.search = search
  W.Placeholder(search, "Search items or members")
  local searchSuggest = W.Suggest(frame, search, false, function(s)
    if s.kind == "player" then
      search:SetText(ns:ShortName(s.id))
      UI:LookupPlayer(s.id)
    else
      search:SetText(s.label)
      UI:LookupItem(s.id)
    end
  end, function(text) if T.Trim(text) ~= "" then UI:LookupItem(text) end end)
  search:SetScript("OnTextChanged", function(box, userInput)
    local text = box:GetText()
    if T.Trim(text) == "" then
      UI.lookupItem, UI.lookupPlayer = nil, nil
      searchSuggest:Hide()
      UI:Refresh()
      return
    end
    if userInput then searchSuggest:Update(text) end
    UI:Refresh()
  end)

  local modeButtons = {}
  -- With text typed but nothing looked up yet, these look up the typed text first
  local function lookupTyped()
    if UI.lookupItem then return true end
    local text = T.Trim(search:GetText())
    if text == "" then return false end
    UI:LookupItem(text)
    return UI.lookupItem ~= nil
  end
  local function modeButton(key, label, x, width)
    local b = W.Button(frame, label, x, y, width)
    b:SetScript("OnClick", function()
      UI.mode = key
      searchSuggest:Hide()
      if lookupTyped() then UI:Refresh() end
    end)
    modeButtons[key] = b
  end
  modeButton("used", "Who buys it", 228, 90)
  modeButton("made", "Who makes it", 320, 96)
  modeButton("has", "Who has it", 418, 84)
  W.Tip(modeButtons.has, "Members selling this item from their bags, and what they ask.")
  W.Tip(modeButtons.used, "Members who craft with this item or requested it, and what they pay.")
  W.Tip(modeButtons.made, "Members who can craft this item, and what they charge.")
  modeButtons.request = W.Button(frame, "Request", 504, y, 74)
  W.Tip(modeButtons.request, "Post a request to buy this item.")
  UI.modeButtons = modeButtons
  modeButtons.request:SetScript("OnClick", function()
    searchSuggest:Hide()
    if not lookupTyped() then return end
    UI:SelectTab("requests")
    UI.filterBox:SetText(ns:ItemName(UI.lookupItem))
    UI.filterText = ns:ItemName(UI.lookupItem)
    UI:Refresh()
    UI:EditRequest(UI.lookupItem)
  end)
  UI.toolbars.lookup = { search, modeButtons.used, modeButtons.made, modeButtons.has, modeButtons.request }
end

-- The buttons work once something is typed; the picked list stays lit
UI.refreshers[#UI.refreshers + 1] = function()
  local hasText = T.Trim(UI.search:GetText()) ~= ""
  for key, b in pairs(UI.modeButtons) do
    b:SetEnabled(hasText)
    if key == UI.mode and UI.lookupItem then b:LockHighlight() else b:UnlockHighlight() end
  end
end
