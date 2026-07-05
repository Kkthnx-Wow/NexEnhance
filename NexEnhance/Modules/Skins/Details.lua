--[[
	NexEnhance - Details (skin)
	-------------------------------------------------------------------------
	Skins each Details! Damage Meter window: switches it to the Minimalistic
	skin, drops the wallpaper/own backdrop, desaturates the menu, tidies the
	toolbar, then frames the window with a Blizzard tooltip-style border and a
	dark background.

	Details! is optional third-party. Style on enable if loaded, else wait for
	ADDON_LOADED. New windows caught via DETAILS_INSTANCE_OPEN (no OnUpdate).
	SetBarSettings / SetBarTextSettings skipped — Details bar texture/font want
	SharedMedia *names* and we don't register a statusbar/font for it.
--]]

---@diagnostic disable: undefined-field
local _, ns = ...
local L = ns.L

local _G = _G
local max = math.max
local CreateFrame = CreateFrame
local C_AddOns = C_AddOns

ns:RegisterDefaults({
	detailsSkin = {
		enable = true,
	},
})

local DetailsSkin = ns:NewModule("DetailsSkin", "detailsSkin", { group = "skins", title = L["Details"], order = 40 })

-- A classic Blizzard tooltip border + dark background fill.
local DETAILS_BACKDROP = {
	bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true,
	tileSize = 16,
	edgeSize = 14,
	insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

-- Every border we create, so we can show/hide them on a live toggle.
local borders = {}

local function SetBordersShown(shown)
	for i = 1, #borders do
		borders[i]:SetShown(shown)
	end
end

-- Add a border + dark background behind a Details window's base frame (once per
-- frame). Parented to the window's parent at a lower level so the fill sits
-- behind the bars rather than covering them.
local function ApplyBorder(frame)
	if not frame or frame.__nexDetailsBorder then
		return
	end

	local bg = CreateFrame("Frame", nil, frame:GetParent() or frame, "BackdropTemplate")
	bg:SetFrameStrata(frame:GetFrameStrata())
	bg:SetFrameLevel(max(frame:GetFrameLevel() - 1, 0))
	-- Extend up 18 (to cover the Details toolbar/title) and out 1px each side.
	bg:SetPoint("TOPLEFT", frame, "TOPLEFT", -4, 22)
	bg:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 4, -4)
	bg:SetBackdrop(DETAILS_BACKDROP)
	bg:SetBackdropColor(0.06, 0.06, 0.06, 0.9)

	frame.__nexDetailsBorder = bg
	borders[#borders + 1] = bg
end

-- Skin a single Details instance: configure the meter window (Minimalistic skin,
-- no wallpaper/own backdrop, desaturated menu, tidy toolbar) then frame it.
-- Every Details call is guarded so we stay safe across Details versions.
local function SetupInstance(instance)
	if not instance or instance.__nexStyled then
		return
	end

	if instance.ChangeSkin then
		instance:ChangeSkin("Minimalistic")
	end
	if instance.InstanceWallpaper then
		instance:InstanceWallpaper(false)
	end
	if instance.DesaturateMenu then
		instance:DesaturateMenu(true)
	end
	if instance.HideMainIcon then
		instance:HideMainIcon(false)
	end
	-- Drops Details' own backdrop; upstream notes this can block resizing - set
	-- back to "Details Ground" if that ever becomes an issue.
	if instance.SetBackdropTexture then
		instance:SetBackdropTexture("None")
	end
	if instance.MenuAnchor then
		instance:MenuAnchor(16, 3)
	end
	if instance.ToolbarMenuButtonsSize then
		instance:ToolbarMenuButtonsSize(1)
	end

	ApplyBorder(instance.baseframe)

	instance.__nexStyled = true
end

-- Hook Details' instance-open event so freshly shown windows get skinned too.
local function HookInstanceOpen()
	if DetailsSkin.listenerHooked then
		return
	end
	local Details = _G.Details
	if not (Details and Details.CreateEventListener) then
		return
	end
	DetailsSkin.listenerHooked = true

	local listener = Details:CreateEventListener()
	listener:RegisterEvent("DETAILS_INSTANCE_OPEN")
	function listener:OnDetailsEvent(event, instance)
		if event == "DETAILS_INSTANCE_OPEN" and instance then
			SetupInstance(instance)
			if ns.db.detailsSkin.enable == false then
				SetBordersShown(false)
			end
		end
	end
end

function DetailsSkin:Style()
	if self.styled then
		return
	end
	local Details = _G.Details
	if not (Details and Details.GetInstance) then
		return
	end
	self.styled = true

	local index = 1
	local instance = Details:GetInstance(index)
	while instance do
		SetupInstance(instance)
		index = index + 1
		instance = Details:GetInstance(index)
	end

	HookInstanceOpen()
end

function DetailsSkin:ADDON_LOADED(addon)
	if addon == "Details" then
		self:Style()
	end
end

function DetailsSkin:OnEnable()
	if not ns.db.detailsSkin.enable then
		return
	end
	if C_AddOns.IsAddOnLoaded("Details") then
		self:Style()
	else
		self:RegisterEvent("ADDON_LOADED")
	end
end

-- Live toggle: build (first enable) and show, or hide the borders.
function DetailsSkin:OnSettingChanged(key)
	if key ~= "enable" then
		return
	end
	if ns.db.detailsSkin.enable then
		if C_AddOns.IsAddOnLoaded("Details") then
			self:Style()
		else
			self:RegisterEvent("ADDON_LOADED")
		end
		SetBordersShown(true)
	else
		SetBordersShown(false)
	end
end

function DetailsSkin:RegisterOptions(category, builder)
	builder:Checkbox(category, self, "enable", L["Enable Details Border"], L["Skin Details! Damage Meter windows with the Minimalistic skin plus a Blizzard-style border and background (reload to fully revert)."])
end
