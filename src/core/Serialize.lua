-- core/Serialize.lua: compact, length-prefixed encoding for strings, numbers, booleans and
-- tables, used by core/Comm.lua for every addon message and by features/Records.lua for a
-- record's hash. Tables are written in pairs() order; the reader doesn't mind.
local _, ns = ...
local S = {}
ns.Serialize = S

local function encode(v, out)
  local t = type(v)
  if t == "string" then
    out[#out + 1] = "s" .. #v .. ":" .. v
  elseif t == "number" then
    out[#out + 1] = "n" .. tostring(v) .. ";"
  elseif t == "boolean" then
    out[#out + 1] = v and "T" or "F"
  elseif t == "table" then
    out[#out + 1] = "{"
    for k, val in pairs(v) do
      local kt, vt = type(k), type(val)
      if (kt == "string" or kt == "number") and vt ~= "function" and vt ~= "userdata" then
        encode(k, out)
        encode(val, out)
      end
    end
    out[#out + 1] = "}"
  else
    out[#out + 1] = "N"
  end
end

function S.Encode(v)
  local out = {}
  encode(v, out)
  return table.concat(out)
end

local decode
decode = function(s, pos)
  local c = s:sub(pos, pos)
  if c == "s" then
    local colon = s:find(":", pos, true)
    if not colon then error("bad string") end
    local len = tonumber(s:sub(pos + 1, colon - 1))
    if not len then error("bad length") end
    local str = s:sub(colon + 1, colon + len)
    if #str ~= len then error("short string") end
    return str, colon + len + 1
  elseif c == "n" then
    local semi = s:find(";", pos, true)
    if not semi then error("bad number") end
    local n = tonumber(s:sub(pos + 1, semi - 1))
    if not n then error("bad number") end
    return n, semi + 1
  elseif c == "T" then
    return true, pos + 1
  elseif c == "F" then
    return false, pos + 1
  elseif c == "N" then
    return nil, pos + 1
  elseif c == "{" then
    local t = {}
    pos = pos + 1
    while s:sub(pos, pos) ~= "}" do
      if pos > #s then error("unterminated table") end
      local k, v
      k, pos = decode(s, pos)
      v, pos = decode(s, pos)
      if k ~= nil then t[k] = v end
    end
    return t, pos + 1
  end
  error("bad type at " .. pos)
end

-- Returns the value, or nil plus an error message
function S.Decode(s)
  if type(s) ~= "string" or s == "" then return nil, "empty" end
  local ok, v, pos = pcall(decode, s, 1)
  if not ok then return nil, v end
  if pos ~= #s + 1 then return nil, "trailing data" end
  return v
end
