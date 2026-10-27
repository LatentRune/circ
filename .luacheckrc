-- luacheck settings for Circ (https://github.com/lunarmodules/luacheck). Run from the
-- repo root: luacheck src
std = "lua51"
max_line_length = false
self = false -- methods on ns often don't need self

-- The only globals Circ writes. The game needs these names:
--   CircDB                 saved variables (## SavedVariables in Circ.toc)
--   SLASH_CIRC1, SlashCmdList.CIRC   the /circ command
--   StaticPopupDialogs.CIRC_*        Circ's popups
-- Circ also names some frames (CircFrame, CircFrameTab1-5, CircScroll, CircGuide,
-- CircRequestDialog, CircMinimapButton, CircSearchBox, CircFilterBox, CircInviteBox,
-- CircUnionBox) so the game can close them with Escape and other addons can find them.
globals = {
  "CircDB",
  "SLASH_CIRC1",
  SlashCmdList = { fields = { "CIRC" } },
  StaticPopupDialogs = { fields = { "CIRC_EDIT", "CIRC_SWITCH", "CIRC_INVITE", "CIRC_TAKEOVER" } },
}

-- What Circ reads from the game and from price addons
read_globals = {
  "ACCEPT", "Auctionator", "BackdropTemplateMixin", "CANCEL", "CLASS_ICON_TCOORDS",
  "C_ChatInfo", "C_Container", "C_Item", "C_Timer", "ChatEdit_GetActiveWindow",
  "ChatEdit_InsertLink", "ChatFrameUtil", "ChatFrame_AddMessageEventFilter",
  "ChatFrame_SendTell", "CraftFrameAvailableFilterCheckButton", "CraftOnlyShowMakeable",
  "CreateFrame", "DECLINE", "DEFAULT_CHAT_FRAME", "ERR_TRADE_COMPLETE", "Enum",
  "ExpandTradeSkillSubClass", "FRIENDS_TEXTURE_OFFLINE", "FRIENDS_TEXTURE_ONLINE",
  "FauxScrollFrame_GetOffset", "FauxScrollFrame_OnVerticalScroll",
  "FauxScrollFrame_Update", "GameTooltip", "GetAuctionSellItemInfo", "GetChannelList",
  "GetChannelName", "GetCoinTextureString", "GetContainerItemID", "GetContainerItemInfo",
  "GetContainerNumSlots", "GetCraftDisplaySkillLine", "GetCraftInfo", "GetCraftItemLink",
  "GetCraftNumReagents", "GetCraftReagentInfo", "GetCraftReagentItemLink",
  "GetCraftRecipeLink", "GetCursorPosition", "GetItemIcon", "GetItemInfo",
  "GetNormalizedRealmName", "GetNumCrafts", "GetNumTradeSkills", "GetPlayerTradeMoney",
  "GetRealmName", "GetTargetTradeMoney", "GetTime", "GetTradePlayerItemInfo",
  "GetTradePlayerItemLink", "GetTradeSkillInfo", "GetTradeSkillItemLink",
  "GetTradeSkillLine", "GetTradeSkillNumMade", "GetTradeSkillNumReagents",
  "GetTradeSkillReagentInfo", "GetTradeSkillReagentItemLink", "GetTradeSkillRecipeLink",
  "GetTradeTargetItemInfo", "GetTradeTargetItemLink", "GetUnitName",
  "HandleModifiedItemClick", "IsModifiedClick", "ItemRefTooltip", "JoinPermanentChannel",
  "LeaveChannelByName", "Minimap", "MouseIsOver", "NO", "OKAY", "OpenStackSplitFrame",
  "PanelTemplates_SetNumTabs", "PanelTemplates_SetTab", "PanelTemplates_TabResize",
  "PlaySound", "RAID_CLASS_COLORS", "SOUNDKIT", "SetChannelOwner",
  "SetTradeSkillInvSlotFilter", "SetTradeSkillSubClassFilter", "StackSplitFrame",
  "StaticPopup_Show", "TSM_API", "TooltipDataProcessor", "TradeSkillFrame",
  "TradeSkillFrameAvailableFilterCheckButton", "TradeSkillOnlyShowMakeable",
  "UIErrorsFrame", "UIParent", "UISpecialFrames", "UnitClass", "UnitFactionGroup",
  "UnitIsPlayer", "UnitName", "YES", "aux", "date", "debugprofilestop", "debugstack",
  "hooksecurefunc", "strjoin", "time", "tinsert", "tostringall", "wipe",
}

-- Generated from the game's data; see tools/gen_recipes.py and tools/gen_boe.py
files["src/data"] = { ignore = { "631" } }
