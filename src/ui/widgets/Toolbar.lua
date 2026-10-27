-- ui/widgets/Toolbar.lua: buttons for the window's toolbars, hover help, and rows of
-- buttons that pick which list a tab shows (All / Mine / Others ...).
local _, ns = ...
ns.Widgets = ns.Widgets or {}
local W = ns.Widgets

function W.Button(parent, label, x, y, width)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(width or 80, 22)
  b:SetPoint("TOPLEFT", x, y)
  b:SetText(label)
  return b
end

-- Hover help
function W.Tip(widget, text)
  widget:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine(text, 1, 1, 1, true)
    GameTooltip:Show()
  end)
  widget:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

-- One button per view: views = { { key, label, width, tip }, ... }. get() says which is
-- picked, set(key) picks one, then onPick() runs. Returns the buttons by key and in order,
-- with .get kept for highlighting.
function W.ViewButtons(parent, y, views, get, set, onPick)
  local buttons, x = {}, 222
  for _, v in ipairs(views) do
    local b = W.Button(parent, v[2], x, y, v[3])
    b:SetScript("OnClick", function()
      set(v[1])
      onPick()
    end)
    W.Tip(b, v[4])
    buttons[v[1]] = b
    buttons[#buttons + 1] = b
    x = x + v[3] + 4
  end
  buttons.get = get
  return buttons
end
