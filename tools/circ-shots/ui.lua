-- A stand-in for the game's widget system: frames, textures, font strings and status
-- bars that remember what the addon told them, lay themselves out the way the game does
-- (anchor points, sizes, scale), and can be dumped as a flat, ordered list of things to
-- draw. Anything the addon calls that isn't modeled here quietly does nothing.

-- Runs on Lua 5.1, as the game does (unpack, not table.unpack).
local unpack = unpack or table.unpack

-- The game's UI is 768 units tall; 16:9 makes it about 1366 wide.
local SCREEN_W, SCREEN_H = 1366, 768
local NARROW = 0.82          -- Arial Narrow is about this wide next to Arial
local CHARW = dofile(SIM_DIR .. "charwidths.lua")

local STRATA = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6,
  FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }
local LAYERS = { BACKGROUND = 1, BORDER = 2, ARTWORK = 3, OVERLAY = 4, HIGHLIGHT = 5 }

ALL_FRAMES = {}   -- every frame, in creation order
local serial = 0
local function nextId() serial = serial + 1; return serial end

local noop = function() end

-- Classes: each is a method table; unknown capitalized methods resolve to a no-op.
local function class(base)
  local c = {}
  setmetatable(c, { __index = function(_, k)
    if base and base[k] ~= nil then return base[k] end
    if type(k) == "string" and k:match("^[A-Z]") then return noop end
  end })
  c.__index = c
  return c
end

local Region = class()
local Texture = class(Region)
local FontString = class(Region)
local Frame = class(Region)
local StatusBar = class(Frame)
local Slider = class(Frame)
local CheckButton = class(Frame)
local Tooltip = class(Frame)
local Cooldown = class(Frame)
local Button = class(Frame)
local EditBox = class(Frame)
local ScrollFrame = class(Frame)

------------------------------------------------------------------------------
-- Regions: points, size, visibility, alpha
------------------------------------------------------------------------------

local function newRegion(cls, kind, parent)
  local o = setmetatable({}, cls)
  o._kind, o._id, o._parent = kind, nextId(), parent
  o._points, o._order = {}, {}
  o._shown, o._alpha = true, 1
  return o
end

function Region:GetObjectType() return self._kind end
function Region:IsObjectType(t) return self._kind == t end
function Region:GetParent() return self._parent end
function Region:GetName() return self._name end

function Region:ClearAllPoints() self._points, self._order = {}, {} end

function Region:SetPoint(point, a, b, c, d)
  local rel, relPoint, x, y
  if type(a) == "number" or a == nil and b == nil then
    rel, relPoint, x, y = self._parent, point, a or 0, b or 0
  else
    rel = a
    if type(rel) == "string" then rel = _G[rel] end
    rel = rel or self._parent
    if type(b) == "string" then relPoint, x, y = b, c or 0, d or 0
    else relPoint, x, y = point, b or 0, c or 0 end
  end
  if not self._points[point] then self._order[#self._order + 1] = point end
  self._points[point] = { rel = rel, relPoint = relPoint, x = x, y = y }
end

function Region:SetAllPoints(rel)
  if type(rel) == "string" then rel = _G[rel] end
  rel = rel or self._parent
  self:ClearAllPoints()
  self:SetPoint("TOPLEFT", rel, "TOPLEFT", 0, 0)
  self:SetPoint("BOTTOMRIGHT", rel, "BOTTOMRIGHT", 0, 0)
end

function Region:GetNumPoints() return #self._order end
function Region:GetPoint(i)
  local p = self._order[i or 1]
  if not p then return end
  local s = self._points[p]
  return p, s.rel, s.relPoint, s.x, s.y
end

function Region:SetWidth(w) self._w = w end
function Region:SetHeight(h) self._h = h end
function Region:SetSize(w, h) self._w, self._h = w, h end

function Region:Show() self._shown = true; if self.OnShowChanged then self:OnShowChanged() end end
function Region:Hide() self._shown = false; if self.OnShowChanged then self:OnShowChanged() end end
function Region:SetShown(v) if v then self:Show() else self:Hide() end end
function Region:IsShown() return self._shown end
function Region:IsVisible()
  local r = self
  while r do
    if not r._shown then return false end
    r = r._parent
  end
  return true
end

function Region:SetAlpha(a) self._alpha = a end
function Region:SetClampedToScreen(v) self._clamped = v and true or false end
function Region:GetAlpha() return self._alpha end
function Region:SetIgnoreParentAlpha(v) self._ignoreParentAlpha = v and true or false end
function Region:GetEffectiveAlpha()
  if self._ignoreParentAlpha then return self._alpha or 1 end
  local a, r = 1, self
  while r do
    a = a * (r._alpha or 1)
    r = r._parent
    if r and r._ignoreParentAlpha then a = a * (r._alpha or 1); break end
  end
  return a
end

function Region:GetEffectiveScale()
  local s, r = 1, self
  while r do s = s * (r._scale or 1); r = r._parent end
  return s
end

------------------------------------------------------------------------------
-- Layout: where a region ends up, in screen pixels with y going up
------------------------------------------------------------------------------

local function split(point)
  local h = point:find("LEFT") and "L" or point:find("RIGHT") and "R" or "C"
  local v = point:find("TOP") and "T" or point:find("BOTTOM") and "B" or "C"
  return h, v
end

local resolving = {}

-- Measured width of a string (escape codes stripped) at a font size.
local function Plain(s)
  s = tostring(s or "")
  s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "  "):gsub("|H.-|h", ""):gsub("|h", ""):gsub("||", "|")
  return s
end
function TextWidth(s, size)
  local w = 0
  for line in (Plain(s) .. "|n"):gmatch("(.-)|n") do
    local lw = 0
    for i = 1, #line do lw = lw + (CHARW[line:byte(i)] or 0.55) end
    w = math.max(w, lw)
  end
  return w * size * NARROW
end
local function Lines(s) local n = 1; for _ in tostring(s or ""):gmatch("|n") do n = n + 1 end; return n end

-- Natural size when no width or height was set.
local function naturalSize(r)
  if r._kind == "FontString" then
    local size = r._font and r._font.size or 12
    local tw = TextWidth(r._text, size) + (r._font and r._font.flags ~= "" and 2 or 0)
    local lines = Lines(r._text)
    -- A set width with word wrap on (the game's default) breaks long text into lines.
    if r._w and r._wrap ~= false and tw > r._w then lines = lines + math.ceil(tw / r._w) - 1 end
    return tw, size * 1.15 * lines
  end
  return 0, 0
end

-- l, r, t, b in screen pixels (y up), or nil when it isn't fully anchored.
function Resolve(r, memo)
  memo = memo or {}
  if memo[r] ~= nil then return unpack(memo[r]) end
  if r == UIParent then return 0, SCREEN_W, SCREEN_H, 0 end
  if r._fillOf then  -- a status bar's fill
    local bar = r._fillOf
    local l, rr, t, b = Resolve(bar, memo)
    if not l then return end
    local span = (bar._max or 1) - (bar._min or 0)
    local f = span > 0 and math.max(0, math.min(1, ((bar._value or 0) - (bar._min or 0)) / span)) or 0
    if bar._orient == "VERTICAL" then
      memo[r] = { l, rr, b + (t - b) * f, b }
    elseif bar._reverse then
      memo[r] = { rr - (rr - l) * f, rr, t, b }
    else
      memo[r] = { l, l + (rr - l) * f, t, b }
    end
    return unpack(memo[r])
  end
  if resolving[r] or #r._order == 0 then return end
  resolving[r] = true
  local s = r:GetEffectiveScale()
  local L, R, CX, T, B, CY
  for _, p in ipairs(r._order) do
    local a = r._points[p]
    local rl, rr, rt, rb = Resolve(a.rel or UIParent, memo)
    if not rl then resolving[r] = nil; return end
    local rh, rv = split(a.relPoint)
    local px = (rh == "L" and rl or rh == "R" and rr or (rl + rr) / 2) + (a.x or 0) * s
    local py = (rv == "T" and rt or rv == "B" and rb or (rt + rb) / 2) + (a.y or 0) * s
    local h, v = split(p)
    if h == "L" then L = px elseif h == "R" then R = px else CX = px end
    if v == "T" then T = py elseif v == "B" then B = py else CY = py end
  end
  resolving[r] = nil
  local nw, nh = naturalSize(r)
  local w = (r._w or nw) * s
  local hgt = (r._h or nh) * s
  if L and R then elseif L then R = L + w elseif R then L = R - w elseif CX then L, R = CX - w / 2, CX + w / 2 else return end
  if T and B then elseif T then B = T - hgt elseif B then T = B + hgt elseif CY then T, B = CY + hgt / 2, CY - hgt / 2 else return end
  if r._clamped then  -- kept on screen, as the game does
    if L < 0 then R, L = R - L, 0 end
    if R > SCREEN_W then L, R = L - (R - SCREEN_W), SCREEN_W end
    if B < 0 then T, B = T - B, 0 end
    if T > SCREEN_H then B, T = B - (T - SCREEN_H), SCREEN_H end
  end
  memo[r] = { L, R, T, B }
  return L, R, T, B
end

-- Whether a font string's width is set (two side anchors or a width), so long text is cut.
local function fixedWidth(r)
  if r._w then return true end
  local left, right
  for p in pairs(r._points) do
    if p:find("LEFT") then left = true end
    if p:find("RIGHT") then right = true end
  end
  return left and right
end

function Region:GetWidth()
  local l, r = Resolve(self)
  if l then return (r - l) / self:GetEffectiveScale() end
  return self._w or 0
end
function Region:GetHeight()
  local l, _, t, b = Resolve(self)
  if l then return (t - b) / self:GetEffectiveScale() end
  return self._h or 0
end
function Region:GetSize() return self:GetWidth(), self:GetHeight() end
function Region:GetLeft() local l = Resolve(self); return l and l / self:GetEffectiveScale() end
function Region:GetRight() local _, r = Resolve(self); return r and r / self:GetEffectiveScale() end
function Region:GetTop() local _, _, t = Resolve(self); return t and t / self:GetEffectiveScale() end
function Region:GetBottom() local _, _, _, b = Resolve(self); return b and b / self:GetEffectiveScale() end
function Region:GetCenter()
  local l, r, t, b = Resolve(self)
  if not l then return end
  local s = self:GetEffectiveScale()
  return (l + r) / 2 / s, (t + b) / 2 / s
end
function Region:GetRect()
  local l, r, t, b = Resolve(self)
  if not l then return end
  local s = self:GetEffectiveScale()
  return l / s, b / s, (r - l) / s, (t - b) / s
end

-- The mouse, placed by scenarios (screen pixels, y up).
MOUSE = nil
function Region:IsMouseOver()
  if not MOUSE then return false end
  local l, r, t, b = Resolve(self)
  return l ~= nil and MOUSE.x >= l and MOUSE.x <= r and MOUSE.y >= b and MOUSE.y <= t
end
function MouseIsOver(r) return r:IsMouseOver() end
function GetCursorPosition() if MOUSE then return MOUSE.x, MOUSE.y end return 0, 0 end

------------------------------------------------------------------------------
-- Textures and font strings
------------------------------------------------------------------------------

function Texture:SetColorTexture(r, g, b, a) self._path, self._color = nil, { r, g, b, a or 1 } end
function Texture:SetTexture(path, ...)
  if type(path) == "number" then path = "fileid:" .. path end
  self._path, self._color = path, nil
  self._raid = nil
end
function Texture:GetTexture() return self._path end
function Texture:SetVertexColor(r, g, b, a) self._vc = { r, g, b, a or 1 } end
-- A gradient is drawn flat, at its average color.
function Texture:SetGradient(_, lo, hi)
  self._color = { (lo.r + hi.r) / 2, (lo.g + hi.g) / 2, (lo.b + hi.b) / 2, ((lo.a or 1) + (hi.a or 1)) / 2 }
end
function CreateColor(r, g, b, a) return { r = r, g = g, b = b, a = a or 1 } end
function Texture:SetGradientAlpha(_, r1, g1, b1, a1, r2, g2, b2, a2)
  self._color = { (r1 + r2) / 2, (g1 + g2) / 2, (b1 + b2) / 2, (a1 + a2) / 2 }
end
function Texture:GetVertexColor() local c = self._vc or { 1, 1, 1, 1 }; return c[1], c[2], c[3], c[4] end
function Texture:SetBlendMode(m) self._blend = m end
function Texture:SetDesaturated(d) self._desat = d end
function Texture:SetTexCoord(...) self._coord = { ... } end
function Texture:SetDrawLayer(layer, sub) self._layer, self._sub = layer, sub or 0 end
function Texture:SetAtlas(name) self._path = "atlas:" .. tostring(name) end

function FontString:SetFont(path, size, flags) self._font = { path = path, size = size, flags = flags or "" }; return true end
function FontString:GetFont() local f = self._font or {}; return f.path, f.size, f.flags end
function FontString:SetFontObject(o)
  if type(o) == "string" then o = _G[o] end
  if type(o) == "table" and o._font then
    self._font = { path = o._font.path, size = o._font.size, flags = o._font.flags }
    self._tc = { o._tc[1], o._tc[2], o._tc[3], 1 }
  end
end
function FontString:SetText(s) self._text = s ~= nil and tostring(s) or nil end
function FontString:SetFormattedText(fmt, ...) self._text = string.format(fmt, ...) end
function FontString:GetText() return self._text end
function FontString:SetTextColor(r, g, b, a) self._tc = { r, g, b, a or 1 } end
function FontString:GetTextColor() local c = self._tc or { 1, 1, 1, 1 }; return c[1], c[2], c[3], c[4] end
function FontString:SetJustifyH(j) self._jh = j end
function FontString:SetJustifyV(j) self._jv = j end
function FontString:SetWordWrap(w) self._wrap = w end
function FontString:SetShadowOffset(x, y) self._shadow = { x, y } end
function FontString:GetStringWidth() return TextWidth(self._text, self._font and self._font.size or 12) end
function FontString:GetStringHeight() local _, h = naturalSize(self); return h end
function FontString:SetDrawLayer(layer, sub) self._layer, self._sub = layer, sub or 0 end

-- Named font objects the game ships, for template strings.
local function FontObject(size, r, g, b)
  return { _font = { path = "Fonts\\FRIZQT__.TTF", size = size, flags = "" }, _tc = { r, g, b, 1 } }
end
GameFontNormal = FontObject(12, 1, 0.82, 0)
GameFontHighlight = FontObject(12, 1, 1, 1)
GameFontHighlightSmall = FontObject(10, 1, 1, 1)
GameFontNormalSmall = FontObject(10, 1, 0.82, 0)
GameFontDisableSmall = FontObject(10, 0.5, 0.5, 0.5)
GameFontDisable = FontObject(12, 0.5, 0.5, 0.5)
GameFontNormalLarge = FontObject(16, 1, 0.82, 0)
GameFontHighlightLarge = FontObject(16, 1, 1, 1)
ChatFontNormal = FontObject(14, 1, 1, 1)

------------------------------------------------------------------------------
-- Frames
------------------------------------------------------------------------------

function Frame:CreateTexture(name, layer, template, sub)
  local t = newRegion(Texture, "Texture", self)
  t._layer, t._sub = layer or "ARTWORK", sub or 0
  self._regions[#self._regions + 1] = t
  if name then _G[name] = t end
  return t
end

-- Masks only shape another texture; they aren't drawn on their own.
function Frame:CreateMaskTexture() return newRegion(Texture, "MaskTexture", self) end
function Texture:AddMaskTexture(m) self._masked = true end

function Frame:CreateFontString(name, layer, template)
  local fs = newRegion(FontString, "FontString", self)
  fs._layer, fs._sub = layer or "ARTWORK", 0
  local fo = type(template) == "string" and _G[template]
  if fo and fo._font then
    fs._font = { path = fo._font.path, size = fo._font.size, flags = fo._font.flags }
    fs._tc = { fo._tc[1], fo._tc[2], fo._tc[3], 1 }
  end
  self._regions[#self._regions + 1] = fs
  if name then _G[name] = fs end
  return fs
end

function Frame:SetScript(name, fn) self._scripts[name] = fn end
function Frame:GetScript(name) return self._scripts[name] end
function Frame:HookScript(name, fn)
  local old = self._scripts[name]
  self._scripts[name] = old and function(...) old(...); fn(...) end or fn
end
function Frame:HasScript() return true end

function Frame:RegisterEvent(e) self._events[e] = true end
function Frame:RegisterUnitEvent(e) self._events[e] = true end
function Frame:UnregisterEvent(e) self._events[e] = nil end
function Frame:UnregisterAllEvents() self._events = {} end
function Frame:IsEventRegistered(e) return self._events[e] == true end

function Frame:SetFrameStrata(s) self._strata = s end
function Frame:GetFrameStrata()
  local r = self
  while r do if r._strata then return r._strata end; r = r._parent end
  return "MEDIUM"
end
function Frame:SetFrameLevel(l) self._level = l end
function Frame:GetFrameLevel()
  if self._level then return self._level end
  local p = self._parent
  return p and p.GetFrameLevel and p:GetFrameLevel() + 1 or 0
end
function Frame:SetScale(s) self._scale = s end
function Frame:GetScale() return self._scale or 1 end
function Frame:SetParent(p)
  if self._parent and self._parent._children then
    for i, c in ipairs(self._parent._children) do if c == self then table.remove(self._parent._children, i); break end end
  end
  self._parent = p
  if p and p._children then p._children[#p._children + 1] = self end
end
function Frame:GetChildren() return unpack(self._children) end

function Frame:SetAttribute(k, v) self._attrs[k] = v end
function Frame:GetAttribute(k) return self._attrs[k] end
function Frame:SetFrameRef(k, v) self._attrs["frameref-" .. k] = v end
function Frame:GetFrameRef(k) return self._attrs["frameref-" .. k] end

function Frame:EnableMouse(v) self._mouse = v and true or false end
function Frame:IsMouseEnabled() return self._mouse end
function Frame:SetMouseClickEnabled(v) self._clicks = v end

function Frame:Show()
  local was = self:IsVisible()
  self._shown = true
  if not was and self:IsVisible() and self._scripts.OnShow then self._scripts.OnShow(self) end
end
function Frame:Hide()
  local was = self:IsVisible()
  self._shown = false
  if was and self._scripts.OnHide then self._scripts.OnHide(self) end
end
function Frame:SetShown(v) if v then self:Show() else self:Hide() end end

function Frame:SetChecked(v)
  self._checked = v and true or false
  if self._checkMark then self._checkMark:SetShown(self._checked) end
end
function Frame:GetChecked() return self._checked end

-- Status bars: a fill texture sized by the value.
function StatusBar:SetStatusBarTexture(path)
  if type(path) == "table" then return end
  self._fill._path = path
end
function StatusBar:GetStatusBarTexture() return self._fill end
function StatusBar:SetStatusBarColor(r, g, b, a) self._fill._vc = { r, g, b, a or 1 } end
function StatusBar:GetStatusBarColor() local c = self._fill._vc or { 1, 1, 1, 1 }; return c[1], c[2], c[3], c[4] end
function StatusBar:SetMinMaxValues(a, b) self._min, self._max = a, b end
function StatusBar:GetMinMaxValues() return self._min or 0, self._max or 1 end
function StatusBar:SetValue(v) self._value = v end
function StatusBar:GetValue() return self._value or 0 end
function StatusBar:SetReverseFill(v) self._reverse = v and true or false end
function StatusBar:GetReverseFill() return self._reverse end
function StatusBar:SetOrientation(o) self._orient = o end

-- Cooldown sweeps: drawn as a pie (see Dump), from when it started and how long it runs.
function Cooldown:SetCooldown(start, duration) self._cdStart, self._cdDur = start, duration end
function Cooldown:Clear() self._cdStart, self._cdDur = nil, nil end
function Cooldown:SetReverse(v) self._cdReverse = v and true or false end
function Cooldown:SetSwipeColor(r, g, b, a) self._cdColor = { r, g, b, a or 1 } end
function Cooldown:SetDrawEdge(v) self._cdEdge = v and true or false end
function Cooldown:SetDrawSwipe() end
function Cooldown:SetSwipeTexture() end
function Cooldown:SetEdgeTexture() end
function Cooldown:SetDrawBling() end
function Cooldown:SetHideCountdownNumbers() end

function Slider:SetMinMaxValues(a, b) self._min, self._max = a, b end
function Slider:GetMinMaxValues() return self._min or 0, self._max or 1 end
function Slider:SetValue(v)
  self._value = v
  if self._scripts.OnValueChanged then self._scripts.OnValueChanged(self, v) end
end
function Slider:GetValue() return self._value or 0 end
function Slider:SetThumbTexture(path)
  self._thumb = self._thumb or self:CreateTexture(nil, "OVERLAY")
  self._thumb._path = path
  self._thumb:SetSize(16, 16)
end

local CLASSES = { Frame = Frame, Button = Button, StatusBar = StatusBar, Slider = Slider,
  CheckButton = CheckButton, GameTooltip = Tooltip, EditBox = EditBox, ScrollFrame = ScrollFrame, Cooldown = Cooldown }

function CreateFrame(kind, name, parent, template)
  local cls = CLASSES[kind] or Frame
  local f = newRegion(cls, kind or "Frame", nil)
  f._regions, f._children, f._scripts, f._events, f._attrs = {}, {}, {}, {}, {}
  f._template = template
  f:SetParent(parent)
  if kind == "StatusBar" then
    f._fill = newRegion(Texture, "Texture", f)
    f._fill._layer, f._fill._sub, f._fill._fillOf = "ARTWORK", 0, f
    f._regions[#f._regions + 1] = f._fill
  end
  if template and template:find("UICheckButtonTemplate") then
    local box = f:CreateTexture(nil, "BACKGROUND")
    box:SetPoint("TOPLEFT", 4, -4); box:SetPoint("BOTTOMRIGHT", -4, 4)
    box:SetColorTexture(0.15, 0.15, 0.15, 1)
    f._checkMark = f:CreateTexture(nil, "OVERLAY")
    f._checkMark:SetPoint("TOPLEFT", 7, -7); f._checkMark:SetPoint("BOTTOMRIGHT", -7, 7)
    f._checkMark:SetColorTexture(1, 0.82, 0, 1)
    f._checkMark:Hide()
  end
  if template and template:find("UIPanelCloseButton") then
    f:SetSize(24, 24)
    local x = f:CreateFontString(nil, "OVERLAY")
    x:SetFont("Fonts\\ARIALN.TTF", 14, "OUTLINE"); x:SetPoint("CENTER"); x:SetText("x")
  end
  if name then f._name = name; _G[name] = f end
  ALL_FRAMES[#ALL_FRAMES + 1] = f
  if TEMPLATES then TEMPLATES(f, kind, template) end
  return f
end

------------------------------------------------------------------------------
-- The tooltip: lines kept for drawing
------------------------------------------------------------------------------

function Tooltip:SetOwner(owner, anchor) self._owner, self._anchor, self._lines = owner, anchor, {} end
function Tooltip:GetOwner() return self._owner end
function Tooltip:IsOwned(o) return self._owner == o and self._shown end
function Tooltip:ClearLines() self._lines = {} end
function Tooltip:SetText(text, r, g, b)
  self._lines = { { text = tostring(text or ""), r = r or 1, g = g or 0.82, b = b or 0, big = true } }
end
function Tooltip:AddLine(text, r, g, b, wrap)
  self._lines = self._lines or {}
  self._lines[#self._lines + 1] = { text = tostring(text or ""), r = r or 1, g = g or 0.82, b = b or 0, wrap = wrap }
end
function Tooltip:AddDoubleLine(a, b2, r1, g1, b1, r2, g2, bb2)
  self:AddLine(a, r1, g1, b1)
  local l = self._lines[#self._lines]
  l.right, l.rr, l.rg, l.rb = tostring(b2 or ""), r2 or 1, g2 or 1, bb2 or 1
end
function Tooltip:NumLines() return #(self._lines or {}) end
function Tooltip:SetUnitAura(unit, index, filter)
  local name = UnitAura(unit, index, filter)
  self:SetText(name or "Aura", 1, 1, 1)
  local d = AURA_TEXT and AURA_TEXT[name or ""]
  if d then self:AddLine(d, 1, 0.82, 0, true) end
end
function Tooltip:SetUnit(unit) self:SetText(UnitName(unit) or unit, 1, 1, 1) end

------------------------------------------------------------------------------
-- The screen, events and time
------------------------------------------------------------------------------

UIParent = newRegion(Frame, "Frame", nil)
UIParent._regions, UIParent._children, UIParent._scripts, UIParent._events, UIParent._attrs = {}, {}, {}, {}, {}
UIParent._level, UIParent._name = 0, "UIParent"
WorldFrame = UIParent

GameTooltip = CreateFrame("GameTooltip", "GameTooltip", UIParent)
GameTooltip:SetFrameStrata("TOOLTIP")
GameTooltip._shown = false
GameTooltipTextLeft1 = { GetText = function() local l = GameTooltip._lines and GameTooltip._lines[1]; return l and l.text end }

function FireEvent(event, ...)
  for _, f in ipairs(ALL_FRAMES) do
    if f._events[event] and f._scripts.OnEvent then f._scripts.OnEvent(f, event, ...) end
  end
end

-- Runs the game for a while: OnUpdate on every visible frame, frame by frame.
UNIT_WATCH = {}
function RegisterUnitWatch(f) UNIT_WATCH[f] = true end
function UnregisterUnitWatch(f) UNIT_WATCH[f] = nil end
function RegisterStateDriver() end
function UnregisterStateDriver() end

function Advance(seconds, fps)
  fps = fps or 60
  local dt = 1 / fps
  local steps = math.max(1, math.floor(seconds * fps + 0.5))
  for _ = 1, steps do
    NOW = NOW + dt
    for f in pairs(UNIT_WATCH) do
      local unit = f:GetAttribute("unit")
      if unit then f:SetShown(UnitExists(unit)) end
    end
    for _, f in ipairs(ALL_FRAMES) do
      local fn = f._scripts.OnUpdate
      if fn and f:IsVisible() then fn(f, dt) end
    end
  end
end

-- Points the mouse at a region's center and sends OnEnter to it.
function HoverOver(r, dx, dy)
  local l, rr, t, b = Resolve(r)
  if not l then error("can't hover something that isn't placed") end
  MOUSE = { x = (l + rr) / 2 + (dx or 0), y = (t + b) / 2 + (dy or 0) }
  if r._scripts and r._scripts.OnEnter then r._scripts.OnEnter(r) end
end

------------------------------------------------------------------------------
-- The dump: everything visible, back to front
------------------------------------------------------------------------------

local function rgba(c) if c then return { c[1], c[2], c[3], c[4] or 1 } end end

local function frameOrder(f)
  return STRATA[f:GetFrameStrata()] or 3, f:GetFrameLevel(), f._id
end

function Dump()
  local memo = {}
  local frames = {}
  for _, f in ipairs(ALL_FRAMES) do
    if f:IsVisible() and f ~= GameTooltip then frames[#frames + 1] = f end
  end
  table.sort(frames, function(a, b)
    local s1, l1, i1 = frameOrder(a)
    local s2, l2, i2 = frameOrder(b)
    if s1 ~= s2 then return s1 < s2 end
    if l1 ~= l2 then return l1 < l2 end
    return i1 < i2
  end)
  local out = {}
  for _, f in ipairs(frames) do
    local regions = {}
    for _, r in ipairs(f._regions) do
      if r._shown and (LAYERS[r._layer] or 3) < 5 then regions[#regions + 1] = r end
    end
    table.sort(regions, function(a, b)
      local la, lb = LAYERS[a._layer] or 3, LAYERS[b._layer] or 3
      if la ~= lb then return la < lb end
      if (a._sub or 0) ~= (b._sub or 0) then return (a._sub or 0) < (b._sub or 0) end
      return a._id < b._id
    end)
    if f._kind == "Cooldown" and f._cdDur and f._cdDur > 0 then
      local l, rr, t, b = Resolve(f, memo)
      if l then
        out[#out + 1] = { kind = "sweep", x = l, y = SCREEN_H - t, w = rr - l, h = t - b,
          alpha = f:GetEffectiveAlpha(), done = math.max(0, math.min((GetTime() - f._cdStart) / f._cdDur, 1)),
          reverse = f._cdReverse, edge = f._cdEdge, color = f._cdColor or { 0, 0, 0, 0.8 } }
      end
    end
    for _, r in ipairs(regions) do
      local l, rr, t, b = Resolve(r, memo)
      if l and rr - l > 0.01 and t - b > 0.01 then
        local item = { x = l, y = SCREEN_H - t, w = rr - l, h = t - b, alpha = r:GetEffectiveAlpha() }
        if r._kind == "FontString" then
          if r._text and r._text ~= "" then
            item.kind = "text"
            item.text = r._text
            item.size = (r._font and r._font.size or 12) * r:GetEffectiveScale()
            item.outline = r._font and r._font.flags and r._font.flags:find("OUTLINE") ~= nil
            item.color = rgba(r._tc) or { 1, 1, 1, 1 }
            item.justify = r._jh or "CENTER"
            item.narrow = NARROW
            item.clip = fixedWidth(r)
            item.wrap = r._w ~= nil and r._wrap ~= false and TextWidth(r._text, item.size) > r._w + 0.5 or nil
            item.valign = r._jv
            out[#out + 1] = item
          end
        else
          item.kind = "texture"
          item.color = rgba(r._color)
          item.path = r._path
          item.vc = rgba(r._vc)
          item.blend = r._blend
          item.raid = r._raid
          item.desat = r._desat
          item.coord = r._coord
          item.round = r._masked
          if item.color or item.path or item.raid then out[#out + 1] = item end
        end
      end
    end
  end
  -- The tooltip, if one is up.
  local tip = GameTooltip
  if tip._shown and tip._lines and #tip._lines > 0 then
    local item = { kind = "tooltip", lines = tip._lines, anchor = tip._anchor }
    local o = tip._owner
    if o and o ~= UIParent then
      local l, rr, t, b = Resolve(o, memo)
      if l then item.owner = { x = l, y = SCREEN_H - t, w = rr - l, h = t - b } end
    end
    if MOUSE then item.mouse = { x = MOUSE.x, y = SCREEN_H - MOUSE.y } end
    out[#out + 1] = item
  end
  return out, MOUSE and { x = MOUSE.x, y = SCREEN_H - MOUSE.y }
end

SCREEN = { w = SCREEN_W, h = SCREEN_H }

------------------------------------------------------------------------------
-- Buttons, edit boxes, scroll frames and the game's templates Circ builds on.
-- Each template gets a rough look made of plain colored rectangles, so the shape of
-- a window reads in a screenshot. The art itself can't ship here.
------------------------------------------------------------------------------

local function rect(f, layer, r, g, b, a, inset)
  local t = f:CreateTexture(nil, layer)
  inset = inset or 0
  t:SetPoint("TOPLEFT", inset, -inset)
  t:SetPoint("BOTTOMRIGHT", -inset, inset)
  t:SetColorTexture(r, g, b, a)
  return t
end

-- A 1-pixel border in four strips.
local function border(f, r, g, b, a, layer)
  local strips = {}
  for i, pts in ipairs({ { "TOPLEFT", "TOPRIGHT", 0, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", 0, 1 },
                         { "TOPLEFT", "BOTTOMLEFT", 1, 0 }, { "TOPRIGHT", "BOTTOMRIGHT", 1, 0 } }) do
    local t = f:CreateTexture(nil, layer or "BORDER")
    t:SetPoint(pts[1]); t:SetPoint(pts[2])
    if pts[3] == 1 then t:SetWidth(1) else t:SetHeight(1) end
    t:SetColorTexture(r, g, b, a or 1)
    strips[i] = t
  end
  return strips
end

-- Button text, like the game's GetFontString / SetText on a button.
function Button:SetText(t)
  if not self._label then
    self._label = self:CreateFontString(nil, "OVERLAY", self._labelFont or "GameFontNormal")
    self._label:SetPoint("CENTER", 0, self._labelY or 0)
  end
  self._label:SetText(t)
  self:_paint()
end
function Button:GetText() return self._label and self._label:GetText() end
function Button:GetFontString() return self._label end
function Button:SetFormattedText(fmt, ...) self:SetText(string.format(fmt, ...)) end
function Button:Enable() self._disabled = false; self:_paint() end
function Button:Disable() self._disabled = true; self:_paint() end
function Button:SetEnabled(v) if v then self:Enable() else self:Disable() end end
function Button:IsEnabled() return not self._disabled end
function Button:LockHighlight() self._locked = true; self:_paint() end
function Button:UnlockHighlight() self._locked = false; self:_paint() end
function Button:Click(which) if self._scripts.OnClick and not self._disabled then self._scripts.OnClick(self, which or "LeftButton") end end
function Button:SetNormalTexture(p)
  self._normalTex = self._normalTex or self:CreateTexture(nil, "ARTWORK")
  self._normalTex:SetAllPoints()
  self._normalPath = p
  self:_paint()
end
function Button:SetHighlightTexture() end
function Button:SetPushedTexture() end
function Button:SetDisabledTexture(p) self._disabledPath = p; self:_paint() end
-- How a button looks now: enabled, disabled, or held lit (a selected view or tab).
function Button:_paint()
  if self._normalTex then
    self._normalTex:SetTexture(self._disabled and self._disabledPath or self._normalPath)
  end
  if self._bg then
    local c = self._disabled and self._bgOff or self._locked and self._bgLit or self._bgOn
    self._bg:SetColorTexture(c[1], c[2], c[3], c[4])
  end
  if self._label then
    if self._disabled then self._label:SetTextColor(0.5, 0.5, 0.5)
    elseif self._tab and self._selected then self._label:SetTextColor(1, 1, 1)
    elseif self._locked then self._label:SetTextColor(1, 1, 1)
    else self._label:SetTextColor(1, 0.82, 0) end
  end
end
CheckButton.SetText = Button.SetText

-- Edit boxes: the text shows in a font string; SetText fires OnTextChanged like the game.
function EditBox:_fs()
  if not self._textFS then
    self._textFS = self:CreateFontString(nil, "OVERLAY", "ChatFontNormal")
    self._textFS:SetPoint("LEFT", self._textInset or 2, 0)
    self._textFS:SetPoint("RIGHT", -2, 0)
    self._textFS:SetJustifyH(self._jh or "LEFT")
  end
  return self._textFS
end
function EditBox:SetText(t, userInput)
  t = tostring(t or "")
  if self._max and self._max > 0 and #t > self._max then t = t:sub(1, self._max) end
  local changed = t ~= (self._text or "")
  self._text = t
  self:_fs():SetText(t)
  if changed and self._scripts.OnTextChanged then self._scripts.OnTextChanged(self, userInput or false) end
end
function EditBox:GetText() return self._text or "" end
function EditBox:GetNumber() return tonumber(self._text) or 0 end
function EditBox:SetMaxLetters(n) self._max = n end
function EditBox:SetJustifyH(j) self._jh = j; self:_fs():SetJustifyH(j) end
function EditBox:SetTextColor(r, g, b, a) self:_fs():SetTextColor(r, g, b, a) end
function EditBox:SetFontObject(o) self:_fs():SetFontObject(o) end
function EditBox:SetFocus()
  if FOCUS and FOCUS ~= self then FOCUS:ClearFocus() end
  if FOCUS == self then return end
  FOCUS = self
  if self._scripts.OnEditFocusGained then self._scripts.OnEditFocusGained(self) end
end
function EditBox:ClearFocus()
  if FOCUS ~= self then return end
  FOCUS = nil
  if self._scripts.OnEditFocusLost then self._scripts.OnEditFocusLost(self) end
end
function EditBox:HasFocus() return FOCUS == self end
function EditBox:Insert(t) self:SetText((self._text or "") .. t, true) end

-- Scroll frames: FauxScrollFrame keeps an offset and shows a bar when the list is longer.
function ScrollFrame:SetVerticalScroll(v) self._offsetPx = v end
function ScrollFrame:GetVerticalScroll() return self._offsetPx or 0 end

function FauxScrollFrame_Update(frame, numItems, numToDisplay, valueStep)
  frame._numItems, frame._numToDisplay, frame._step = numItems, numToDisplay, valueStep
  local bar = frame._bar
  if not bar then return end
  local need = numItems > numToDisplay
  bar:SetShown(need)
  if need then
    local maxOff = numItems - numToDisplay
    local off = math.min(frame._offset or 0, maxOff)
    frame._offset = off
    local track = bar:GetHeight()
    local thumbH = math.max(16, track * numToDisplay / numItems)
    bar._thumb:ClearAllPoints()
    bar._thumb:SetPoint("TOPLEFT", 1, -(track - thumbH) * off / maxOff)
    bar._thumb:SetSize(14, thumbH)
  else
    frame._offset = 0
  end
end
function FauxScrollFrame_GetOffset(frame) return frame._offset or 0 end
function FauxScrollFrame_OnVerticalScroll(frame, value, itemHeight, updateFn)
  frame._offset = math.floor(value / itemHeight + 0.5)
  if updateFn then updateFn(frame) end
end

-- Tabs: the game's PanelTemplates helpers, so the selected tab looks selected.
function PanelTemplates_TabResize(tab, padding)
  local w = tab._label and TextWidth(tab._label:GetText(), 10) or 60
  tab:SetWidth(w + 30 + (padding or 0))
end
function PanelTemplates_SetNumTabs(frame, n) frame.numTabs = n end
function PanelTemplates_SetTab(frame, id)
  frame.selectedTab = id
  for i = 1, frame.numTabs or 0 do
    local tab = _G[frame:GetName() .. "Tab" .. i]
    if tab then
      tab._selected = i == id
      local c = tab._selected and { 0.32, 0.25, 0.10, 1 } or { 0.16, 0.12, 0.06, 1 }
      tab._bgOn, tab._bgLit = c, c
      tab:_paint()
    end
  end
end

-- Backdrops: a background inset by the insets, and a border in the edge color.
local function addBackdrop(f)
  function f:SetBackdrop(b)
    local i = b and b.insets and b.insets.left or 0
    self._bdBg = self._bdBg or rect(self, "BACKGROUND", 0, 0, 0, 1, i)
    self._bdEdge = self._bdEdge or border(self, 0.6, 0.6, 0.6, 1)
  end
  function f:SetBackdropColor(r, g, b, a) if self._bdBg then self._bdBg:SetColorTexture(r, g, b, a or 1) end end
  function f:SetBackdropBorderColor(r, g, b, a)
    for _, t in ipairs(self._bdEdge or {}) do t:SetColorTexture(r, g, b, a or 1) end
  end
end

-- What each template adds when a frame is made with it.
function TEMPLATES(f, kind, template)
  template = template or ""
  if template:find("BackdropTemplate") then addBackdrop(f) end
  if template:find("BasicFrameTemplate") then
    -- A dark window with a title strip, a lighter inset and a close button.
    rect(f, "BACKGROUND", 0.07, 0.07, 0.08, 0.96)
    local strip = f:CreateTexture(nil, "BORDER")
    strip:SetPoint("TOPLEFT", 2, -2); strip:SetPoint("TOPRIGHT", -2, -2); strip:SetHeight(20)
    strip:SetColorTexture(0.22, 0.17, 0.07, 1)
    border(f, 0.55, 0.45, 0.25, 1, "ARTWORK")
    if template:find("WithInset") then
      local inset = f:CreateTexture(nil, "BORDER")
      inset:SetPoint("TOPLEFT", 4, -24); inset:SetPoint("BOTTOMRIGHT", -6, 4)
      inset:SetColorTexture(0.11, 0.11, 0.12, 1)
    end
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 1)
  elseif template:find("UIPanelButtonTemplate") then
    f._bgOn, f._bgLit, f._bgOff = { 0.50, 0.08, 0.06, 1 }, { 0.68, 0.16, 0.10, 1 }, { 0.28, 0.24, 0.22, 1 }
    f._bg = rect(f, "BACKGROUND", 0, 0, 0, 1)
    border(f, 0.75, 0.6, 0.3, 1, "BORDER")
    f._labelFont = "GameFontNormalSmall"
    f:_paint()
  elseif template:find("TabButtonTemplate") then
    f._tab = true
    f:SetSize(80, 30)
    f._bgOn, f._bgLit, f._bgOff = { 0.16, 0.12, 0.06, 1 }, { 0.16, 0.12, 0.06, 1 }, { 0.16, 0.12, 0.06, 1 }
    -- The game's tab art has see-through edges, so neighbors overlap without touching.
    local edge = f:CreateTexture(nil, "BACKGROUND")
    edge:SetPoint("TOPLEFT", 7, -2); edge:SetPoint("BOTTOMRIGHT", -7, 4)
    edge:SetColorTexture(0.55, 0.45, 0.25, 1)
    f._bg = f:CreateTexture(nil, "BORDER")
    f._bg:SetPoint("TOPLEFT", 8, -2); f._bg:SetPoint("BOTTOMRIGHT", -8, 5)
    f._labelFont, f._labelY = "GameFontNormalSmall", 2
    f:_paint()
  elseif template:find("InputBoxTemplate") then
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", -5, 0); bg:SetPoint("BOTTOMRIGHT", 0, 0)
    bg:SetColorTexture(0.02, 0.02, 0.02, 0.9)
    local b = CreateFrame("Frame", nil, f)
    b:SetPoint("TOPLEFT", -5, 0); b:SetPoint("BOTTOMRIGHT", 0, 0)
    border(b, 0.45, 0.45, 0.45, 1)
    f:_fs():SetFontObject("ChatFontNormal")
  elseif template:find("FauxScrollFrameTemplate") then
    local bar = CreateFrame("Frame", nil, f)
    bar:SetPoint("TOPLEFT", f, "TOPRIGHT", 6, -16)
    bar:SetPoint("BOTTOMLEFT", f, "BOTTOMRIGHT", 6, 16)
    bar:SetWidth(16)
    rect(bar, "BACKGROUND", 0.05, 0.05, 0.05, 0.8)
    bar._thumb = bar:CreateTexture(nil, "ARTWORK")
    bar._thumb:SetColorTexture(0.55, 0.45, 0.25, 1)
    bar:Hide()
    f._bar = bar
  end
  if kind == "EditBox" and not f._textFS then f:_fs() end
end
