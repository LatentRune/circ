-- ui/Guide.lua: the getting-started bar pinned to the bottom of the window. Shows the
-- first step from features/Guide.lua that isn't done, a button that goes there, and
-- arrows and dots to look at the other steps. Hides once every step is done.
-- Setting: the "Getting-started guide" checkbox on the Settings tab.
local _, ns = ...
local UI = ns.UI
local G = ns.Guide
local GUIDE = G.STEPS
local GREEN = ns.Text.GREEN
UI.GUIDE = GUIDE

local guideBar
local guideView, guideDoneCount

-- Whether the guide shows, and which step: { visible, step, done = count }
function UI:Guide()
  local first, count = G:Progress()
  if guideDoneCount and count > guideDoneCount then guideView = nil end -- a step was just done
  guideDoneCount = count
  if not first then
    G:Finish()
    return { visible = false, done = count }
  end
  return { visible = not CircDB.guide.hidden, step = guideView or first, done = count }
end

-- Forget which step the player was looking at (the guide was turned back on)
function UI:ResetGuide()
  guideView, guideDoneCount = nil, nil
end

-- What the step's button does: open its tab, and for Search, put the cursor in the box
local function goTo(step)
  UI:Show(step.tab)
  if step.tab == "lookup" then UI.search:SetFocus() end
end

-- Shows the bar for the current step. Returns whether it is showing.
function UI:UpdateGuide()
  local g = UI:Guide()
  UI.guideState = g
  guideBar:SetShown(g.visible)
  if not g.visible then return false end
  local step = GUIDE[g.step]
  local done = step.done()
  guideBar.count:SetText("Step " .. g.step .. " of " .. #GUIDE)
  guideBar.text:SetText((done and (GREEN .. "Done:|r ") or "") .. step.text)
  guideBar.go:SetShown(step.go ~= nil and not done)
  if step.go then guideBar.go:SetText(step.go) end
  guideBar.prev:SetEnabled(g.step > 1)
  guideBar.next:SetEnabled(g.step < #GUIDE)
  for i, dot in ipairs(guideBar.dots) do
    if i == g.step then dot.tex:SetVertexColor(1, 0.82, 0)
    elseif GUIDE[i].done() then dot.tex:SetVertexColor(0.25, 0.8, 0.25)
    else dot.tex:SetVertexColor(0.35, 0.35, 0.35) end
    dot:SetSize(i == g.step and 10 or 8, i == g.step and 10 or 8)
  end
  return true
end

-- Builds the bar along the bottom of the window
function UI:BuildGuide(frame)
  guideBar = CreateFrame("Frame", "CircGuide", frame, ns.Compat.Backdrop())
  guideBar:SetPoint("BOTTOMLEFT", 8, 8)
  guideBar:SetPoint("BOTTOMRIGHT", -8, 8)
  guideBar:SetHeight(68)
  if guideBar.SetBackdrop then
    guideBar:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
      insets = { left = 4, right = 4, top = 4, bottom = 4 } })
    guideBar:SetBackdropColor(0.12, 0.09, 0.02, 0.95)
    guideBar:SetBackdropBorderColor(1, 0.82, 0, 0.8)
  end
  local gTitle = guideBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  gTitle:SetPoint("TOPLEFT", 12, -9)
  gTitle:SetText("GETTING STARTED")
  guideBar.count = guideBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  guideBar.count:SetPoint("LEFT", gTitle, "RIGHT", 8, 0)
  guideBar.count:SetTextColor(0.65, 0.65, 0.65)
  guideBar.text = guideBar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  guideBar.text:SetPoint("TOPLEFT", 12, -25)
  guideBar.text:SetWidth(440)
  guideBar.text:SetJustifyH("LEFT")
  guideBar.text:SetJustifyV("TOP")
  guideBar.go = CreateFrame("Button", nil, guideBar, "UIPanelButtonTemplate")
  guideBar.go:SetSize(90, 22)
  guideBar.go:SetPoint("TOPRIGHT", -12, -9)
  guideBar.go:SetScript("OnClick", function()
    local step = GUIDE[UI.guideState and UI.guideState.step or 1]
    if step and step.tab then goTo(step) end
    UI:Refresh()
  end)
  local function arrow(dir)
    local b = CreateFrame("Button", nil, guideBar)
    b:SetSize(22, 22)
    local base = "Interface\\Buttons\\UI-SpellbookIcon-" .. (dir < 0 and "Prev" or "Next") .. "Page-"
    b:SetNormalTexture(base .. "Up")
    b:SetPushedTexture(base .. "Down")
    b:SetDisabledTexture(base .. "Disabled")
    b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    b:SetScript("OnClick", function()
      local s = (UI.guideState and UI.guideState.step or 1) + dir
      guideView = math.max(1, math.min(#GUIDE, s))
      UI:Refresh()
    end)
    return b
  end
  guideBar.next = arrow(1)
  guideBar.next:SetPoint("BOTTOMRIGHT", -10, 6)
  guideBar.dots = {}
  local dotsWidth = #GUIDE * 14
  for i = 1, #GUIDE do
    local dot = CreateFrame("Button", nil, guideBar)
    dot:SetSize(8, 8)
    dot:SetPoint("CENTER", guideBar.next, "LEFT", -6 - dotsWidth + (i - 0.5) * 14, 0)
    dot.tex = dot:CreateTexture(nil, "ARTWORK")
    dot.tex:SetAllPoints()
    dot.tex:SetColorTexture(1, 1, 1, 1)
    if dot.CreateMaskTexture and dot.tex.AddMaskTexture then
      local mask = dot:CreateMaskTexture()
      mask:SetAllPoints()
      mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
      dot.tex:AddMaskTexture(mask)
    end
    dot:SetScript("OnClick", function() guideView = i; UI:Refresh() end)
    guideBar.dots[i] = dot
  end
  guideBar.prev = arrow(-1)
  guideBar.prev:SetPoint("RIGHT", guideBar.next, "LEFT", -12 - dotsWidth, 0)
  guideBar:Hide()
end
