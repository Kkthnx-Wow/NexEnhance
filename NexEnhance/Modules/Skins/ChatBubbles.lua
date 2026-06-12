--[[
	NexEnhance - Chat Bubbles (skin)
	-------------------------------------------------------------------------
	Replaces the default chat-bubble art with the game's tooltip border and
	dark fill, matching the chat edit box, tinted per channel.

	Adapted from KkthnxUI by Josh "Kkthnx" Russell:
	  https://github.com/Kkthnx-Wow/KkthnxUI

	Integration notes:
	  * Chat bubbles are created on demand and recycled, so we poll the active
	    set on a throttled OnUpdate (driven by chat events) and style any we
	    have not seen yet. Purely cosmetic, so it is taint-safe.
--]]

local _, ns = ...
local F, L = ns.F, ns.L

local ipairs, pairs = ipairs, pairs
local CreateFrame = CreateFrame
local GetCVarBool = GetCVarBool
local C_ChatBubbles_GetAllChatBubbles = C_ChatBubbles.GetAllChatBubbles

ns:RegisterDefaults({
	chatBubbles = {
		enable = true,
	},
})

local ChatBubbles = ns:NewModule("ChatBubbles", "chatBubbles", { group = "skins", title = L["Chat Bubbles"], order = 30 })

-- Only chat (not nameplate) bubbles should be reskinned; these CVars say which
-- chat-bubble types the user has enabled, and gate the polling worker.
local bubbleCVars = {
	CHAT_MSG_SAY = "chatBubbles",
	CHAT_MSG_YELL = "chatBubbles",
	CHAT_MSG_MONSTER_SAY = "chatBubbles",
	CHAT_MSG_MONSTER_YELL = "chatBubbles",
	CHAT_MSG_PARTY = "chatBubblesParty",
	CHAT_MSG_PARTY_LEADER = "chatBubblesParty",
	CHAT_MSG_MONSTER_PARTY = "chatBubblesParty",
}

-- Tint the border to the message's text colour, which mirrors the chat
-- channel (white say, red yell, blue party, ...). Falls back to white.
local function UpdateBubbleBorder(chatBubble, frame)
	local bg = chatBubble.__nexBG
	if not bg then
		return
	end

	local r, g, b = 1, 1, 1
	local str = frame.String
	if str and str.GetTextColor then
		local tr, tg, tb = str:GetTextColor()
		r, g, b = tr or 1, tg or 1, tb or 1
	end

	bg:SetBackdropBorderColor(r, g, b)
end

local function ReskinBubble(chatBubble)
	local frame = chatBubble:GetChildren()
	if not frame or frame:IsForbidden() then
		return
	end

	if not chatBubble.__nexStyled then
		-- Drop Blizzard's nine-slice border/fill and the speech tail, then sit our
		-- own backdrop just behind the text so the message stays readable.
		frame:DisableDrawLayer("BORDER")
		frame:DisableDrawLayer("BACKGROUND")
		if frame.Tail then
			frame.Tail:SetAlpha(0)
		end

		local bg = CreateFrame("Frame", nil, chatBubble)
		local level = frame:GetFrameLevel()
		bg:SetFrameLevel(level > 0 and level - 1 or 0)
		bg:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -4)
		bg:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 4)
		-- Tooltip border + dark fill; tinted to the channel colour below.
		F.CreateTooltipBackdrop(bg, { edgeSize = 8 })

		chatBubble.__nexBG = bg.nexBackdrop
		chatBubble.__nexStyled = true
	end

	-- Re-applied on every poll so recycled bubbles pick up their new channel colour.
	UpdateBubbleBorder(chatBubble, frame)
end

local worker
local function CreateWorker()
	worker = CreateFrame("Frame")
	worker:Hide()

	local elapsed = 0
	worker:SetScript("OnUpdate", function(self, e)
		elapsed = elapsed + (e or 0)
		if elapsed < 0.1 then
			return
		end
		elapsed = 0

		local bubbles = C_ChatBubbles_GetAllChatBubbles()
		if bubbles then
			for _, chatBubble in ipairs(bubbles) do
				ReskinBubble(chatBubble)
			end
		end
		self:Hide()
	end)

	worker:SetScript("OnEvent", function(self, event)
		if GetCVarBool(bubbleCVars[event]) then
			elapsed = 0
			self:Show()
		end
	end)

	for event in pairs(bubbleCVars) do
		worker:RegisterEvent(event)
	end
end

-- Chat bubbles inherit the shared ChatBubbleFont object, so shrinking it once
-- downsizes every (recycled) bubble's text without per-bubble bookkeeping.
local FONT_REDUCTION = 4
local function ShrinkBubbleFont()
	local font = _G.ChatBubbleFont
	if not font or ChatBubbles.fontResized then
		return
	end

	local fontFile, fontSize, fontFlags = font:GetFont()
	if fontFile and fontSize then
		-- Never shrink below a legible floor (and never grow it).
		font:SetFont(fontFile, math.max(fontSize - FONT_REDUCTION, 8), fontFlags)
		ChatBubbles.fontResized = true
	end
end

function ChatBubbles:OnEnable()
	if not ns.db.chatBubbles.enable then
		return
	end
	if not worker then
		CreateWorker()
	end
	ShrinkBubbleFont()
end

function ChatBubbles:RegisterOptions(category, builder)
	builder:Checkbox(category, self, "enable", L["Enable Chat Bubble Border"], L["Give chat bubbles a clean Blizzard-style border (reload to disable)."])
end
