local _, Module = ...

-- Lua Standard Functions
local ipairs = ipairs
local string_find = string.find
local string_gmatch = string.gmatch
local string_gsub = string.gsub
local string_len = string.len
local string_sub = string.sub

-- WoW API Functions
local Ambiguate = Ambiguate
local C_GuildInfo_IsGuildOfficer = C_GuildInfo.IsGuildOfficer
local ChatEdit_ChooseBoxForSend = ChatEdit_ChooseBoxForSend
local ChatFrame_SendTell = ChatFrame_SendTell
local GetChannelName = GetChannelName
local GetInstanceInfo = GetInstanceInfo
local GetTime = GetTime
local IsControlKeyDown = IsControlKeyDown
local IsInGroup = IsInGroup
local IsInRaid = IsInRaid
local IsShiftKeyDown = IsShiftKeyDown
local PlaySound = PlaySound
local SetCVar = SetCVar
local UnitName = UnitName
local hooksecurefunc = hooksecurefunc

-- WoW Global Variables
local CHAT_FRAMES = CHAT_FRAMES
local CHAT_OPTIONS = CHAT_OPTIONS
local GeneralDockManager = GeneralDockManager
local NUM_CHAT_WINDOWS = NUM_CHAT_WINDOWS
local SOUNDKIT = SOUNDKIT

local messageSoundID = SOUNDKIT.TELL_MESSAGE
local maxLines = 2048
Module.MuteCache = {}

local whisperEvents = {
	["CHAT_MSG_WHISPER"] = true,
	["CHAT_MSG_BN_WHISPER"] = true,
}

local function getGroupDistribution()
	local _, instanceType = GetInstanceInfo()
	if instanceType == "pvp" then
		return "/bg "
	end

	if IsInRaid() then
		return "/ra "
	end

	if IsInGroup() then
		return "/p "
	end

	return "/s "
end

local MIN_REPEAT_CHARACTERS = 5
local charCount = 0
local repeatedText

local function countLinkCharacters(text)
	charCount = charCount + (string_len(text) + 4)
end

local function editBoxOnTextChanged(self)
	local text = self:GetText()
	local len = string_len(text)

	if (not repeatedText or not string_find(text, repeatedText, 1, true)) and InCombatLockdown() then
		if len > MIN_REPEAT_CHARACTERS then
			local repeatChar = true
			for i = 1, MIN_REPEAT_CHARACTERS do
				local first = -1 - i
				if string.sub(text, -i, -i) ~= string.sub(text, first, first) then
					repeatChar = false
					break
				end
			end

			if repeatChar then
				repeatedText = text
				self:Hide()
				return
			end
		end
	end

	if len == 4 then
		if text == "/tt " then
			local name, realm = UnitName("target")
			if name then
				name = string_gsub(name, "%s", "")
				if realm and realm ~= "" then
					name = name .. "-" .. string_gsub(realm, "[%s%-]", "")
				end
			end

			if name then
				ChatFrame_SendTell(name, self.chatFrame)
			else
				UIErrorsFrame:AddMessage(Module.L["Invalid Target"])
			end
		elseif text == "/gr " then
			self:SetText(getGroupDistribution() .. string.sub(text, 5))
			ChatEdit_ParseText(self, 0)
		end
	end

	-- recalculate the character count correctly with hyperlinks in it, using gmatch so it matches multiple without gmatch
	charCount = 0
	for link in string_gmatch(text, "(|c%x-|H.-|h).-|h|r") do
		countLinkCharacters(link)
	end
	if charCount ~= 0 then
		len = len - charCount
	end

	local remainingCount = 255 - len
	if remainingCount >= 50 then
		self.characterCount:SetTextColor(0.74, 0.74, 0.74, 0.5) -- grey color
	elseif remainingCount >= 20 then
		self.characterCount:SetTextColor(1, 0.6, 0, 0.5) -- orange color
	else
		self.characterCount:SetTextColor(1, 0, 0, 0.5) -- red color
	end

	self.characterCount:SetText(len > 0 and (255 - len) or "")

	if repeatedText then
		repeatedText = nil
	end
end

function Module:TabSetAlpha(alpha)
	if self.glow:IsShown() and alpha ~= 1 then
		self:SetAlpha(1)
	elseif alpha < 0 then
		self:SetAlpha(0)
	end
end

local chatEditboxes = {}
local chatBottomBox = false
local function UpdateEditBoxAnchor(eb)
	local parent = eb.__owner
	eb:ClearAllPoints()

	if chatBottomBox then
		eb:SetPoint("TOPLEFT", parent, "BOTTOMLEFT", 4, -10 + 2)
		eb:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -4, -34 + -2)
	else
		eb:SetPoint("BOTTOMLEFT", parent, "TOPLEFT", 4, 26 + -2)
		eb:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -4, 50 + 2)
	end
end

function Module:ToggleEditBoxAnchor()
	for _, eb in pairs(chatEditboxes) do
		UpdateEditBoxAnchor(eb)
	end
end

local function CreateBackground(self)
	local frame = CreateFrame("Frame", nil, self, "TooltipBackdropTemplate")
	frame:SetPoint("TOPLEFT", self.Background, "TOPLEFT", -4, 4)
	frame:SetPoint("BOTTOMRIGHT", self.Background, "BOTTOMRIGHT", 4, -4)
	frame:SetFrameLevel(0)
	frame:SetShown(Module.db.profile.chat.Background)

	return frame
end

local function UpdateEditboxFont(editbox)
	editbox:SetFont(Module.Font[1], 13, "")
	editbox.header:SetFont(Module.Font[1], 13, "")
end

function Module:SkinChat()
	if not self or self.styled then
		return
	end

	local name = self:GetName()
	local font, fontSize = self:GetFont()
	self:SetFont(font, fontSize, "")
	self:SetClampRectInsets(0, 0, 0, 0)
	self:SetClampedToScreen(false)
	if self:GetMaxLines() < maxLines then
		self:SetMaxLines(maxLines)
	end

	self.__background = CreateBackground(self)

	local eb = _G[name .. "EditBox"]
	Module.RemoveTextures(eb, 2)
	eb:SetAltArrowKeyMode(false)
	eb:SetClampedToScreen(true)
	eb.__owner = self
	UpdateEditBoxAnchor(eb)
	UpdateEditboxFont(eb)
	tinsert(chatEditboxes, eb)
	eb:HookScript("OnTextChanged", editBoxOnTextChanged)

	Module.CreateBackdropFrame(eb)

	-- local backdrop = CreateFrame("Frame", nil, eb, "TooltipBackdropTemplate")
	-- backdrop:SetAllPoints(eb)
	-- backdrop:SetFrameLevel(eb:GetFrameLevel())
	-- eb.backdrop = backdrop

	local lang = _G[name .. "EditBoxLanguage"]
	lang:GetRegions():SetAlpha(0)
	lang:SetPoint("TOPLEFT", eb, "TOPRIGHT", 5, 0)
	lang:SetPoint("BOTTOMRIGHT", eb, "BOTTOMRIGHT", 29, 0)

	local backdrop2 = CreateFrame("Frame", nil, lang, "TooltipBackdropTemplate")
	backdrop2:SetAllPoints(lang)
	backdrop2:SetFrameLevel(lang:GetFrameLevel())
	lang.backdrop2 = backdrop2

	local tab = _G[name .. "Tab"]
	Module.RemoveTextures(tab, 7)
	tab:SetAlpha(1)
	tab.Text:SetFont(font, Module.Font[2] + 2, "")
	hooksecurefunc(tab, "SetAlpha", Module.TabSetAlpha)

	-- Character count
	local charCount = eb:CreateFontString(nil, "ARTWORK")
	charCount:SetFont(font, 12, "")
	charCount:SetPoint("TOPRIGHT", eb, "TOPRIGHT", -4, 0)
	charCount:SetPoint("BOTTOMRIGHT", eb, "BOTTOMRIGHT", -4, 0)
	charCount:SetJustifyH("CENTER")
	charCount:SetWidth(40)
	eb.characterCount = charCount

	Module.DisableUIElement(self.buttonFrame)
	Module:ToggleChatFrameTextures(self)

	self.oldAlpha = self.oldAlpha or 0 -- fix blizz error

	self:HookScript("OnMouseWheel", Module.QuickMouseScroll)

	self.styled = true
end

function Module:ToggleChatFrameTextures(frame)
	if Module.db.profile.chat.Background then
		frame:DisableDrawLayer("BORDER")
		frame:DisableDrawLayer("BACKGROUND")
	else
		frame:EnableDrawLayer("BORDER")
		frame:EnableDrawLayer("BACKGROUND")
	end
end

function Module:ToggleChatBackground()
	for _, chatFrameName in ipairs(CHAT_FRAMES) do
		local frame = _G[chatFrameName]
		if frame.__background then
			frame.__background:SetShown(Module.db.profile.chat.Background)
		end
		Module:ToggleChatFrameTextures(frame)
	end
end

-- Swith channels by Tab
local cycles = {
	{
		chatType = "SAY",
		IsActive = function()
			return true
		end,
	},

	{
		chatType = "PARTY",
		IsActive = function()
			return IsInGroup()
		end,
	},

	{
		chatType = "RAID",
		IsActive = function()
			return IsInRaid()
		end,
	},

	{
		chatType = "INSTANCE_CHAT",
		IsActive = function()
			return IsPartyLFG()
		end,
	},

	{
		chatType = "GUILD",
		IsActive = function()
			return IsInGuild()
		end,
	},

	{
		chatType = "OFFICER",
		IsActive = function()
			return C_GuildInfo_IsGuildOfficer()
		end,
	},

	{
		chatType = "CHANNEL",
		IsActive = function(_, editbox)
			if Module.InWorldChannel and Module.WorldChannelID then
				editbox:SetAttribute("channelTarget", Module.WorldChannelID)
				return true
			end
		end,
	},

	{
		chatType = "SAY",
		IsActive = function()
			return true
		end,
	},
}

-- Update editbox border color
function Module:UpdateEditBoxColor()
	-- if not C["Chat"].Enable then
	-- 	return
	-- end

	if IsAddOnLoaded("Prat-3.0") or IsAddOnLoaded("Chatter") or IsAddOnLoaded("BasicChatMods") or IsAddOnLoaded("Glass") then
		return
	end

	local editBox = ChatEdit_ChooseBoxForSend()
	local chatType = editBox:GetAttribute("chatType")
	local editBoxBorder = editBox.NE_Background

	if not chatType then
		return
	end

	-- Increase inset on right side to make room for character count text
	local insetLeft, insetRight, insetTop, insetBottom = editBox:GetTextInsets()
	editBox:SetTextInsets(insetLeft, insetRight + 18, insetTop, insetBottom)

	if editBoxBorder then
		if chatType == "CHANNEL" then
			local id = GetChannelName(editBox:GetAttribute("channelTarget"))

			if id == 0 then
				local r, g, b
				r, g, b = 1, 1, 1
				editBoxBorder:SetBackdropBorderColor(r, g, b)
			else
				local r, g, b = ChatTypeInfo[chatType .. id].r, ChatTypeInfo[chatType .. id].g, ChatTypeInfo[chatType .. id].b
				editBoxBorder:SetBackdropBorderColor(r, g, b)
			end
		else
			local r, g, b = ChatTypeInfo[chatType].r, ChatTypeInfo[chatType].g, ChatTypeInfo[chatType].b
			editBoxBorder:SetBackdropBorderColor(r, g, b)
		end
	end
end
hooksecurefunc("ChatEdit_UpdateHeader", Module.UpdateEditBoxColor)

function Module:SwitchToChannel(chatType)
	self:SetAttribute("chatType", chatType)
	ChatEdit_UpdateHeader(self)
end

function Module:UpdateTabChannelSwitch()
	-- if not C["Chat"].Enable then
	-- 	return
	-- end

	if IsAddOnLoaded("Prat-3.0") or IsAddOnLoaded("Chatter") or IsAddOnLoaded("BasicChatMods") or IsAddOnLoaded("Glass") then
		return
	end

	if string_sub(self:GetText(), 1, 1) == "/" then
		return
	end

	local isShiftKeyDown = IsShiftKeyDown()
	local currentType = self:GetAttribute("chatType")
	if isShiftKeyDown and (currentType == "WHISPER" or currentType == "BN_WHISPER") then
		Module.SwitchToChannel(self, "SAY")
		return
	end

	local numCycles = #cycles
	for i = 1, numCycles do
		local cycle = cycles[i]
		if currentType == cycle.chatType then
			local from, to, step = i + 1, numCycles, 1
			if isShiftKeyDown then
				from, to, step = i - 1, 1, -1
			end

			for j = from, to, step do
				local nextCycle = cycles[j]
				if nextCycle:IsActive() then
					Module.SwitchToChannel(self, nextCycle.chatType)
					return
				end
			end
		end
	end
end
hooksecurefunc("ChatEdit_CustomTabPressed", Module.UpdateTabChannelSwitch)

-- Quick Scroll
function Module:QuickMouseScroll(dir)
	-- if not C["Chat"].Enable then
	-- 	return
	-- end

	if IsAddOnLoaded("Prat-3.0") or IsAddOnLoaded("Chatter") or IsAddOnLoaded("BasicChatMods") or IsAddOnLoaded("Glass") then
		return
	end

	if dir > 0 then
		if IsShiftKeyDown() then
			self:ScrollToTop()
		elseif IsControlKeyDown() then
			self:ScrollUp()
			self:ScrollUp()
		end
	else
		if IsShiftKeyDown() then
			self:ScrollToBottom()
		elseif IsControlKeyDown() then
			self:ScrollDown()
			self:ScrollDown()
		end
	end
end

-- Sticky whisper
function Module:ChatWhisperSticky()
	--if C["Chat"].Sticky then
	ChatTypeInfo["WHISPER"].sticky = 1
	ChatTypeInfo["BN_WHISPER"].sticky = 1
	--else
	--ChatTypeInfo["WHISPER"].sticky = 0
	--ChatTypeInfo["BN_WHISPER"].sticky = 0
	--end
end

-- Tab colors
function Module:UpdateTabColors(selected)
	if selected then
		self.Text:SetTextColor(1, 0.8, 0)
		self.whisperIndex = 0
	else
		self.Text:SetTextColor(0.5, 0.5, 0.5)
	end

	if self.whisperIndex == 1 then
		self.glow:SetVertexColor(1, 0.5, 1)
	elseif self.whisperIndex == 2 then
		self.glow:SetVertexColor(0, 1, 0.96)
	else
		self.glow:SetVertexColor(1, 0.8, 0)
	end
end

function Module:UpdateTabEventColors(event)
	local tab = _G[self:GetName() .. "Tab"]
	local selected = GeneralDockManager.selected:GetID() == tab:GetID()

	if event == "CHAT_MSG_WHISPER" then
		tab.whisperIndex = 1
		Module.UpdateTabColors(tab, selected)
	elseif event == "CHAT_MSG_BN_WHISPER" then
		tab.whisperIndex = 2
		Module.UpdateTabColors(tab, selected)
	end
end

function Module:PlayWhisperSound(event, _, author)
	if whisperEvents[event] then
		local name = Ambiguate(author, "none")
		local currentTime = GetTime()

		if Module.MuteCache[name] == currentTime then
			return
		end

		if not self.soundTimer or currentTime > self.soundTimer then
			PlaySound(messageSoundID, "master")
		end

		self.soundTimer = currentTime + 5
	end
end

function Module:PLAYER_LOGIN()
	-- if not C["Chat"].Enable then
	-- 	return
	-- end

	if IsAddOnLoaded("Prat-3.0") or IsAddOnLoaded("Chatter") or IsAddOnLoaded("BasicChatMods") or IsAddOnLoaded("Glass") then
		return
	end

	for i = 1, NUM_CHAT_WINDOWS do
		local chatframe = _G["ChatFrame" .. i]
		Module.SkinChat(chatframe)
	end

	hooksecurefunc("FCF_OpenTemporaryWindow", function()
		for _, chatFrameName in ipairs(CHAT_FRAMES) do
			local frame = _G[chatFrameName]
			if frame.isTemporary then
				Module.SkinChat(frame)
			end
		end
	end)

	hooksecurefunc("FCFTab_UpdateColors", Module.UpdateTabColors)
	hooksecurefunc("FloatingChatFrame_OnEvent", Module.UpdateTabEventColors)
	hooksecurefunc("ChatFrame_MessageEventHandler", Module.PlayWhisperSound)

	-- Font size
	for i = 1, 15 do
		CHAT_FONT_HEIGHTS[i] = i + 9
	end

	-- Default
	if CHAT_OPTIONS then -- only flash whisper
		CHAT_OPTIONS.HIDE_FRAME_ALERTS = true
	end
	SetCVar("chatStyle", "classic")
	SetCVar("chatMouseScroll", 1) -- Enable mousescroll

	Module:ChatWhisperSticky()
end
