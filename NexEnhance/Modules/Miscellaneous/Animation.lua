--[[
	NexEnhance - Animation
	-------------------------------------------------------------------------
	Eye-candy animations built on Blizzard's AnimationGroup API:

	  * Login Logo - the NexEnhance logo flies across the screen the first
	    time you move after logging in (replayable with /nexlogo).
	  * Combat Text - an animated "Entering/Leaving Combat" banner.

	Ported from NDui's Modules/Misc/Animation.lua (by siweia), adapted to the
	NexEnhance framework and branded with our own logo media.
--]]

-- luacheck: globals SlashCmdList SLASH_NEXLOGO1
local _, ns = ...
local F, C, L = ns.F, ns.C, ns.L

local CreateFrame, UIParent = CreateFrame, UIParent
local PlaySound = PlaySound
local GetScreenHeight = GetScreenHeight
local IsInInstance, InCombatLockdown = IsInInstance, InCombatLockdown

local soundID = SOUNDKIT.UI_LEGENDARY_LOOT_TOAST

ns:RegisterDefaults({
	animation = {
		loginLogo = true,
		combatText = false,
	},
})

local Animation = ns:NewModule("Animation", "animation", { group = "misc", title = L["Animation"], order = 60 })

-- ---------------------------------------------------------------------------
-- Shared animation builders
-- ---------------------------------------------------------------------------
local function createTranslation(group, order, x, y, duration, smoothing, delay)
	local obj = group:CreateAnimation("Translation")
	obj:SetOffset(x, y)
	obj:SetDuration(duration)
	obj:SetOrder(order)
	if smoothing then
		obj:SetSmoothing(smoothing)
	end
	if delay then
		obj:SetStartDelay(delay)
	end
	return obj
end

local function createAlpha(group, order, fromAlpha, toAlpha, duration, delay)
	local obj = group:CreateAnimation("Alpha")
	obj:SetFromAlpha(fromAlpha)
	obj:SetToAlpha(toAlpha)
	obj:SetDuration(duration)
	obj:SetOrder(order)
	if delay then
		obj:SetStartDelay(delay)
	end
	return obj
end

local function createScale(group, order, fromX, fromY, toX, toY, duration, smoothing, delay)
	local obj = group:CreateAnimation("Scale")
	obj:SetScaleFrom(fromX, fromY)
	obj:SetScaleTo(toX, toY)
	obj:SetDuration(duration)
	obj:SetOrder(order)
	obj:SetOrigin("CENTER", 0, 0)
	if smoothing then
		obj:SetSmoothing(smoothing)
	end
	if delay then
		obj:SetStartDelay(delay)
	end
	return obj
end

-- ---------------------------------------------------------------------------
-- Login logo flyby
-- ---------------------------------------------------------------------------
local logoFrame, needAnimation

function Animation:CreateLogo()
	if logoFrame then
		return
	end

	local frame = CreateFrame("Frame", nil, UIParent)
	frame:SetSize(220, 220)
	frame:SetPoint("CENTER", UIParent, "BOTTOM", -500, GetScreenHeight() * 0.618)
	frame:SetFrameStrata("HIGH")
	frame:SetAlpha(0)
	frame:Hide()

	local tex = frame:CreateTexture(nil, "ARTWORK")
	tex:SetAllPoints()
	tex:SetTexture(C.Media.Textures.logo)

	local anim = frame:CreateAnimationGroup()
	local t1, t2, t3 = 0.5, 2.0, 0.2
	createTranslation(anim, 1, 480, 0, t1, "IN") -- slide in from the left + fade in
	local fadeIn = createAlpha(anim, 1, 0, 1, t1)
	createTranslation(anim, 2, 80, 0, t2) -- slow drift right
	createTranslation(anim, 3, -40, 0, t3) -- small pull back
	createTranslation(anim, 4, 480, 0, t1) -- fast exit right + fade out
	createAlpha(anim, 4, 1, 0, t1)

	frame:SetScript("OnShow", function()
		anim:Play()
	end)
	anim:SetScript("OnFinished", function()
		frame:Hide()
	end)
	fadeIn:SetScript("OnFinished", function()
		PlaySound(soundID)
	end)

	logoFrame = frame
end

function Animation:PlayLogo()
	if not logoFrame then
		self:CreateLogo()
	end
	logoFrame:Show()
end

-- A private frame so we can stop listening cleanly after the first movement.
local moveWatcher = CreateFrame("Frame")
moveWatcher:SetScript("OnEvent", function(self)
	if needAnimation and logoFrame then
		logoFrame:Show()
		self:UnregisterEvent("PLAYER_STARTED_MOVING")
		needAnimation = false
	end
end)

function Animation:PLAYER_ENTERING_WORLD(isInitialLogin)
	if not ns.db.animation.loginLogo then
		return
	end
	if not isInitialLogin then
		return
	end
	if IsInInstance() and InCombatLockdown() then
		return
	end

	needAnimation = true
	self:CreateLogo()
	moveWatcher:RegisterEvent("PLAYER_STARTED_MOVING")
end

-- ---------------------------------------------------------------------------
-- Combat banner
-- ---------------------------------------------------------------------------
local combatFrame

function Animation:SetupCombatText()
	if combatFrame then
		return
	end

	---@diagnostic disable-next-line: undefined-field
	local ENTERING_COMBAT, LEAVING_COMBAT = _G.ENTERING_COMBAT, _G.LEAVING_COMBAT

	local cfg = {
		slideInDist = 350,
		nudgeDist = -40,
		slideOutDist = 480,
		targetY = 150,
		minScale = 0.1,
		maxScale = 1.5,
		inDuration = 0.3,
		bounceDuration = 0.15,
		holdDuration = 0.8,
		nudgeDuration = 0.2,
		outDuration = 0.5,
	}

	local frame = CreateFrame("Frame", nil, UIParent)
	frame:SetSize(1, 1)
	frame:SetPoint("CENTER", -cfg.slideInDist, cfg.targetY)
	frame:Hide()

	local text = F.CreateFS(frame, 32, "")
	text:ClearAllPoints()
	text:SetPoint("CENTER")

	local anim = frame:CreateAnimationGroup()
	createTranslation(anim, 1, cfg.slideInDist, 0, cfg.inDuration, "IN")
	createAlpha(anim, 1, 0, 1, cfg.inDuration)
	createScale(anim, 1, cfg.minScale, cfg.minScale, cfg.maxScale, cfg.maxScale, cfg.inDuration, "IN")
	createScale(anim, 2, cfg.maxScale, cfg.maxScale, 1.0, 1.0, cfg.bounceDuration, "OUT")
	createTranslation(anim, 3, cfg.nudgeDist, 0, cfg.nudgeDuration, nil, cfg.holdDuration)
	local totalMoveOut = -cfg.nudgeDist + cfg.slideOutDist
	createTranslation(anim, 4, totalMoveOut, 0, cfg.outDuration)
	createAlpha(anim, 4, 1, 0, cfg.outDuration)
	createScale(anim, 4, 1.0, 1.0, cfg.minScale, cfg.minScale, cfg.outDuration)

	anim:SetScript("OnFinished", function()
		frame:Hide()
	end)

	combatFrame = frame

	local function updateCombatState(event)
		if not ns.db.animation.combatText then
			return
		end
		if event == "PLAYER_REGEN_DISABLED" then
			text:SetText(ENTERING_COMBAT)
			text:SetTextColor(1, 0.1, 0.1)
		else
			text:SetText(LEAVING_COMBAT)
			text:SetTextColor(0.1, 1, 0.1)
		end
		anim:Stop()
		frame:Show()
		anim:Play()
	end
	ns:RegisterEvent("PLAYER_REGEN_ENABLED", updateCombatState)
	ns:RegisterEvent("PLAYER_REGEN_DISABLED", updateCombatState)
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------
function Animation:OnEnable()
	self:RegisterEvent("PLAYER_ENTERING_WORLD")

	if ns.db.animation.combatText then
		self:SetupCombatText()
	end

	SlashCmdList["NEXLOGO"] = function()
		Animation:PlayLogo()
	end
	SLASH_NEXLOGO1 = "/nexlogo"
end

function Animation:OnSettingChanged()
	-- Enabling the combat banner can build live; disabling it needs a reload.
	if ns.db.animation.combatText then
		self:SetupCombatText()
	end
end

function Animation:RegisterOptions(category, builder)
	builder:Checkbox(category, self, "loginLogo", L["Login Logo"], L["Play a logo flyby the first time you move after logging in. Replay it with /nexlogo."])
	builder:Checkbox(category, self, "combatText", L["Combat Text"], L["Show an animated Entering/Leaving Combat banner (reload to disable)."])
end
