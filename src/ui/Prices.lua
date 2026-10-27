-- ui/Prices.lua: the Prices tab. Items this character sells from the bags, what it crafts
-- and sells, and the materials it buys, each with a price in gold, silver and copper.
-- Gray prices are suggestions from a price addon (features/Prices.lua); typing or turning
-- the mouse wheel sets your own. Shift-clicking an item in the bags lists it for sale
-- (ui/Window.lua). Shares the filter box with the Requests tab (ui/Requests.lua).
local _, ns = ...
local UI = ns.UI
local W, T = ns.Widgets, ns.Text
local GRAY = T.GRAY

UI.priceView = "all" -- which list shows: all, selling, crafts, materials

-- Item order on the Prices tab: highest price first. The order is kept while the player edits
-- so rows don't jump under the mouse; it is worked out again on opening the tab or filtering.
local function priceList(kind, set, priceOf)
  UI.priceOrder = UI.priceOrder or {}
  local cached = UI.priceOrder[kind]
  local n = 0
  for itemID in pairs(set) do if UI:MatchesFilter(itemID) then n = n + 1 end end
  if cached and #cached == n then return cached end
  local list = {}
  for itemID, v in pairs(set) do
    if UI:MatchesFilter(itemID) then list[#list + 1] = { id = itemID, v = v, price = priceOf(itemID, v) or 0 } end
  end
  table.sort(list, function(a, b)
    if a.price ~= b.price then return a.price > b.price end
    return ns:ItemName(a.id) < ns:ItemName(b.id)
  end)
  UI.priceOrder[kind] = list
  return list
end

function UI.builders.prices()
  local src = ns.Prices:Source()
  if src then
    UI:SetHeader("Prices", "Gray prices are suggested by " .. src .. ". Type or scroll the mouse wheel to set your own.")
  else
    UI:SetHeader("Prices", "Type a price or scroll the mouse wheel on it. Blank means buyers whisper you.")
  end
  local out = {}
  local function showing(view) return UI.priceView == "all" or UI.priceView == view end

  -- Items for sale from the bags. Zero means "whisper me"; Remove takes the listing down.
  if showing("selling") then
    out[#out + 1] = { header = true, left = "Items I'm selling", right = GRAY .. "price each|r" }
    local stock = ns.Stock:List()
    local selling = priceList("stock", stock, function(_, e) return e.price end)
    for _, e in ipairs(selling) do
      local itemID, n = e.id, ns.Stock:Count(e.id)
      local entry = stock[itemID]
      out[#out + 1] = { icon = itemID, tip = "The checkbox puts this listing on or off the market; the price is kept.",
        check = { on = not entry.off, fn = function(on) entry.off = not on or nil; ns:Fire("DataChanged") end },
        left = T.ItemText(itemID) .. (n > 0 and (GRAY .. "  x" .. n .. "|r") or (GRAY .. "  none in bags|r"))
          .. (entry.off and (GRAY .. "  off the market|r") or ""),
        money = { copper = stock[itemID] and stock[itemID].price or 0, gray = n == 0, fn = function(copper) ns.Stock:SetPrice(itemID, copper) end },
        action = { label = "Remove", fn = function() ns.Stock:Remove(itemID) end } }
    end
    if #selling == 0 then
      out[#out + 1] = { left = GRAY .. "Shift-click an item in your bags to sell it, like BoE gear or spare materials.|r" }
    end
  end
  if UI.priceView == "selling" then return out end

  local products, reagents = ns.Recipes:Mine()
  if not next(products) and not next(reagents) then
    local scanned = {}
    for prof, p in pairs(ns:CharDB().professions) do scanned[#scanned + 1] = prof .. " (" .. #(p.recipes or {}) .. ")" end
    out[#out + 1] = { header = true, left = "Crafts and materials" }
    if #scanned > 0 then
      out[#out + 1] = { left = "Scanned " .. table.concat(scanned, ", ") .. " but no recipes were recognized." }
      if ns.Dev then
        out[#out + 1] = { left = GRAY .. "Turn on debug messages in Settings and reopen the profession window,|r" }
        out[#out + 1] = { left = GRAY .. "then report the debug lines at github.com/LatentRune/circ/issues|r" }
      else
        out[#out + 1] = { left = GRAY .. "Please report this at github.com/LatentRune/circ/issues|r" }
      end
    else
      out[#out + 1] = { left = GRAY .. "Open each of your profession windows once. Your crafts and materials will appear here.|r" }
    end
    return out
  end
  -- Each item shows its price in gold / silver / copper boxes. Gray = suggested; typing or
  -- turning the mouse wheel sets your own price, and bringing it to zero clears it.
  local function priceRow(kind, itemID, price)
    local set = CircDB.overrides[kind][itemID] ~= nil
    return { icon = itemID, left = T.ItemText(itemID),
      money = { copper = price or 0, gray = not set, fn = function(copper)
        local value = copper > 0 and copper or nil
        if kind == "buy" then ns.Prices:SetBuy(itemID, value) else ns.Prices:SetSell(itemID, value) end
      end } }
  end
  if showing("crafts") then
    local sells = priceList("sell", products, function(_, rid) return ns.Prices:Sell(rid) end)
    out[#out + 1] = { header = true, left = "What I craft and sell", right = GRAY .. "price each|r" }
    for _, e in ipairs(sells) do out[#out + 1] = priceRow("sell", e.id, ns.Prices:Sell(e.v)) end
    if #sells == 0 then out[#out + 1] = { left = GRAY .. "Nothing matches.|r" } end
  end
  if showing("materials") then
    local buys = priceList("buy", reagents, function(itemID) return ns.Prices:Buy(itemID) end)
    out[#out + 1] = { header = true, left = "Materials I buy", right = GRAY .. "price each|r" }
    for _, e in ipairs(buys) do out[#out + 1] = priceRow("buy", e.id, ns.Prices:Buy(e.id)) end
    if #buys == 0 then out[#out + 1] = { left = GRAY .. "Nothing matches.|r" } end
  end
  return out
end

-- The All / Selling / Crafts / Materials buttons, next to the shared filter box
function UI:BuildPricesToolbar(frame)
  local priceViews = W.ViewButtons(frame, UI.TOOLBAR_Y, {
    { "all", "All", 46, "Show every list." },
    { "selling", "Selling", 66, "Items you are selling from your bags." },
    { "crafts", "Crafts", 62, "What you craft and sell." },
    { "materials", "Materials", 84, "Materials you buy for your recipes." },
  }, function() return UI.priceView end, function(v) UI.priceView = v end, UI.ViewPicked)
  UI.priceViews = priceViews
  UI.toolbars.prices = { UI.filterBox, unpack(priceViews) }
end

UI.refreshers[#UI.refreshers + 1] = function() UI:HighlightViews(UI.priceViews) end
