-- core/Compat.lua: the one place that knows how game versions differ. Other files call
-- these instead of checking which API this client has.
--
-- Covers bag slots (C_Container or the older globals), item icons, item tooltips
-- (TooltipDataProcessor or OnTooltipSetItem), shift-click item links (ChatEdit_InsertLink,
-- ChatFrameUtil.InsertLink, HandleModifiedItemClick), the stack-split box, the backdrop
-- template, tab button templates, and what C_ChatInfo.SendAddonMessage returns.
local _, ns = ...
local C = {}
ns.Compat = C

-- Bags ---------------------------------------------------------------------------------

function C.NumSlots(bag)
  if C_Container and C_Container.GetContainerNumSlots then return C_Container.GetContainerNumSlots(bag) end
  return GetContainerNumSlots and GetContainerNumSlots(bag) or 0
end

function C.ItemIDAt(bag, slot)
  if C_Container and C_Container.GetContainerItemID then return C_Container.GetContainerItemID(bag, slot) end
  return GetContainerItemID(bag, slot)
end

-- itemID, stack count, whether the copy is soulbound, and quality, for one bag slot
function C.SlotInfo(bag, slot)
  if C_Container and C_Container.GetContainerItemInfo then
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if type(info) == "table" then return info.itemID, info.stackCount or 1, info.isBound, info.quality end
    return nil
  end
  if GetContainerItemInfo then
    local _, count, _, quality, _, _, link, _, _, itemID, isBound = GetContainerItemInfo(bag, slot)
    return itemID or ns:ItemIDFromLink(link), count or 1, isBound, quality
  end
  return nil
end

-- Items -------------------------------------------------------------------------------

-- An item's icon, or nil when the client doesn't know the item yet
function C.ItemIcon(itemID)
  local icon = GetItemIcon and GetItemIcon(itemID)
  if not icon and C_Item and C_Item.GetItemIconByID then icon = C_Item.GetItemIconByID(itemID) end
  return icon or select(10, GetItemInfo(itemID))
end

-- fn(tooltip) after the game fills an item tooltip (the main tooltip or a clicked link)
function C.HookItemTooltips(fn)
  if TooltipDataProcessor and Enum and Enum.TooltipDataType and TooltipDataProcessor.AddTooltipPostCall then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip)
      if tooltip == GameTooltip or tooltip == ItemRefTooltip then fn(tooltip) end
    end)
  else
    GameTooltip:HookScript("OnTooltipSetItem", fn)
    ItemRefTooltip:HookScript("OnTooltipSetItem", fn)
  end
end

-- fn(link) when the player shift-clicks an item, wherever it is. Several of these can see
-- the same click, so fn should ignore repeats.
function C.HookItemLinks(fn)
  if ChatEdit_InsertLink then hooksecurefunc("ChatEdit_InsertLink", fn) end
  if ChatFrameUtil and ChatFrameUtil.InsertLink then hooksecurefunc(ChatFrameUtil, "InsertLink", fn) end
  if HandleModifiedItemClick then
    hooksecurefunc("HandleModifiedItemClick", function(link)
      if IsModifiedClick("CHATLINK") then fn(link) end
    end)
  end
end

-- fn() when the game opens the stack-split box (shift-click on a stack opens it too)
function C.HookStackSplit(fn)
  if OpenStackSplitFrame then hooksecurefunc("OpenStackSplitFrame", fn) end
  if StackSplitFrame and StackSplitFrame.OpenStackSplitFrame then
    hooksecurefunc(StackSplitFrame, "OpenStackSplitFrame", fn)
  end
end

-- Frames ------------------------------------------------------------------------------

-- Template for frames with a backdrop (nil on clients where every frame has one)
function C.Backdrop() return BackdropTemplateMixin and "BackdropTemplate" or nil end

-- Tab button templates to try, best first
C.TAB_TEMPLATES = { "CharacterFrameTabButtonTemplate", "PanelTabButtonTemplate" }

-- Messages ----------------------------------------------------------------------------

-- Sends one addon message. Returns "sent", "throttled" (try again later), "refused" (the
-- client said no), or "error" plus the error. Newer clients return a result code, where
-- 0 means sent and 3 or 8 mean throttled; older ones return nothing or true.
function C.SendAddonMessage(prefix, text, kind, target)
  local ok, result = pcall(C_ChatInfo.SendAddonMessage, prefix, text, kind, target)
  if not ok then return "error", result end
  if type(result) == "number" and result ~= 0 then
    if result == 3 or result == 8 then return "throttled" end
    return "refused"
  end
  return "sent"
end
