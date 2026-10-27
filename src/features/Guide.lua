-- features/Guide.lua: the five getting-started steps and how Circ knows each is done.
-- ui/Guide.lua shows the first step not done yet in a bar at the bottom of the window.
-- Setting: the "Getting-started guide" checkbox on the Settings tab (CircDB.guide.hidden).
local _, ns = ...
local G = {}
ns.Guide = G

-- text: what to do; go: the button that takes the player there, and tab: where it goes
G.STEPS = {
  { text = "Open each of your profession windows once (press P, then click the profession). Your ledger then sees what you craft.",
    done = function() return next(ns:CharDB().professions) ~= nil end },
  { text = "Look up an item to see who in your ledger buys it or makes it. You can also shift-click an item in your bags.",
    go = "Search", tab = "lookup", done = function() return CircDB.guide.looked end },
  { text = "Check your prices. Any price you leave blank tells buyers to whisper you instead.",
    go = "Prices", tab = "prices", done = function() return CircDB.guide.prices end },
  { text = "Post a request for something you need, like materials for your recipes.",
    go = "Requests", tab = "requests", done = function() return next(CircDB.wants) ~= nil end },
  { text = "Meet your ledger: see who is in it, the gold you trade, and invite friends.",
    go = "Ledger", tab = "ledger", done = function() return CircDB.guide.ledger end },
}

-- The first step not done yet (nil once all are), and how many are done
function G:Progress()
  local first, count = nil, 0
  for i, step in ipairs(G.STEPS) do
    if step.done() then count = count + 1 elseif not first then first = i end
  end
  return first, count
end

-- Every step is done: say so, once
function G:Finish()
  if not CircDB.guide.finished then
    CircDB.guide.finished = true
    ns:Print("You finished getting started. Happy trading!")
  end
end

-- Start over: the Settings checkbox turned the guide back on
function G:Restart()
  CircDB.guide.finished, CircDB.guide.looked, CircDB.guide.prices, CircDB.guide.ledger = nil, nil, nil, nil
end
