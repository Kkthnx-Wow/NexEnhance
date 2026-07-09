--[[
	NexEnhance - Cursor Trail
	-------------------------------------------------------------------------
	A soft glowing motion trail that follows the mouse. Fixed texture pool,
	ring-buffer samples, SetPoint only on emit, paint only alpha/size/color.

	Performance: OnUpdate sleeps when the cursor is idle and the trail has
	fully faded (dormant). Hitch after load screens wipes the buffer once.
	No PlayerModels, no per-frame table allocs, no secret combat APIs.

	Ideas studied from Frogski (pooled dots / dormant) and CursorTrail
	(mouselook + cinematic hide) — original NexEnhance implementation.
--]]

local _, ns = ...
local F, C, L = ns.F, ns.C, ns.L

local GetCursorPosition = GetCursorPosition
local GetTime = GetTime
local CreateFrame = CreateFrame
local UIParent = UIParent
local UnitAffectingCombat = UnitAffectingCombat
local wipe = wipe
local floor = math.floor
local sqrt = math.sqrt
local min = math.min
local max = math.max

local MAX_POOL = 120
local HITCH_SECONDS = 0.25
local DORMANT_MOVE = 0.5 -- px before we wake from sleep
local COLOR_CLASS, COLOR_CUSTOM, COLOR_RAINBOW = 1, 2, 3

ns:RegisterDefaults({
	cursorTrail = {
		enable = false,
		combatOnly = false,
		hideMouseLook = true,
		colorMode = COLOR_CLASS,
		color = F.RGBAToHex(C.Colors.brand),
		size = 18,
		spacing = 8,
		lifetime = 0.45,
		maxDots = 48,
		alpha = 0.85,
		shrink = true,
		offsetX = 0,
		offsetY = 0,
	},
})

local Module = ns:NewModule("CursorTrail", "cursorTrail", {
	group = "cursor",
	title = L["Cursor Trail"],
	order = 20,
	since = "1.6.0",
})

local running = false
local eventsRegistered = false
local eventHandles = {}

local root
local pool = {} -- [i] = Texture
local poolSize = 0

-- Ring buffer: birth times only (positions live on the textures via SetPoint).
local pointsT = {}
local head = 0 -- next write index (1..capacity)
local count = 0
local capacity = 0

local lastX, lastY -- latest cursor sample (wake / dormant)
local emitX, emitY -- last place we dropped a trail dot (spacing accumulates here)
local lastTick = 0
local mouseLookDepth = 0
local cinematicHidden = false
local dormant = true
local updateFrame
local cfg = {} -- hot-path snapshot of settings
local rainbowHue = 0 -- set once per Paint when rainbow mode is on
local prevOffsetX, prevOffsetY -- detect live offset changes without a full wipe

-- ---------------------------------------------------------------------------
-- Config snapshot (no ns.db lookups in OnUpdate)
-- ---------------------------------------------------------------------------
local function DotTexture()
	return C.Media.Textures.cursorTrailDot
end

local function RebuildConfig()
	local db = ns.db.cursorTrail
	cfg.enable = db.enable and true or false
	cfg.combatOnly = db.combatOnly and true or false
	cfg.hideMouseLook = db.hideMouseLook ~= false
	cfg.colorMode = db.colorMode or COLOR_CLASS
	cfg.size = db.size or 18
	cfg.spacing = max(2, db.spacing or 8)
	cfg.lifetime = max(0.1, db.lifetime or 0.45)
	cfg.maxDots = min(MAX_POOL, max(8, floor(db.maxDots or 48)))
	cfg.alpha = max(0.05, min(1, db.alpha or 0.85))
	cfg.shrink = db.shrink ~= false
	cfg.offsetX = db.offsetX or 0
	cfg.offsetY = db.offsetY or 0

	local r, g, b = F.HexToRGBA(db.color or F.RGBAToHex(C.Colors.brand))
	cfg.cr, cfg.cg, cfg.cb = r, g, b

	if cfg.colorMode == COLOR_CLASS then
		local cc = C.ClassColor
		cfg.cr, cfg.cg, cfg.cb = cc[1], cc[2], cc[3]
	end
end

local function ResolveColor(ageFrac)
	if cfg.colorMode == COLOR_RAINBOW then
		-- ageFrac 0 = newest; hue drifts along the trail + slow time shift.
		local h = ((1 - ageFrac) * 0.85 + rainbowHue) % 1
		local i = floor(h * 6) % 6
		local f = h * 6 - floor(h * 6)
		local q = 1 - f
		if i == 0 then
			return 1, f, 0
		elseif i == 1 then
			return q, 1, 0
		elseif i == 2 then
			return 0, 1, f
		elseif i == 3 then
			return 0, q, 1
		elseif i == 4 then
			return f, 0, 1
		end
		return 1, 0, q
	end
	return cfg.cr, cfg.cg, cfg.cb
end

-- ---------------------------------------------------------------------------
-- Visibility gates
-- ---------------------------------------------------------------------------
local function IsSuppressed()
	if not cfg.enable then
		return true
	end
	if cinematicHidden then
		return true
	end
	if cfg.hideMouseLook and mouseLookDepth > 0 then
		return true
	end
	if cfg.combatOnly and not UnitAffectingCombat("player") then
		return true
	end
	return false
end

-- ---------------------------------------------------------------------------
-- Pool / buffer
-- ---------------------------------------------------------------------------
local function EnsureRoot()
	if root then
		return
	end
	root = CreateFrame("Frame", "NexEnhanceCursorTrail", UIParent)
	root:SetAllPoints(UIParent)
	root:SetFrameStrata("TOOLTIP")
	root:EnableMouse(false)
	root:Hide()
end

local function EnsurePool(n)
	EnsureRoot()
	n = min(MAX_POOL, max(n, 1))
	while poolSize < n do
		poolSize = poolSize + 1
		local tex = root:CreateTexture(nil, "ARTWORK", nil, 0)
		tex:SetTexture(DotTexture())
		tex:SetBlendMode("ADD")
		tex:Hide()
		pool[poolSize] = tex
	end
	-- Hide extras if maxDots shrank.
	for i = n + 1, poolSize do
		pool[i]:Hide()
	end
end

local function ClearTrail()
	count = 0
	head = 0
	lastX, lastY = nil, nil
	emitX, emitY = nil, nil
	for i = 1, poolSize do
		pool[i]:Hide()
	end
end

local function ResizeCapacity(n)
	if capacity == n then
		return
	end
	capacity = n
	wipe(pointsT)
	ClearTrail()
	EnsurePool(n)
end

-- ---------------------------------------------------------------------------
-- Emit + paint
-- ---------------------------------------------------------------------------
local function Emit(x, y, now)
	if capacity < 1 then
		return
	end
	head = head + 1
	if head > capacity then
		head = 1
	end
	pointsT[head] = now
	if count < capacity then
		count = count + 1
	end

	-- Position once at emit — paint never SetPoints (unless offset settings change).
	local tex = pool[head]
	if tex then
		tex:ClearAllPoints()
		tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x + cfg.offsetX, y + cfg.offsetY)
		-- Stash raw cursor coords so live offset tweaks can re-anchor without wipe.
		tex._nx, tex._ny = x, y
	end
end

local function ReanchorActiveDots()
	if count < 1 then
		return
	end
	local ox, oy = cfg.offsetX, cfg.offsetY
	for i = 0, count - 1 do
		local idx = head - i
		if idx < 1 then
			idx = idx + capacity
		end
		local tex = pool[idx]
		if tex and tex._nx then
			tex:ClearAllPoints()
			tex:SetPoint("CENTER", UIParent, "BOTTOMLEFT", tex._nx + ox, tex._ny + oy)
		end
	end
end

local function Paint(now)
	if count < 1 then
		return false
	end

	local life = cfg.lifetime
	local baseSize = cfg.size
	local baseAlpha = cfg.alpha
	local anyVisible = false
	local keep = 0
	if cfg.colorMode == COLOR_RAINBOW then
		rainbowHue = (now * 0.15) % 1
	end

	-- Walk from newest → oldest in ring order.
	for i = 0, count - 1 do
		local idx = head - i
		if idx < 1 then
			idx = idx + capacity
		end
		local t = pointsT[idx]
		local age = now - t
		local tex = pool[idx]
		if not tex then
			break
		end
		if age >= life then
			tex:Hide()
		else
			local frac = age / life -- 0 new → 1 dead
			local a = baseAlpha * (1 - frac)
			local size = baseSize
			if cfg.shrink then
				size = baseSize * (1 - frac * 0.75)
			end
			local r, g, b = ResolveColor(frac)
			tex:SetSize(size, size)
			tex:SetVertexColor(r, g, b, a)
			tex:Show()
			anyVisible = true
			keep = keep + 1
		end
	end

	-- Drop expired oldest samples without reshuffling the ring.
	if keep < count then
		while count > 0 do
			local oldest = head - count + 1
			if oldest < 1 then
				oldest = oldest + capacity
			end
			if (now - pointsT[oldest]) < life then
				break
			end
			count = count - 1
			pool[oldest]:Hide()
		end
	end

	return anyVisible
end

-- ---------------------------------------------------------------------------
-- OnUpdate — dormant when idle + trail gone
-- Only one of (watch / paint) runs at a time.
-- ---------------------------------------------------------------------------
local watchFrame
local watchElapsed = 0
local WATCH_INTERVAL = 0.05

local function OnWatch(_, elapsed)
	if not running or not cfg.enable or not dormant then
		return
	end
	watchElapsed = watchElapsed + (elapsed or 0)
	if watchElapsed < WATCH_INTERVAL then
		return
	end
	watchElapsed = 0
	if IsSuppressed() then
		return
	end
	local scale = UIParent:GetEffectiveScale()
	if scale == 0 then
		return
	end
	local cx, cy = GetCursorPosition()
	cx, cy = cx / scale, cy / scale
	if lastX then
		local dx, dy = cx - lastX, cy - lastY
		if (dx * dx + dy * dy) >= (DORMANT_MOVE * DORMANT_MOVE) then
			Module:WakeUpdate()
		end
	else
		lastX, lastY = cx, cy
		Module:WakeUpdate()
	end
end

local function StartWatch()
	if not watchFrame then
		watchFrame = CreateFrame("Frame")
	end
	watchElapsed = 0
	watchFrame:SetScript("OnUpdate", OnWatch)
	watchFrame:Show()
end

local function StopWatch()
	if watchFrame then
		watchFrame:SetScript("OnUpdate", nil)
		watchFrame:Hide()
	end
end

local function StopUpdate()
	if updateFrame then
		updateFrame:SetScript("OnUpdate", nil)
		updateFrame:Hide()
	end
	dormant = true
	if running and cfg.enable then
		StartWatch()
	end
end

local function OnUpdate()
	if not running or not cfg.enable then
		StopUpdate()
		ClearTrail()
		if root then
			root:Hide()
		end
		return
	end

	local now = GetTime()
	local dt = now - lastTick
	if lastTick > 0 and dt > HITCH_SECONDS then
		-- Load screen / alt-tab hitch — drop stale samples once.
		ClearTrail()
	end
	lastTick = now

	local suppressed = IsSuppressed()
	local scale = UIParent:GetEffectiveScale()
	if scale == 0 then
		return
	end

	local cx, cy = GetCursorPosition()
	cx, cy = cx / scale, cy / scale

	-- Incident (CursorTrail, Jul 2026): spacing used last-frame delta, so slow
	-- moves never reached the threshold (lastX kept resetting). Distance must
	-- accumulate from the last *emitted* point.
	local moved = false
	if lastX then
		local mdx, mdy = cx - lastX, cy - lastY
		if (mdx * mdx + mdy * mdy) >= (DORMANT_MOVE * DORMANT_MOVE) then
			moved = true
		end
	else
		moved = true
	end
	lastX, lastY = cx, cy

	if suppressed then
		-- Don't bridge a streak across mouselook / combat-only / cinematic.
		emitX, emitY = nil, nil
	elseif not emitX then
		-- Seed emit origin without painting a stationary blob on wake.
		emitX, emitY = cx, cy
	else
		local dx, dy = cx - emitX, cy - emitY
		local dist = sqrt(dx * dx + dy * dy)
		if dist >= cfg.spacing then
			-- Fill gaps on fast flicks (cap steps so one frame can't explode).
			local steps = min(12, floor(dist / cfg.spacing))
			if steps < 1 then
				steps = 1
			end
			for s = 1, steps do
				local p = s / steps
				Emit(emitX + dx * p, emitY + dy * p, now)
			end
			emitX, emitY = cx, cy
		end
	end

	local visible = Paint(now)
	if visible then
		if root then
			root:Show()
		end
	elseif root then
		root:Hide()
	end

	-- While suppressed, motion alone must not keep the paint loop alive
	-- (combat-only OOC mouse wiggle would otherwise burn OnUpdate forever).
	if (not moved or suppressed) and not visible then
		StopUpdate()
	end
end

function Module:WakeUpdate()
	if not running or not cfg.enable then
		return
	end
	StopWatch()
	if not updateFrame then
		updateFrame = CreateFrame("Frame")
	end
	dormant = false
	lastTick = GetTime()
	updateFrame:SetScript("OnUpdate", OnUpdate)
	updateFrame:Show()
	if root then
		root:Show()
	end
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------
function Module:PLAYER_REGEN_DISABLED()
	-- combatOnly: wake so the first in-combat mouse move paints immediately.
	if cfg.combatOnly and dormant then
		self:WakeUpdate()
	end
end

function Module:PLAYER_STARTED_LOOKING()
	mouseLookDepth = mouseLookDepth + 1
end

function Module:PLAYER_STOPPED_LOOKING()
	mouseLookDepth = max(0, mouseLookDepth - 1)
end

function Module:PLAYER_STARTED_TURNING()
	mouseLookDepth = mouseLookDepth + 1
end

function Module:PLAYER_STOPPED_TURNING()
	mouseLookDepth = max(0, mouseLookDepth - 1)
end

function Module:CINEMATIC_START()
	cinematicHidden = true
	ClearTrail()
end

function Module:CINEMATIC_STOP()
	cinematicHidden = false
end

function Module:UI_SCALE_CHANGED()
	ClearTrail()
end

function Module:PLAYER_ENTERING_WORLD()
	ClearTrail()
	mouseLookDepth = 0
	cinematicHidden = false
end

function Module:EnsureEvents()
	if eventsRegistered then
		return
	end
	eventsRegistered = true
	self:TrackEvent(eventHandles, "PLAYER_REGEN_DISABLED")
	self:TrackEvent(eventHandles, "PLAYER_STARTED_LOOKING")
	self:TrackEvent(eventHandles, "PLAYER_STOPPED_LOOKING")
	self:TrackEvent(eventHandles, "PLAYER_STARTED_TURNING")
	self:TrackEvent(eventHandles, "PLAYER_STOPPED_TURNING")
	self:TrackEvent(eventHandles, "CINEMATIC_START")
	self:TrackEvent(eventHandles, "CINEMATIC_STOP")
	self:TrackEvent(eventHandles, "UI_SCALE_CHANGED")
	self:TrackEvent(eventHandles, "PLAYER_ENTERING_WORLD")
end

function Module:UnregisterModuleEvents()
	if not eventsRegistered then
		return
	end
	eventsRegistered = false
	ns:UnregisterModuleEventHandles(eventHandles)
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------
function Module:Apply()
	local oldOx, oldOy = prevOffsetX, prevOffsetY
	RebuildConfig()
	ResizeCapacity(cfg.maxDots)
	EnsurePool(cfg.maxDots)
	for i = 1, poolSize do
		pool[i]:SetTexture(DotTexture())
		pool[i]:SetBlendMode("ADD")
	end
	-- Live offset tweak: re-anchor active dots instead of wiping the trail.
	if oldOx and (oldOx ~= cfg.offsetX or oldOy ~= cfg.offsetY) then
		ReanchorActiveDots()
	end
	prevOffsetX, prevOffsetY = cfg.offsetX, cfg.offsetY
end

function Module:OnEnable()
	if not ns.db.cursorTrail.enable then
		return
	end
	running = true
	self:Apply()
	self:EnsureEvents()
	self:WakeUpdate()
end

function Module:OnDisable()
	running = false
	self:UnregisterModuleEvents()
	if updateFrame then
		updateFrame:SetScript("OnUpdate", nil)
		updateFrame:Hide()
	end
	StopWatch()
	dormant = true
	ClearTrail()
	if root then
		root:Hide()
	end
	mouseLookDepth = 0
	cinematicHidden = false
	prevOffsetX, prevOffsetY = nil, nil
end

function Module:OnSettingChanged(key)
	-- enable toggles go through OnEnable / OnDisable (Commands.ApplyModuleSetting).
	if key == "enable" then
		return
	end
	if not running then
		return
	end
	self:Apply()
	-- Offset-only tweaks don't need a wake; other keys may want a fresh paint pass.
	if key ~= "offsetX" and key ~= "offsetY" and dormant then
		self:WakeUpdate()
	end
end

function Module:RegisterOptions(category, builder)
	local _, enableInit = builder:Checkbox(
		category,
		self,
		"enable",
		L["Enable Cursor Trail"],
		L["Show a soft glowing trail that follows your mouse cursor. Lightweight pooled dots; sleeps when idle."]
	)

	local _, combatInit = builder:Checkbox(
		category,
		self,
		"combatOnly",
		L["Combat Only"],
		L["Only draw the cursor trail while you are in combat."]
	)

	local _, lookInit = builder:Checkbox(
		category,
		self,
		"hideMouseLook",
		L["Hide While Turning"],
		L["Hide the trail while you turn or look with the mouse (mouselook)."]
	)

	local _, modeInit = builder:Dropdown(category, self, "colorMode", L["Trail Color Mode"], L["Class colour, a custom colour, or a rainbow flow along the trail."], {
		{ label = L["Class Color"], value = COLOR_CLASS },
		{ label = L["Custom Color"], value = COLOR_CUSTOM },
		{ label = L["Rainbow"], value = COLOR_RAINBOW },
	})

	local _, colorInit = builder:Color(category, self, "color", L["Trail Color"], L["Used when Trail Color Mode is Custom Color."])

	local _, sizeInit = builder:Slider(category, self, "size", L["Trail Dot Size"], L["Diameter of each trail dot in pixels."], 8, 40, 1)
	local _, spaceInit = builder:Slider(category, self, "spacing", L["Trail Spacing"], L["Minimum pixels the cursor must move before a new dot is placed."], 4, 30, 1)
	local _, lifeInit = builder:Slider(category, self, "lifetime", L["Trail Lifetime"], L["How long each dot lasts, in seconds."], 0.15, 1.2, 0.05)
	local _, dotsInit = builder:Slider(category, self, "maxDots", L["Max Trail Dots"], L["Maximum dots in the pool. Higher looks denser but costs more GPU."], 16, MAX_POOL, 4)
	local _, alphaInit = builder:Slider(category, self, "alpha", L["Trail Opacity"], L["Peak opacity of the newest trail dots."], 0.2, 1, 0.05)
	local _, shrinkInit = builder:Checkbox(category, self, "shrink", L["Shrink Over Time"], L["Dots get smaller as they fade out."])
	local _, oxInit = builder:Slider(category, self, "offsetX", L["Offset X"], L["Horizontal offset from the cursor tip, in pixels."], -20, 20, 1)
	local _, oyInit = builder:Slider(category, self, "offsetY", L["Offset Y"], L["Vertical offset from the cursor tip, in pixels."], -20, 20, 1)

	builder:DependsOn(combatInit, enableInit)
	builder:DependsOn(lookInit, enableInit)
	builder:DependsOn(modeInit, enableInit)
	builder:DependsOn(colorInit, enableInit)
	builder:DependsOn(sizeInit, enableInit)
	builder:DependsOn(spaceInit, enableInit)
	builder:DependsOn(lifeInit, enableInit)
	builder:DependsOn(dotsInit, enableInit)
	builder:DependsOn(alphaInit, enableInit)
	builder:DependsOn(shrinkInit, enableInit)
	builder:DependsOn(oxInit, enableInit)
	builder:DependsOn(oyInit, enableInit)
end
