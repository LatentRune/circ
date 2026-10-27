-- core/Timers.lua: run something later, or every few seconds, so dev/Profiler.lua can see
-- which file each timer belongs to. Thin wrappers around the game's C_Timer.
--
--   ns:After(seconds, fn)    once
--   ns:Every(seconds, fn)    repeatedly; returns a ticker with :Cancel()
local _, ns = ...

-- True while /circ cpu is timing (dev/Profiler.lua)
ns.profiling = false

-- The owner is only looked up while profiling, since timers are started often
local function wrap(fn)
  if not ns.profiling then return function(...) ns.Run(nil, fn, ...) end end
  local part = ns.Caller(3) .. " timer"
  return function(...) ns.Run(part, fn, ...) end
end

function ns:After(seconds, fn)
  C_Timer.After(seconds, wrap(fn))
end

function ns:Every(seconds, fn)
  return C_Timer.NewTicker(seconds, wrap(fn))
end
