--[[
	NexEnhance - Chat (core)
	-------------------------------------------------------------------------
	Mostly functional chat enhancements.

	Features:
	  * Tab key cycles SAY -> PARTY -> RAID -> INSTANCE -> GUILD
	  * Shift/Ctrl + mouse-wheel quick scroll (top/bottom, page)
	  * sticky whisper, whisper sound, keyword auto-invite
	  * a font-size submenu on the tab right-click menu
	  * optionally hide the social/menu buttons beside the chat window
	  * flatten the chat tab textures
	  * a clean edit box border, docked to the top, tinted by active channel

	Ported (functional parts only) from NDui's Chat module by siweia. Chat
	frames are not protected, so this is taint-safe.
--]]

-- luacheck: globals ChatTypeInfo Menu CURRENT_CHAT_FRAME_ID
local _, ns = ...
local F, C, L = ns.F, ns.C, ns.L

local _G = _G
local ipairs = ipairs
local strsub, strlower = string.sub, string.lower
local floor, format = math.floor, string.format
local CreateFrame, max = CreateFrame, math.max

-- A classic Blizzard tooltip-style border (gold edge + dark fill) for the box.
local EDITBOX_BACKDROP = {
	bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true,
	tileSize = 16,
	edgeSize = 16,
	insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

local IsInGroup, IsInRaid, IsInGuild = IsInGroup, IsInRaid, IsInGuild
local IsShiftKeyDown, IsControlKeyDown = IsShiftKeyDown, IsControlKeyDown
local IsPartyLFG = IsPartyLFG
local Ambiguate, GetTime, PlaySound = Ambiguate, GetTime, PlaySound
local ChatEdit_UpdateHeader = ChatEdit_UpdateHeader
local UnitIsGroupLeader, UnitIsGroupAssistant = UnitIsGroupLeader, UnitIsGroupAssistant
local hooksecurefunc = hooksecurefunc

ns:RegisterDefaults({
	chat = {
		enable = true,
		styleTabs = true,
		editBoxBorder = true,
		editBoxTop = true,
		colorEditBox = true,
		hideButtons = true,
		tabChannelSwitch = true,
		quickScroll = true,
		stickyWhisper = true,
		whisperSound = false,
		fontSizeMenu = true,
		autoInvite = false,
		inviteKeyword = "inv",
		guildInviteOnly = true,
	},
})

local Chat = ns:NewModule("Chat", "chat", { group = "chat", title = L["Chat"], order = 10 })

local cfg
local messageSoundID = SOUNDKIT and SOUNDKIT.TELL_MESSAGE
local chatEditBoxes = {}

local function RegisterEditBox(editBox)
	if editBox.__nexRegistered then return end
	editBox.__nexRegistered = true
	chatEditBoxes[#chatEditBoxes + 1] = editBox
end

local function UpdateEditBoxAnchor(editBox)
	if not cfg or not cfg.editBoxTop or not editBox then return end

	local owner = editBox.__nexOwner
	if not owner or owner:IsForbidden() then return end

	-- Docked frames don't all sit at the same top edge. When the Combat Log
	-- (ChatFrame2) is selected, Blizzard shoves that frame DOWN by the height of
	-- its quick-button bar (Blizzard_CombatLog_AdjustCombatLogHeight ->
	-- COMBATLOG:SetPoint("TOPLEFT", ..., -quickButtonHeight)). An edit box anchored
	-- to that frame's top rides down with it, landing on the tabs. Anchor docked
	-- edit boxes to the dock's primary frame (ChatFrame1) instead -- it never gets
	-- shoved, so the box stays put no matter which tab is active.
	local anchor = owner
	if owner.isDocked then
		local dock = _G["GeneralDockManager"]
		if dock and dock.primary then
			anchor = dock.primary
		end
	end

	editBox:ClearAllPoints()
	editBox:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", -2, 24)
	editBox:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", 2, 24)
end

local function UpdateAllEditBoxAnchors()
	for i = 1, #chatEditBoxes do
		UpdateEditBoxAnchor(chatEditBoxes[i])
	end
end

-- ---------------------------------------------------------------------------
-- Per-frame setup (behaviour only, no skinning)
-- ---------------------------------------------------------------------------
function Chat:QuickMouseScroll(dir)
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

function Chat:SetupChat(frame)
	if not frame or frame.__nexSetup then return end

	-- Let the chat window be dragged anywhere without being clamped to the screen edge.
	frame:SetClampRectInsets(0, 0, 0, 0)
	frame:SetClampedToScreen(false)

	if cfg.quickScroll then
		frame:HookScript("OnMouseWheel", Chat.QuickMouseScroll)
	end

	if cfg.hideButtons and frame.buttonFrame then
		frame.buttonFrame:SetAlpha(0)
	end

	-- Tab styling: strip the busy default tab textures for a flat look and
	-- nudge the tab label up one point so it reads a touch larger.
	if cfg.styleTabs then
		local tab = _G[frame:GetName() .. "Tab"]
		if tab then
			F.StripTextures(tab, 7)
			local tabText = tab.Text or _G[tab:GetName() .. "Text"]
			if tabText then
				local file, size, flags = tabText:GetFont()
				if file and size then
					tabText:SetFont(file, size + 2, flags)
				end
			end
		end
	end

	Chat:SetupEditBox(frame)

	frame.__nexSetup = true
end

-- ---------------------------------------------------------------------------
-- Edit box: replace Blizzard's chunky input border with a clean 1px border
-- and (optionally) dock it to the top of the chat window.
-- ---------------------------------------------------------------------------
function Chat:SetupEditBox(frame)
	local editBox = frame.editBox or _G[frame:GetName() .. "EditBox"]
	if not editBox then return end

	editBox.__nexOwner = frame
	RegisterEditBox(editBox)
	if editBox.__nexEditBox then
		UpdateEditBoxAnchor(editBox)
		return
	end

	if cfg.editBoxBorder then
		-- Strip the default border art (Left/Mid/Right + focus glow) and give
		-- the box a proper Blizzard tooltip-style border instead.
		F.StripTextures(editBox)

		local bg = CreateFrame("Frame", nil, editBox, "BackdropTemplate")
		bg:SetPoint("TOPLEFT", editBox, "TOPLEFT", 0, -3)
		bg:SetPoint("BOTTOMRIGHT", editBox, "BOTTOMRIGHT", 0, 3)
		bg:SetFrameLevel(max(0, editBox:GetFrameLevel() - 1))
		bg:SetBackdrop(EDITBOX_BACKDROP)
		bg:SetBackdropColor(0.06, 0.06, 0.06, 0.9)
		bg:SetBackdropBorderColor(1, 1, 1)
		editBox.nexBackdrop = bg
	end

	if cfg.editBoxTop then
		-- Lock the anchor at the source. Blizzard re-points the edit box from a
		-- few paths (notably selecting the Combat Log tab, which loads/sets up
		-- Blizzard_CombatLog and re-anchors the box after any tab hook would
		-- have run). Post-hooking SetPoint re-applies our anchor no matter who
		-- moves it; the re-entrancy guard stops our own SetPoint from looping.
		hooksecurefunc(editBox, "SetPoint", function(self)
			if self.__nexAnchoring or not cfg or not cfg.editBoxTop then return end
			self.__nexAnchoring = true
			UpdateEditBoxAnchor(self)
			self.__nexAnchoring = false
		end)
		UpdateEditBoxAnchor(editBox)
	end

	editBox:SetHeight(editBox:GetHeight() + 2)

	editBox.__nexEditBox = true
end

-- ---------------------------------------------------------------------------
-- Colour the edit box border by the active channel. When we've reskinned the
-- box we tint the clean backdrop border; otherwise we tint Blizzard's own art.
-- ---------------------------------------------------------------------------
-- Resolve the channel colour for the edit box's current chat type. The base
-- ChatTypeInfo["CHANNEL"] entry carries no r/g/b, so for channels we look up
-- the numbered "CHANNEL<id>" entry; returns nil when no real colour is known.
local function GetEditBoxColor(editBox)
	local chatType = editBox:GetAttribute("chatType")
	if not chatType then return end

	local info = ChatTypeInfo[chatType]
	if chatType == "CHANNEL" then
		local id = editBox:GetAttribute("channelTarget")
		if id and id > 0 then
			info = ChatTypeInfo["CHANNEL" .. id] or info
		end
	end

	if info and info.r then
		return info.r, info.g, info.b
	end
end

local function ColorEditBox(editBox)
	if not cfg or not cfg.colorEditBox then return end
	if not editBox or editBox:IsForbidden() then return end

	local r, g, b = GetEditBoxColor(editBox)
	if not r then return end

	if editBox.nexBackdrop then
		editBox.nexBackdrop:SetBackdropBorderColor(r, g, b)
		return
	end

	local name = editBox:GetName()
	local left, right, mid = _G[name .. "Left"], _G[name .. "Right"], _G[name .. "Mid"]
	if left then left:SetVertexColor(r, g, b) end
	if right then right:SetVertexColor(r, g, b) end
	if mid then mid:SetVertexColor(r, g, b) end
	if editBox.focusLeft then editBox.focusLeft:SetVertexColor(r, g, b) end
	if editBox.focusRight then editBox.focusRight:SetVertexColor(r, g, b) end
	if editBox.focusMid then editBox.focusMid:SetVertexColor(r, g, b) end
end

-- ---------------------------------------------------------------------------
-- Tab-key channel switching
-- ---------------------------------------------------------------------------
local cycles = {
	{ chatType = "SAY", IsActive = function(_, _) return true end },
	{ chatType = "PARTY", IsActive = function(_, _) return IsInGroup() end },
	{ chatType = "RAID", IsActive = function(_, _) return IsInRaid() end },
	{ chatType = "INSTANCE_CHAT", IsActive = function(_, _) return IsPartyLFG() end },
	{ chatType = "GUILD", IsActive = function(_, _) return IsInGuild() end },
	{ chatType = "SAY", IsActive = function(_, _) return true end },
}

local function SwitchToChannel(editbox, chatType)
	editbox:SetAttribute("chatType", chatType)
	ChatEdit_UpdateHeader(editbox)
end

function Chat:UpdateTabChannelSwitch()
	if not cfg.tabChannelSwitch then return end
	if strsub(self:GetText(), 1, 1) == "/" then return end

	local isShiftKeyDown = IsShiftKeyDown()
	local currentType = self:GetAttribute("chatType")
	if isShiftKeyDown and (currentType == "WHISPER" or currentType == "BN_WHISPER") then
		SwitchToChannel(self, "SAY")
		return
	end

	local numCycles = #cycles
	for i = 1, numCycles do
		if currentType == cycles[i].chatType then
			local from, to, step = i + 1, numCycles, 1
			if isShiftKeyDown then from, to, step = i - 1, 1, -1 end
			for j = from, to, step do
				local nextCycle = cycles[j]
				if nextCycle and nextCycle:IsActive(self) then
					SwitchToChannel(self, nextCycle.chatType)
					return
				end
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- Sticky whisper / whisper sound
-- ---------------------------------------------------------------------------
function Chat:ChatWhisperSticky()
	local sticky = cfg.stickyWhisper and 1 or 0
	if ChatTypeInfo["WHISPER"] then ChatTypeInfo["WHISPER"].sticky = sticky end
	if ChatTypeInfo["BN_WHISPER"] then ChatTypeInfo["BN_WHISPER"].sticky = sticky end
end

local whisperEvents = {
	CHAT_MSG_WHISPER = true,
	CHAT_MSG_BN_WHISPER = true,
}

function Chat:PlayWhisperSound(event, _, author)
	if not cfg.whisperSound then return end
	if F.IsSecret(author) then return end
	if not whisperEvents[event] or not messageSoundID then return end

	local currentTime = GetTime()
	if not self._soundTimer or currentTime > self._soundTimer then
		PlaySound(messageSoundID, "Master")
	end
	self._soundTimer = currentTime + 5
end

-- ---------------------------------------------------------------------------
-- Keyword auto-invite
-- ---------------------------------------------------------------------------
local InviteToGroup = C_PartyInfo and C_PartyInfo.InviteUnit
local BNInviteFriend = BNInviteFriend
local CanCooperateWithGameAccount = CanCooperateWithGameAccount
local C_BattleNet_GetAccountInfoByID = C_BattleNet and C_BattleNet.GetAccountInfoByID
local IsGuildMember = IsGuildMember

local function IsUnitInGuild(unitName)
	if not unitName then return end
	for i = 1, GetNumGuildMembers() do
		local name = GetGuildRosterInfo(i)
		if name and Ambiguate(name, "none") == Ambiguate(unitName, "none") then
			return true
		end
	end
end

function Chat:OnChatWhisper(event, ...)
	if not cfg.autoInvite then return end
	local msg, author, _, _, _, _, _, _, _, _, _, guid, presenceID = ...
	if F.IsSecret(msg) then return end
	local keyword = strlower(cfg.inviteKeyword or "")
	if keyword == "" or strlower(msg) ~= keyword then return end

	-- Only the leader/assistant can invite to an existing group.
	if IsInGroup() and not (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then return end

	if event == "CHAT_MSG_BN_WHISPER" then
		if not (C_BattleNet_GetAccountInfoByID and BNInviteFriend) then return end
		local accountInfo = C_BattleNet_GetAccountInfoByID(presenceID)
		local gameAccountInfo = accountInfo and accountInfo.gameAccountInfo
		local gameID = gameAccountInfo and gameAccountInfo.gameAccountID
		if gameID and gameAccountInfo and CanCooperateWithGameAccount(accountInfo) then
			local fullName = (gameAccountInfo.characterName or "") .. "-" .. (gameAccountInfo.realmName or "")
			if not cfg.guildInviteOnly or IsUnitInGuild(fullName) then
				BNInviteFriend(gameID)
			end
		end
	elseif InviteToGroup then
		if not cfg.guildInviteOnly or (guid and IsGuildMember and IsGuildMember(guid)) then
			InviteToGroup(author)
		end
	end
end

-- ---------------------------------------------------------------------------
-- Font-size submenu on the tab right-click menu
-- ---------------------------------------------------------------------------
local function SetupFontSizeMenu()
	if not (Menu and Menu.ModifyMenu) then return end

	local function IsSelected(height)
		local frame = FCF_GetCurrentChatFrame()
		if not frame then return false end
		local _, fontHeight = frame:GetFont()
		return height == floor(fontHeight + 0.5)
	end
	local function SetSelected(height)
		FCF_SetChatWindowFontSize(nil, FCF_GetChatFrameByID(CURRENT_CHAT_FRAME_ID), height)
	end

	Menu.ModifyMenu("MENU_FCF_TAB", function(_, rootDescription)
		local root = rootDescription ---@type any
		local submenu = root:CreateButton(C.InfoColor .. L["Font Size"] .. "|r")
		for i = 10, 22 do
			submenu:CreateRadio(format(FONT_SIZE_TEMPLATE, i), IsSelected, SetSelected, i)
		end
	end)
end

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------
function Chat:OnSettingChanged()
	if not cfg then return end
	self:ChatWhisperSticky()
end

function Chat:OnEnable()
	cfg = ns.db.chat
	if not cfg.enable then return end

	for i = 1, NUM_CHAT_WINDOWS do
		self:SetupChat(_G["ChatFrame" .. i])
	end

	-- Handle temporary (whisper/combat-log popout) windows as they open.
	hooksecurefunc("FCF_OpenTemporaryWindow", function()
		for _, chatFrameName in ipairs(CHAT_FRAMES) do
			local frame = _G[chatFrameName]
			if frame and frame.isTemporary then
				self:SetupChat(frame)
			end
		end
	end)

	if cfg.tabChannelSwitch and _G["ChatEdit_CustomTabPressed"] then
		hooksecurefunc("ChatEdit_CustomTabPressed", Chat.UpdateTabChannelSwitch)
	end

	if cfg.colorEditBox then
		hooksecurefunc("ChatEdit_UpdateHeader", ColorEditBox)
	end

	-- The Combat Log frame is load-on-demand: selecting its tab loads
	-- Blizzard_CombatLog and sets up its quick-button bar, which re-anchors the
	-- shared edit box. Re-skin that frame (and re-apply the anchor) once it
	-- exists so the box does not snap back below the tabs.
	if cfg.editBoxTop and _G["FCF_SelectDockFrame"] then
		hooksecurefunc("FCF_SelectDockFrame", UpdateAllEditBoxAnchors)
	end

	self:ChatWhisperSticky()

	ns:RegisterEvent("CHAT_MSG_WHISPER", function(event, ...) Chat:PlayWhisperSound(event, ...) end)
	ns:RegisterEvent("CHAT_MSG_BN_WHISPER", function(event, ...) Chat:PlayWhisperSound(event, ...) end)
	ns:RegisterEvent("CHAT_MSG_WHISPER", function(event, ...) Chat:OnChatWhisper(event, ...) end)
	ns:RegisterEvent("CHAT_MSG_BN_WHISPER", function(event, ...) Chat:OnChatWhisper(event, ...) end)

	if cfg.fontSizeMenu then
		SetupFontSizeMenu()
	end
end

function Chat:RegisterOptions(category, builder)
	builder:Checkbox(category, self, "enable", L["Enable Chat"], L["Enable the chat enhancements (reload to fully disable)."])
	builder:Checkbox(category, self, "styleTabs", L["Flatten Tabs"], L["Strip the busy default chat tab textures for a flat look (reload to apply)."])
	builder:Checkbox(category, self, "editBoxBorder", L["Edit Box Border"], L["Give the chat input a Blizzard tooltip-style border (reload to apply)."])
	builder:Checkbox(category, self, "editBoxTop", L["Edit Box on Top"], L["Dock the chat edit box to the top of the chat window (reload to apply)."])
	builder:Checkbox(category, self, "colorEditBox", L["Colour Edit Box"], L["Tint the edit box border to match the active chat channel (reload to apply)."])
	builder:Checkbox(category, self, "hideButtons", L["Hide Side Buttons"], L["Hide the social/menu buttons beside the chat window."])
	builder:Checkbox(category, self, "tabChannelSwitch", L["Tab Channel Switch"], L["Press Tab in an empty edit box to cycle chat channels."])
	builder:Checkbox(category, self, "quickScroll", L["Quick Scroll"], L["Shift + wheel jumps to top/bottom; Ctrl + wheel pages faster."])
	builder:Checkbox(category, self, "stickyWhisper", L["Sticky Whisper"], L["Keep the edit box in whisper mode after replying."])
	builder:Checkbox(category, self, "whisperSound", L["Whisper Sound"], L["Play a sound when you receive a whisper."])
	builder:Checkbox(category, self, "fontSizeMenu", L["Font Size Menu"], L["Add a font-size submenu to the chat tab right-click menu (reload to apply)."])
	builder:Checkbox(category, self, "autoInvite", L["Keyword Auto-Invite"], L["Invite players who whisper you the keyword below."])
	builder:Checkbox(category, self, "guildInviteOnly", L["Guild/Friends Only"], L["Only auto-invite guild members and Battle.net friends."])
end
