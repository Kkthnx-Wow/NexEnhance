--[[
	NexEnhance - Wowhead Links
	-------------------------------------------------------------------------
	Adds small, copyable Wowhead-link edit boxes to the World Map (for the
	tracked/opened quest) and the Achievement frame (for the open achievement).
	Hover to highlight, drag-select to copy.

	Adapted from KkthnxUI by Josh "Kkthnx" Russell:
	  https://github.com/Kkthnx-Wow/KkthnxUI_Firestorm/blob/main/KkthnxUI/Modules/Maps/Elements/WowHeadLink.lua

	K.* helpers are replaced with framework equivalents. The Wowhead subdomain
	follows the client locale. Defers to Leatrix_Maps if that addon is loaded.
--]]

---@diagnostic disable: undefined-field, undefined-global
local _, ns = ...
local L = ns.L

local setmetatable = setmetatable
local strmatch = string.match
local CreateFrame = CreateFrame
local hooksecurefunc = hooksecurefunc
local GetLocale = GetLocale
local GetAchievementLink = GetAchievementLink
local GetQuestLink = GetQuestLink
local C_AddOns_IsAddOnLoaded = C_AddOns and C_AddOns.IsAddOnLoaded
local C_SuperTrack = C_SuperTrack

local function noop() end

-- Map client locales to their Wowhead subdomain (default www).
local subDomain = setmetatable({
	ruRU = "ru",
	frFR = "fr",
	deDE = "de",
	esES = "es",
	esMX = "es",
	ptBR = "pt",
	ptPT = "pt",
	itIT = "it",
	koKR = "ko",
	zhTW = "cn",
	zhCN = "cn",
}, {
	__index = function()
		return "www"
	end,
})[GetLocale()]

local wowheadLoc = subDomain .. ".wowhead.com"
local urlIcon = "|TInterface\\OptionsFrame\\UI-OptionsFrame-NewFeatureIcon:0:0:0:0|t"

ns:RegisterDefaults({
	wowheadLink = {
		enable = true,
	},
})

local WowheadLink = ns:NewModule("WowheadLink", "wowheadLink", { group = "maps", title = L["Wowhead Links"], order = 30 })

local achievementEditBox, questEditBox

local function FormatLink(id, kind)
	return urlIcon .. "https://" .. wowheadLoc .. "/" .. kind .. "=" .. id
end

-- A read-only edit box that highlights its text on hover/click for copying.
local function CreateLinkEditBox(parent, point, x, y, fontObject)
	local eb = CreateFrame("EditBox", nil, parent)
	eb:SetHeight(16)
	eb:SetPoint(point, x, y)
	eb:SetFontObject(fontObject)
	eb:SetBlinkSpeed(0)
	eb:SetAutoFocus(false)
	eb:EnableKeyboard(false)
	eb:SetScript("OnKeyDown", noop)

	eb.hiddenText = eb:CreateFontString(nil, "ARTWORK", fontObject)
	eb.hiddenText:Hide()

	eb:SetScript("OnMouseUp", function(self)
		if self:IsMouseOver() then
			self:HighlightText()
		else
			self:HighlightText(0, 0)
		end
	end)

	return eb
end

-- ---------------------------------------------------------------------------
-- Achievement frame (load-on-demand: Blizzard_AchievementUI)
-- ---------------------------------------------------------------------------
local function InitAchievementLink()
	if achievementEditBox then
		return
	end
	if not _G.AchievementFrame or not _G.AchievementTemplateMixin then
		return
	end

	local eb = CreateLinkEditBox(_G.AchievementFrame, "BOTTOMRIGHT", -50, 1, "GameFontNormalSmall")
	eb:SetJustifyH("RIGHT")
	eb:SetHitRectInsets(90, 0, 0, 0)
	achievementEditBox = eb

	local lastLink

	local function SetAchievementLink(_, achievementID)
		if not ns.db.wowheadLink.enable then
			eb:Hide()
			return
		end
		if not achievementID then
			return
		end

		local url = FormatLink(achievementID, "achievement")
		eb:SetText(url)
		eb.hiddenText:SetText(url)
		eb:SetWidth(eb.hiddenText:GetStringWidth() + 90)

		local link = GetAchievementLink(achievementID)
		eb.tooltipText = link and (strmatch(link, "%[(.-)%]") .. "|n" .. L["Press To Copy"]) or ""

		eb:Show()
		lastLink = eb:GetText()
	end

	hooksecurefunc(_G.AchievementTemplateMixin, "DisplayObjectives", SetAchievementLink)
	if _G.AchievementFrameComparisonTab_OnClick then
		hooksecurefunc("AchievementFrameComparisonTab_OnClick", function()
			eb:Hide()
		end)
	end

	eb:SetScript("OnEnter", function(self)
		self:HighlightText()
		self:SetFocus()
		GameTooltip:SetOwner(self, "ANCHOR_TOP", 0, 10)
		GameTooltip:SetText(self.tooltipText, nil, nil, nil, nil, true)
		GameTooltip:Show()
	end)

	eb:SetScript("OnLeave", function(self)
		if self:GetText() ~= lastLink then
			self:SetText(lastLink or "")
		end
		self:HighlightText(0, 0)
		self:ClearFocus()
		GameTooltip:Hide()
	end)
end

-- ---------------------------------------------------------------------------
-- World Map (tracked / opened quest)
-- ---------------------------------------------------------------------------
local function InitQuestLink()
	if questEditBox then
		return
	end
	local wmf = _G.WorldMapFrame
	if not wmf or not wmf.BorderFrame then
		return
	end

	local eb = CreateLinkEditBox(wmf.BorderFrame, "TOPLEFT", 100, -4, "GameFontNormal")
	eb:SetFrameLevel(501)
	eb:SetHitRectInsets(0, 90, 0, 0)
	questEditBox = eb

	local function UpdateQuestURL()
		if not ns.db.wowheadLink.enable then
			eb:Hide()
			return
		end

		local questID = (_G.QuestMapFrame and _G.QuestMapFrame.DetailsFrame and _G.QuestMapFrame.DetailsFrame:IsShown() and _G.QuestMapFrame_GetDetailQuestID and _G.QuestMapFrame_GetDetailQuestID()) or (C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID and C_SuperTrack.GetSuperTrackedQuestID())
		if questID and questID ~= 0 then
			local url = FormatLink(questID, "quest")
			eb:SetText(url)
			eb.hiddenText:SetText(url)
			eb:SetWidth(eb.hiddenText:GetStringWidth() + 90)

			local link = GetQuestLink(questID)
			eb.tooltipText = link and (strmatch(link, "%[(.-)%]") .. "|n" .. L["Press To Copy"]) or ""
			if not link and eb:IsMouseOver() then
				GameTooltip:Hide()
			end
			eb:Show()
		else
			eb:Hide()
		end
	end
	eb.UpdateURL = UpdateQuestURL

	eb:RegisterEvent("SUPER_TRACKING_CHANGED")
	eb:SetScript("OnEvent", UpdateQuestURL)
	UpdateQuestURL()

	if _G.QuestMapFrame_ShowQuestDetails then
		hooksecurefunc("QuestMapFrame_ShowQuestDetails", UpdateQuestURL)
	end
	if _G.QuestMapFrame_CloseQuestDetails then
		hooksecurefunc("QuestMapFrame_CloseQuestDetails", UpdateQuestURL)
	end

	eb:SetScript("OnEnter", function(self)
		self:HighlightText()
		self:SetFocus()
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM", 0, -10)
		GameTooltip:SetText(self.tooltipText, nil, nil, nil, nil, true)
		GameTooltip:Show()
	end)

	eb:SetScript("OnLeave", function(self)
		self:HighlightText(0, 0)
		self:ClearFocus()
		GameTooltip:Hide()
		UpdateQuestURL()
	end)
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------
-- One-shot wait for the load-on-demand achievement UI. Registered through the
-- engine's event API (not the module helper) so it can cleanly unregister
-- itself by callback once the addon has loaded.
local function OnAchievementUILoaded(_, addon)
	if addon ~= "Blizzard_AchievementUI" then
		return
	end
	InitAchievementLink()
	ns:UnregisterEvent("ADDON_LOADED", OnAchievementUILoaded)
end

function WowheadLink:Setup()
	if self.started then
		return
	end
	if C_AddOns_IsAddOnLoaded and C_AddOns_IsAddOnLoaded("Leatrix_Maps") then
		return
	end
	self.started = true

	if C_AddOns_IsAddOnLoaded and C_AddOns_IsAddOnLoaded("Blizzard_AchievementUI") then
		InitAchievementLink()
	else
		ns:RegisterEvent("ADDON_LOADED", OnAchievementUILoaded)
	end

	InitQuestLink()

	-- Hide the default map title to make room for the quest link edit box.
	if _G.WorldMapFrameTitleText then
		_G.WorldMapFrameTitleText:Hide()
	end
end

-- Show/hide the boxes live when the option is toggled.
function WowheadLink:Refresh()
	if achievementEditBox and not ns.db.wowheadLink.enable then
		achievementEditBox:Hide()
	end
	if questEditBox then
		if questEditBox.UpdateURL then
			questEditBox.UpdateURL()
		elseif not ns.db.wowheadLink.enable then
			questEditBox:Hide()
		end
	end
end

function WowheadLink:OnEnable()
	if ns.db.wowheadLink.enable then
		self:Setup()
	end
end

function WowheadLink:OnSettingChanged(key)
	if key ~= "enable" then
		return
	end
	if ns.db.wowheadLink.enable then
		self:Setup()
	end
	self:Refresh()
end

function WowheadLink:RegisterOptions(category, builder)
	builder:Checkbox(category, self, "enable", L["Enable Wowhead Links"], L["Add a copyable Wowhead link to the world map (tracked quest) and the achievement frame."])
end
