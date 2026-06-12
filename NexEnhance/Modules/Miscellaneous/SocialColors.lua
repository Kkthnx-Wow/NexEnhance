--[[
	NexEnhance - SocialColors
	-------------------------------------------------------------------------
	Class-colours player names and difficulty-colours levels across the
	social panels:
	  * Friends list (WoW + Battle.net friends).
	  * /who results window.
	  * Guild roster (only if the legacy Blizzard_GuildUI is present).

	Adapted to the NexEnhance architecture from NDui's yClassColors (by yleaf):
	  https://github.com/siweia/NDui/blob/master/Interface/AddOns/NDui/Plugins/yClassColors.lua

	Every hook target is guarded for existence so the module degrades quietly
	on UI layouts where a given frame/API is missing (e.g. the modern
	Communities-based guild UI), rather than erroring on login.
--]]

local _, ns = ...
local F, L = ns.F, ns.L

-- Localised globals / API.
local _G = _G
local pairs, ipairs, select, wipe = pairs, ipairs, select, wipe
local format = string.format
local floor = math.floor
local hooksecurefunc = hooksecurefunc

local GetAreaText = GetAreaText
local GetGuildInfo = GetGuildInfo
local UnitRace = UnitRace
local GetGuildRosterInfo = GetGuildRosterInfo
local GetGuildTradeSkillInfo = GetGuildTradeSkillInfo
local GetQuestDifficultyColor = GetQuestDifficultyColor
local C_FriendList = C_FriendList
local C_BattleNet = C_BattleNet

local CLASS_COLORS = _G["CUSTOM_CLASS_COLORS"] or RAID_CLASS_COLORS

ns:RegisterDefaults({
	socialColors = {
		enable = true,
	},
})

local SocialColors = ns:NewModule("SocialColors", "socialColors", { group = "misc", title = L["Social Colours"], order = 10 })

-- ---------------------------------------------------------------------------
-- Colour helpers
-- ---------------------------------------------------------------------------

-- Localised class name -> class token (e.g. "Death Knight" -> "DEATHKNIGHT").
-- Built once so per-row work in the scroll hooks stays a single table lookup.
local classToken = {}
do
	local male = _G["LOCALIZED_CLASS_NAMES_MALE"]
	local female = _G["LOCALIZED_CLASS_NAMES_FEMALE"]
	if male then
		for token, localized in pairs(male) do
			classToken[localized] = token
		end
	end
	if female then
		for token, localized in pairs(female) do
			classToken[localized] = token
		end
	end
end

-- Accepts either a class token or a localised class name and returns the
-- "|cffRRGGBB" escape, falling back to white if the class is unknown.
local function ClassColorStr(class)
	if not class then
		return "|cffffffff"
	end
	local token = classToken[class] or class
	local color = CLASS_COLORS[token]
	if not color then
		return "|cffffffff"
	end
	return "|c" .. color.colorStr
end

-- Class colour as an r, g, b triplet (for SetTextColor). Falls back to white.
local function ClassColorRGB(class)
	local token = class and (classToken[class] or class)
	local color = token and CLASS_COLORS[token]
	if not color then
		return 1, 1, 1
	end
	return color.r, color.g, color.b
end

-- Difficulty colour for a level, as a "|cffRRGGBB" escape.
local function DiffColor(level)
	local color = GetQuestDifficultyColor(level)
	return "|c" .. F.RGBToHex(color.r, color.g, color.b)
end

-- Linear gradient across a flat {r,g,b, r,g,b, ...} stop list (used for the
-- guild rank / reputation columns). `cur` in [0, max] selects the position.
local function GradientHex(cur, max, stops)
	if max <= 0 then
		max = 1
	end
	local percent = cur / max
	if percent < 0 then
		percent = 0
	elseif percent > 1 then
		percent = 1
	end

	local segments = (#stops / 3) - 1
	local segment = percent * segments
	local index = floor(segment)
	if index >= segments then
		index = segments - 1
	end
	local relative = segment - index

	local i = index * 3
	local r1, g1, b1 = stops[i + 1], stops[i + 2], stops[i + 3]
	local r2, g2, b2 = stops[i + 4], stops[i + 5], stops[i + 6]

	local r = r1 + (r2 - r1) * relative
	local g = g1 + (g2 - g1) * relative
	local b = b1 + (b2 - b1) * relative
	return "|c" .. F.RGBToHex(r, g, b)
end

local rankColor = { 1, 0, 0, 1, 1, 0, 0, 1, 0 }
local repColor = { 1, 0, 0, 1, 1, 0, 0, 1, 0, 0, 1, 1, 0, 0, 1 }

-- ---------------------------------------------------------------------------
-- Friends list (WoW + Battle.net)
-- ---------------------------------------------------------------------------
-- The level template uses %d which we can't feed a coloured string, so swap
-- the integer specifiers for string ones (matching NDui's approach).
local levelTemplate
local function GetLevelTemplate()
	if not levelTemplate then
		local raw = _G["FRIENDS_LEVEL_TEMPLATE"] or "Level %d %s"
		levelTemplate = raw:gsub("%%d", "%%s"):gsub("%$d", "%$s")
	end
	return levelTemplate
end

local function IsActive()
	return ns.db.socialColors.enable
end

-- Enumerate a ScrollBox's live row frames without the O(n^2) repeated
-- `select(i, ScrollTarget:GetChildren())` pattern (each select re-walks the
-- whole child list). Modern ScrollBoxes expose GetFrames(), which returns the
-- active-frame array directly with no allocation; fall back to the legacy
-- enumeration (into a reused scratch table) only if that API is missing.
local enumScratch = {}
local function GetRowFrames(scrollBox)
	if scrollBox.GetFrames then
		return scrollBox:GetFrames()
	end
	local target = scrollBox.ScrollTarget
	if not target then
		return nil
	end
	wipe(enumScratch)
	for i = 1, target:GetNumChildren() do
		enumScratch[i] = select(i, target:GetChildren())
	end
	return enumScratch
end

local function UpdateFriendsList(self)
	if not IsActive() then
		return
	end
	local buttons = GetRowFrames(self)
	if not buttons then
		return
	end
	local playerArea = GetAreaText()

	for i = 1, #buttons do
		local button = buttons[i]
		if button and button:IsShown() then
			local nameText, infoText

			if button.buttonType == _G["FRIENDS_BUTTON_TYPE_WOW"] then
				local info = C_FriendList.GetFriendInfoByIndex(button.id)
				if info and info.connected then
					nameText = ClassColorStr(info.className) .. info.name .. "|r, " .. format(GetLevelTemplate(), DiffColor(info.level) .. info.level .. "|r", info.className)
					if info.area == playerArea then
						infoText = format("|cff00ff00%s|r", info.area)
					end
				end
			elseif button.buttonType == _G["FRIENDS_BUTTON_TYPE_BNET"] then
				local accountInfo = C_BattleNet.GetFriendAccountInfo(button.id)
				if accountInfo then
					local gameAccountInfo = accountInfo.gameAccountInfo
					if gameAccountInfo and gameAccountInfo.isOnline and gameAccountInfo.clientProgram == _G["BNET_CLIENT_WOW"] then
						local charName = gameAccountInfo.characterName
						local class = gameAccountInfo.className or UNKNOWN
						local zoneName = gameAccountInfo.areaName or UNKNOWN
						local accountName = accountInfo.accountName
						if accountName and charName and class then
							local wow = _G["FRIENDS_WOW_NAME_COLOR_CODE"] or "|cffffffff"
							nameText = accountName .. " " .. wow .. "(" .. ClassColorStr(class) .. charName .. wow .. ")"
							if zoneName == playerArea then
								infoText = format("|cff00ff00%s|r", zoneName)
							end
						end
					end
				end
			end

			if nameText and button.name then
				button.name:SetText(nameText)
			end
			if infoText and button.info then
				button.info:SetText(infoText)
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- /who results
-- ---------------------------------------------------------------------------
local whoColumns = { zone = "", guild = "", race = "" }
local whoSortType = "zone"

local function UpdateWhoList(self)
	if not IsActive() then
		return
	end
	local buttons = GetRowFrames(self)
	if not buttons then
		return
	end
	local playerZone = GetAreaText()
	local playerGuild = GetGuildInfo("player")
	local playerRace = UnitRace("player")

	for i = 1, #buttons do
		local button = buttons[i]
		if button and button.index then
			local info = C_FriendList.GetWhoInfo(button.index)
			if info then
				local guild, level, race, zone, class = info.fullGuildName, info.level, info.raceStr, info.area, info.filename
				if zone and zone == playerZone then
					zone = "|cff00ff00" .. zone
				end
				if guild and guild == playerGuild then
					guild = "|cff00ff00" .. guild
				end
				if race and race == playerRace then
					race = "|cff00ff00" .. race
				end

				whoColumns.zone = zone or ""
				whoColumns.guild = guild or ""
				whoColumns.race = race or ""

				if button.Name then
					button.Name:SetTextColor(ClassColorRGB(class))
				end
				if button.Level then
					button.Level:SetText(DiffColor(level) .. level)
				end
				if button.Variable then
					button.Variable:SetText(whoColumns[whoSortType] or "")
				end
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- Guild roster (legacy Blizzard_GuildUI only)
-- ---------------------------------------------------------------------------
local guildView
local function SetGuildView(view)
	guildView = view
end

local function UpdateGuildView()
	if not IsActive() then
		return
	end
	local container = _G["GuildRosterContainer"]
	if not container or not container.buttons then
		return
	end

	guildView = guildView or (GetCVar and GetCVar("guildRosterView")) or "playerStatus"
	local playerArea = GetAreaText()

	for _, button in ipairs(container.buttons) do
		if button:IsShown() and button.online and button.guildIndex then
			if guildView == "tradeskill" then
				local _, _, _, headerName, _, _, _, _, _, _, _, zone = GetGuildTradeSkillInfo(button.guildIndex)
				if not headerName and zone == playerArea and button.string2 then
					button.string2:SetText("|cff00ff00" .. zone)
				end
			else
				local _, rank, rankIndex, level, _, zone, _, _, _, _, _, _, _, _, _, repStanding = GetGuildRosterInfo(button.guildIndex)
				if guildView == "playerStatus" then
					if button.string1 then
						button.string1:SetText(DiffColor(level) .. level)
					end
					if zone == playerArea and button.string3 then
						button.string3:SetText("|cff00ff00" .. zone)
					end
				elseif guildView == "guildStatus" then
					if rankIndex and rank and button.string2 then
						button.string2:SetText(GradientHex(rankIndex, 10, rankColor) .. rank)
					end
				elseif guildView == "achievement" then
					if button.string1 then
						button.string1:SetText(DiffColor(level) .. level)
					end
				elseif guildView == "reputation" then
					if button.string1 then
						button.string1:SetText(DiffColor(level) .. level)
					end
					if repStanding and button.string3 then
						local label = _G["FACTION_STANDING_LABEL" .. repStanding]
						button.string3:SetText(GradientHex(repStanding - 4, 5, repColor) .. (label or ""))
					end
				end
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- Hook installation
-- ---------------------------------------------------------------------------
function SocialColors:HookFriends()
	local frame = _G["FriendsListFrame"]
	if frame and frame.ScrollBox then
		hooksecurefunc(frame.ScrollBox, "Update", UpdateFriendsList)
	end
end

function SocialColors:HookWho()
	local frame = _G["WhoFrame"]
	if frame and frame.ScrollBox then
		hooksecurefunc(frame.ScrollBox, "Update", UpdateWhoList)
		if C_FriendList and C_FriendList.SortWho then
			hooksecurefunc(C_FriendList, "SortWho", function(sortType)
				whoSortType = sortType
			end)
		end
	end
end

function SocialColors:HookGuild()
	-- Legacy guild roster only; the modern Communities UI lacks these.
	if _G["GuildRoster_SetView"] then
		hooksecurefunc("GuildRoster_SetView", SetGuildView)
	end
	if _G["GuildRoster_Update"] then
		hooksecurefunc("GuildRoster_Update", UpdateGuildView)
	end
	local container = _G["GuildRosterContainer"]
	if container and container.update then
		hooksecurefunc(container, "update", UpdateGuildView)
	end
end

function SocialColors:ADDON_LOADED(addon)
	if addon == "Blizzard_GuildUI" then
		self:HookGuild()
	end
end

function SocialColors:OnEnable()
	if self.hooksInstalled then
		return
	end
	self.hooksInstalled = true

	self:HookFriends()
	self:HookWho()

	-- Guild UI is load-on-demand: hook now if already loaded, else wait.
	if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_GuildUI") then
		self:HookGuild()
	else
		self:RegisterEvent("ADDON_LOADED")
	end
end

function SocialColors:OnSettingChanged(key, value)
	-- Enabling later installs the hooks (they no-op while disabled via IsActive).
	if key == "enable" and value then
		self:OnEnable()
	end
end

function SocialColors:RegisterOptions(category, builder)
	builder:Checkbox(category, self, "enable", L["Enable Social Class Colours"], L["Class-colour names and difficulty-colour levels in the Friends, Who and Guild panels (reload to disable)."])
end
