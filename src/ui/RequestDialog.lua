-- ui/RequestDialog.lua: the small window for posting a request to buy: the item, a
-- quantity, and the price each in gold, silver and copper (ui/widgets/MoneyInput.lua).
-- Opens from the Requests tab, the Lookup tab's Request button, or a suggestion.
-- Saves into CircDB.wants, which features/Records.lua publishes to the ledger.
local _, ns = ...
local UI = ns.UI
local T = ns.Text

-- Request dialog: quantity, and price each in gold / silver / copper
local requestDialog
local function buildRequestDialog()
  local d = CreateFrame("Frame", "CircRequestDialog", UIParent, "BasicFrameTemplateWithInset")
  d:SetSize(300, 160)
  d:SetPoint("CENTER", 0, 120)
  d:SetFrameStrata(ns.STRATA)
  d:SetFrameLevel(200) -- above the main window
  d:SetToplevel(true)
  d:EnableMouse(true)
  d:SetMovable(true)
  d:RegisterForDrag("LeftButton")
  d:SetScript("OnDragStart", d.StartMoving)
  d:SetScript("OnDragStop", d.StopMovingOrSizing)
  tinsert(UISpecialFrames, "CircRequestDialog")
  d.title = d:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  d.title:SetPoint("TOP", 0, -5)
  d.title:SetText("Request to buy")
  d.icon = d:CreateTexture(nil, "ARTWORK")
  d.icon:SetSize(24, 24)
  d.icon:SetPoint("TOPLEFT", 20, -32)
  d.item = d:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  d.item:SetPoint("LEFT", d.icon, "RIGHT", 8, 0)
  d.item:SetWidth(230)
  d.item:SetJustifyH("LEFT")

  local qtyLabel = d:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  qtyLabel:SetPoint("TOPLEFT", 20, -70)
  qtyLabel:SetText("Quantity")
  d.qty = ns.MoneyInput.NumberBox(d, 44, 9999)
  d.qty:SetPoint("TOPLEFT", 90, -66)

  local priceLabel = d:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  priceLabel:SetPoint("TOPLEFT", 20, -96)
  priceLabel:SetText("Price each")
  d.price = ns.MoneyInput.Money(d)
  d.price:SetPoint("TOPLEFT", 78, -92)

  local ok = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
  ok:SetSize(100, 22)
  ok:SetPoint("BOTTOMRIGHT", d, "BOTTOM", -4, 12)
  ok:SetText("Post request")
  d.ok = ok
  local cancel = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
  cancel:SetSize(100, 22)
  cancel:SetPoint("BOTTOMLEFT", d, "BOTTOM", 4, 12)
  cancel:SetText(CANCEL or "Cancel")
  cancel:SetScript("OnClick", function() d:Hide() end)
  ok:SetScript("OnClick", function()
    d.qty:ClearFocus()
    for _, b in ipairs(d.price.boxes) do b:ClearFocus() end
    local qty = d.qty:GetValue()
    if qty < 1 then ns:Print("Enter a quantity of 1 or more.") return end
    local old = CircDB.wants[d.itemID]
    CircDB.wants[d.itemID] = { qty = qty, price = d.price:GetCopper(), off = old and old.off or nil }
    ns:Fire("DataChanged")
    d:Hide()
  end)
  -- Enter in any box places the request
  d.qty:HookScript("OnEnterPressed", function() ok:Click() end)
  for _, b in ipairs(d.price.boxes) do b:HookScript("OnEnterPressed", function() ok:Click() end) end
  d:Hide()
  return d
end

function UI:EditRequest(itemID)
  requestDialog = requestDialog or buildRequestDialog()
  local w = CircDB.wants[itemID]
  requestDialog.itemID = itemID
  requestDialog.icon:SetTexture(T.ItemIcon(itemID))
  requestDialog.item:SetText(T.ItemText(itemID))
  requestDialog.qty:SetValue(w and w.qty or 20)
  requestDialog.price:SetCopper(w and w.price or ns.Prices:Buy(itemID) or 0)
  requestDialog:Show()
  requestDialog:Raise()
  requestDialog.qty:SetFocus()
  requestDialog.qty:HighlightText()
end
