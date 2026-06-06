--[[
	NexEnhance - Minimap
	-------------------------------------------------------------------------
	Lightweight minimap tweaks ported from KkthnxUI by Josh "Kkthnx" Russell:
	  https://github.com/Kkthnx-Wow/KkthnxUI_Firestorm/blob/main/KkthnxUI/Modules/Maps/Minimap.lua

	Two self-contained features, each independently toggleable:
	  - Easy Volume: Ctrl + MouseWheel over the minimap adjusts the master
	    volume (hold Alt to jump straight to 0/100), showing a fading readout.
	  - Micro Menu: Middle-click the minimap to open a sorted shortcut menu
	    (character, spellbook, talents, ...). Uses the modern MenuUtil API.

	Retail only. We never reparent or hide Blizzard's minimap, so default
	left/right-click behaviour (pinging, the tracking menu) is preserved.
--]]

---@diagnostic disable: undefined-field, undefined-global
local _, ns = ...
local C, L, F = ns.C, ns.L, ns.F

local _G = _G
local ipairs = ipairs
local floor, min, max = math.floor, math.min, math.max
local sort, tinsert = table.sort, table.insert
local tonumber, tostring = tonumber, tostring

local CreateFrame = CreateFrame
local IsAltKeyDown = IsAltKeyDown
local IsControlKeyDown = IsControlKeyDown
local Minimap = Minimap
local C_CVar = C_CVar

ns:RegisterDefaults({
	minimap = {
		enable = true,
		easyVolume = true,
		microMenu = true,
	},
})

local Module = ns:NewModule("Minimap", "minimap", { group = "maps", title = L["Minimap"], order = 40 })

-- ---------------------------------------------------------------------------
-- Easy Volume (Ctrl + MouseWheel)
-- ---------------------------------------------------------------------------
local volumeText, volumeAnim

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
	if volumeText then return end

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
	if menuList then return end

	menuList = {
		{ text = _G.CHARACTER_BUTTON, icon = 236415, func = function() _G.ToggleCharacter("PaperDollFrame") end },
		{ text = _G.SPELLBOOK, icon = 133741, func = function()
			if _G.PlayerSpellsUtil then _G.PlayerSpellsUtil.ToggleSpellBookFrame() else _G.ToggleFrame(_G.SpellBookFrame) end
		end },
		{ text = _G.TALENTS_BUTTON, icon = 3717418, func = function()
			if _G.PlayerSpellsUtil then _G.PlayerSpellsUtil.ToggleClassTalentFrame() else _G.ToggleTalentFrame() end
		end },
		{ text = _G.ACHIEVEMENT_BUTTON, icon = 1033987, func = function() _G.ToggleAchievementFrame() end },
		{ text = _G.QUESTLOG_BUTTON, icon = 236669, func = function() _G.ToggleQuestLog() end },
		{ text = _G.GUILD, icon = 135026, func = function() _G.ToggleGuildFrame() end },
		{ text = _G.SOCIAL_BUTTON, icon = 442272, func = function() _G.ToggleFriendsFrame() end },
		{ text = _G.COLLECTIONS, icon = 5321228, func = function() _G.ToggleCollectionsJournal() end },
		{ text = _G.LFG_TITLE, icon = 134149, func = function() _G.ToggleLFDParentFrame() end },
		{ text = _G.ENCOUNTER_JOURNAL, icon = 236409, func = function()
			local loaded = _G.C_AddOns and _G.C_AddOns.IsAddOnLoaded("Blizzard_EncounterJournal")
			if not loaded then _G.UIParentLoadAddOn("Blizzard_EncounterJournal") end
			_G.ToggleFrame(_G.EncounterJournal)
		end },
		{ text = _G.PROFESSIONS_BUTTON, icon = 236574, func = function() _G.ToggleProfessionsBook() end },
		{ text = _G.CHAT_CHANNELS, icon = 2056011, func = function() _G.ToggleChannelFrame() end },
		{ text = _G.TIMEMANAGER_TITLE, icon = 237538, func = function() _G.ToggleFrame(_G.TimeManagerFrame) end },
		{ text = L["Calendar"], icon = 3007435, func = function()
			if _G.GameTimeFrame then _G.GameTimeFrame:Click() end
		end },
		{ text = _G.GARRISON_TYPE_8_0_LANDING_PAGE_TITLE, icon = 1044996, func = function()
			if _G.ExpansionLandingPageMinimapButton then _G.ExpansionLandingPageMinimapButton:ToggleLandingPage() end
		end },
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
	tinsert(menuList, { text = _G.MAINMENU_BUTTON, icon = 134400, func = function()
		if not _G.GameMenuFrame:IsShown() then
			_G.CloseMenus()
			_G.CloseAllWindows()
			_G.PlaySound(_G.SOUNDKIT.IG_MAINMENU_OPEN)
			_G.ShowUIPanel(_G.GameMenuFrame)
		else
			_G.PlaySound(_G.SOUNDKIT.IG_MAINMENU_QUIT)
			_G.HideUIPanel(_G.GameMenuFrame)
		end
	end })
	tinsert(menuList, { text = _G.HELP_BUTTON, icon = 511544, func = function() _G.ToggleHelpFrame() end })

	-- Pre-bake the icon markup so the menu generator stays cheap.
	for _, entry in ipairs(menuList) do
		entry.display = entry.icon and ("|T" .. entry.icon .. ":14:14:0:0|t  " .. entry.text) or entry.text
	end
end

local function ShowMicroMenu()
	if not (_G.MenuUtil and _G.MenuUtil.CreateContextMenu) then return end

	_G.MenuUtil.CreateContextMenu(Minimap, function(_, root)
		root:CreateTitle(_G.MINIMAP_LABEL or L["Minimap"])
		for _, entry in ipairs(menuList) do
			root:CreateButton(entry.display, entry.func)
		end
	end)
end

-- ---------------------------------------------------------------------------
-- Module
-- ---------------------------------------------------------------------------
function Module:OnEnable()
	if not ns.db.minimap.enable or not Minimap then return end

	if ns.db.minimap.easyVolume then
		CreateVolumeDisplay()
		Minimap:EnableMouseWheel(true)
		Minimap:SetScript("OnMouseWheel", OnMouseWheel)
	end

	if ns.db.minimap.microMenu then
		BuildMenuList()
		-- Hook (don't replace) so Blizzard's left/right-click handling stays intact.
		Minimap:HookScript("OnMouseUp", function(_, button)
			if button == "MiddleButton" then
				ShowMicroMenu()
			end
		end)
	end
end

function Module:RegisterOptions(category, builder)
	local _, enableInit = builder:Checkbox(category, self, "enable", L["Enable Minimap"], L["Adds optional minimap conveniences (reload to apply)."])
	local _, volumeInit = builder:Checkbox(category, self, "easyVolume", L["Easy Volume"], L["Hold Ctrl and scroll over the minimap to adjust the master volume (hold Alt for full range)."])
	local _, menuInit = builder:Checkbox(category, self, "microMenu", L["Minimap Menu"], L["Middle-click the minimap to open a shortcut menu of Blizzard panels."])

	builder:DependsOn(volumeInit, enableInit)
	builder:DependsOn(menuInit, enableInit)
end
