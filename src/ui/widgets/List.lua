-- ui/widgets/List.lua: the list in the middle of the window: up to 18 rows, each with an
-- optional checkbox, icon, text on both sides, a money box and a button (Whisper, Remove,
-- Request...). Each tab's builder describes its rows; FillRow draws one.
--
-- A row description:
--   { left, right, icon = itemID, cls, header, empty, whisper, onClick, tip,
--     action = { label, fn }, check = { on, fn }, money = { copper, gray, fn } }
local _, ns = ...
ns.Widgets = ns.Widgets or {}
local W = ns.Widgets
local T = ns.Text

-- count rows of height rowH on parent, from y = top down. The mouse wheel over a row
-- scrolls `scroll`; onWhisper(name) runs for the Whisper button.
function W.List(parent, scroll, count, rowH, top, onWhisper)
  local rows = {}
  for i = 1, count do
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(546, rowH)
    row:SetPoint("TOPLEFT", 14, top - (i - 1) * rowH)
    row:EnableMouse(true)
    row:EnableMouseWheel(true)
    row:SetScript("OnMouseWheel", function(_, delta)
      local wheel = scroll:GetScript("OnMouseWheel")
      if wheel then wheel(scroll, delta) end
    end)
    row.stripe = row:CreateTexture(nil, "BACKGROUND")
    row.stripe:SetAllPoints()
    row.stripe:SetColorTexture(1, 1, 1, 0.035)
    row.hl = row:CreateTexture(nil, "BACKGROUND")
    row.hl:SetAllPoints()
    row.hl:SetColorTexture(1, 0.82, 0, 0.08)
    row.hl:Hide()
    row.line = row:CreateTexture(nil, "ARTWORK")
    row.line:SetHeight(1)
    row.line:SetPoint("BOTTOMLEFT", 2, 0)
    row.line:SetPoint("BOTTOMRIGHT", -2, 0)
    row.line:SetColorTexture(1, 0.82, 0, 0.35)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(18, 18)
    row.left = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.left:SetWordWrap(false)
    row.right = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.right:SetJustifyH("RIGHT")
    row.button = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.button:SetSize(74, rowH)
    row.button:SetPoint("RIGHT", -2, 0)
    row.button:SetScript("OnClick", function()
      if row.action then row.action.fn() return end
      if not row.whisper then return end
      onWhisper(row.whisper)
    end)
    row.money = ns.MoneyInput.Money(row, function(copper)
      if row.priceSet then row.priceSet(copper) end
    end)
    row.money:SetPoint("RIGHT", -8, 0)
    row.money:Hide()
    row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    row.check:SetSize(24, 24)
    row.check:SetPoint("LEFT", 2, 0)
    row.check:SetScript("OnClick", function(self)
      if row.toggle then row.toggle.fn(self:GetChecked() and true or false) end
    end)
    row:SetScript("OnEnter", function(self)
      local d = self.d
      if not d or d.header or d.empty then return end
      self.hl:Show()
      if d.icon then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink("item:" .. d.icon)
        if d.tip then GameTooltip:AddLine(d.tip, 0.6, 0.8, 1, true) end
        GameTooltip:Show()
      elseif d.tip then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(d.tip, 1, 1, 1, true)
        GameTooltip:Show()
      end
    end)
    row:SetScript("OnLeave", function(self)
      self.hl:Hide()
      GameTooltip:Hide()
    end)
    row:SetScript("OnMouseUp", function(self)
      local d = self.d
      if d and d.onClick then d.onClick() elseif d and d.check then
        self.check:SetChecked(not self.check:GetChecked())
        d.check.fn(self.check:GetChecked() and true or false)
      end
    end)
    row.icon:SetPoint("LEFT", row.left, "LEFT", -22, 0) -- icons sit just before the text
    rows[i] = row
  end
  return rows
end

-- Fill one list row from its description
function W.FillRow(row, d, index)
  row.d = d
  row.whisper = d.whisper
  row.action = d.action
  row.toggle = d.check
  row.priceSet = d.money and d.money.fn
  row.icon:Hide()
  row.check:Hide()
  row.button:Hide()
  row.money:Hide()
  row.line:SetShown(d.header == true)
  row.stripe:SetShown(not d.header and not d.empty and index % 2 == 0)
  row.left:ClearAllPoints()
  row.right:ClearAllPoints()
  row.left:SetText(d.left or "")
  row.right:SetText(d.right or "")

  if d.header then
    row.left:SetFontObject("GameFontNormal")
    row.left:SetJustifyH("LEFT")
    row.left:SetPoint("BOTTOMLEFT", 4, 2)
    row.right:SetPoint("BOTTOMRIGHT", -8, 3)
    return
  end
  if d.empty then
    row.left:SetFontObject("GameFontHighlight")
    row.left:SetJustifyH("CENTER")
    row.left:SetPoint("LEFT", 8, 0)
    row.left:SetPoint("RIGHT", -8, 0)
    return
  end

  local x = 6
  if d.check then
    row.check:Show()
    row.check:SetChecked(d.check.on)
    x = x + 26
  end
  if d.icon or d.cls then
    row.icon:Show()
    if d.icon then
      row.icon:SetTexture(T.ItemIcon(d.icon))
      row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    elseif CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[d.cls] then
      row.icon:SetTexture("Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes")
      row.icon:SetTexCoord(unpack(CLASS_ICON_TCOORDS[d.cls]))
    else
      row.icon:Hide()
      x = x - 22
    end
    x = x + 22
  end

  local pad = 6
  if d.whisper or d.action then
    row.button:SetText(d.whisper and "Whisper" or d.action.label)
    row.button:Show()
    pad = 82
  end
  local textRight = pad
  if d.money then
    row.money:Show()
    row.money:ClearAllPoints()
    row.money:SetPoint("RIGHT", -pad - 2, 0)
    row.money:SetCopper(d.money.copper)
    row.money:SetGray(d.money.gray)
    textRight = pad + 160
  elseif d.right and d.right ~= "" then
    local w = tonumber(row.right:GetStringWidth()) or 120
    textRight = pad + math.min(w, 220) + 10
  end
  row.left:SetFontObject("GameFontHighlight")
  row.left:SetJustifyH("LEFT")
  row.left:SetPoint("LEFT", x, 0)
  row.left:SetPoint("RIGHT", row, "RIGHT", -textRight, 0)
  row.right:SetPoint("RIGHT", -pad, 0)
end

-- A list that shows nothing yet: three blank rows, then the given lines centered
function W.EmptyRows(lines)
  local out = { { empty = true }, { empty = true }, { empty = true } }
  for _, l in ipairs(lines) do out[#out + 1] = { empty = true, left = l } end
  return out
end
