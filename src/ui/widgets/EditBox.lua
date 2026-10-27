-- ui/widgets/EditBox.lua: the text boxes in the window's toolbars, and the gray hint
-- inside an empty box ("Search items or members").
local _, ns = ...
ns.Widgets = ns.Widgets or {}
local W = ns.Widgets

-- A one-line box at x, y on parent. Escape takes the cursor out of it.
function W.EditBox(parent, name, x, y, width, maxLetters)
  local b = CreateFrame("EditBox", name, parent, "InputBoxTemplate")
  b:SetSize(width, 22)
  b:SetPoint("TOPLEFT", x, y)
  b:SetAutoFocus(false)
  if maxLetters then b:SetMaxLetters(maxLetters) end
  b:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  return b
end

-- Gray hint text inside an empty edit box
function W.Placeholder(box, text)
  local p = box:CreateFontString(nil, "ARTWORK", "GameFontDisable")
  p:SetPoint("LEFT", 2, 0)
  p:SetText(text)
  box.placeholder = p
  local function update() p:SetShown(not box:HasFocus() and ns.Text.Trim(box:GetText()) == "") end
  box:HookScript("OnEditFocusGained", update)
  box:HookScript("OnEditFocusLost", update)
  box:HookScript("OnTextChanged", update)
  box:HookScript("OnShow", update)
end
