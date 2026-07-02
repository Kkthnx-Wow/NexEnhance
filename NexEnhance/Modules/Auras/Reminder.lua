--[[
	NexEnhance - Buff Reminder
	-------------------------------------------------------------------------
	Shows a small "Lack" icon for buffs you can provide but are currently
	missing (e.g. your own raid buff), so you never zone in unbuffed. The
	anchor is a real Edit Mode frame (via LibEditMode) - drag it in Edit Mode.

	Ported from NDui's Modules/Auras/Reminder.lua (by siweia), adapted to the
	NexEnhance framework. The per-class buff list below is intentionally small
	and stable (core raid buffs); extend `ReminderBuffs` to taste. Each entry:
	  spells      = { [spellID] = true, ... }  -- any of these present == OK
	  texture     = optional icon override
	  depend      = spellID that must be known
	  spec        = required specialization index
	  combat      = only while in combat
	  instance    = only inside scenario/party/raid
	  pvp         = only in arena/bg/world-pvp
	  inGroup     = only while grouped
	  itemID/equip/weaponIndex = item & weapon-enchant variants
--]]

local _, ns = ...
local C, F, L = ns.C, ns.F, ns.L

local pairs, tinsert, next, select, wipe = pairs, table.insert, next, select, wipe
local CreateFrame, UIParent = CreateFrame, UIParent
local C_SpecializationInfo = _G.C_SpecializationInfo
local GetSpecialization = (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization) or GetSpecialization
local UnitIsDeadOrGhost, UnitInVehicle, InCombatLockdown = UnitIsDeadOrGhost, UnitInVehicle, InCombatLockdown
local IsInInstance, IsPlayerSpell = IsInInstance, IsPlayerSpell
local GetWeaponEnchantInfo = GetWeaponEnchantInfo
local GetNumGroupMembers = GetNumGroupMembers
local UnitClass = UnitClass
local GetZonePVPInfo = C_PvP and C_PvP.GetZonePVPInfo
local C_UnitAuras_GetBuffDataByIndex = C_UnitAuras.GetBuffDataByIndex
local C_UnitAuras_GetPlayerAuraBySpellID = C_UnitAuras.GetPlayerAuraBySpellID
local C_Spell_GetSpellTexture = C_Spell.GetSpellTexture
local C_Item_GetItemCount = C_Item.GetItemCount
local C_Item_GetItemCooldown = C_Item.GetItemCooldown
local C_Item_IsEquippedItem = C_Item.IsEquippedItem
local C_Item_GetItemIconByID = C_Item.GetItemIconByID
local C_Spell_GetSpellCooldownDuration = C_Spell and C_Spell.GetSpellCooldownDuration
local C_DurationUtil_CreateDuration = C_DurationUtil and C_DurationUtil.CreateDuration
local C_Timer = C_Timer

ns:RegisterDefaults({
	reminder = {
		enable = false,
		iconSize = 50,
		glow = true,
	},
})

local Reminder = ns:NewModule("Reminder", "reminder", { group = "auras", title = L["Buff Reminder"], order = 10 })
local eventHandles = {}

-- Reminder buffs checklist (ported from NDui's DB.ReminderBuffs).
local ReminderBuffs = {
	ITEMS = {
		{
			itemID = 190384, -- 9.0 permanent stat rune
			spells = {
				[393438] = true, -- Draconic Augment Rune (itemID 201325)
				[367405] = true, -- permanent rune buff
			},
			instance = true,
			disable = true, -- disabled until a new rune exists
		},
		--[=[
		{
			itemID = 178742, -- Bottled Toxin trinket
			spells = {
				[345545] = true,
			},
			equip = true,
			instance = true,
			combat = true,
		},
		]=]
	},
	MAGE = {
		{ -- Arcane Intellect
			spells = { [1459] = true, [432778] = true }, -- 432778 = AI (alternate raid buff id)
			depend = 1459,
			instance = true,
		},
	},
	PRIEST = {
		{ -- Power Word: Fortitude
			spells = { [21562] = true },
			depend = 21562,
			instance = true,
		},
	},
	WARRIOR = {
		{ -- Battle Shout
			spells = { [6673] = true },
			depend = 6673,
			instance = true,
		},
	},
	SHAMAN = {
		{ -- Windfury Weapon
			spells = { [319773] = true },
			depend = 33757, -- Windfury Weapon (cast), not the enchant buff id
			combat = true,
			instance = true,
			pvp = true,
			weaponIndex = 1,
			spec = 2,
		},
		{ -- Flametongue Weapon
			spells = { [319778] = true },
			depend = 318038, -- Flametongue Weapon (cast)
			combat = true,
			instance = true,
			pvp = true,
			weaponIndex = 2,
			spec = 2,
		},
		{ -- Skyfury
			spells = { [462854] = true },
			depend = 462854,
			instance = true,
		},
	},
	ROGUE = {
		{ -- Lethal poisons
			spells = {
				[2823] = true, -- Deadly Poison
				[8679] = true, -- Wound Poison
				[315584] = true, -- Instant Poison
				[381664] = true, -- Amplifying Poison
			},
			texture = 132273,
			depends = { 2823, 8679, 315584, 381664 }, -- any known lethal poison
			combat = true,
			instance = true,
			pvp = true,
		},
		{ -- Non-lethal poisons
			spells = {
				[3408] = true, -- Crippling Poison
				[5761] = true, -- Numbing Poison
				[381637] = true, -- Atrophic Poison
			},
			depends = { 3408, 5761, 381637 },
			pvp = true,
		},
	},
	EVOKER = {
		{ -- Blessing of the Bronze (all class-variant buff ids)
			spells = {
				[381732] = true,
				[381741] = true,
				[381746] = true,
				[381748] = true,
				[381749] = true,
				[381750] = true,
				[381751] = true,
				[381752] = true,
				[381753] = true,
				[381754] = true,
				[381756] = true,
				[381757] = true,
				[381758] = true,
			},
			depend = 364342, -- Blessing of the Bronze (cast)
			instance = true,
		},
	},
	DRUID = {
		{ -- Mark of the Wild
			spells = { [1126] = true, [432661] = true }, -- 432661 = MOTW (alternate raid buff id)
			depend = 1126,
			instance = true,
		},
	},
}

local MyClass = select(2, UnitClass("player"))
local groups = ReminderBuffs[MyClass]

-- Pull any usable consumables (runes, trinkets) from the ITEMS list into the
-- active group, the same way NDui does. Runs once, after bags are available.
local function AddItemGroup()
	for _, value in pairs(ReminderBuffs.ITEMS) do
		if not value.disable and C_Item_GetItemCount(value.itemID) > 0 then
			if not value.texture then
				value.texture = C_Item_GetItemIconByID(value.itemID)
			end
			if not groups then
				groups = {}
			end
			tinsert(groups, value)
		end
	end
end

local iconSize = 50
local frames = {}
local parentFrame
local testFrames = {}
local manualTest -- /nex reminder toggle (persists outside Edit Mode)
local editPreview -- samples shown because Edit Mode is open
local preview -- samples currently shown (manualTest or editPreview); pauses the live rescan
local combatSnapshot = {} -- spell ids present on player at combat start (secret-safe fallback)

-- Tooltip-style border (same art as minimap); edge tinted red for missing buffs.
local REMINDER_BORDER = {
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	edgeSize = 14,
}
local REMINDER_BORDER_COLOR = { 1, 0.15, 0.1 }
local REMINDER_GLOW_COLOR = { 1, 0.15, 0.1 }
local REMINDER_BORDER_OUTSET = 3

local function Reminder_ItemOnCooldown(itemID)
	local start, dur = C_Item_GetItemCooldown(itemID)
	if F.IsSecret(start) or F.IsSecret(dur) then
		return true
	end
	return dur and dur > 0
end

local function Reminder_ApplyItemCooldown(frame, itemID)
	local cd = frame.Cooldown
	if not (cd and C_DurationUtil_CreateDuration) then
		return
	end
	local start, dur = C_Item_GetItemCooldown(itemID)
	if F.IsSecret(start) or F.IsSecret(dur) or not dur or dur <= 0 then
		cd:Clear()
		return
	end
	local durObj = C_DurationUtil_CreateDuration()
	durObj:SetTimeFromStart(start, dur)
	cd:SetCooldownFromDurationObject(durObj)
	F.MaskCooldownSwipeFromDurationObject(cd, durObj)
end

local function Reminder_ApplyDependCooldown(frame, spellID)
	local cd = frame.Cooldown
	if not (cd and spellID and C_Spell_GetSpellCooldownDuration) then
		return
	end
	local durObj = C_Spell_GetSpellCooldownDuration(spellID)
	if durObj then
		cd:SetCooldownFromDurationObject(durObj)
		F.MaskCooldownSwipeFromDurationObject(cd, durObj)
	else
		cd:Clear()
	end
end

local function Reminder_AnchorBorderRing(anchor, frame)
	anchor:ClearAllPoints()
	anchor:SetPoint("TOPLEFT", frame, "TOPLEFT", -REMINDER_BORDER_OUTSET, REMINDER_BORDER_OUTSET)
	anchor:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", REMINDER_BORDER_OUTSET, -REMINDER_BORDER_OUTSET)
end

local function Reminder_AttachPulseGlow(frame)
	local glowHost = CreateFrame("Frame", nil, frame)
	Reminder_AnchorBorderRing(glowHost, frame)
	glowHost:SetFrameLevel(frame:GetFrameLevel() + 1)
	F.CreateGlowBorder(glowHost, { outset = 3, blend = "BLEND", color = REMINDER_GLOW_COLOR })
	local anim = glowHost:CreateAnimationGroup()
	anim:SetLooping("REPEAT")
	local fadeIn = anim:CreateAnimation("Alpha")
	fadeIn:SetFromAlpha(0.2)
	fadeIn:SetToAlpha(0.9)
	fadeIn:SetDuration(0.36)
	fadeIn:SetOrder(1)
	fadeIn:SetSmoothing("OUT")
	local fadeOut = anim:CreateAnimation("Alpha")
	fadeOut:SetFromAlpha(0.9)
	fadeOut:SetToAlpha(0.2)
	fadeOut:SetDuration(0.36)
	fadeOut:SetOrder(2)
	fadeOut:SetSmoothing("IN")
	glowHost.Anim = anim
	glowHost:SetScript("OnShow", function(self)
		self.Anim:Play()
	end)
	glowHost:SetScript("OnHide", function(self)
		self.Anim:Stop()
	end)
	glowHost:Hide()
	frame.ReminderGlow = glowHost
end

local function Reminder_ApplyFrameArt(frame, size)
	size = size or iconSize
	frame:SetSize(size, size)
	if frame.Border then
		Reminder_AnchorBorderRing(frame.Border, frame)
	end
	if frame.ReminderGlow then
		Reminder_AnchorBorderRing(frame.ReminderGlow, frame)
	end
end

-- ---------------------------------------------------------------------------
-- Per-buff state evaluation (1:1 with NDui, guarded for secret aura values)
-- ---------------------------------------------------------------------------
local function Reminder_PlayerEligible(cfg)
	if cfg.depends then
		for i = 1, #cfg.depends do
			if IsPlayerSpell(cfg.depends[i]) then
				return true
			end
		end
		return false
	end
	if cfg.depend then
		return IsPlayerSpell(cfg.depend)
	end
	return true
end

local function PlayerHasConfiguredBuff(cfg)
	for spellId in pairs(cfg.spells) do
		if F.NotSecret(spellId) then
			if C_UnitAuras_GetPlayerAuraBySpellID(spellId) then
				return true
			end
			if combatSnapshot[spellId] then
				return true
			end
		end
	end
	for i = 1, 40 do
		local auraData = C_UnitAuras_GetBuffDataByIndex("player", i, "HELPFUL")
		if not auraData then
			break
		end
		local spellId = auraData.spellId
		if F.NotSecret(spellId) and spellId and cfg.spells[spellId] then
			return true
		end
	end
	return false
end

local function Reminder_WantsGlow()
	local db = ns.db and ns.db.reminder
	if not db or db.glow == nil then
		return true
	end
	return db.glow
end

local function Reminder_FrameStep()
	return iconSize + 5
end

local function Reminder_SetGlowVisible(frame, visible)
	local glow = frame.ReminderGlow
	if not glow then
		return
	end
	if visible and Reminder_WantsGlow() then
		glow:Show()
	else
		glow:Hide()
	end
end

local function Reminder_ShowFrame(frame)
	frame:Show()
	Reminder_SetGlowVisible(frame, true)
end

local function Reminder_HideFrame(frame)
	if frame.Cooldown then
		frame.Cooldown:Clear()
	end
	frame:Hide()
	Reminder_SetGlowVisible(frame, false)
end

local function SnapshotCombatBuffs()
	if not groups then
		return
	end
	wipe(combatSnapshot)
	for _, cfg in pairs(groups) do
		if cfg.spells and not cfg.weaponIndex then
			for spellId in pairs(cfg.spells) do
				if F.NotSecret(spellId) and C_UnitAuras_GetPlayerAuraBySpellID(spellId) then
					combatSnapshot[spellId] = true
				end
			end
		end
	end
end

local function Reminder_Update(cfg)
	local frame = cfg.frame
	local spec = cfg.spec
	local combat, instance, pvp = cfg.combat, cfg.instance, cfg.pvp
	local itemID, equip, inGroup = cfg.itemID, cfg.equip, cfg.inGroup
	local weaponIndex = cfg.weaponIndex

	local isEligible, isRightSpec, isEquipped, isGrouped = true, true, true, true
	local isInCombat, isInInst, isInPVP = false, false, false
	local inInst, instType = IsInInstance()

	if itemID then
		if inGroup and GetNumGroupMembers() < 2 then
			isGrouped = false
		end
		if equip and not C_Item_IsEquippedItem(itemID) then
			isEquipped = false
		end
		if C_Item_GetItemCount(itemID) == 0 or not isEquipped or not isGrouped or Reminder_ItemOnCooldown(itemID) then
			if frame.Cooldown then
				frame.Cooldown:Clear()
			end
			Reminder_HideFrame(frame)
			return
		end
		Reminder_ApplyItemCooldown(frame, itemID)
	end

	if not Reminder_PlayerEligible(cfg) then
		isEligible = false
	end
	if spec and spec ~= GetSpecialization() then
		isRightSpec = false
	end
	if combat and InCombatLockdown() then
		isInCombat = true
	end
	if instance and inInst and (instType == "scenario" or instType == "party" or instType == "raid") then
		isInInst = true
	end
	if pvp and (instType == "arena" or instType == "pvp" or GetZonePVPInfo() == "combat") then
		isInPVP = true
	end
	if not combat and not instance and not pvp then
		isInCombat, isInInst, isInPVP = true, true, true
	end

	Reminder_HideFrame(frame)
	if isEligible and isRightSpec and (isInCombat or isInInst or isInPVP) and not UnitInVehicle("player") and not UnitIsDeadOrGhost("player") then
		if weaponIndex then
			local hasMainHandEnchant, _, _, _, hasOffHandEnchant = GetWeaponEnchantInfo()
			local enchant = (weaponIndex == 1) and hasMainHandEnchant or hasOffHandEnchant
			local hasEnchant = F.BooleanIsTrue(enchant)
			if hasEnchant == true then
				return
			end
			if hasEnchant == nil then
				-- Secret: cannot tell if the enchant is present — avoid a false "Lack".
				Reminder_HideFrame(frame)
				return
			end
		elseif PlayerHasConfiguredBuff(cfg) then
			if frame.Cooldown then
				frame.Cooldown:Clear()
			end
			return
		end
		if cfg.depend and frame.Cooldown then
			Reminder_ApplyDependCooldown(frame, cfg.depend)
		elseif frame.Cooldown then
			frame.Cooldown:Clear()
		end
		Reminder_ShowFrame(frame)
	end
end

-- Shared icon builder used by both the live reminders and the test icons, so a
-- skin added here is reflected by `/nex reminder` test mode too.
local function Reminder_BuildFrame(texture)
	local frame = CreateFrame("Frame", nil, parentFrame)
	frame:SetSize(iconSize, iconSize)
	frame:SetClipsChildren(false)

	Reminder_AttachPulseGlow(frame)

	local icon = frame:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints(frame)
	icon:SetTexCoord(C.TexCoord[1], C.TexCoord[2], C.TexCoord[3], C.TexCoord[4])
	icon:SetTexture(texture)
	frame.Icon = icon

	local cd = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
	cd:SetAllPoints(icon)
	cd:SetDrawEdge(false)
	cd:SetHideCountdownNumbers(true)
	cd.noCooldownCount = true
	frame.Cooldown = cd

	local border = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	Reminder_AnchorBorderRing(border, frame)
	border:SetFrameLevel(frame:GetFrameLevel() + 2)
	border:SetBackdrop(REMINDER_BORDER)
	border:SetBackdropBorderColor(REMINDER_BORDER_COLOR[1], REMINDER_BORDER_COLOR[2], REMINDER_BORDER_COLOR[3])
	frame.Border = border

	local text = F.CreatePlainFS(frame, 13, L["Lack"])
	text:ClearAllPoints()
	text:SetPoint("TOP", frame, "TOP", 0, 18)
	text:SetTextColor(1, 0.1, 0.1)
	frame.text = text

	Reminder_HideFrame(frame)
	return frame
end

local function Reminder_Create(cfg)
	local texture = cfg.texture
	if not texture then
		local spellID = next(cfg.spells)
		if spellID then
			texture = C_Spell_GetSpellTexture(spellID)
		end
	end

	local frame = Reminder_BuildFrame(texture)
	cfg.frame = frame
	tinsert(frames, frame)
end

local function Reminder_UpdateAnchor()
	local index = 0
	local offset = Reminder_FrameStep()
	for _, frame in next, frames do
		if frame:IsShown() then
			frame:ClearAllPoints()
			frame:SetPoint("LEFT", parentFrame, "LEFT", offset * index, 0)
			index = index + 1
		end
	end
	parentFrame:SetWidth(offset * (index > 0 and index or 1))
end

local updatePending
local function Reminder_RunUpdate()
	updatePending = nil
	if preview then
		return
	end
	if not ns.db.reminder.enable or not groups then
		return
	end

	for _, cfg in pairs(groups) do
		if not cfg.frame then
			Reminder_Create(cfg)
		end
		Reminder_Update(cfg)
	end
	Reminder_UpdateAnchor()
end

-- UNIT_AURA fires in bursts (e.g. a fresh set of raid buffs lands all at once);
-- coalesce them into a single end-of-frame rescan instead of doing a full
-- buff scan + visibility + reanchor pass per individual aura change.
local function Reminder_OnEvent()
	if updatePending then
		return
	end
	updatePending = true
	C_Timer.After(0, Reminder_RunUpdate)
end

-- ---------------------------------------------------------------------------
-- Sample icons (shown for /nex reminder and while Edit Mode is open)
-- ---------------------------------------------------------------------------
local function Reminder_BuildSamples()
	-- Rebuild each time preview opens so /nex reminder always reflects current skin.
	if #testFrames > 0 then
		for i = 1, #testFrames do
			testFrames[i]:Hide()
			testFrames[i]:SetParent(nil)
		end
		wipe(testFrames)
	end
	-- Prefer the player's real reminder icons; fall back to placeholders for
	-- classes/specs with nothing configured.
	local textures = {}
	if groups then
		for _, cfg in pairs(groups) do
			local tex = cfg.texture
			if not tex then
				local spellID = next(cfg.spells)
				if spellID then
					tex = C_Spell_GetSpellTexture(spellID)
				end
			end
			textures[#textures + 1] = tex
		end
	end
	if #textures == 0 then
		textures = { 135932, 135987, 132333 }
	end
	for i = 1, #textures do
		testFrames[i] = Reminder_BuildFrame(textures[i])
	end
end

local function Reminder_LayoutSamples()
	local offset = Reminder_FrameStep()
	for i = 1, #testFrames do
		local frame = testFrames[i]
		frame:ClearAllPoints()
		frame:SetPoint("LEFT", parentFrame, "LEFT", offset * (i - 1), 0)
	end
	parentFrame:SetWidth(offset * (#testFrames > 0 and #testFrames or 1))
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------
-- Create the draggable Edit Mode anchor once. Kept separate from Setup so it
-- always exists (even for classes without reminder buffs, or while disabled),
-- which is what lets the mover show up in Edit Mode without test mode.
function Reminder:CreateAnchor()
	if parentFrame then
		return
	end
	iconSize = (ns.db.reminder and ns.db.reminder.iconSize) or iconSize
	parentFrame = CreateFrame("Frame", nil, UIParent)
	parentFrame:SetSize(iconSize, iconSize)
	parentFrame:SetClipsChildren(false)
	F.CreateMover(parentFrame, "reminder", L["Buff Reminder"], "CENTER", -220, 130)

	-- Mirror the icon-size slider onto the frame's Edit Mode dialog.
	local lib = _G.LibStub and _G.LibStub("LibEditMode", true)
	if lib and lib.AddFrameSettings and lib.SettingType then
		lib:AddFrameSettings(parentFrame, {
			{
				kind = lib.SettingType.Slider,
				name = L["Icon Size"],
				desc = L["Size of the buff reminder icons. Preview with /nex reminder."],
				default = 50,
				minValue = 20,
				maxValue = 64,
				valueStep = 1,
				get = function()
					return ns.db.reminder.iconSize
				end,
				set = function(_, value)
					ns.db.reminder.iconSize = value
					Reminder:ApplyIconSize()
				end,
			},
		})
	end
end

function Reminder:RegisterModuleEvents()
	if self.eventsRegistered then
		return
	end
	self.eventsRegistered = true

	self:TrackUnitEvent(eventHandles, "UNIT_AURA", Reminder_OnEvent, "player")
	self:TrackEvent(eventHandles, "UNIT_EXITED_VEHICLE", Reminder_OnEvent)
	self:TrackEvent(eventHandles, "UNIT_ENTERED_VEHICLE", Reminder_OnEvent)
	self:TrackEvent(eventHandles, "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_ENABLED")
	self:TrackEvent(eventHandles, "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_DISABLED")
	self:TrackEvent(eventHandles, "ZONE_CHANGED_NEW_AREA", Reminder_OnEvent)
	self:TrackEvent(eventHandles, "PLAYER_ENTERING_WORLD", Reminder_OnEvent)
	self:TrackEvent(eventHandles, "WEAPON_ENCHANT_CHANGED", Reminder_OnEvent)
	self:TrackEvent(eventHandles, "SPELL_UPDATE_COOLDOWN", Reminder_OnEvent)
end

function Reminder:UnregisterModuleEvents()
	if not self.eventsRegistered then
		return
	end
	self.eventsRegistered = false
	ns:UnregisterModuleEventHandles(eventHandles)
end

function Reminder:PLAYER_REGEN_ENABLED()
	wipe(combatSnapshot)
	Reminder_OnEvent()
end

function Reminder:PLAYER_REGEN_DISABLED()
	SnapshotCombatBuffs()
	Reminder_OnEvent()
end

function Reminder:Setup()
	if self.started then
		return
	end

	-- Fold in usable consumables once (bags are ready by OnEnable).
	if not self.itemsAdded then
		AddItemGroup()
		self.itemsAdded = true
	end

	if not groups then
		return
	end
	self.started = true

	self:CreateAnchor()
	self:RegisterModuleEvents()
end

function Reminder:OnDisable()
	self:UnregisterModuleEvents()
	self.started = false
	if parentFrame then
		parentFrame:Hide()
	end
	for _, frame in next, frames do
		Reminder_HideFrame(frame)
	end
end

function Reminder:Update()
	if ns.db.reminder.enable then
		self:Setup()
		if parentFrame then
			parentFrame:Show()
			Reminder_OnEvent()
		end
	else
		self:OnDisable()
	end
end

-- Resize the anchor and every icon (live + sample) to the configured size, then
-- re-lay-out whichever set is currently shown.
function Reminder:ApplyIconSize()
	iconSize = (ns.db.reminder and ns.db.reminder.iconSize) or iconSize
	if parentFrame then
		parentFrame:SetSize(iconSize, iconSize)
	end
	for _, frame in next, frames do
		Reminder_ApplyFrameArt(frame, iconSize)
	end
	for i = 1, #testFrames do
		Reminder_ApplyFrameArt(testFrames[i], iconSize)
	end

	if not parentFrame then
		return
	end
	if preview then
		Reminder_LayoutSamples()
	else
		Reminder_UpdateAnchor()
	end
end

function Reminder:ApplyGlow()
	for _, frame in next, frames do
		Reminder_SetGlowVisible(frame, frame:IsShown())
	end
	if preview then
		for i = 1, #testFrames do
			Reminder_SetGlowVisible(testFrames[i], testFrames[i]:IsShown())
		end
		Reminder_LayoutSamples()
	else
		Reminder_UpdateAnchor()
	end
end

-- Show/hide the sample icons based on whether the test toggle or Edit Mode wants
-- them, restoring the live state when neither does.
function Reminder:RefreshPreview()
	self:CreateAnchor()

	local shouldShow = manualTest or editPreview
	if shouldShow == preview then
		if shouldShow then
			Reminder_LayoutSamples()
			self:ApplyGlow()
		end
		return
	end
	preview = shouldShow

	if shouldShow then
		-- Hide the live icons so they don't overlap the samples.
		for _, frame in next, frames do
			Reminder_HideFrame(frame)
		end
		Reminder_BuildSamples()
		parentFrame:Show()
		for i = 1, #testFrames do
			Reminder_ShowFrame(testFrames[i])
		end
		Reminder_LayoutSamples()
	else
		for i = 1, #testFrames do
			Reminder_HideFrame(testFrames[i])
		end
		if ns.db.reminder.enable and groups then
			Reminder_RunUpdate()
		else
			Reminder_UpdateAnchor()
			parentFrame:Hide()
		end
	end
end

function Reminder:OnEnable()
	iconSize = (ns.db.reminder and ns.db.reminder.iconSize) or iconSize

	-- Always build the anchor so the mover is available in Edit Mode, and show
	-- sample icons on it whenever Edit Mode is open (no test mode required).
	self:CreateAnchor()
	if not self.editModeHooked then
		local lib = _G.LibStub and _G.LibStub("LibEditMode", true)
		if lib and lib.RegisterCallback then
			self.editModeHooked = true
			lib:RegisterCallback("enter", function()
				editPreview = true
				self:RefreshPreview()
			end)
			lib:RegisterCallback("exit", function()
				editPreview = false
				self:RefreshPreview()
			end)
		end
	end

	self:Update()
end

function Reminder:OnSettingChanged(key)
	if key == "enable" and not ns.db.reminder.enable then
		self:OnDisable()
		return
	end
	if key == "iconSize" then
		self:ApplyIconSize()
		return
	end
	if key == "glow" then
		self:ApplyGlow()
		return
	end
	self:Update()
end

-- /nex reminder: force-show sample "Lack" icons on the anchor so the layout can
-- be positioned and skinned without waiting to actually be missing a buff.
function Reminder:ToggleTest()
	manualTest = not manualTest
	self:RefreshPreview()
	if manualTest then
		F.Print(F.Colorize(L["Buff Reminder"] .. ": ", "brand") .. L["Test mode on - drag the anchor in Edit Mode."])
	else
		F.Print(F.Colorize(L["Buff Reminder"] .. ": ", "brand") .. L["Test mode off."])
	end
end

function Reminder:RegisterOptions(category, builder)
	local _, enableInit = builder:Checkbox(category, self, "enable", L["Enable Buff Reminder"], L["Show a 'Lack' icon when you are missing a buff you can provide. Move the anchor in Edit Mode."])
	local _, glowInit = builder:Checkbox(category, self, "glow", L["Reminder Glow"], L["Draw a soft red halo around missing-buff icons (retail tutorial glow). Preview with /nex reminder."])
	local _, sizeInit = builder:Slider(category, self, "iconSize", L["Icon Size"], L["Size of the buff reminder icons. Preview with /nex reminder."], 20, 64, 1)
	builder:DependsOn(glowInit, enableInit)
	builder:DependsOn(sizeInit, enableInit)
end
