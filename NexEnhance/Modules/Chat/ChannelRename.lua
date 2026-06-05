--[[
	NexEnhance - Chat Channels
	-------------------------------------------------------------------------
	Tidies chat output: abbreviates channel brackets ([1. General] -> [1],
	[Party] -> [P]), makes URLs clickable/copyable, and can prepend a
	timestamp.

	Inspired by NDui's Modules/Chat/ChannelRename.lua by siweia. NDui's master
	rewrites each message through the newest ChatFrameUtil API, which this
	client build does not fully expose; instead we wrap each frame's AddMessage,
	which is client-agnostic and far less fragile.
--]]

local _, ns = ...
local F, C, L = ns.F, ns.C, ns.L

local _G = _G
local gsub, format, strupper, strsub = string.gsub, string.format, string.upper, string.sub
local strmatch = string.match
local type, tostring, date = type, tostring, date

ns:RegisterDefaults({
	chatChannels = {
		enable = true,
		abbreviate = true,
		urls = true,
		timestamp = false,
	},
})

local ChatChannels = ns:NewModule("ChatChannels", "chatChannels", { group = "chat", title = L["Chat Channels"], order = 30 })

local cfg

-- ---------------------------------------------------------------------------
-- Channel abbreviation
-- ---------------------------------------------------------------------------
local groupAbbr = {
	PARTY = "P",
	PARTY_LEADER = "PL",
	PARTY_GUIDE = "PG",
	RAID = "R",
	RAID_LEADER = "RL",
	RAID_WARNING = "RW",
	INSTANCE_CHAT = "I",
	INSTANCE_CHAT_LEADER = "IL",
	GUILD = "G",
	OFFICER = "O",
}

-- "|Hchannel:ARG|h[Name]|h" -> abbreviated bracket, preserving the link target.
local function AbbrChannelName(channelArg, channelName)
	if strsub(channelArg, 1, 8) == "channel:" then
		-- Numbered custom channel: keep just the number.
		local id = strmatch(channelArg, "channel:(%d+)")
		if id then return "|Hchannel:" .. channelArg .. "|h[" .. id .. "]|h" end
	end

	local abbr = groupAbbr[strupper(channelArg)]
	if not abbr then
		-- Fall back to trimming "N. Name" down to the leading number if present.
		local id = strmatch(channelName, "^(%d+)%.")
		abbr = id or channelName
	end
	return "|Hchannel:" .. channelArg .. "|h[" .. abbr .. "]|h"
end

-- ---------------------------------------------------------------------------
-- URL highlighting
-- ---------------------------------------------------------------------------
local function ConvertLink(text, value)
	return "|Hurl:" .. tostring(value) .. "|h" .. C.InfoColor .. text .. "|r|h"
end

local function HighlightURL(prefix, url, suffix)
	return prefix .. ConvertLink("[" .. url .. "]", url) .. suffix
end

local function ApplyURLs(text)
	text = gsub(text, "(%s?)(%a+://[%w_/%.%?%%=~&%-'%-]+)(%s?)", HighlightURL)
	text = gsub(text, "(%s?)(www%.[%w_/%.%?%%=~&%-'%-]+)(%s?)", HighlightURL)
	text = gsub(text, "(%s?)([_%w%-%.~]+@[_%w%-]+%.[_%w%-%.]+)(%s?)", HighlightURL)
	return text
end

-- ---------------------------------------------------------------------------
-- Timestamp
-- ---------------------------------------------------------------------------
local function GetTimestamp()
	return format("|cff909090[%s]|r ", date("%H:%M"))
end

-- ---------------------------------------------------------------------------
-- AddMessage wrapper
-- ---------------------------------------------------------------------------
local function TransformText(text)
	if cfg.abbreviate then
		text = gsub(text, "|Hchannel:(.-)|h%[(.-)%]|h", AbbrChannelName)
	end
	if cfg.urls then
		text = ApplyURLs(text)
	end
	if cfg.timestamp then
		text = GetTimestamp() .. text
	end
	return text
end

local function WrappedAddMessage(frame, text, ...)
	if type(text) == "string" and F.NotSecret(text) then
		text = TransformText(text)
	end
	return frame.__nexOldAddMessage(frame, text, ...)
end

local function HookFrame(frame)
	if not frame or frame.__nexMsgHooked then return end
	frame.__nexOldAddMessage = frame.AddMessage
	frame.AddMessage = WrappedAddMessage
	frame.__nexMsgHooked = true
end

-- ---------------------------------------------------------------------------
-- URL click -> copy popup
-- ---------------------------------------------------------------------------
local function SetupURLCopy()
	if StaticPopupDialogs["NEXENHANCE_COPY_URL"] then return end
	StaticPopupDialogs["NEXENHANCE_COPY_URL"] = {
		text = L["Copy the link below:"],
		button1 = OKAY or "Okay",
		hasEditBox = true,
		editBoxWidth = 350,
		hideOnEscape = true,
		timeout = 0,
		whileDead = true,
		preferredIndex = 3,
		OnShow = function(self, data)
			local eb = self.editBox or (self.GetEditBox and self:GetEditBox())
			if eb then
				eb:SetText(data or "")
				eb:HighlightText()
				eb:SetFocus()
			end
		end,
		EditBoxOnEscapePressed = function(eb) eb:GetParent():Hide() end,
	}

	hooksecurefunc("SetItemRef", function(link)
		local ltype, value = strmatch(link, "^(%a+):(.+)$")
		if ltype == "url" and value then
			StaticPopup_Show("NEXENHANCE_COPY_URL", nil, nil, value)
		end
	end)
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------
function ChatChannels:OnEnable()
	cfg = ns.db.chatChannels
	if not cfg.enable then return end

	for _, chatFrameName in ipairs(CHAT_FRAMES) do
		HookFrame(_G[chatFrameName])
	end

	hooksecurefunc("FCF_OpenTemporaryWindow", function()
		for _, chatFrameName in ipairs(CHAT_FRAMES) do
			local frame = _G[chatFrameName]
			if frame and frame.isTemporary then
				HookFrame(frame)
			end
		end
	end)

	if cfg.urls then
		SetupURLCopy()
	end
end

function ChatChannels:RegisterOptions(category, builder)
	builder:Checkbox(category, self, "enable", L["Enable Chat Channels"], L["Tidy channel names, URLs and timestamps in chat (reload to fully disable)."])
	builder:Checkbox(category, self, "abbreviate", L["Abbreviate Channels"], L["Shorten channel brackets, e.g. [1. General] becomes [1]."])
	builder:Checkbox(category, self, "urls", L["Clickable URLs"], L["Make web links clickable and copyable (reload to apply)."])
	builder:Checkbox(category, self, "timestamp", L["Timestamps"], L["Prepend a [HH:MM] timestamp to each message."])
end
