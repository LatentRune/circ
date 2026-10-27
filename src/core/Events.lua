-- core/Events.lua: how Circ's files hear about things.
--
--   ns:On(event, fn)      a game event, through one hidden frame. Several files may
--                         listen to the same event; they run in the order they were added,
--                         which is the order of the files in Circ.toc.
--   ns:Listen(name, fn)   a Circ callback between files, such as "Ready", "DataChanged"
--                         or "Msg:REC" (an addon message of type REC, from core/Comm.lua)
--   ns:Fire(name, ...)    runs every ns:Listen for that name
--
-- An error in one handler is caught and shown as a debug line, so the others still run.
-- Every handler runs through ns.Run, which dev/Profiler.lua swaps out to time each part.
local _, ns = ...

-- The file that added a handler, read from the call stack, so the profiler can say where
-- time goes. The game has debugstack; elsewhere this is "?".
function ns.Caller(level)
  if not debugstack then return "?" end
  return (debugstack(level + 1, 1, 0) or ""):match("([%w_]+)%.lua") or "?"
end

-- Runs one handler. part names it, as "File event"; dev/Profiler.lua replaces this.
function ns.Run(_, fn, ...)
  return fn(...)
end

local frame = CreateFrame("Frame")
local handlers, parts = {}, {}

-- Register a handler for an event. Several modules may listen to the same event.
function ns:On(event, fn)
  if not handlers[event] then
    handlers[event] = {}
    parts[event] = {}
    frame:RegisterEvent(event)
  end
  table.insert(handlers[event], fn)
  table.insert(parts[event], ns.Caller(2) .. " " .. event)
end

-- Like ns:On, for an event this client may not have. Returns whether it was registered.
function ns:TryOn(event, fn)
  if not handlers[event] and not pcall(frame.RegisterEvent, frame, event) then return false end
  if not handlers[event] then
    handlers[event] = {}
    parts[event] = {}
  end
  table.insert(handlers[event], fn)
  table.insert(parts[event], ns.Caller(2) .. " " .. event)
  return true
end

frame:SetScript("OnEvent", function(_, event, ...)
  local list = handlers[event]
  if not list then return end
  local names = parts[event]
  for i = 1, #list do
    local ok, err = pcall(ns.Run, names[i], list[i], ...)
    if not ok then ns:Debug("error in", event, err) end
  end
end)

-- Internal callbacks between modules
local callbacks, callbackParts = {}, {}
function ns:Listen(name, fn)
  callbacks[name] = callbacks[name] or {}
  callbackParts[name] = callbackParts[name] or {}
  table.insert(callbacks[name], fn)
  table.insert(callbackParts[name], ns.Caller(2) .. " " .. name)
end
function ns:Fire(name, ...)
  local list = callbacks[name]
  if not list then return end
  local names = callbackParts[name]
  for i = 1, #list do
    local ok, err = pcall(ns.Run, names[i], list[i], ...)
    if not ok then ns:Debug("error in callback", name, err) end
  end
end
