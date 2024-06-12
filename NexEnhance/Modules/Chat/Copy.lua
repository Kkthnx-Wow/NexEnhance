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

local frame, menu
local lines = {}
local editBox

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
			lines[index] = tostring(msg)
			index = index + 1
		end
	end

	return index - 1
end

function Module:ChatCopy_OnClick(btn)
	if btn == "LeftButton" then
		if not frame:IsShown() then
			local chatframe = SELECTED_DOCK_FRAME
			local _, fontSize = chatframe:GetFont()
			FCF_SetChatWindowFontSize(chatframe, chatframe, 0.01)
			PlaySound(21968)
			frame:Show()

			local lineCt = Module.GetChatLines(chatframe)
			local text = table_concat(lines, "\n", 1, lineCt)
			FCF_SetChatWindowFontSize(chatframe, chatframe, fontSize)
			editBox:SetText(text)
		else
			frame:Hide()
		end
	elseif btn == "RightButton" then
		-- B:TogglePanel(menu)
		-- C.db["Chat"]["ChatMenu"] = menu:IsShown()
	end
end

local function ResetChatAlertJustify(frame)
	frame:SetJustification("LEFT")
end

local CChatMenu = true
function Module:ChatCopy_CreateMenu()
	menu = CreateFrame("Frame", "NE_ChatMenu", UIParent)
	menu:SetSize(25, 100)
	menu:SetPoint("TOPLEFT", _G.ChatFrame1, "TOPRIGHT", 15, 0)
	menu:SetShown(CChatMenu)

	_G.ChatFrameMenuButton:ClearAllPoints()
	_G.ChatFrameMenuButton:SetPoint("TOP", menu)
	_G.ChatFrameMenuButton:SetParent(menu)
	_G.ChatFrameChannelButton:ClearAllPoints()
	_G.ChatFrameChannelButton:SetPoint("TOP", _G.ChatFrameMenuButton, "BOTTOM", 0, -4)
	_G.ChatFrameChannelButton:SetParent(menu)
	_G.ChatFrameToggleVoiceDeafenButton:SetParent(menu)
	_G.ChatFrameToggleVoiceMuteButton:SetParent(menu)
	_G.QuickJoinToastButton:SetParent(menu)

	_G.ChatAlertFrame:ClearAllPoints()
	_G.ChatAlertFrame:SetPoint("BOTTOMLEFT", _G.ChatFrame1Tab, "TOPLEFT", 5, 25)
	ResetChatAlertJustify(_G.ChatAlertFrame)
	hooksecurefunc(_G.ChatAlertFrame, "SetChatButtonSide", ResetChatAlertJustify)
end

function Module:ChatCopy_Create()
	frame = Module:CreateFrame("Frame", "Module", UIParent, "TooltipBackdropTemplate")
	frame:SetPoint("CENTER")
	frame:SetSize(700, 400)
	frame:Hide()
	frame:SetFrameStrata("DIALOG")
	Module.CreateMoverFrame(frame)

	frame.close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	frame.close:SetPoint("TOPRIGHT", frame)

	local scrollArea = CreateFrame("ScrollFrame", "ModuleScrollFrame", frame, "UIPanelScrollFrameTemplate")
	scrollArea:SetPoint("TOPLEFT", 12, -40)
	scrollArea:SetPoint("BOTTOMRIGHT", -30, 20)

	editBox = CreateFrame("EditBox", nil, frame)
	editBox:SetMultiLine(true)
	editBox:SetMaxLetters(99999)
	editBox:EnableMouse(true)
	editBox:SetAutoFocus(false)
	editBox:SetFontObject(GameFontNormal)
	editBox:SetWidth(scrollArea:GetWidth())
	editBox:SetHeight(400)
	editBox:SetScript("OnEscapePressed", function()
		frame:Hide()
	end)

	editBox:SetScript("OnTextChanged", function(_, userInput)
		if userInput then
			return
		end

		local _, max = scrollArea.ScrollBar:GetMinMaxValues()
		for _ = 1, max do
			ScrollFrameTemplate_OnMouseWheel(scrollArea, -1)
		end
	end)

	scrollArea:SetScrollChild(editBox)
	scrollArea:HookScript("OnVerticalScroll", function(self, offset)
		editBox:SetHitRectInsets(0, 0, offset, (editBox:GetHeight() - offset - self:GetHeight()))
	end)

	local copy = CreateFrame("Button", "NE_ChatCopyButton", UIParent)
	copy:SetPoint("BOTTOMRIGHT", _G.ChatFrame1, 15, -6)
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
