local NexEnhance, NE_CopyChat = ...

-- Sourced: NDui (siweia)

local string_gsub = string.gsub
local table_concat = table.concat
local tostring = tostring

local AUCTION_CATEGORY_QUEST_ITEMS = AUCTION_CATEGORY_QUEST_ITEMS
local BINDING_NAME_TOGGLECOMBATLOG = BINDING_NAME_TOGGLECOMBATLOG
local CLOSE = CLOSE
local COMBATLOGDISABLED = COMBATLOGDISABLED
local COMBATLOGENABLED = COMBATLOGENABLED
local CreateFrame = CreateFrame
local FCF_SetChatWindowFontSize = FCF_SetChatWindowFontSize
local GameTooltip = GameTooltip
local HEIRLOOMS = HEIRLOOMS
local InCombatLockdown = InCombatLockdown
local C_AddOns_IsAddOnLoaded = C_AddOns.IsAddOnLoaded
local OPTIONS_MENU = OPTIONS_MENU
local PlaySound = PlaySound
local QUESTS_LABEL = QUESTS_LABEL
local RELOADUI = RELOADUI
local ReloadUI = ReloadUI
local STATUS = STATUS
local ScrollFrameTemplate_OnMouseWheel = ScrollFrameTemplate_OnMouseWheel
local SlashCmdList = SlashCmdList
local StaticPopup_Show = StaticPopup_Show
local TASKS_COLON = TASKS_COLON
local UIErrorsFrame = UIErrorsFrame
local UIParent = UIParent

local lines = {}
local editBox
local frame
local menu

local leftButtonString = "|TInterface\\TutorialFrame\\UI-TUTORIAL-FRAME:16:12:0:0:512:512:1:76:218:318|t "
local rightButtonString = "|TInterface\\TutorialFrame\\UI-TUTORIAL-FRAME:16:12:0:0:512:512:1:76:321:421|t "

local function canChangeMessage(arg1, id)
	if id and arg1 == "" then
		return id
	end
end

local function isMessageProtected(msg)
	return msg and (msg ~= string_gsub(msg, "(:?|?)|K(.-)|k", canChangeMessage))
end

local function replaceMessage(msg, r, g, b)
	-- Convert the color values to a hex string
	local hexRGB = NE_CopyChat.RGBToHex(r, g, b)
	-- Replace the texture path or id with only the path/id
	msg = string.gsub(msg, "|T(.-):.-|t", "%1")
	-- Replace the atlas path or id with only the path/id
	msg = string.gsub(msg, "|A(.-):.-|a", "%1")
	-- Return the modified message with the hex color code added
	return string.format("%s%s|r", hexRGB, msg)
end

function NE_CopyChat:GetChatLines()
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

function NE_CopyChat:ChatCopy_OnClick(btn)
	if btn == "LeftButton" then
		if not frame:IsShown() then
			local chatframe = SELECTED_DOCK_FRAME
			local _, fontSize = chatframe:GetFont()
			FCF_SetChatWindowFontSize(chatframe, chatframe, 0.01)
			PlaySound(21968)
			frame:Show()

			local lineCt = NE_CopyChat.GetChatLines(chatframe)
			local text = table_concat(lines, "\n", 1, lineCt)
			FCF_SetChatWindowFontSize(chatframe, chatframe, fontSize)
			editBox:SetText(text)
		else
			frame:Hide()
		end
	end
end

function NE_CopyChat:ChatCopy_Create()
	frame = NE_CopyChat:CreateFrame("Frame", "NE_CopyChat", UIParent, "TooltipBackdropTemplate")
	frame:SetPoint("CENTER")
	frame:SetSize(700, 400)
	frame:Hide()
	frame:SetFrameStrata("DIALOG")
	NE_CopyChat.CreateMoverFrame(frame)

	frame.close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	frame.close:SetPoint("TOPRIGHT", frame)

	local scrollArea = CreateFrame("ScrollFrame", "NE_CopyChatScrollFrame", frame, "UIPanelScrollFrameTemplate")
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
	copy:SetPoint("BOTTOMRIGHT", _G.ChatFrame1, "BOTTOMRIGHT", 14, -6)
	copy:SetSize(16, 16)
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
		GameTooltip:AddDoubleLine(leftButtonString .. NE_CopyChat.L["Left Click"], "Copy Chat", 1, 1, 1)

		GameTooltip:Show()
	end)

	copy:SetScript("OnLeave", function(self)
		UIFrameFadeOut(self, 1, self:GetAlpha(), 0.25)

		if not GameTooltip:IsForbidden() then
			GameTooltip:Hide()
		end
	end)
end

function NE_CopyChat:PLAYER_LOGIN()
	self:ChatCopy_Create()
end
