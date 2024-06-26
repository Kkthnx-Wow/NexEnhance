local _, Module = ...

-- Sourced: NDui (siweia)

local string_gsub = string.gsub
local table_concat = table.concat
local tostring = tostring

local CreateFrame = CreateFrame
local FCF_SetChatWindowFontSize = FCF_SetChatWindowFontSize
local GameTooltip = GameTooltip
local PlaySound = PlaySound
local ScrollFrameTemplate_OnMouseWheel = ScrollFrameTemplate_OnMouseWheel
local UIParent = UIParent

local chatFrame, chatMenu
local chatLines = {}
local chatEditBox

local leftButtonString = "|TInterface\\TutorialFrame\\UI-TUTORIAL-FRAME:16:12:0:0:512:512:1:76:218:318|t "

local function canChangeMessage(arg1, id)
	if id and arg1 == "" then
		return id
	end
end

local function isMessageProtected(msg)
	return msg and (msg ~= string_gsub(msg, "(:?|?)|K(.-)|k", canChangeMessage))
end

local function replaceMessage(msg, r, g, b)
	local hexRGB = Module.RGBToHex(r, g, b)
	msg = gsub(msg, "|T(.-):.-|t", "")
	msg = gsub(msg, "|A(.-):.-|a", "")
	return format("%s%s|r", hexRGB, msg)
end

function Module:GetChatLines()
	local index = 1
	for i = 1, self:GetNumMessages() do
		local msg, r, g, b = self:GetMessageInfo(i)
		if msg and not isMessageProtected(msg) then
			r, g, b = r or 1, g or 1, b or 1
			msg = replaceMessage(msg, r, g, b)
			chatLines[index] = tostring(msg)
			index = index + 1
		end
	end

	return index - 1
end

function Module:ChatCopy_OnClick(btn)
	if btn == "LeftButton" then
		if not chatFrame:IsShown() then
			local chatframe = SELECTED_DOCK_FRAME
			local _, fontSize = chatframe:GetFont()
			FCF_SetChatWindowFontSize(chatframe, chatframe, 0.01)
			PlaySound(21968)
			chatFrame:Show()

			local lineCt = Module.GetChatLines(chatframe)
			local text = table_concat(chatLines, "\n", 1, lineCt)
			FCF_SetChatWindowFontSize(chatframe, chatframe, fontSize)
			chatEditBox:SetText(text)
		else
			chatFrame:Hide()
		end
	elseif btn == "RightButton" then
		-- Module:TogglePanel(chatMenu)
		-- CChatMenu = chatMenu:IsShown()
	end
end

local function ResetChatAlertJustify(frame)
	frame:SetJustification("LEFT")
end

local CChatMenu = true
function Module:ChatCopy_CreateMenu()
	chatMenu = CreateFrame("Frame", "NE_ChatMenu", UIParent)
	chatMenu:SetSize(20, 20)
	chatMenu:SetPoint("TOPRIGHT", _G.ChatFrame1, 12, 0)
	chatMenu:SetShown(CChatMenu)

	_G.ChatFrameMenuButton:ClearAllPoints()
	_G.ChatFrameMenuButton:SetPoint("TOP", chatMenu)
	_G.ChatFrameMenuButton:SetParent(chatMenu)
	_G.ChatFrameChannelButton:ClearAllPoints()
	_G.ChatFrameChannelButton:SetPoint("TOP", _G.ChatFrameMenuButton, "BOTTOM", 0, -4)
	_G.ChatFrameChannelButton:SetParent(chatMenu)
	_G.ChatFrameToggleVoiceDeafenButton:SetParent(chatMenu)
	_G.ChatFrameToggleVoiceMuteButton:SetParent(chatMenu)
	_G.QuickJoinToastButton:SetParent(chatMenu)

	_G.ChatAlertFrame:ClearAllPoints()
	_G.ChatAlertFrame:SetPoint("BOTTOMLEFT", _G.ChatFrame1Tab, "TOPLEFT", 5, 25)
	ResetChatAlertJustify(_G.ChatAlertFrame)
	hooksecurefunc(_G.ChatAlertFrame, "SetChatButtonSide", ResetChatAlertJustify)
end

function Module:ChatCopy_Create()
	chatFrame = Module:CreateFrame("Frame", "Module", UIParent, "TooltipBackdropTemplate")
	chatFrame:SetPoint("CENTER")
	chatFrame:SetSize(700, 400)
	chatFrame:Hide()
	chatFrame:SetFrameStrata("DIALOG")
	Module.CreateMoverFrame(chatFrame)

	chatFrame.close = CreateFrame("Button", nil, chatFrame, "UIPanelCloseButton")
	chatFrame.close:SetPoint("TOPRIGHT", chatFrame)

	local scrollArea = CreateFrame("ScrollFrame", "ModuleScrollFrame", chatFrame, "UIPanelScrollFrameTemplate")
	scrollArea:SetPoint("TOPLEFT", 12, -40)
	scrollArea:SetPoint("BOTTOMRIGHT", -30, 20)

	chatEditBox = CreateFrame("EditBox", nil, chatFrame)
	chatEditBox:SetMultiLine(true)
	chatEditBox:SetMaxLetters(99999)
	chatEditBox:EnableMouse(true)
	chatEditBox:SetAutoFocus(false)
	chatEditBox:SetFontObject(GameFontNormal)
	chatEditBox:SetWidth(scrollArea:GetWidth())
	chatEditBox:SetHeight(400)
	chatEditBox:SetScript("OnEscapePressed", function()
		chatFrame:Hide()
	end)

	chatEditBox:SetScript("OnTextChanged", function(_, userInput)
		if userInput then
			return
		end

		local _, max = scrollArea.ScrollBar:GetMinMaxValues()
		for _ = 1, max do
			ScrollFrameTemplate_OnMouseWheel(scrollArea, -1)
		end
	end)

	scrollArea:SetScrollChild(chatEditBox)
	scrollArea:HookScript("OnVerticalScroll", function(self, offset)
		chatEditBox:SetHitRectInsets(0, 0, offset, (chatEditBox:GetHeight() - offset - self:GetHeight()))
	end)

	local copy = CreateFrame("Button", "NE_ChatCopyButton", UIParent)
	copy:SetPoint("BOTTOMRIGHT", _G.ChatFrame1, 12, -4)
	copy:SetSize(20, 20)
	copy:SetAlpha(0.25)

	copy.Texture = copy:CreateTexture(nil, "ARTWORK")
	copy.Texture:SetAllPoints()
	copy.Texture:SetTexture("Interface\\Buttons\\UI-GuildButton-PublicNote-Up")
	copy:RegisterForClicks("AnyUp")
	copy:SetScript("OnClick", self.ChatCopy_OnClick)

	copy:SetScript("OnEnter", function(self)
		UIFrameFadeIn(self, 0.25, self:GetAlpha(), 1)

		local anchor, _, xoff, yoff = "ANCHOR_RIGHT", self:GetParent(), 10, 5
		GameTooltip:SetOwner(self, anchor, xoff, yoff)
		GameTooltip:ClearLines()
		GameTooltip:AddDoubleLine(leftButtonString .. Module.L["Left Click"], "Copy Chat", 1, 1, 1)

		GameTooltip:Show()
	end)

	copy:SetScript("OnLeave", function(self)
		UIFrameFadeOut(self, 1, self:GetAlpha(), 0.25)

		if not GameTooltip:IsForbidden() then
			GameTooltip:Hide()
		end
	end)
end

function Module:PLAYER_LOGIN()
	self:ChatCopy_CreateMenu()
	self:ChatCopy_Create()
end
