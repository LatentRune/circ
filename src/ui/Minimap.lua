-- ui/Minimap.lua: a small button on the minimap's edge. Left-click opens the window,
-- right-click opens Prices, dragging moves it around the edge (saved as minimapAngle).
-- Setting: minimap ("Minimap button", or /circ minimap on|off).
local _, ns = ...
local M = {}
ns.Minimap = M

local button

local function place()
  local angle = math.rad(CircDB.settings.minimapAngle or 210)
  button:ClearAllPoints()
  button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * 80, math.sin(angle) * 80)
end

function M:Update()
  if CircDB.settings.minimap == false then
    if button then button:Hide() end
    return
  end
  if not button then
    button = CreateFrame("Button", "CircMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local icon = button:CreateTexture(nil, "BACKGROUND")
    icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_02")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", 0, 1)
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetScript("OnClick", function(_, which)
      ns.Union:Nudge()
      if which == "RightButton" then ns.UI:Show("prices") else ns.UI:Toggle() end
    end)
    button:SetScript("OnDragStart", function(b)
      b:SetScript("OnUpdate", function()
        local mx, my = Minimap:GetCenter()
        local cx, cy = GetCursorPosition()
        local scale = Minimap:GetEffectiveScale()
        CircDB.settings.minimapAngle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
        place()
      end)
    end)
    button:SetScript("OnDragStop", function(b) b:SetScript("OnUpdate", nil) end)
    button:SetScript("OnEnter", function(b)
      GameTooltip:SetOwner(b, "ANCHOR_LEFT")
      GameTooltip:AddLine("Circ")
      GameTooltip:AddLine("Left-click: open   Right-click: prices   Drag: move", 1, 1, 1)
      GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end
  place()
  button:Show()
end

ns:Listen("Ready", function() M:Update() end)
