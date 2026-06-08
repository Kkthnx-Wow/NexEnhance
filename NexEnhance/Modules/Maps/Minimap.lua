--[[
	NexEnhance - Minimap
	-------------------------------------------------------------------------
	A fuller minimap pass adapted from KkthnxUI by Josh "Kkthnx" Russell:
	  https://github.com/Kkthnx-Wow/KkthnxUI_Firestorm/blob/main/KkthnxUI/Modules/Maps/Minimap.lua

	What we do (all gated behind the module toggle):
	  - Square the minimap and frame it with a Blizzard tooltip-style gold border.
	  - Kill the cluster chrome outright (ring, zoom buttons, compass, clock,
	    zone-text bar) since we replace it; the tracking button stays alive but
	    invisible so right-click still opens its menu.
	  - Re-home the landing-page button, indicator (mail), instance difficulty,
	    calendar, streaming and queue-status regions to tidy minimap corners.
	  - Spin a dungeon icon over the LFG/queue eye with a time-in-queue readout,
	    draw the calendar day number, and pulse a coloured glow for combat /
	    pending mail / calendar invites.
	  - Easy Volume (Ctrl + wheel) and a middle-click shortcut menu (unchanged).

	We do NOT add our own mover: Blizzard's Edit Mode already moves the minimap
	cluster, so we leave positioning to it and never detach the minimap.

	Retail only.
--]]

---@diagnostic disable: undefined-field, undefined-global, inject-field, param-type-mismatch, redundant-parameter
-- luacheck: globals Minimap
local _, ns = ...
local C, L, F = ns.C, ns.L, ns.F

-- Shared tooltip palette (single source of truth in Constants.lua): gold section
-- headers, light-blue labels/hints, white values.
local HDR = C.Colors.header
local LBL = C.Colors.label

local _G = _G
local ipairs = ipairs
local floor, min, max = math.floor, math.min, math.max
local sort, tinsert = table.sort, table.insert
local tonumber, tostring = tonumber, tostring

local CreateFrame = CreateFrame
local GetFrameMetatable = GetFrameMetatable
local IsAltKeyDown = IsAltKeyDown
local IsControlKeyDown = IsControlKeyDown
local InCombatLockdown = InCombatLockdown
local Minimap = Minimap
local MinimapCluster = MinimapCluster
local C_CVar = C_CVar
local hooksecurefunc = hooksecurefunc
local GetTime = GetTime
local UnitClass = UnitClass
local RAID_CLASS_COLORS = RAID_CLASS_COLORS

local DEFAULTS = {
	enable = true,
	easyVolume = true,
	microMenu = true,
	border = true,
	mailPulse = true,
	collectButtons = true,
	buttonBinPosition = 3, -- 1 BL, 2 BR, 3 TL, 4 TR
}

ns:RegisterDefaults({ minimap = DEFAULTS })

local Module = ns:NewModule("Minimap", "minimap", { group = "maps", title = L["Minimap"], order = 40 })

-- ---------------------------------------------------------------------------
-- Easy Volume (Ctrl + MouseWheel)
-- ---------------------------------------------------------------------------
local volumeText, volumeAnim
local minimapClicker

-- Smooth green -> yellow -> red gradient across 0..100%.
local function VolumeColor(value)
	value = value / 100
	if value > 0.5 then
		return (1 - value) * 2, 1, 0
	end
	return 1, value * 2, 0
end

local function GetVolume()
	return floor((tonumber(C_CVar.GetCVar("Sound_MasterVolume")) or 1) * 100 + 0.5)
end

local function CreateVolumeDisplay()
	if volumeText then
		return
	end

	local frame = CreateFrame("Frame", nil, Minimap)
	frame:SetAllPoints()
	frame:SetAlpha(0)

	volumeText = F.CreateFS(frame, 30)
	volumeText:SetPoint("CENTER", frame, "CENTER", 0, 0)

	volumeAnim = frame:CreateAnimationGroup()
	volumeAnim:SetScript("OnPlay", function()
		frame:SetAlpha(1)
	end)
	volumeAnim:SetScript("OnFinished", function()
		frame:SetAlpha(0)
	end)

	local fader = volumeAnim:CreateAnimation("Alpha")
	fader:SetFromAlpha(1)
	fader:SetToAlpha(0)
	fader:SetDuration(3)
	fader:SetSmoothing("OUT")
	fader:SetStartDelay(1)
end

-- Replicate Blizzard's default wheel zoom so non-Ctrl scrolling still works
-- after we take over the script.
local function ZoomMinimap(delta)
	local zoom = Minimap:GetZoom()
	local levels = Minimap:GetZoomLevels()
	if delta > 0 then
		if zoom < levels - 1 then
			Minimap:SetZoom(zoom + 1)
		end
	elseif zoom > 0 then
		Minimap:SetZoom(zoom - 1)
	end
end

local function OnMouseWheel(_, delta)
	if IsControlKeyDown() and volumeText then
		local step = IsAltKeyDown() and 100 or 2
		local value = min(100, max(0, GetVolume() + delta * step))

		C_CVar.SetCVar("Sound_MasterVolume", tostring(value / 100))
		volumeText:SetText(value .. "%")
		volumeText:SetTextColor(VolumeColor(value))
		volumeAnim:Stop()
		volumeAnim:Play()
	else
		ZoomMinimap(delta)
	end
end

-- ---------------------------------------------------------------------------
-- Micro Menu (Middle-click)
-- ---------------------------------------------------------------------------
local menuList

local function BuildMenuList()
	if menuList then
		return
	end

	menuList = {
		{
			text = _G.CHARACTER_BUTTON,
			icon = 236415,
			func = function()
				_G.ToggleCharacter("PaperDollFrame")
			end,
		},
		{
			text = _G.SPELLBOOK,
			icon = 133741,
			func = function()
				if _G.PlayerSpellsUtil then
					_G.PlayerSpellsUtil.ToggleSpellBookFrame()
				else
					_G.ToggleFrame(_G.SpellBookFrame)
				end
			end,
		},
		{
			text = _G.TALENTS_BUTTON,
			icon = 3717418,
			func = function()
				if _G.PlayerSpellsUtil then
					_G.PlayerSpellsUtil.ToggleClassTalentFrame()
				else
					_G.ToggleTalentFrame()
				end
			end,
		},
		{
			text = _G.ACHIEVEMENT_BUTTON,
			icon = 1033987,
			func = function()
				_G.ToggleAchievementFrame()
			end,
		},
		{
			text = _G.QUESTLOG_BUTTON,
			icon = 236669,
			func = function()
				_G.ToggleQuestLog()
			end,
		},
		{
			text = _G.GUILD,
			icon = 135026,
			func = function()
				_G.ToggleGuildFrame()
			end,
		},
		{
			text = _G.SOCIAL_BUTTON,
			icon = 442272,
			func = function()
				_G.ToggleFriendsFrame()
			end,
		},
		{
			text = _G.COLLECTIONS,
			icon = 5321228,
			func = function()
				_G.ToggleCollectionsJournal()
			end,
		},
		{
			text = _G.LFG_TITLE,
			icon = 134149,
			func = function()
				_G.ToggleLFDParentFrame()
			end,
		},
		{
			text = _G.ENCOUNTER_JOURNAL,
			icon = 236409,
			func = function()
				local loaded = _G.C_AddOns and _G.C_AddOns.IsAddOnLoaded("Blizzard_EncounterJournal")
				if not loaded then
					_G.UIParentLoadAddOn("Blizzard_EncounterJournal")
				end
				_G.ToggleFrame(_G.EncounterJournal)
			end,
		},
		{
			text = _G.PROFESSIONS_BUTTON,
			icon = 236574,
			func = function()
				_G.ToggleProfessionsBook()
			end,
		},
		{
			text = _G.CHAT_CHANNELS,
			icon = 2056011,
			func = function()
				_G.ToggleChannelFrame()
			end,
		},
		{
			text = _G.TIMEMANAGER_TITLE,
			icon = 237538,
			func = function()
				_G.ToggleFrame(_G.TimeManagerFrame)
			end,
		},
		{
			text = L["Calendar"],
			icon = 3007435,
			func = function()
				if _G.GameTimeFrame then
					_G.GameTimeFrame:Click()
				end
			end,
		},
		{
			text = _G.GARRISON_TYPE_8_0_LANDING_PAGE_TITLE,
			icon = 1044996,
			func = function()
				if _G.ExpansionLandingPageMinimapButton then
					_G.ExpansionLandingPageMinimapButton:ToggleLandingPage()
				end
			end,
		},
	}

	-- Strip entries whose Blizzard global text is missing on this client.
	for i = #menuList, 1, -1 do
		if not menuList[i].text then
			table.remove(menuList, i)
		end
	end

	-- Alphabetical for quick scanning.
	sort(menuList, function(a, b)
		return a.text < b.text
	end)

	-- Pinned to the bottom, after the sort.
	tinsert(menuList, {
		text = _G.MAINMENU_BUTTON,
		icon = 134400,
		func = function()
			if not _G.GameMenuFrame:IsShown() then
				_G.CloseMenus()
				_G.CloseAllWindows()
				_G.PlaySound(_G.SOUNDKIT.IG_MAINMENU_OPEN)
				_G.ShowUIPanel(_G.GameMenuFrame)
			else
				_G.PlaySound(_G.SOUNDKIT.IG_MAINMENU_QUIT)
				_G.HideUIPanel(_G.GameMenuFrame)
			end
		end,
	})
	tinsert(menuList, {
		text = _G.HELP_BUTTON,
		icon = 511544,
		func = function()
			_G.ToggleHelpFrame()
		end,
	})

	-- Pre-bake the icon markup so the menu generator stays cheap.
	for _, entry in ipairs(menuList) do
		entry.display = entry.icon and ("|T" .. entry.icon .. ":14:14:0:0|t  " .. entry.text) or entry.text
	end
end

local function ShowMicroMenu()
	if not (_G.MenuUtil and _G.MenuUtil.CreateContextMenu) then
		return
	end

	_G.MenuUtil.CreateContextMenu(Minimap, function(_, root)
		root:CreateTitle(_G.MINIMAP_LABEL or L["Minimap"])
		for _, entry in ipairs(menuList) do
			root:CreateButton(entry.display, entry.func)
		end
	end)
end

-- Open Blizzard's tracking menu (the button itself is hidden) on right-click.
local function ShowTrackingMenu()
	local tracking = MinimapCluster and MinimapCluster.Tracking
	local button = tracking and tracking.Button
	if button and button.OpenMenu then
		button:OpenMenu()
	end
end

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
-- Fully remove a Blizzard element: F.Kill unregisters its events and reparents
-- it to NexEnhance's permanent hider frame, so it can never come back (this is
-- KkthnxUI's HideInterfaceOption pattern). Guarded so a missing frame is a no-op.
local function Kill(frame)
	if frame then
		F.Kill(frame)
	end
end

-- Re-anchor a Blizzard region to one of our points and keep it there even when
-- Blizzard's layout code tries to move it back (guarded against recursion).
local function Pin(frame, point, relPoint, x, y)
	if not frame then
		return
	end
	local locked
	local function apply()
		if locked then
			return
		end
		locked = true
		frame:ClearAllPoints()
		frame:SetPoint(point, Minimap, relPoint, x, y)
		locked = false
	end
	apply()
	hooksecurefunc(frame, "SetPoint", apply)
end

-- ---------------------------------------------------------------------------
-- Border: the classic Blizzard tooltip-style gold edge we use on chat bubbles,
-- drawn on top of the square minimap so it frames the edges cleanly.
-- ---------------------------------------------------------------------------
local MINIMAP_BACKDROP = {
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	edgeSize = 14,
}
local borderFrame

local function CreateBorder()
	if borderFrame or not ns.db.minimap.border then
		return
	end

	borderFrame = CreateFrame("Frame", nil, Minimap, "BackdropTemplate")
	-- Sit the gold edge just outside the map so it wraps the square.
	borderFrame:SetPoint("TOPLEFT", Minimap, "TOPLEFT", -3, 3)
	borderFrame:SetPoint("BOTTOMRIGHT", Minimap, "BOTTOMRIGHT", 3, -3)
	borderFrame:SetFrameLevel(Minimap:GetFrameLevel() + 3)
	borderFrame:SetBackdrop(MINIMAP_BACKDROP)
end

-- ---------------------------------------------------------------------------
-- Status pulse (combat / pending mail / calendar invites)
--   Rather than draw a second frame, we tint and fade our gold border so the
--   whole frame pulses red (combat) or yellow (mail / calendar invites).
-- ---------------------------------------------------------------------------
local pulseAnim

local function CreatePulse()
	-- Needs the border to colour; bail if either the border or pulse is off.
	if pulseAnim or not ns.db.minimap.mailPulse or not borderFrame then
		return
	end

	pulseAnim = borderFrame:CreateAnimationGroup()
	pulseAnim:SetLooping("BOUNCE")
	local fader = pulseAnim:CreateAnimation("Alpha")
	fader:SetFromAlpha(1)
	fader:SetToAlpha(0.3)
	fader:SetDuration(1)
	fader:SetSmoothing("OUT")
end

local function UpdatePulse()
	if not (borderFrame and pulseAnim) then
		return
	end

	local r, g, b
	local invites = _G.C_Calendar and _G.C_Calendar.GetNumPendingInvites and _G.C_Calendar.GetNumPendingInvites() or 0
	local indicator = MinimapCluster and MinimapCluster.IndicatorFrame
	local mail = indicator and indicator.MailFrame
	if invites > 0 or (mail and mail:IsShown()) then
		r, g, b = 1, 1, 0
	end

	if r then
		borderFrame:SetBackdropBorderColor(r, g, b)
		if not pulseAnim:IsPlaying() then
			pulseAnim:Play()
		end
	else
		if pulseAnim:IsPlaying() then
			pulseAnim:Stop()
		end
		-- Restore the untinted gold border at full opacity.
		borderFrame:SetAlpha(1)
		borderFrame:SetBackdropBorderColor(1, 1, 1)
	end
end

-- ---------------------------------------------------------------------------
-- Declutter the Blizzard cluster
-- ---------------------------------------------------------------------------
local function Declutter()
	Minimap:SetArchBlobRingScalar(0)
	Minimap:SetQuestBlobRingScalar(0)

	-- Kill the default chrome outright since we replace it all.
	Kill(Minimap.ZoomIn)
	Kill(Minimap.ZoomOut)
	Kill(_G.MinimapCompassTexture)
	Kill(_G.TimeManagerClockButton)
	Kill(_G.MiniMapWorldMapButton)
	Kill(_G.MinimapBorder)
	Kill(_G.MinimapBorderTop)
	Kill(_G.MinimapZoomIn)
	Kill(_G.MinimapZoomOut)

	if MinimapCluster then
		MinimapCluster:EnableMouse(false)
		Kill(MinimapCluster.BorderTop)
		Kill(MinimapCluster.ZoneTextButton)

		-- Tracking is the one piece we keep alive (invisible) so right-click can
		-- still open its menu; everything else is gone.
		local tracking = MinimapCluster.Tracking
		if tracking then
			tracking:SetAlpha(0)
			tracking:EnableMouse(false)
		end
	end

	-- Midnight housing overlay: the static overlay is built for the round mask,
	-- so pin it inside the square map and crop the texcoords to match (NDui).
	local overlay = _G.MinimapBackdrop and _G.MinimapBackdrop.StaticOverlayTexture
	if overlay then
		overlay:ClearAllPoints()
		overlay:SetPoint("TOPLEFT", Minimap, "TOPLEFT", 0, 0)
		overlay:SetPoint("BOTTOMRIGHT", Minimap, "BOTTOMRIGHT", 0, 0)
		overlay:SetTexCoord(0.2, 0.8, 0.2, 0.8)
	end
end

-- ---------------------------------------------------------------------------
-- Tighten the Edit Mode footprint
--   The cluster reserves vertical space for the header we removed, so its Edit
--   Mode selection box floats above the square map. A one-shot resize loses to
--   Blizzard's layout pass, so instead we hook the cluster's SetSize and force
--   our footprint through the *raw* frame method on every layout - the
--   ls_Minimap / Blizzard-supported pattern. Calling the metatable SetSize
--   directly bypasses our own post-hook (no recursion), and re-applying an
--   unchanged size is a no-op, so it converges instead of fighting Blizzard.
--   Forcing it from inside the hook means it also stays flush while Edit Mode
--   is open. Keep the logical cluster size equal to the logical minimap size;
--   Edit Mode/container scaling is applied after that, so multiplying by scale
--   here would double-count the slider.
-- ---------------------------------------------------------------------------
local RAW_SET_SIZE = GetFrameMetatable().__index.SetSize

local function ApplyClusterFootprint()
	if InCombatLockdown() then
		return
	end
	local cluster = MinimapCluster
	local container = cluster and cluster.MinimapContainer
	if not container then
		return
	end

	local w, h = Minimap:GetSize()
	if not w or w < 10 then
		return
	end

	container:ClearAllPoints()
	container:SetPoint("CENTER", cluster, "CENTER", 0, 0)
	RAW_SET_SIZE(cluster, w, h)
end

local clusterHooked
local function HookClusterFootprint()
	if not MinimapCluster then
		return
	end
	ApplyClusterFootprint()
	if clusterHooked then
		return
	end
	clusterHooked = true
	hooksecurefunc(MinimapCluster, "SetSize", ApplyClusterFootprint)
end

-- ---------------------------------------------------------------------------
-- Re-home the Blizzard regions to tidy corners
-- ---------------------------------------------------------------------------
local FLAG_TEX = C.Media.Textures.flag
local CALENDAR_TEX = C.Media.Textures.calendar

-- Swap an instance-difficulty flag's atlas background for our Flag texture and
-- keep it swapped (Blizzard re-applies the atlas whenever difficulty changes).
local function ReskinDifficultyFlag(frame)
	if not (frame and frame.Background) then
		return
	end
	if frame.Border then
		frame.Border:Hide()
	end
	local function apply()
		frame.Background:SetTexture(FLAG_TEX)
	end
	apply()
	hooksecurefunc(frame.Background, "SetAtlas", apply)
end

-- Replace the calendar button's icon with our Calendar texture. Our art is a
-- blank calendar, so we draw the day number ourselves (Blizzard's is part of the
-- texture we replaced).
local calendarText

local function ApplyCalendarSkin()
	local gameTime = _G.GameTimeFrame
	if not gameTime then
		return
	end
	gameTime:SetNormalTexture(CALENDAR_TEX)
	gameTime:SetPushedTexture(CALENDAR_TEX)
	gameTime:SetHighlightTexture(0)
	local normal = gameTime:GetNormalTexture()
	local pushed = gameTime:GetPushedTexture()
	if normal then
		normal:SetTexCoord(0, 1, 0, 1)
	end
	if pushed then
		pushed:SetTexCoord(0, 1, 0, 1)
	end
end

local function UpdateCalendarDate()
	if not calendarText then
		return
	end
	local now = _G.C_DateAndTime and _G.C_DateAndTime.GetCurrentCalendarTime and _G.C_DateAndTime.GetCurrentCalendarTime()
	if now and now.monthDay then
		calendarText:SetText(now.monthDay)
	end
end

-- Garrison / covenant / warband landing page button -> bottom-left. Left-click
-- remains Blizzard's default; right-click offers the summary switch menu.
local LANDING_PAGE_ATLAS = "ShipMissionIcon-Combat-Mission"

local function ToggleLandingPage(garrisonType)
	if _G.C_Garrison and _G.C_Garrison.HasGarrison and not _G.C_Garrison.HasGarrison(garrisonType) then
		_G.UIErrorsFrame:AddMessage(C.InfoColor .. (_G.CONTRIBUTION_TOOLTIP_UNLOCKED_WHEN_ACTIVE or _G.NOT_APPLICABLE))
		return
	end
	if _G.ShowGarrisonLandingPage then
		_G.ShowGarrisonLandingPage(garrisonType)
	end
end

local LANDING_PAGE_SIZE = 26

local function SkinLandingPageButton(button)
	-- Blizzard re-applies the icon + size on RefreshButton / UpdateIcon /
	-- SetLandingPageIconFromAtlases, all of which we hook; guard against the
	-- re-entrancy our own SetSize/SetAtlas could trigger.
	if button.__nexSkinning then
		return
	end
	button.__nexSkinning = true

	local normal = button:GetNormalTexture()
	local pushed = button:GetPushedTexture()
	local highlight = button:GetHighlightTexture()

	if normal and normal.SetAtlas then
		normal:SetAtlas(LANDING_PAGE_ATLAS)
		normal:SetVertexColor(1, 1, 1, 1)
	end
	if pushed and pushed.SetAtlas then
		pushed:SetAtlas(LANDING_PAGE_ATLAS)
		pushed:SetVertexColor(1, 1, 1, 1)
	end
	if highlight and highlight.SetAtlas then
		highlight:SetAtlas(LANDING_PAGE_ATLAS)
		highlight:SetVertexColor(1, 1, 1, 1)
	end
	if button.LoopingGlow and button.LoopingGlow.SetAtlas then
		button.LoopingGlow:SetAtlas(LANDING_PAGE_ATLAS)
		button.LoopingGlow:SetSize(LANDING_PAGE_SIZE, LANDING_PAGE_SIZE)
	end

	button:SetSize(LANDING_PAGE_SIZE, LANDING_PAGE_SIZE)

	button.__nexSkinning = false
end

-- Retail 12.0 re-anchors this button through an *internal* anchor region via
-- ExpansionLandingPageMinimapButtonMixin:UpdateIconForGarrison() ->
-- ApplyGarrisonTypeAnchor() and :SetLandingPageIconOffset(), NOT through the
-- button's own SetPoint. Hooking the button's SetPoint (our generic Pin helper)
-- therefore misses these and Blizzard drags it back to its default corner -
-- off our squared map. Re-pin from those exact paths instead. Guard against the
-- re-entrancy our own ClearAllPoints/SetPoint could cause.
local function PositionLandingPageButton(button)
	if button.__nexPositioning then
		return
	end
	button.__nexPositioning = true
	button:ClearAllPoints()
	button:SetPoint("BOTTOMLEFT", Minimap, "BOTTOMLEFT", 4, 4)
	button:SetHitRectInsets(0, 0, 0, 0)
	button.__nexPositioning = false
end

local function RefreshLandingPageButton(button)
	PositionLandingPageButton(button)
	SkinLandingPageButton(button)
end

local function ShowLandingPageMenu(button)
	if not (_G.MenuUtil and _G.MenuUtil.CreateContextMenu and _G.Enum and _G.Enum.GarrisonType) then
		return
	end

	if _G.GarrisonLandingPage and _G.GarrisonLandingPage:IsShown() then
		_G.HideUIPanel(_G.GarrisonLandingPage)
	end
	if _G.ExpansionLandingPage and _G.ExpansionLandingPage:IsShown() then
		_G.HideUIPanel(_G.ExpansionLandingPage)
	end

	local types = _G.Enum.GarrisonType
	_G.MenuUtil.CreateContextMenu(button, function(_, root)
		if _G.GARRISON_TYPE_9_0_LANDING_PAGE_TITLE then
			root:CreateButton(_G.GARRISON_TYPE_9_0_LANDING_PAGE_TITLE, function()
				ToggleLandingPage(types.Type_9_0_Garrison)
			end)
		end
		if _G.GARRISON_TYPE_8_0_LANDING_PAGE_TITLE then
			root:CreateButton(_G.GARRISON_TYPE_8_0_LANDING_PAGE_TITLE, function()
				ToggleLandingPage(types.Type_8_0_Garrison)
			end)
		end
		if _G.ORDER_HALL_LANDING_PAGE_TITLE then
			root:CreateButton(_G.ORDER_HALL_LANDING_PAGE_TITLE, function()
				ToggleLandingPage(types.Type_7_0_Garrison)
			end)
		end
		if _G.GARRISON_LANDING_PAGE_TITLE then
			root:CreateButton(_G.GARRISON_LANDING_PAGE_TITLE, function()
				ToggleLandingPage(types.Type_6_0_Garrison)
			end)
		end
	end)
end

local function ReskinRegions()
	-- Expansion / garrison landing-page button -> bottom-left. Mirror KkthnxUI:
	-- leave it under Blizzard's parent and only reposition + skin it; Blizzard
	-- still controls when it is shown (via UpdateIcon).
	local garrMinimapButton = _G.ExpansionLandingPageMinimapButton
	if garrMinimapButton then
		RefreshLandingPageButton(garrMinimapButton)
		garrMinimapButton:HookScript("OnShow", RefreshLandingPageButton)
		hooksecurefunc(garrMinimapButton, "UpdateIcon", RefreshLandingPageButton)

		garrMinimapButton:HookScript("OnMouseDown", function(self, button)
			if button == "RightButton" then
				ShowLandingPageMenu(self)
			end
		end)
		garrMinimapButton:HookScript("OnEnter", function(self)
			local tooltip = _G.GameTooltip
			if tooltip and tooltip:IsOwned(self) then
				tooltip:AddLine("\n" .. L["Right Click to switch Summaries"], LBL[1], LBL[2], LBL[3], true)
				tooltip:Show()
			end
		end)
	end

	-- Mail / crafting indicators -> bottom centre. When the Clock DataText is
	-- enabled it sits at the bottom centre too, so lift the mail icon above it.
	local indicator = MinimapCluster and MinimapCluster.IndicatorFrame
	if indicator then
		indicator:SetFrameLevel(Minimap:GetFrameLevel() + 5)
		local clockOn = ns.db.timeText and ns.db.timeText.enable
		Pin(indicator, "BOTTOM", "BOTTOM", 0, clockOn and 24 or 4)
	end

	-- Instance difficulty flags -> top-left, reskinned with our Flag texture.
	local difficulty = MinimapCluster and MinimapCluster.InstanceDifficulty
	if difficulty then
		difficulty:SetParent(Minimap)
		difficulty:SetScale(0.85)
		Pin(difficulty, "TOPLEFT", "TOPLEFT", 2, -2)
		ReskinDifficultyFlag(difficulty.Instance)
		ReskinDifficultyFlag(difficulty.Guild)
		ReskinDifficultyFlag(difficulty.ChallengeMode)
	end

	-- Calendar button -> top-right, reskinned with our Calendar texture.
	local gameTime = _G.GameTimeFrame
	if gameTime then
		gameTime:SetParent(Minimap)
		gameTime:SetFrameLevel(Minimap:GetFrameLevel() + 6)
		gameTime:SetSize(22, 22)
		gameTime:SetHitRectInsets(0, 0, 0, 0)
		Pin(gameTime, "TOPRIGHT", "TOPRIGHT", -4, -4)
		ApplyCalendarSkin()

		if not calendarText then
			calendarText = gameTime:CreateFontString(nil, "OVERLAY")
			calendarText:SetFont(C.Media.Fonts.normal, 12, "")
			calendarText:SetPoint("CENTER", gameTime, "CENTER", 0, -4)
			calendarText:SetTextColor(0, 0, 0)
			calendarText:SetShadowOffset(0, 0)
			calendarText:SetAlpha(0.9)
		end
		UpdateCalendarDate()

		-- Blizzard re-textures the button when the date ticks over; re-apply both.
		if _G.GameTimeFrame_SetDate then
			hooksecurefunc("GameTimeFrame_SetDate", function()
				ApplyCalendarSkin()
				UpdateCalendarDate()
			end)
		end
	end

	-- Pending calendar invite texture -> top-left corner.
	local invites = _G.GameTimeCalendarInvitesTexture
	if invites then
		invites:SetParent(Minimap)
		invites:ClearAllPoints()
		invites:SetPoint("TOPLEFT", Minimap, "TOPLEFT", 2, -2)
	end

	-- Background downloader icon -> left edge, dimmed.
	local streaming = _G.StreamingIcon
	if streaming then
		streaming:SetParent(Minimap)
		streaming:SetScale(0.8)
		streaming:SetAlpha(0.5)
		streaming:SetFrameStrata("LOW")
		Pin(streaming, "LEFT", "LEFT", -6, 0)
	end
end

-- ---------------------------------------------------------------------------
-- Queue / LFG eye: re-home, spin a dungeon icon while queued, and show the
-- time spent in queue under the eye.
-- ---------------------------------------------------------------------------
local queueDisplay

-- Branded class-coloured h/m/s format templates, built once. Precomputing the
-- three "%d<color>X|r" strings keeps QueueTimeFormat (runs ~1Hz while queued)
-- allocation-free instead of concatenating the suffix on every tick.
local queueFmtH, queueFmtM, queueFmtS
local function QueueSuffix()
	local _, class = UnitClass("player")
	local color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	local suffix = "|c" .. ((color and color.colorStr) or "ffffffff")
	queueFmtH = "%d" .. suffix .. "h|r"
	queueFmtM = "%d" .. suffix .. "m|r"
	queueFmtS = "%d" .. suffix .. "s|r"
	return suffix
end

local function QueueTimeFormat(seconds)
	local text = queueDisplay and queueDisplay.text
	if not text then
		return
	end

	local hours = floor((seconds % 86400) / 3600)
	if hours > 0 then
		text:SetFormattedText(queueFmtH, hours)
		return
	end
	local minutes = floor((seconds % 3600) / 60)
	if minutes > 0 then
		text:SetFormattedText(queueFmtM, minutes)
		return
	end
	local secs = floor(seconds % 60)
	if secs > 0 then
		text:SetFormattedText(queueFmtS, secs)
	end
end

local function ClearQueueStatus()
	if not queueDisplay then
		return
	end
	queueDisplay.text:SetText("")
	queueDisplay.title = nil
	queueDisplay.queuedTime = nil
	queueDisplay:SetScript("OnUpdate", nil)
end

local function QueueOnUpdate(self, elapsed)
	self.throttle = (self.throttle or 0) - elapsed
	if self.throttle <= 0 then
		QueueTimeFormat(GetTime() - (self.queuedTime or 0))
		queueDisplay.text:SetTextColor(1, 1, 1)
		self.throttle = 0.1
	end
end

-- Hooks for QueueStatusEntry_SetFullDisplay(entry, title, queuedTime, ...): the
-- secure-hook receives the original args, so the entry is the leading arg here.
local function SetFullQueueStatus(_, title, queuedTime)
	if not queueDisplay then
		return
	end
	if not queueDisplay.title or queueDisplay.title == title then
		if queuedTime then
			queueDisplay.title = title
			queueDisplay.queuedTime = queuedTime
			queueDisplay.throttle = 0
			queueDisplay:SetScript("OnUpdate", QueueOnUpdate)
		else
			ClearQueueStatus()
		end
	end
end

local function SetMinimalQueueStatus(_, title)
	if queueDisplay and queueDisplay.title == title then
		ClearQueueStatus()
	end
end

local function ReskinQueueStatus()
	local button = _G.QueueStatusButton
	if not button then
		return
	end

	button:SetParent(MinimapCluster or Minimap)
	button:SetSize(24, 24)
	button:SetFrameLevel(Minimap:GetFrameLevel() + 6)
	Pin(button, "BOTTOMRIGHT", "BOTTOMRIGHT", -4, 4)

	if _G.QueueStatusButtonIcon then
		_G.QueueStatusButtonIcon:SetAlpha(0)
	end
	if _G.QueueStatusFrame then
		_G.QueueStatusFrame:ClearAllPoints()
		_G.QueueStatusFrame:SetPoint("TOPRIGHT", button, "TOPLEFT")
	end

	-- Spinning dungeon icon over the eye.
	local icon = Minimap:CreateTexture(nil, "ARTWORK")
	icon:SetPoint("CENTER", button)
	icon:SetSize(32, 32)
	icon:SetAtlas("RaidFrame-Icon-LFR")
	icon:Hide()

	-- Visibility follows the eye; spin play/pause follows its animation so we
	-- only rotate while actually searching for a group.
	if _G.QueueStatusFrame then
		hooksecurefunc(_G.QueueStatusFrame, "Update", function()
			icon:SetShown(button:IsShown())
		end)
	end

	-- Time-in-queue text under the eye.
	queueDisplay = CreateFrame("Frame", nil, button)
	QueueSuffix()
	queueDisplay.text = F.CreateFS(queueDisplay, 13)
	queueDisplay.text:ClearAllPoints()
	queueDisplay.text:SetPoint("CENTER", button, "CENTER", 0, -3)

	button:HookScript("OnHide", ClearQueueStatus)
	if _G.QueueStatusEntry_SetMinimalDisplay then
		hooksecurefunc("QueueStatusEntry_SetMinimalDisplay", SetMinimalQueueStatus)
	end
	if _G.QueueStatusEntry_SetFullDisplay then
		hooksecurefunc("QueueStatusEntry_SetFullDisplay", SetFullQueueStatus)
	end
end

-- ---------------------------------------------------------------------------
-- Collect Buttons - sweep stray addon minimap buttons into a pop-out tray
--   Adapted from KkthnxUI's CollectButtons.lua (by Kkthnx). We scan the
--   minimap's children a handful of times after login, square + border the
--   addon buttons we find, and park them in a fade-in tray behind a small
--   corner toggle. Blizzard frames and our own widgets are never touched.
-- ---------------------------------------------------------------------------
local strfind, strmatch, strupper = string.find, string.match, string.upper
local wipe, ceil, select, type, unpack = wipe, math.ceil, select, type, unpack
local PlaySound = PlaySound
local UIFrameFadeIn, UIFrameFadeOut = UIFrameFadeIn, UIFrameFadeOut
local C_Timer = C_Timer

local BIN_ICON_SIZE, BIN_PER_ROW = 16, 6
local BIN_PAD, BIN_GAP = 6, 6
local BIN_TEXCOORD = { 0.08, 0.92, 0.08, 0.92 }
local BIN_SOUND = (SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) or 856
local BIN_SCAN_PASSES, BIN_SCAN_INTERVAL = 12, 5
local BIN_AUTOCLOSE = 6

-- Background/border art fileIDs we strip so a collected button is just its icon.
local binRemovedTextures = { [136430] = true, [136467] = true }
-- Addons whose icons are already clean squares: skip the texcoord crop.
local binGoodIcon = { Narci_MinimapButton = true, ZygorGuidesViewerMapIcon = true }

-- Blizzard frames and our own reskinned regions: never collect these.
local binBlacklist = {
	BattlefieldMinimap = true,
	BattlefieldMinimapTab = true,
	ExpansionLandingPageMinimapButton = true,
	GameTimeFrame = true,
	GarrisonLandingPageMinimapButton = true,
	MiniMapMailFrame = true,
	MiniMapTracking = true,
	MinimapBackdrop = true,
	MinimapCluster = true,
	MinimapZoneTextButton = true,
	MinimapZoomIn = true,
	MinimapZoomOut = true,
	QueueStatusButton = true,
	QueueStatusMinimapButton = true,
	TimeManagerClockButton = true,
}

-- Name patterns to leave alone: our own widgets and map "pins" that must stay
-- anchored to the world map rather than being parked.
local binIgnorePatterns = { "^NexEnhance", "GatherMatePin", "HandyNotes%.-Pin", "TTMinimapButton" }

local binToggleAnchor = {
	[1] = { "BOTTOMLEFT", -7, -7 },
	[2] = { "BOTTOMRIGHT", 7, -7 },
	[3] = { "TOPLEFT", -7, 7 },
	[4] = { "TOPRIGHT", 7, 7 },
}
-- The tray grows away from the minimap edge the toggle hugs.
local binPopAnchor = {
	[1] = { "BOTTOMRIGHT", "BOTTOMLEFT", -7, 0 },
	[2] = { "BOTTOMRIGHT", "BOTTOMRIGHT", 7, -7 },
	[3] = { "TOPRIGHT", "TOPLEFT", -7, 7 },
	[4] = { "TOPLEFT", "TOPRIGHT", 7, 7 },
}

local binFrame, binToggle
local binCollected, binShown = {}, {}
local binChildCount, binScanCount, binAutoCloseTimer = 0, 0, nil
local OpenBin, CloseBin, LayoutBin, StartAutoClose, StopAutoClose

local function BinIgnored(name)
	for i = 1, #binIgnorePatterns do
		if strmatch(name, binIgnorePatterns[i]) then
			return true
		end
	end
end

local function AddBinBorder(button)
	if button.nexBinBorder then
		return
	end
	local border = CreateFrame("Frame", nil, button, "BackdropTemplate")
	border:SetPoint("TOPLEFT", button, "TOPLEFT", -1, 1)
	border:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 1, -1)
	border:SetFrameLevel(max(button:GetFrameLevel() - 1, 0))
	border:SetBackdrop({ edgeFile = C.Media.Textures.blank, edgeSize = 1 })
	border:SetBackdropBorderColor(0, 0, 0)
	button.nexBinBorder = border
end

local function SkinBinButton(button, name)
	for i = 1, button:GetNumRegions() do
		local region = select(i, button:GetRegions())
		if region and region.IsObjectType and region:IsObjectType("Texture") then
			local tex = region:GetTexture()
			if tex and (binRemovedTextures[tex] or (type(tex) == "string" and (strfind(tex, "Interface\\CharacterFrame") or strfind(tex, "Interface\\Minimap")))) then
				region:SetTexture(nil)
				region:Hide()
			else
				region:ClearAllPoints()
				region:SetAllPoints(button)
				if not binGoodIcon[name] then
					region:SetTexCoord(unpack(BIN_TEXCOORD))
				end
			end
		end
	end

	button:SetSize(BIN_ICON_SIZE, BIN_ICON_SIZE)
	AddBinBorder(button)
	tinsert(binCollected, button)
end

local function ParkBinButtons()
	for _, button in ipairs(binCollected) do
		if button and not button.nexParked then
			button:SetParent(binFrame)

			-- Drop drag scripts so LibDBIcon buttons stop chasing the minimap ring.
			if button:HasScript("OnDragStart") then
				button:SetScript("OnDragStart", nil)
			end
			if button:HasScript("OnDragStop") then
				button:SetScript("OnDragStop", nil)
			end
			-- Close the tray after a click so it doesn't linger.
			if button:HasScript("OnClick") then
				button:HookScript("OnClick", function()
					CloseBin()
				end)
			end

			-- Per-addon quirks that misbehave when reparented.
			local name = button.GetName and button:GetName()
			if name == "DBMMinimapButton" then
				button:SetScript("OnMouseDown", nil)
				button:SetScript("OnMouseUp", nil)
			elseif name == "WIM3MinimapButton" then
				button.SetParent = F and F.Noop or function() end
			end

			button.nexParked = true
		end
	end
end

LayoutBin = function()
	wipe(binShown)
	for _, b in ipairs(binCollected) do
		if b and b.IsShown and b:IsShown() then
			tinsert(binShown, b)
		end
	end

	local n = #binShown
	if n == 0 then
		binFrame:SetSize(BIN_ICON_SIZE + BIN_PAD * 2, BIN_ICON_SIZE + BIN_PAD * 2)
		return
	end

	local perRow = min(n, BIN_PER_ROW)
	local rows = ceil(n / BIN_PER_ROW)
	binFrame:SetSize(perRow * BIN_ICON_SIZE + (perRow - 1) * BIN_GAP + BIN_PAD * 2, rows * BIN_ICON_SIZE + (rows - 1) * BIN_GAP + BIN_PAD * 2)

	for i, b in ipairs(binShown) do
		local col = (i - 1) % BIN_PER_ROW
		local row = floor((i - 1) / BIN_PER_ROW)
		b:ClearAllPoints()
		b:SetParent(binFrame)
		b:SetPoint("TOPLEFT", binFrame, "TOPLEFT", BIN_PAD + col * (BIN_ICON_SIZE + BIN_GAP), -(BIN_PAD + row * (BIN_ICON_SIZE + BIN_GAP)))
	end
end

local function ScanBinButtons()
	if not ns.db.minimap.collectButtons or not binFrame then
		return
	end

	local num = Minimap:GetNumChildren()
	if num ~= binChildCount then
		local kids = { Minimap:GetChildren() }
		for i = 1, num do
			local child = kids[i]
			local name = child and child.GetName and child:GetName()
			if name and not child.nexExamined and not binBlacklist[name] then
				if (child:IsObjectType("Button") or strfind(strupper(name), "BUTTON")) and not BinIgnored(name) then
					SkinBinButton(child, name)
				end
				child.nexExamined = true
			end
		end
		binChildCount = num
	end

	ParkBinButtons()

	binScanCount = binScanCount + 1
	if binScanCount < BIN_SCAN_PASSES then
		C_Timer.After(BIN_SCAN_INTERVAL, ScanBinButtons)
	end
end

StopAutoClose = function()
	if binAutoCloseTimer then
		binAutoCloseTimer:Cancel()
		binAutoCloseTimer = nil
	end
end

StartAutoClose = function()
	StopAutoClose()
	binAutoCloseTimer = C_Timer.NewTimer(BIN_AUTOCLOSE, function()
		if binFrame and binFrame:IsShown() then
			CloseBin()
		end
	end)
end

CloseBin = function()
	if not binFrame then
		return
	end
	PlaySound(BIN_SOUND)
	StopAutoClose()
	UIFrameFadeOut(binFrame, 0.25, binFrame:GetAlpha(), 0)
	C_Timer.After(0.25, function()
		if binFrame and binFrame:GetAlpha() <= 0.05 then
			binFrame:Hide()
		end
	end)
end

OpenBin = function()
	if not binFrame then
		return
	end
	PlaySound(BIN_SOUND)
	LayoutBin()
	binFrame:Show()
	UIFrameFadeIn(binFrame, 0.25, 0, 1)
	StartAutoClose()
end

local function CreateCollectButtons()
	if binFrame or not ns.db.minimap.collectButtons then
		return
	end

	local pos = ns.db.minimap.buttonBinPosition or 3
	local tAnchor = binToggleAnchor[pos] or binToggleAnchor[3]
	local pAnchor = binPopAnchor[pos] or binPopAnchor[3]

	binToggle = CreateFrame("Button", nil, Minimap)
	binToggle:SetSize(16, 16)
	binToggle:SetFrameLevel(Minimap:GetFrameLevel() + 6)
	binToggle:SetAlpha(0.25)
	binToggle:SetPoint(tAnchor[1], Minimap, tAnchor[1], tAnchor[2], tAnchor[3])
	binToggle.icon = binToggle:CreateTexture(nil, "ARTWORK")
	binToggle.icon:SetAllPoints()
	binToggle.icon:SetTexture("Interface\\COMMON\\Indicator-Gray")
	binToggle:SetHighlightTexture("Interface\\COMMON\\Indicator-Yellow")
	binToggle:SetPushedTexture("Interface\\COMMON\\Indicator-Green")

	binFrame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
	binFrame:SetFrameStrata("MEDIUM")
	binFrame:SetClampedToScreen(true)
	binFrame:SetPoint(pAnchor[1], binToggle, pAnchor[2], pAnchor[3], pAnchor[4])
	binFrame:SetSize(BIN_ICON_SIZE + BIN_PAD * 2, BIN_ICON_SIZE + BIN_PAD * 2)
	binFrame:SetBackdrop({
		bgFile = C.Media.Textures.blank,
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 14,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	binFrame:SetBackdropColor(0.06, 0.06, 0.06, 0.9)
	binFrame:Hide()

	binToggle:SetScript("OnClick", function()
		if binFrame:IsShown() then
			CloseBin()
		else
			OpenBin()
		end
	end)
	binToggle:SetScript("OnEnter", function(self)
		self:SetAlpha(0.6)
		StopAutoClose()
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine(L["Minimap Buttons"], HDR[1], HDR[2], HDR[3])
		GameTooltip:AddLine(L["Collect addon minimap buttons into a pop-out tray."], LBL[1], LBL[2], LBL[3], true)
		GameTooltip:Show()
	end)
	binToggle:SetScript("OnLeave", function(self)
		self:SetAlpha(0.25)
		GameTooltip:Hide()
		if binFrame:IsShown() then
			StartAutoClose()
		end
	end)

	binFrame:SetScript("OnEnter", StopAutoClose)
	binFrame:SetScript("OnLeave", function()
		if binFrame:IsShown() then
			StartAutoClose()
		end
	end)

	ScanBinButtons()
end

-- Required by LibDBIcon-style libraries so minimap buttons hug a square edge.
---@diagnostic disable-next-line: inject-field
function _G.GetMinimapShape()
	return "SQUARE"
end

-- ---------------------------------------------------------------------------
-- Edit Mode dialog settings
--   Mirror the minimap options onto Blizzard's native Minimap Edit Mode dialog.
--   The minimap keeps its built-in mover, so we attach to the system (via
--   LibEditMode's AddSystemSettings) rather than registering our own frame.
--   Both paths read/write the same profile keys; like the Settings panel, most
--   take effect on reload.
-- ---------------------------------------------------------------------------
local editMode

local function MakeCheckbox(key, name, desc)
	return {
		kind = editMode.SettingType.Checkbox,
		name = name,
		desc = desc,
		default = DEFAULTS[key],
		get = function()
			return ns.db.minimap[key]
		end,
		set = function(_, value)
			ns.db.minimap[key] = value
		end,
	}
end

local function SetupEditModeSettings()
	editMode = _G.LibStub and _G.LibStub("LibEditMode", true)
	if not editMode or not editMode.AddSystemSettings then
		return
	end
	if not (_G.Enum and _G.Enum.EditModeSystem and _G.Enum.EditModeSystem.Minimap) then
		return
	end

	editMode:AddSystemSettings(_G.Enum.EditModeSystem.Minimap, {
		MakeCheckbox("easyVolume", L["Easy Volume"], L["Hold Ctrl and scroll over the minimap to adjust the master volume (hold Alt for full range)."]),
		MakeCheckbox("microMenu", L["Minimap Menu"], L["Middle-click the minimap to open a shortcut menu of Blizzard panels."]),
		MakeCheckbox("border", L["Minimap Border"], L["Frame the minimap with a Blizzard tooltip-style border (reload to apply)."]),
		MakeCheckbox("mailPulse", L["Status Pulse"], L["Pulse the minimap border for pending mail / calendar invites (yellow)."]),
		MakeCheckbox("collectButtons", L["Collect Buttons"], L["Sweep stray addon minimap buttons into a pop-out tray behind a small corner toggle (reload to disable)."]),
		{
			kind = editMode.SettingType.Dropdown,
			name = L["Button Tray Position"],
			desc = L["Which minimap corner the button tray toggle hugs."],
			default = DEFAULTS.buttonBinPosition,
			get = function()
				return ns.db.minimap.buttonBinPosition
			end,
			set = function(_, value)
				ns.db.minimap.buttonBinPosition = value
			end,
			disabled = function()
				return not ns.db.minimap.collectButtons
			end,
			values = {
				{ text = L["Top Left"], value = 3 },
				{ text = L["Top Right"], value = 4 },
				{ text = L["Bottom Left"], value = 1 },
				{ text = L["Bottom Right"], value = 2 },
			},
		},
	})
end

-- ---------------------------------------------------------------------------
-- Module
-- ---------------------------------------------------------------------------
function Module:OnEnable()
	local cfg = ns.db.minimap
	if not cfg.enable or not Minimap then
		return
	end

	-- Square shape.
	Minimap:SetMaskTexture(C.Media.Textures.blank)

	if cfg.easyVolume then
		CreateVolumeDisplay()
	end

	if cfg.microMenu then
		BuildMenuList()
	end

	-- Mouse input lives on a dedicated overlay rather than scripted straight onto
	-- the minimap (NDui-style): left-click passes through to Blizzard so the
	-- default ping still fires, mouse motion propagates so minimap mouseover /
	-- tooltips keep working, and we own the wheel (zoom/volume) plus the
	-- middle-click micro menu and right-click tracking menu.
	if not minimapClicker then
		minimapClicker = CreateFrame("Frame", "NexEnhanceMinimapClicker", Minimap)
		minimapClicker:SetAllPoints(Minimap)
		minimapClicker:EnableMouse(true)
		minimapClicker:EnableMouseWheel(true)
		if minimapClicker.SetPassThroughButtons then
			minimapClicker:SetPassThroughButtons("LeftButton")
		end
		if minimapClicker.SetPropagateMouseMotion then
			minimapClicker:SetPropagateMouseMotion(true)
		end
		minimapClicker:SetScript("OnMouseWheel", OnMouseWheel)
		minimapClicker:SetScript("OnMouseUp", function(_, button)
			if button == "MiddleButton" and cfg.microMenu then
				ShowMicroMenu()
			elseif button == "RightButton" then
				ShowTrackingMenu()
			end
		end)
	end

	Declutter()
	CreateBorder()
	ReskinRegions()
	ReskinQueueStatus()
	CreatePulse()

	if cfg.collectButtons then
		CreateCollectButtons()
	end

	-- Keep the Edit Mode selection box flush with the square minimap by hooking
	-- the cluster's SetSize (re-applied on world enter as a safety kick).
	HookClusterFootprint()
	ns:RegisterEvent("PLAYER_ENTERING_WORLD", ApplyClusterFootprint)

	-- Mirror the minimap options onto the native Minimap Edit Mode dialog.
	SetupEditModeSettings()

	-- Status pulse events (the pulse colours the border, so it needs both on).
	-- Pending mail / calendar invites only - no combat flash.
	if cfg.mailPulse and cfg.border then
		ns:RegisterEvent("UPDATE_PENDING_MAIL", UpdatePulse)
		ns:RegisterEvent("CALENDAR_UPDATE_PENDING_INVITES", UpdatePulse)
		ns:RegisterEvent("PLAYER_ENTERING_WORLD", UpdatePulse)
	end
end

function Module:RegisterOptions(category, builder)
	local _, enableInit = builder:Checkbox(category, self, "enable", L["Enable Minimap"], L["Square the minimap, add a clean border and tidy its buttons (reload to apply)."])
	local _, volumeInit = builder:Checkbox(category, self, "easyVolume", L["Easy Volume"], L["Hold Ctrl and scroll over the minimap to adjust the master volume (hold Alt for full range)."])
	local _, menuInit = builder:Checkbox(category, self, "microMenu", L["Minimap Menu"], L["Middle-click the minimap to open a shortcut menu of Blizzard panels."])
	local _, borderInit = builder:Checkbox(category, self, "border", L["Minimap Border"], L["Frame the minimap with a Blizzard tooltip-style border (reload to apply)."])
	local _, pulseInit = builder:Checkbox(category, self, "mailPulse", L["Status Pulse"], L["Pulse the minimap border for pending mail / calendar invites (yellow)."])
	local _, collectInit = builder:Checkbox(category, self, "collectButtons", L["Collect Buttons"], L["Sweep stray addon minimap buttons into a pop-out tray behind a small corner toggle (reload to disable)."])
	local _, binPosInit = builder:Dropdown(category, self, "buttonBinPosition", L["Button Tray Position"], L["Which minimap corner the button tray toggle hugs."], {
		{ value = 3, label = L["Top Left"] },
		{ value = 4, label = L["Top Right"] },
		{ value = 1, label = L["Bottom Left"] },
		{ value = 2, label = L["Bottom Right"] },
	})

	builder:DependsOn(volumeInit, enableInit)
	builder:DependsOn(menuInit, enableInit)
	builder:DependsOn(borderInit, enableInit)
	builder:DependsOn(pulseInit, borderInit)
	builder:DependsOn(collectInit, enableInit)
	builder:DependsOn(binPosInit, collectInit)
end
