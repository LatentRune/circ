-- dev/Profiler.lua: /circ cpu [seconds] times every part of Circ for a while (30 seconds
-- by default) and prints where the time went, one line per file and event, callback or
-- timer. Play as usual meanwhile. Works by swapping ns.Run (core/Events.lua), which every
-- event handler, callback and timer goes through. Left out of the release zip with the
-- rest of dev/.
local _, ns = ...

local function say(...) ns:Print("cpu:", ...) end

local function profile(seconds)
  if ns.profiling then return say("already timing.") end
  if not debugprofilestop then return say("this client can't time addons.") end
  local spent, plain = {}, ns.Run
  ns.Run = function(part, fn, ...)
    local t = debugprofilestop()
    local results = { fn(...) }
    part = part or "timer"
    spent[part] = (spent[part] or 0) + debugprofilestop() - t
    return unpack(results)
  end
  local t0 = debugprofilestop()
  ns.profiling = true
  say(("timing for %d seconds; play as usual."):format(seconds))
  C_Timer.After(seconds, function()
    ns.Run = plain
    ns.profiling = false
    local secs, keys, total = (debugprofilestop() - t0) / 1000, {}, 0
    for k, ms in pairs(spent) do keys[#keys + 1] = k; total = total + ms end
    table.sort(keys, function(a, b) return spent[a] > spent[b] end)
    say(("%.2f ms per second in all."):format(total / secs))
    for i = 1, math.min(#keys, 15) do
      local k = keys[i]
      say(("  %s: %.3f ms/s"):format(k, spent[k] / secs))
    end
  end)
end

ns.Slash.commands.cpu = function(rest)
  local seconds = tonumber(rest) or 30
  profile(math.max(5, math.min(seconds, 600)))
end
