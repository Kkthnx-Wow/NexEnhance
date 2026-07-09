--[[
	NexEnhance - Wowhead Links
	-------------------------------------------------------------------------
	Adds copyable Wowhead-link edit boxes to the world map (tracked/opened quest)
	and the achievement frame. Hover to highlight; Ctrl+C copies when focused.

	Wowhead subdomain follows client locale. Skips if Leatrix_Maps is loaded.
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

local COPY_HINT = L["Press Ctrl-C to copy"]

-- PortraitFrame TitleContainer sits at frame level 510; WorldMap enables mouse on
-- it for title-bar dragging, so our link box must stack above or it never receives
-- hover, tooltip, or copy input.
local function RaiseAboveTitleBar(frame, borderFrame)
	if not frame or not borderFrame then
		return
	end
	local titleContainer = borderFrame.TitleContainer
	local titleLevel = (titleContainer and titleContainer.GetFrameLevel and titleContainer:GetFrameLevel()) or 510
	frame:SetFrameStrata(borderFrame.GetFrameStrata and borderFrame:GetFrameStrata() or "HIGH")
	frame:SetFrameLevel(titleLevel + 15)
	frame:EnableMouse(true)
end

local function SetMapTitleShown(borderFrame, shown)
	if not borderFrame then
		return
	end
	local titleText = borderFrame.TitleContainer and borderFrame.TitleContainer.TitleText
	if titleText then
		titleText:SetShown(shown)
	end
	-- Pre-Dragonflight global; harmless if absent.
	if _G.WorldMapFrameTitleText then
		_G.WorldMapFrameTitleText:SetShown(shown)
	end
end

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

-- A read-only edit box that highlights its text on hover; Ctrl+C copies when focused.
local function LinkEditBox_OnKeyDown(self, key)
	if IsControlKeyDown() and key == "C" then
		return
	end
	if key == "ESCAPE" then
		self:ClearFocus()
	end
end

local function CreateLinkEditBox(parent, point, x, y, fontObject)
	local eb = CreateFrame("EditBox", nil, parent)
	eb:SetHeight(16)
	eb:SetPoint(point, x, y)
	eb:SetFontObject(fontObject)
	eb:SetBlinkSpeed(0)
	eb:SetAutoFocus(false)
	eb:EnableKeyboard(true)
	eb:SetScript("OnKeyDown", LinkEditBox_OnKeyDown)

	eb.hiddenText = eb:CreateFontString(nil, "ARTWORK", fontObject)
	eb.hiddenText:Hide()

	eb:SetScript("OnTextChanged", function(self, userInput)
		if userInput and self.linkText then
			self:SetText(self.linkText)
			self:HighlightText()
		end
	end)

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
		eb.linkText = url
		eb.hiddenText:SetText(url)
		eb:SetWidth(eb.hiddenText:GetStringWidth() + 90)

		local link = GetAchievementLink(achievementID)
		eb.tooltipText = link and (strmatch(link, "%[(.-)%]") .. "|n" .. COPY_HINT) or ""

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
	RaiseAboveTitleBar(eb, wmf.BorderFrame)
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
			eb.linkText = url
			eb.hiddenText:SetText(url)
			eb:SetWidth(eb.hiddenText:GetStringWidth() + 90)

			local link = GetQuestLink(questID)
			eb.tooltipText = link and (strmatch(link, "%[(.-)%]") .. "|n" .. COPY_HINT) or ""
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

	wmf:HookScript("OnShow", function()
		RaiseAboveTitleBar(eb, wmf.BorderFrame)
		UpdateQuestURL()
	end)
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------
local function OnWorldMapReady()
	InitQuestLink()
	local wmf = _G.WorldMapFrame
	if wmf and wmf.BorderFrame and questEditBox then
		RaiseAboveTitleBar(questEditBox, wmf.BorderFrame)
		SetMapTitleShown(wmf.BorderFrame, not ns.db.wowheadLink.enable)
	end
end

function WowheadLink:Setup()
	if self.started then
		return
	end
	if C_AddOns_IsAddOnLoaded and C_AddOns_IsAddOnLoaded("Leatrix_Maps") then
		return
	end
	self.started = true

	ns:RegisterAddOnLoadedCallback("Blizzard_AchievementUI", InitAchievementLink)
	ns:RegisterAddOnLoadedCallback("Blizzard_WorldMap", OnWorldMapReady)

	InitQuestLink()
	local wmf = _G.WorldMapFrame
	if wmf and wmf.BorderFrame then
		if questEditBox then
			RaiseAboveTitleBar(questEditBox, wmf.BorderFrame)
		end
		SetMapTitleShown(wmf.BorderFrame, not ns.db.wowheadLink.enable)
	end
end

-- Show/hide the boxes live when the option is toggled.
function WowheadLink:Refresh()
	local wmf = _G.WorldMapFrame
	if wmf and wmf.BorderFrame then
		SetMapTitleShown(wmf.BorderFrame, not ns.db.wowheadLink.enable)
		if questEditBox then
			RaiseAboveTitleBar(questEditBox, wmf.BorderFrame)
		end
	end
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
	if not ns.db.wowheadLink.enable then
		return
	end
	self:Setup()
	-- Setup is one-shot; Refresh re-shows boxes / hides map title on re-enable.
	self:Refresh()
end

function WowheadLink:OnDisable()
	-- hooksecurefunc / LOD callbacks stay; hide boxes and restore map title.
	self:Refresh()
end

function WowheadLink:OnSettingChanged(key)
	-- ApplyModuleSetting owns enable lifecycle (OnEnable/OnDisable call Refresh).
	if key == "enable" then
		return
	end
end

function WowheadLink:RegisterOptions(category, builder)
	builder:Checkbox(category, self, "enable", L["Enable Wowhead Links"], L["Add a copyable Wowhead link to the world map (tracked quest) and the achievement frame."])
end
