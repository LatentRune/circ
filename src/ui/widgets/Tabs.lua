-- ui/widgets/Tabs.lua: the tabs along the bottom edge of the window, like the character
-- window's. Falls back to plain buttons if this client has no tab template.
local _, ns = ...
ns.Widgets = ns.Widgets or {}
local W = ns.Widgets

-- Tab number i on parent (named CircFrameTab<i>). Returns the button, and whether it is a
-- real tab rather than the fallback button.
function W.Tab(parent, i, label)
  for _, template in ipairs(ns.Compat.TAB_TEMPLATES) do
    local ok, b = pcall(CreateFrame, "Button", "CircFrameTab" .. i, parent, template)
    if ok and b then
      b:SetText(label)
      if PanelTemplates_TabResize then pcall(PanelTemplates_TabResize, b, 0) end
      return b, true
    end
  end
  local b = CreateFrame("Button", "CircFrameTab" .. i, parent, "UIPanelButtonTemplate")
  b:SetSize(96, 22)
  b:SetText(label)
  return b, false
end
