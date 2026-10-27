-- ui/widgets/MoneyInput.lua: number boxes for quantities and gold / silver / copper, with
-- coin icons, used by the Prices tab's rows (ui/widgets/List.lua) and the request dialog
-- (ui/RequestDialog.lua). The mouse wheel over a box changes it by 1.
local _, ns = ...
local MI = {}
ns.MoneyInput = MI

local COIN_ICONS = {
  "Interface\\MoneyFrame\\UI-GoldIcon",
  "Interface\\MoneyFrame\\UI-SilverIcon",
  "Interface\\MoneyFrame\\UI-CopperIcon",
}

-- A numeric box. onChange(value, fromWheel) runs on Enter, on losing focus and on each wheel step.
function MI.NumberBox(parent, width, maxValue, onChange)
  local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  box:SetSize(width, 18)
  box:SetAutoFocus(false)
  box:SetNumeric(true)
  box:SetMaxLetters(#tostring(maxValue))
  box:SetJustifyH("RIGHT")
  box.maxValue = maxValue
  local function value()
    return math.min(tonumber(box:GetText()) or 0, maxValue)
  end
  box.GetValue = value
  function box:SetValue(n)
    self.shown = n or 0
    self:SetText(n and n > 0 and tostring(n) or "")
  end
  local function commit(fromWheel)
    if onChange then onChange(value(), fromWheel) end
  end
  box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  box:SetScript("OnEditFocusLost", function(self)
    self:HighlightText(0, 0)
    if value() ~= (self.shown or 0) then
      self.shown = value()
      commit(false)
    end
  end)
  box:EnableMouseWheel(true)
  box:SetScript("OnMouseWheel", function(self, delta)
    local n = math.max(0, math.min(maxValue, value() + (delta > 0 and 1 or -1)))
    self:SetValue(n)
    commit(true)
  end)
  return box
end

-- Gold, silver and copper boxes with coin icons. onChange(copper) runs when the player
-- finishes typing in a box or turns the mouse wheel over one.
function MI.Money(parent, onChange)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(150, 18)
  local boxes = {}
  local function total()
    return boxes[1]:GetValue() * 10000 + boxes[2]:GetValue() * 100 + boxes[3]:GetValue()
  end
  local widths, maxes = { 44, 22, 22 }, { 99999, 99, 99 }
  local x = 0
  for i = 1, 3 do
    local box = MI.NumberBox(f, widths[i], maxes[i], function()
      if f.onChange then f.onChange(total()) end
    end)
    box:SetPoint("LEFT", x + 6, 0)
    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(COIN_ICONS[i])
    icon:SetSize(13, 13)
    icon:SetPoint("LEFT", box, "RIGHT", 1, 0)
    boxes[i] = box
    x = x + widths[i] + 6 + 15
  end
  f:SetWidth(x)
  f.boxes = boxes
  f.onChange = onChange
  f.GetCopper = function() return total() end
  function f:SetCopper(copper)
    copper = math.floor(copper or 0)
    for _, b in ipairs(boxes) do
      if b:HasFocus() then return end -- don't overwrite what the player is typing
    end
    boxes[1]:SetValue(math.floor(copper / 10000))
    boxes[2]:SetValue(math.floor(copper / 100) % 100)
    boxes[3]:SetValue(copper % 100)
  end
  function f:SetGray(gray)
    for _, b in ipairs(boxes) do
      if gray then b:SetTextColor(0.6, 0.6, 0.6) else b:SetTextColor(1, 1, 1) end
    end
  end
  return f
end
