-- ui/Window.lua: Circ's window. Opens with /circ or the minimap button, centered, with
-- tabs along the bottom: Lookup, Requests, Ledger, Prices and Settings. Draws the title,
-- the connection status, the tab's toolbar, its heading and its list, and refreshes when
-- anything changes.
--
-- Each tab is its own file that adds a builder (UI.builders.<tab>, returning list rows,
-- see ui/widgets/List.lua) and its toolbar: ui/Lookup.lua, ui/Requests.lua,
-- ui/Ledger.lua, ui/Prices.lua and settings/Panel.lua. The guide bar is ui/Guide.lua.
-- Also catches shift-clicks on items, which look the item up or fill in the filter box.
local _, ns = ...
local UI = {}
ns.UI = UI
local W, T = ns.Widgets, ns.Text
local GREEN = T.GREEN

local MAX_ROWS, ROW_H = 18, 20
local GUIDE_ROWS = 15 -- rows left when the guide is showing
local LIST_TOP = -96
UI.TOOLBAR_Y = -32

local frame, scroll, rows, tabs
local header, subheader, heroIcon, statusText
local data = {}

UI.builders = {}       -- [tab] = function() return rows end
UI.toolbars = {}       -- [tab] = widgets shown only on that tab
UI.refreshers = {}     -- functions run on every refresh, for each tab's toolbar
UI.current = "lookup"  -- the tab showing
UI.filterText = ""     -- the filter box on Requests and Prices
UI.priceOrder = nil    -- the Prices tab's order, kept while the player edits (ui/Prices.lua)

-- The heading over the list: an icon for a looked-up item, a title and a gray line under it
function UI:SetHeader(text, sub, icon)
  header:SetText(text or "")
  subheader:SetText(sub or "")
  heroIcon:SetShown(icon ~= nil)
  if icon then heroIcon:SetTexture(icon) end
  header:ClearAllPoints()
  header:SetPoint("TOPLEFT", icon and 48 or 18, -62)
end

-- True when the item's name contains the filter text (or there is no filter)
function UI:MatchesFilter(itemID)
  if UI.filterText == "" then return true end
  return ns:ItemName(itemID):lower():find(UI.filterText:lower(), 1, true) ~= nil
end

function UI:Refresh()
  if not frame or not frame:IsShown() then return end
  local guideShown = UI:UpdateGuide()
  local visible = guideShown and GUIDE_ROWS or MAX_ROWS
  scroll:ClearAllPoints()
  scroll:SetPoint("TOPLEFT", 12, LIST_TOP)
  scroll:SetPoint("BOTTOMRIGHT", -32, guideShown and 82 or 12)

  data = UI.builders[UI.current]()
  UI.data = data
  -- Show only this tab's toolbar (the filter box is shared by Requests and Prices)
  local show = {}
  for _, w in ipairs(UI.toolbars[UI.current] or {}) do show[w] = true end
  if UI.current == "ledger" and CircDB.settings.advanced == true then
    for _, w in ipairs(UI.toolbars.ledgerAdvanced) do show[w] = true end
  end
  for _, widgets in pairs(UI.toolbars) do
    for _, w in ipairs(widgets) do w:SetShown(show[w] == true) end
  end
  W.HideOrphanSuggestions()
  for _, fn in ipairs(UI.refreshers) do fn() end
  local u = CircDB.union
  if u then
    local connected = ns.Union:ChannelID() ~= nil
    statusText:SetText((connected and GREEN or "|cffffff00") .. ns.Union:DisplayName() .. "|r")
  else
    statusText:SetText("")
  end

  FauxScrollFrame_Update(scroll, #data, visible, ROW_H)
  local offset = FauxScrollFrame_GetOffset(scroll)
  for i = 1, MAX_ROWS do
    local row, d = rows[i], data[i + offset]
    if d and i <= visible then
      W.FillRow(row, d, i + offset)
      row:Show()
    else
      row.d = nil
      row:Hide()
    end
  end
  local index = { lookup = 1, requests = 2, ledger = 3, prices = 4, settings = 5 }
  if PanelTemplates_SetTab and tabs.native then
    pcall(PanelTemplates_SetTab, frame, index[UI.current])
  else
    for key, t in pairs(tabs) do
      if type(t) == "table" and t.LockHighlight then
        if key == UI.current then t:LockHighlight() else t:UnlockHighlight() end
      end
    end
  end
end

-- Switch tab. Visiting Prices or Ledger counts as that guide step.
function UI:SelectTab(tab)
  UI.current = tab
  if tab == "prices" then
    CircDB.guide.prices = true
    UI.priceOrder = nil
  elseif tab == "ledger" then
    CircDB.guide.ledger = true
  end
  W.HideSuggestions()
end

-- Whisper a member from a list row; on Lookup, the looked-up item goes into the whisper
local function whisper(name)
  ChatFrame_SendTell(name)
  if UI.current == "lookup" and UI.lookupItem then
    local _, link = GetItemInfo(UI.lookupItem)
    if link then ChatEdit_InsertLink(link) end
  end
end

-- Shift-click an item anywhere, like the Auction House search box: on Lookup the item is
-- looked up; on Prices an item in the bags is listed for sale; otherwise it goes into the
-- filter. No chat box may be in use.
local lastInsert = 0
local function insertLink(link)
  if type(link) ~= "string" or not link:find("item:", 1, true) then return end
  if not frame:IsShown() then return end
  local current = UI.current
  if current ~= "lookup" and current ~= "prices" and current ~= "requests" then return end
  local chat = ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()
  if chat and not UI.search:HasFocus() and not UI.filterBox:HasFocus() then return end
  if GetTime() - lastInsert < 0.2 then return end -- several hooks can see the same click
  lastInsert = GetTime()
  UI.lastInsert = lastInsert
  local id = ns:ItemIDFromLink(link)
  local name = link:match("%[(.-)%]") or ns:ItemName(id)
  W.HideSuggestions()
  if current == "lookup" then
    UI.search:SetText(name)
    UI.search:ClearFocus()
    UI:LookupItem(id)
  elseif current == "prices" and id and (ns.Stock:BagCounts()[id] or 0) > 0 then
    ns.Stock:Add(id)
    UI.priceOrder = nil
    UI:Refresh()
  else
    UI.filterBox:SetText(name)
    UI.filterText = name
    UI.priceOrder = nil
    UI.filterBox:ClearFocus()
    UI:Refresh()
  end
end

-- The same shift-click also opens the stack-split box on stacked items; close it when the
-- click was ours
local function closeSplit()
  if StackSplitFrame and GetTime() - lastInsert < 0.5 then StackSplitFrame:Hide() end
end

local function build()
  frame = CreateFrame("Frame", "CircFrame", UIParent, "BasicFrameTemplateWithInset")
  frame:SetSize(600, 480)
  frame:SetPoint("CENTER")
  frame:SetFrameStrata(ns.STRATA)
  frame:SetToplevel(true)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:SetClampedToScreen(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  frame:SetScript("OnShow", function() UI:Refresh() end)
  frame:Hide()
  tinsert(UISpecialFrames, "CircFrame")
  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  title:SetPoint("TOP", 0, -5)
  title:SetText("Circ")
  statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  statusText:SetPoint("TOPLEFT", 12, -7)

  tabs = {}
  local tabDefs = { { "lookup", "Lookup" }, { "requests", "Requests" }, { "ledger", "Ledger" }, { "prices", "Prices" }, { "settings", "Settings" } }
  local prev
  for i, def in ipairs(tabDefs) do
    local b, native = W.Tab(frame, i, def[2])
    tabs.native = native
    if prev then
      b:SetPoint("LEFT", prev, "RIGHT", native and -14 or 4, 0)
    else
      b:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", native and 6 or 10, native and 2 or -2)
    end
    b:SetID(i)
    b:SetScript("OnClick", function()
      ns.Union:Nudge()
      UI:SelectTab(def[1])
      if PlaySound and SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_TAB then pcall(PlaySound, SOUNDKIT.IG_CHARACTER_INFO_TAB) end
      UI:Refresh()
    end)
    tabs[def[1]] = b
    prev = b
  end
  if tabs.native and PanelTemplates_SetNumTabs then pcall(PanelTemplates_SetNumTabs, frame, #tabDefs) end

  -- Toolbars, in this order (later ones draw over earlier ones)
  UI:BuildLookupToolbar(frame)
  UI:BuildRequestsToolbar(frame)
  UI:BuildPricesToolbar(frame)
  UI:BuildLedgerToolbar(frame)
  UI.toolbars.settings = {}

  heroIcon = frame:CreateTexture(nil, "ARTWORK")
  heroIcon:SetSize(28, 28)
  heroIcon:SetPoint("TOPLEFT", 14, -61)
  heroIcon:Hide()
  header = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  header:SetPoint("TOPLEFT", 18, -62)
  header:SetWidth(540)
  header:SetJustifyH("LEFT")
  header:SetWordWrap(false)
  subheader = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  subheader:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -3)
  subheader:SetWidth(540)
  subheader:SetJustifyH("LEFT")
  subheader:SetWordWrap(false)
  subheader:SetTextColor(0.65, 0.65, 0.65)

  scroll = CreateFrame("ScrollFrame", "CircScroll", frame, "FauxScrollFrameTemplate")
  scroll:SetScript("OnVerticalScroll", function(self, offset)
    FauxScrollFrame_OnVerticalScroll(self, offset, ROW_H, function() UI:Refresh() end)
  end)
  rows = W.List(frame, scroll, MAX_ROWS, ROW_H, LIST_TOP, whisper)

  UI:BuildGuide(frame)

  ns.Compat.HookItemLinks(insertLink)
  ns.Compat.HookStackSplit(closeSplit)
  ns:TryOn("GLOBAL_MOUSE_DOWN", W.CloseSuggestionsOnOutsideClick)
  UI.CloseSuggestionsOnOutsideClick = W.CloseSuggestionsOnOutsideClick
end

function UI:Show(tab)
  if not frame then build() end
  if tab then UI:SelectTab(tab) end
  frame:Show()
  self:Refresh()
end

function UI:Toggle()
  if frame and frame:IsShown() then frame:Hide() else self:Show() end
end

for _, event in ipairs({ "DataChanged", "RecordsUpdated", "LedgerChanged", "UnionChanged", "UnionConnected", "BagsChanged" }) do
  ns:Listen(event, function() UI:Refresh() end)
end

-- Channel joins and leaves land a moment after the request; refresh then
local refreshQueued = false
local function refreshSoon()
  if refreshQueued then return end
  refreshQueued = true
  ns:After(0.5, function() refreshQueued = false; UI:Refresh() end)
end
ns:On("CHAT_MSG_CHANNEL_NOTICE", refreshSoon)
ns:On("CHANNEL_UI_UPDATE", refreshSoon)
