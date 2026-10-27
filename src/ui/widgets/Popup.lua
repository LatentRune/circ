-- ui/widgets/Popup.lua: the game's popups, raised to Circ's layer, and a popup with a
-- number box (the suggested-price percentages on the Settings tab).
--
--   ns.STRATA                       the layer Circ's windows and popups sit on
--   ns:ShowPopup(which, ...)        StaticPopup_Show, raised above other windows
--   ns:EditNumber(key, label, min, max)   asks for CircDB.settings[key]
local _, ns = ...

-- Circ's windows and popups sit on the top layer, above other windows and addons
ns.STRATA = "FULLSCREEN_DIALOG"

-- StaticPopup_Show, raised to Circ's layer. The game reuses popup frames, so the layer goes
-- back to normal when the popup closes.
function ns:ShowPopup(...)
  local dialog = StaticPopup_Show(...)
  if type(dialog) == "table" and dialog.SetFrameStrata then
    dialog:SetFrameStrata(ns.STRATA)
    if dialog.Raise then dialog:Raise() end
    if not dialog.circHooked and dialog.HookScript then
      dialog.circHooked = true
      dialog:HookScript("OnHide", function(popup) popup:SetFrameStrata("DIALOG") end)
    end
  end
  return dialog
end

-- Popup with a text box, used for the price suggestion percentages
StaticPopupDialogs["CIRC_EDIT"] = {
  text = "%s",
  button1 = OKAY or "OK",
  button2 = CANCEL or "Cancel",
  hasEditBox = true,
  OnShow = function(self, data)
    local box = self.editBox or self.EditBox
    box:SetText(data.current or "")
    box:HighlightText()
    box:SetFocus()
  end,
  OnAccept = function(self, data)
    local box = self.editBox or self.EditBox
    data.save(box:GetText())
  end,
  EditBoxOnEnterPressed = function(self)
    local parent = self:GetParent()
    parent.data.save(self:GetText())
    parent:Hide()
  end,
  EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
}

function ns:EditNumber(key, label, minV, maxV)
  ns:ShowPopup("CIRC_EDIT", label .. " (" .. minV .. " to " .. maxV .. ")", nil, {
    current = tostring(CircDB.settings[key]),
    save = function(text)
      local n = tonumber(text)
      if not n or n < minV or n > maxV then ns:Print("Enter a number from", minV, "to", maxV) return end
      CircDB.settings[key] = n
      ns:Fire("DataChanged")
    end,
  })
end
