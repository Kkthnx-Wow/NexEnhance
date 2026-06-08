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
local F, L = ns.F, ns.L

local pairs, tinsert, next, select = pairs, table.insert, next, select
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
local C_Spell_GetSpellTexture = C_Spell.GetSpellTexture
local C_Item_GetItemCount = C_Item.GetItemCount
local C_Item_GetItemCooldown = C_Item.GetItemCooldown
local C_Item_IsEquippedItem = C_Item.IsEquippedItem
local C_Item_GetItemIconByID = C_Item.GetItemIconByID
local C_Timer = C_Timer

ns:RegisterDefaults({
	reminder = {
		enable = false,
		iconSize = 50,
	},
})

local Reminder = ns:NewModule("Reminder", "reminder", { group = "auras", title = L["Buff Reminder"], order = 10 })

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
			spells = { [1459] = true },
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
			depend = 319773,
			combat = true,
			instance = true,
			pvp = true,
			weaponIndex = 1,
			spec = 2,
		},
		{ -- Flametongue Weapon
			spells = { [319778] = true },
			depend = 319778,
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
			depend = 315584,
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
			depend = 3408,
			pvp = true,
		},
	},
	EVOKER = {
		{ -- Blessing of the Bronze
			spells = { [381748] = true },
			depend = 364342,
			instance = true,
		},
	},
	DRUID = {
		{ -- Mark of the Wild
			spells = { [1126] = true },
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
			if not groups then groups = {} end
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

-- Blizzard tooltip-style gold border, the same edge we frame the minimap with.
local REMINDER_BORDER = {
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	edgeSize = 14,
}

-- ---------------------------------------------------------------------------
-- Per-buff state evaluation (1:1 with NDui, guarded for secret aura values)
-- ---------------------------------------------------------------------------
local function Reminder_Update(cfg)
	local frame = cfg.frame
	local depend, spec = cfg.depend, cfg.spec
	local combat, instance, pvp = cfg.combat, cfg.instance, cfg.pvp
	local itemID, equip, inGroup = cfg.itemID, cfg.equip, cfg.inGroup
	local weaponIndex = cfg.weaponIndex

	local isPlayerSpell, isRightSpec, isEquipped, isGrouped = true, true, true, true
	local isInCombat, isInInst, isInPVP = false, false, false
	local inInst, instType = IsInInstance()

	if itemID then
		if inGroup and GetNumGroupMembers() < 2 then isGrouped = false end
		if equip and not C_Item_IsEquippedItem(itemID) then isEquipped = false end
		if C_Item_GetItemCount(itemID) == 0 or not isEquipped or not isGrouped or C_Item_GetItemCooldown(itemID) > 0 then
			frame:Hide()
			return
		end
	end

	if depend and not IsPlayerSpell(depend) then isPlayerSpell = false end
	if spec and spec ~= GetSpecialization() then isRightSpec = false end
	if combat and InCombatLockdown() then isInCombat = true end
	if instance and inInst and (instType == "scenario" or instType == "party" or instType == "raid") then isInInst = true end
	if pvp and (instType == "arena" or instType == "pvp" or GetZonePVPInfo() == "combat") then isInPVP = true end
	if not combat and not instance and not pvp then isInCombat, isInInst, isInPVP = true, true, true end

	frame:Hide()
	if isPlayerSpell and isRightSpec and (isInCombat or isInInst or isInPVP) and not UnitInVehicle("player") and not UnitIsDeadOrGhost("player") then
		if weaponIndex then
			local hasMainHandEnchant, _, _, _, hasOffHandEnchant = GetWeaponEnchantInfo()
			if (hasMainHandEnchant and weaponIndex == 1) or (hasOffHandEnchant and weaponIndex == 2) then
				frame:Hide()
				return
			end
		else
			for i = 1, 40 do
				local auraData = C_UnitAuras_GetBuffDataByIndex("player", i, "HELPFUL")
				if not auraData then break end
				local spellId = auraData.spellId
				if F.NotSecret(spellId) and spellId and cfg.spells[spellId] then
					frame:Hide()
					return
				end
			end
		end
		frame:Show()
	end
end

-- Shared icon builder used by both the live reminders and the test icons, so a
-- skin added here is reflected by `/nex reminder` test mode too.
local function Reminder_BuildFrame(texture)
	local frame = CreateFrame("Frame", nil, parentFrame)
	frame:SetSize(iconSize, iconSize)

	local icon = frame:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints()
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	icon:SetTexture(texture)
	frame.Icon = icon

	-- Blizzard tooltip-style gold border, wrapping the icon just like the minimap.
	local border = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	border:SetPoint("TOPLEFT", frame, "TOPLEFT", -3, 3)
	border:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 3, -3)
	border:SetFrameLevel(frame:GetFrameLevel() + 1)
	border:SetBackdrop(REMINDER_BORDER)
	frame.Border = border

	local text = F.CreateFS(frame, 13, L["Lack"])
	text:ClearAllPoints()
	text:SetPoint("TOP", frame, "TOP", 0, 16)
	text:SetTextColor(1, 0.1, 0.1)
	frame.text = text

	frame:Hide()
	return frame
end

local function Reminder_Create(cfg)
	local texture = cfg.texture
	if not texture then
		local spellID = next(cfg.spells)
		if spellID then texture = C_Spell_GetSpellTexture(spellID) end
	end

	local frame = Reminder_BuildFrame(texture)
	cfg.frame = frame
	tinsert(frames, frame)
end

local function Reminder_UpdateAnchor()
	local index = 0
	local offset = iconSize + 5
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
	if preview then return end
	if not ns.db.reminder.enable or not groups then return end

	for _, cfg in pairs(groups) do
		if not cfg.frame then Reminder_Create(cfg) end
		Reminder_Update(cfg)
	end
	Reminder_UpdateAnchor()
end

-- UNIT_AURA fires in bursts (e.g. a fresh set of raid buffs lands all at once);
-- coalesce them into a single end-of-frame rescan instead of doing a full
-- buff scan + visibility + reanchor pass per individual aura change.
local function Reminder_OnEvent()
	if updatePending then return end
	updatePending = true
	C_Timer.After(0, Reminder_RunUpdate)
end

-- ---------------------------------------------------------------------------
-- Sample icons (shown for /nex reminder and while Edit Mode is open)
-- ---------------------------------------------------------------------------
local function Reminder_BuildSamples()
	if #testFrames > 0 then return end
	-- Prefer the player's real reminder icons; fall back to placeholders for
	-- classes/specs with nothing configured.
	local textures = {}
	if groups then
		for _, cfg in pairs(groups) do
			local tex = cfg.texture
			if not tex then
				local spellID = next(cfg.spells)
				if spellID then tex = C_Spell_GetSpellTexture(spellID) end
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
	local offset = iconSize + 5
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
	if parentFrame then return end
	iconSize = (ns.db.reminder and ns.db.reminder.iconSize) or iconSize
	parentFrame = CreateFrame("Frame", nil, UIParent)
	parentFrame:SetSize(iconSize, iconSize)
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

function Reminder:Setup()
	if self.started then return end

	-- Fold in usable consumables once (bags are ready by OnEnable).
	if not self.itemsAdded then
		AddItemGroup()
		self.itemsAdded = true
	end

	if not groups then return end
	self.started = true

	self:CreateAnchor()

	self:RegisterUnitEvent("UNIT_AURA", Reminder_OnEvent, "player")
	self:RegisterEvent("UNIT_EXITED_VEHICLE", Reminder_OnEvent)
	self:RegisterEvent("UNIT_ENTERED_VEHICLE", Reminder_OnEvent)
	self:RegisterEvent("PLAYER_REGEN_ENABLED", Reminder_OnEvent)
	self:RegisterEvent("PLAYER_REGEN_DISABLED", Reminder_OnEvent)
	self:RegisterEvent("ZONE_CHANGED_NEW_AREA", Reminder_OnEvent)
	self:RegisterEvent("PLAYER_ENTERING_WORLD", Reminder_OnEvent)
	self:RegisterEvent("WEAPON_ENCHANT_CHANGED", Reminder_OnEvent)
end

function Reminder:Update()
	if ns.db.reminder.enable then
		self:Setup()
		if parentFrame then
			parentFrame:Show()
			Reminder_OnEvent()
		end
	elseif parentFrame then
		parentFrame:Hide()
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
		frame:SetSize(iconSize, iconSize)
	end
	for i = 1, #testFrames do
		testFrames[i]:SetSize(iconSize, iconSize)
	end

	if not parentFrame then return end
	if preview then
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
		if shouldShow then Reminder_LayoutSamples() end
		return
	end
	preview = shouldShow

	if shouldShow then
		-- Hide the live icons so they don't overlap the samples.
		for _, frame in next, frames do
			frame:Hide()
		end
		Reminder_BuildSamples()
		parentFrame:Show()
		for i = 1, #testFrames do
			testFrames[i]:Show()
		end
		Reminder_LayoutSamples()
	else
		for i = 1, #testFrames do
			testFrames[i]:Hide()
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
	if key == "iconSize" then
		self:ApplyIconSize()
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
	local _, sizeInit = builder:Slider(category, self, "iconSize", L["Icon Size"], L["Size of the buff reminder icons. Preview with /nex reminder."], 20, 64, 1)
	builder:DependsOn(sizeInit, enableInit)
end
