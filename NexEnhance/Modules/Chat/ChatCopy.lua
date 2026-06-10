--[[
	NexEnhance - Chat Copy
	-------------------------------------------------------------------------
	Adds a small button by the chat window that opens a copy frame containing
	the current chat window's text, ready to select and copy.

	Ported from NDui's Modules/Chat/Chatcopy.lua by siweia, adapted to the
	NexEnhance framework.
--]]

-- luacheck: globals ChatFontNormal
local _, ns = ...
local F, C, L = ns.F, ns.C, ns.L

local _G = _G
local gsub, format, tconcat, tostring = string.gsub, string.format, table.concat, tostring

ns:RegisterDefaults({
	chatCopy = {
		enable = true,
	},
})

local ChatCopy = ns:NewModule("ChatCopy", "chatCopy", { group = "chat", title = L["Chat Copy"], order = 20 })

-- A classic Blizzard tooltip-style border (gold edge + dark fill), matching the
-- chat edit box so the copy window looks like a native dialog.
local COPY_BACKDROP = C.Backdrops.window

local lines = {}
local frame, editBox

local function canChangeMessage(arg1, id)
	if id and arg1 == "" then return id end
end

local function isMessageProtected(msg)
	return msg and (msg ~= gsub(msg, "(:?|?)|K(.-)|k", canChangeMessage))
end

local function replaceMessage(msg, r, g, b)
	local hexRGB = "|c" .. F.RGBToHex(r, g, b)
	msg = gsub(msg, "|T(.-):.-|t", "")
	msg = gsub(msg, "|A(.-):.-|a", "")
	return format("%s%s|r", hexRGB, msg)
end

local function GetChatLines(chatFrame)
	local index = 1
	for i = 1, chatFrame:GetNumMessages() do
		local msg, r, g, b = chatFrame:GetMessageInfo(i)
		if msg and F.NotSecret(msg) and not isMessageProtected(msg) then
			r, g, b = r or 1, g or 1, b or 1
			lines[index] = tostring(replaceMessage(msg, r, g, b))
			index = index + 1
		end
	end
	return index - 1
end

local function CreateCopyFrame()
	frame = CreateFrame("Frame", "NexEnhanceChatCopy", UIParent, "BackdropTemplate")
	frame:SetPoint("CENTER")
	frame:SetSize(700, 400)
	frame:SetFrameStrata("DIALOG")
	frame:Hide()
	frame:EnableMouse(true)
	frame:SetMovable(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	if not F.CreateNineSlice(frame, { layout = "TooltipDefaultLayout", bg = { 0.06, 0.06, 0.06, 0.9 } }) then
		frame:SetBackdrop(COPY_BACKDROP)
		frame:SetBackdropColor(0.06, 0.06, 0.06, 0.9)
		frame:SetBackdropBorderColor(1, 1, 1)
	end

	frame.close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	frame.close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)

	local scrollArea = CreateFrame("ScrollFrame", "NexEnhanceChatCopyScroll", frame, "UIPanelScrollFrameTemplate")
	scrollArea:SetPoint("TOPLEFT", 12, -32)
	scrollArea:SetPoint("BOTTOMRIGHT", -30, 12)

	editBox = CreateFrame("EditBox", nil, frame)
	editBox:SetMultiLine(true)
	editBox:SetMaxLetters(99999)
	editBox:EnableMouse(true)
	editBox:SetAutoFocus(false)
	editBox:SetFontObject(ChatFontNormal)
	editBox:SetWidth(scrollArea:GetWidth())
	editBox:SetScript("OnEscapePressed", function() frame:Hide() end)
	scrollArea:SetScrollChild(editBox)
end

function ChatCopy:Toggle(chatFrame)
	if not frame then CreateCopyFrame() end
	if frame:IsShown() then
		frame:Hide()
		return
	end

	local count = GetChatLines(chatFrame)
	editBox:SetText(tconcat(lines, "\n", 1, count))
	frame:Show()
	editBox:SetCursorPosition(0)
	editBox:HighlightText()
end

local copyButton

local function CreateCopyButton(chatFrame)
	local button = CreateFrame("Button", nil, chatFrame)
	button:SetSize(16, 16)
	button:SetPoint("BOTTOMRIGHT", chatFrame, "BOTTOMRIGHT", 12, -2)
	button:SetAlpha(0.2)
	button:SetFrameStrata("HIGH")
	button.chatFrame = chatFrame

	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints()
	icon:SetTexture("Interface\\BUTTONS\\UI-GuildButton-PublicNote-Up")
	icon:SetBlendMode("ADD")
	button.icon = icon

	button:SetScript("OnEnter", function(self)
		self:SetAlpha(1)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(L["Chat Copy"])
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function(self)
		self:SetAlpha(0.2)
		GameTooltip:Hide()
	end)
	-- Copy whatever window the button is currently riding, not a captured one.
	button:SetScript("OnClick", function(self)
		ChatCopy:Toggle(self.chatFrame)
	end)

	return button
end

-- The button is a child of one chat frame, so it hides when that frame's tab is
-- deselected (the dock hides the whole frame). Move it onto the newly selected
-- window so a single, tidy button always rides the active tab.
local function UpdateButtonOwner(chatFrame)
	if not copyButton or not chatFrame then return end
	copyButton.chatFrame = chatFrame
	copyButton:SetParent(chatFrame)
	copyButton:ClearAllPoints()
	copyButton:SetPoint("BOTTOMRIGHT", chatFrame, "BOTTOMRIGHT", 12, -2)
	copyButton:SetFrameStrata("HIGH")
end

function ChatCopy:OnEnable()
	if not ns.db.chatCopy.enable then return end
	-- A single copy button on the primary chat window keeps things tidy.
	copyButton = CreateCopyButton(_G["ChatFrame1"])

	-- Follow the active tab. FCFDock_SelectWindow(dock, chatFrame) is called for
	-- every tab change; restrict to the General dock so a second dock can't steal
	-- the button.
	if _G["FCFDock_SelectWindow"] then
		hooksecurefunc("FCFDock_SelectWindow", function(dock, chatFrame)
			if dock == _G["GENERAL_CHAT_DOCK"] then
				UpdateButtonOwner(chatFrame)
			end
		end)
	end
end

function ChatCopy:RegisterOptions(category, builder)
	builder:Checkbox(category, self, "enable", L["Enable Chat Copy"], L["Add a button to copy the chat window's text (reload to disable)."])
end
