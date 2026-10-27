-- ui/widgets/Suggest.lua: the list of item and member names that drops down under a
-- search box while typing. Click, Enter or Tab picks the first; Escape or a click
-- anywhere else closes it. Names come from features/Lookup.lua (Suggest).
local _, ns = ...
ns.Widgets = ns.Widgets or {}
local W = ns.Widgets
local T = ns.Text

local suggestFrames = {}

-- Closes every open suggestion list
function W.HideSuggestions()
  for _, f in pairs(suggestFrames) do f:Hide() end
end

-- Closes the lists whose box is hidden
function W.HideOrphanSuggestions()
  for _, f in pairs(suggestFrames) do
    if not f.owner:IsShown() then f:Hide() end
  end
end

-- A click anywhere outside an open suggestion list closes it, like Escape
function W.CloseSuggestionsOnOutsideClick()
  if not MouseIsOver then return end
  for _, f in pairs(suggestFrames) do
    if f:IsShown() and not MouseIsOver(f) and not MouseIsOver(f.owner) then f:Hide() end
  end
end

-- Autocomplete list under an edit box. onChoose(suggestion) runs on click, Enter or Tab;
-- onEnterWithout(text), if given, runs on Enter with no list open. Returns the list, with
-- :Update(text) to fill it.
function W.Suggest(parent, box, itemsOnly, onChoose, onEnterWithout)
  local f = CreateFrame("Frame", nil, parent, ns.Compat.Backdrop())
  f.owner = box
  f:SetPoint("TOPLEFT", box, "BOTTOMLEFT", -6, 2)
  f:SetSize(300, 8 * 20 + 8)
  f:SetFrameStrata(ns.STRATA)
  f:SetFrameLevel(300) -- above the window and the request dialog
  if f.SetBackdrop then
    f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
      insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    f:SetBackdropColor(0.05, 0.05, 0.05, 0.97)
  end
  f:Hide()
  suggestFrames[#suggestFrames + 1] = f
  local buttons, suggestions = {}, {}
  local function choose(s)
    f:Hide()
    box:ClearFocus()
    onChoose(s)
  end
  for i = 1, 8 do
    local b = CreateFrame("Button", nil, f)
    b:SetSize(288, 20)
    b:SetPoint("TOPLEFT", 6, -4 - (i - 1) * 20)
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(16, 16)
    b.icon:SetPoint("LEFT", 2, 0)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.text:SetPoint("LEFT", 22, 0)
    b.text:SetJustifyH("LEFT")
    b:SetScript("OnClick", function(self) if self.data then choose(self.data) end end)
    buttons[i] = b
  end
  local function update(text)
    suggestions = {}
    for _, s in ipairs(ns.Lookup:Suggest(text, 16)) do
      if (not itemsOnly or s.kind == "item") and #suggestions < 8 then suggestions[#suggestions + 1] = s end
    end
    for i, b in ipairs(buttons) do
      local s = suggestions[i]
      b.data = s
      if s then
        if s.kind == "player" then
          b.text:SetText(T.ClassColor(T.ClassOf(s.id)) .. s.label .. "|r  " .. T.GRAY .. "member|r")
          local cls = T.ClassOf(s.id)
          if CLASS_ICON_TCOORDS and cls and CLASS_ICON_TCOORDS[cls] then
            b.icon:SetTexture("Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes")
            b.icon:SetTexCoord(unpack(CLASS_ICON_TCOORDS[cls]))
          else
            b.icon:SetTexture(nil)
          end
        else
          b.text:SetText(s.label)
          b.icon:SetTexture(T.ItemIcon(s.id))
          b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        end
        b:Show()
      else
        b:Hide()
      end
    end
    f:SetHeight(#suggestions * 20 + 8)
    f:SetShown(#suggestions > 0)
  end
  f.Update = function(_, text) update(text) end
  box:HookScript("OnEnterPressed", function(self)
    if f:IsShown() and suggestions[1] then
      choose(suggestions[1])
    elseif onEnterWithout then
      f:Hide()
      self:ClearFocus()
      onEnterWithout(self:GetText())
    else
      self:ClearFocus()
    end
  end)
  box:HookScript("OnTabPressed", function()
    if f:IsShown() and suggestions[1] then choose(suggestions[1]) end
  end)
  box:HookScript("OnEscapePressed", function(self) self:ClearFocus(); f:Hide() end)
  return f
end
