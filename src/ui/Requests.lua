-- ui/Requests.lua: the Requests tab. Your requests to buy (each with an on/off-the-market
-- checkbox), what other members want to buy, and the materials your recipes use, ready to
-- request. The filter box narrows the lists; on this tab, picking an item from its
-- suggestions opens the request dialog (ui/RequestDialog.lua). The box is shared with the
-- Prices tab (ui/Prices.lua).
local _, ns = ...
local UI = ns.UI
local W, T = ns.Widgets, ns.Text
local GRAY = T.GRAY
local itemText, playerText = T.ItemText, T.PlayerText

UI.requestView = "all" -- which list shows: all, mine, others, materials

function UI.builders.requests()
  UI:SetHeader("Requests", "Post what you want to buy, and see what others in your ledger want.")
  local out = {}
  local requestView = UI.requestView
  local function showing(view) return requestView == "all" or requestView == view end

  if showing("mine") then
    out[#out + 1] = { header = true, left = "Your requests" }
    local mine = 0
    for _, e in ipairs(T.SortedByName(CircDB.wants)) do
      local itemID, w = e[1], e[2]
      if UI:MatchesFilter(itemID) then
        mine = mine + 1
        out[#out + 1] = { icon = itemID, left = itemText(itemID) .. GRAY .. "  x" .. (w.qty or 1) .. (w.off and "  off the market" or "") .. "|r",
          right = w.price and w.price > 0 and (ns:Money(w.price) .. " each") or (GRAY .. "ask|r"),
          onClick = function() UI:EditRequest(itemID) end, tip = "Click to change this request. The checkbox puts it on or off the market.",
          check = { on = not w.off, fn = function(on) w.off = not on or nil; ns:Fire("DataChanged") end },
          action = { label = "Remove", fn = function() CircDB.wants[itemID] = nil; ns:Fire("DataChanged") end } }
      end
    end
    if mine == 0 then out[#out + 1] = { left = GRAY .. "None yet. Search for an item above to request it.|r" } end
  end

  local others = {}
  for player, p in pairs(ns.Records:All()) do
    if player ~= ns:PlayerKey() then
      for itemID, w in pairs(p.wants or {}) do
        if UI:MatchesFilter(itemID) then
          others[#others + 1] = { icon = itemID,
            left = itemText(itemID) .. GRAY .. "  x" .. (w.qty or 1) .. "|r  " .. playerText(player, ns.Records:IsOnline(player)),
            right = w.price and w.price > 0 and ("pays " .. ns:Money(w.price)) or (GRAY .. "ask|r"), whisper = player,
            sortKey = ns:ItemName(itemID) .. player }
        end
      end
    end
  end
  table.sort(others, function(a, b) return a.sortKey < b.sortKey end)
  if showing("others") then
    out[#out + 1] = { header = true, left = "What others want to buy" }
    if #others == 0 then out[#out + 1] = { left = GRAY .. "Nobody has posted a request yet.|r" } end
    for _, r in ipairs(others) do out[#out + 1] = r end
  end

  local _, reagents = ns.Recipes:Mine()
  local list = {}
  for _, e in ipairs(T.SortedByName(reagents)) do
    if UI:MatchesFilter(e[1]) and not CircDB.wants[e[1]] then list[#list + 1] = e[1] end
  end
  if requestView == "materials" and #list == 0 then
    out[#out + 1] = { header = true, left = "Materials your recipes use" }
    out[#out + 1] = { left = GRAY .. "Nothing here. Open your profession windows, or every material is already requested.|r" }
  end
  if showing("materials") and #list > 0 then
    out[#out + 1] = { header = true, left = "Materials your recipes use" }
    for _, itemID in ipairs(list) do
      local price = ns.Prices:Buy(itemID)
      out[#out + 1] = { icon = itemID, left = itemText(itemID), right = price and (GRAY .. ns:Money(price) .. "|r") or "",
        action = { label = "Request", fn = function() UI:EditRequest(itemID) end } }
    end
  end
  return out
end

-- After a view button: work the order out again and close any suggestions
function UI:ViewPicked()
  UI.priceOrder = nil
  W.HideSuggestions()
  UI:Refresh()
end

-- The filter box (shared with Prices) and the All / Mine / Others / Materials buttons
function UI:BuildRequestsToolbar(frame)
  local y = UI.TOOLBAR_Y
  local filterBox = W.EditBox(frame, "CircFilterBox", 22, y, 300)
  UI.filterBox = filterBox
  W.Placeholder(filterBox, "Filter items")
  local function requestText(text)
    if UI.current ~= "requests" then return end
    local id = ns.Lookup:Resolve(text)
    if id then UI:EditRequest(id) elseif T.Trim(text) ~= "" then ns:Print("No item found for", text) end
  end
  local filterSuggest = W.Suggest(frame, filterBox, true, function(s)
    filterBox:SetText("")
    UI.filterText = ""
    UI:EditRequest(s.id)
    UI:Refresh()
  end, requestText)
  filterBox:SetScript("OnTextChanged", function(box, userInput)
    UI.filterText = T.Trim(box:GetText())
    UI.priceOrder = nil
    if userInput and UI.current == "requests" and UI.filterText ~= "" then filterSuggest:Update(UI.filterText) else filterSuggest:Hide() end
    UI:Refresh()
  end)
  W.Tip(filterBox, "Type to narrow the list. On Requests, pick an item to request it.")
  local reqViews = W.ViewButtons(frame, y, {
    { "all", "All", 46, "Show every list." },
    { "mine", "Mine", 58, "Your own requests." },
    { "others", "Others", 66, "What other members want to buy." },
    { "materials", "Materials", 84, "Materials your recipes use, ready to request." },
  }, function() return UI.requestView end, function(v) UI.requestView = v end, UI.ViewPicked)
  UI.requestViews = reqViews
  UI.toolbars.requests = { filterBox, unpack(reqViews) }
end

-- Lights the picked view button of each button row
function UI:HighlightViews(views)
  for key, b in pairs(views) do
    if type(key) == "string" and key ~= "get" then
      if key == views.get() then b:LockHighlight() else b:UnlockHighlight() end
    end
  end
end

UI.refreshers[#UI.refreshers + 1] = function()
  UI.filterBox.placeholder:SetText(UI.current == "requests" and "Item to request" or "Filter items")
  UI.filterBox:SetWidth(190)
  UI:HighlightViews(UI.requestViews)
end
