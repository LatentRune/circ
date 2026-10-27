-- The cast and props most scenarios share: items the game knows, Alice's Tailoring
-- window, a price addon, and four other ledger members. A scenario loads it with
--   dofile(SIM_DIR .. "fixtures.lua")
-- and then picks what it needs.

local I = "Interface\\Icons\\"
Item(2589, "Linen Cloth", 1, I .. "INV_Fabric_Linen_01", 13)
Item(2996, "Bolt of Linen Cloth", 1, I .. "INV_Fabric_Linen_02", 40)
Item(2320, "Coarse Thread", 1, I .. "INV_Fabric_Linen_03", 2)
Item(2570, "Linen Cloak", 1, I .. "INV_Misc_Cape_01", 23)
Item(2568, "Brown Linen Vest", 1, I .. "INV_Shirt_05", 22)
Item(4343, "Brown Linen Pants", 1, I .. "INV_Pants_02", 34)
Item(12359, "Thorium Bar", 1, I .. "INV_Ingot_07", 600)
Item(12363, "Arcane Crystal", 2, I .. "INV_Misc_Gem_Crystal_01", 0)
Item(12360, "Arcanite Bar", 2, I .. "INV_Misc_StoneTablet_05", 0)
Item(720, "Brawler Gloves", 2, I .. "INV_Gauntlets_04", 412)
Item(14047, "Runecloth", 1, I .. "INV_Fabric_Linen_03", 400)
Item(4306, "Silk Cloth", 1, I .. "INV_Fabric_Silk_01", 38)
Item(7073, "Broken Fang", 0, I .. "INV_Misc_Bone_08", 6)

-- Alice's Tailoring window: four recipes, all in the bundled recipe list.
TAILORING = { name = "Tailoring", rank = 75, max = 150, recipes = {
  { name = "Cloth", kind = "header" },
  { name = "Bolt of Linen Cloth", spell = 2963, product = 2996, reagents = { { 2589, 2 } } },
  { name = "Linen Cloak", spell = 2387, product = 2570, reagents = { { 2320, 1 }, { 2996, 1 } } },
  { name = "Brown Linen Vest", spell = 2385, product = 2568, reagents = { { 2320, 1 }, { 2996, 1 } } },
  { name = "Brown Linen Pants", spell = 3914, product = 4343, reagents = { { 2320, 1 }, { 2996, 2 } } },
} }

-- Auction House prices, in copper.
AH = { [2589] = 55, [2996] = 160, [2320] = 30, [2570] = 420, [2568] = 380, [4343] = 610,
  [12359] = 2400, [12363] = 41000, [12360] = 58000, [720] = 9500, [14047] = 1200 }

-- Members, as Member() / OfflineMember() take them.
BOB = { name = "Bob", class = "WARRIOR", profs = { Alchemy = 275, Herbalism = 300 }, recipes = { 17187 },
  buy = { [12359] = 2000, [12363] = 38000 }, sell = { [12360] = 62000 } }
CARA = { name = "Cara", class = "MAGE", profs = { Tailoring = 140, Enchanting = 120 }, recipes = { 2963, 2387, 3914 },
  buy = { [2589] = 60, [2320] = 25 }, sell = { [2570] = 450, [4343] = 0 },
  wants = { [2589] = { 40, 60 }, [14047] = { 20, 1500 } }, stock = { [720] = { 1, 12000 } },
  bags = { [2589] = 12, [4306] = 30 } }
DAIN = { name = "Dain", class = "PRIEST", profs = { Blacksmithing = 225, Mining = 230 }, recipes = { 12260 },
  buy = { [12359] = 2200 }, wants = { [12359] = { 10, 2500 } } }
EIRA = { name = "Eira", class = "HUNTER", profs = { Skinning = 180 }, recipes = {},
  bags = { [2589] = 40, [720] = 1, [12363] = 2 } }

-- Alice's bags: cloth and thread for her recipes, one BoE, and some junk.
function StockBags()
  WORLD.bags = {
    [1] = { 2589, 20 }, [2] = { 2589, 14 }, [3] = { 2320, 10 }, [4] = { 12359, 6 },
    [5] = { 720, 1 }, [6] = { 7073, 3 }, [7] = { 2570, 1, true },
  }
end

-- A returning player in the ledger SMITH with Bob, Cara and Eira online and Dain offline,
-- Tailoring scanned and Auctionator installed. extra: saved variables to add.
function Setup(extra, opts)
  opts = opts or {}
  StockBags()
  if not opts.noPrices then InstallAuctionator(AH) end
  Boot(Returning(extra))
  Advance(5)
  if not opts.noScan then OpenProfession(TAILORING) end
  Member(BOB)
  Member(CARA)
  Member(EIRA)
  OfflineMember(DAIN, "Bob")
  Advance(5)
end
