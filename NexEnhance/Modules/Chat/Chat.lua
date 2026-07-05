--[[
	NexEnhance - Chat (core)
	-------------------------------------------------------------------------
	Mostly functional chat enhancements.

	Features:
	  * Tab key cycles SAY -> PARTY -> RAID -> INSTANCE -> GUILD
	  * Shift/Ctrl + mouse-wheel quick scroll (top/bottom, page)
	  * optional auto scroll-back after scrolling up (0 = off by default)
	  * sticky whisper, whisper sound, flash taskbar icon on whisper
	  * /tt and /gr edit-box shortcuts, combat repeat-spam guard
	  * keyword auto-invite
	  * a font-size submenu on the tab right-click menu
	  * optionally hide the social/menu buttons beside the chat window
	  * flatten the chat tab textures
	  * a clean edit box border, docked to the top, tinted by active channel

	Chat frames are not protected — taint-safe.
--]]

-- luacheck: globals ChatTypeInfo Menu CURRENT_CHAT_FRAME_ID
local _, ns = ...
local F, C, L = ns.F, ns.C, ns.L

local _G = _G
local ipairs = ipairs
local strsub, strlower = string.sub, string.lower
local strlen, gmatch, gsub = string.len, string.gmatch, string.gsub
local floor, format = math.floor, string.format
local CreateFrame, max, min = CreateFrame, math.max, math.min
local UIParent = UIParent

-- WoW chat messages are capped at 255 bytes.
local MAX_CHAT_BYTES = 255

local IsInGroup, IsInRaid, IsInGuild = IsInGroup, IsInRaid, IsInGuild
local IsInInstance = IsInInstance
local IsShiftKeyDown, IsControlKeyDown = IsShiftKeyDown, IsControlKeyDown
local IsPartyLFG = IsPartyLFG
local InCombatLockdown = InCombatLockdown
local UnitExists, UnitName = UnitExists, UnitName
local GetNormalizedRealmName = GetNormalizedRealmName
local Ambiguate, GetTime, PlaySound = Ambiguate, GetTime, PlaySound
local FlashClientIcon = FlashClientIcon
local C_Timer_After = C_Timer.After
local ChatFrame_SendTell = ChatFrame_SendTell
local ChatFrameUtil = _G.ChatFrameUtil
local ChatEdit_ParseText = ChatEdit_ParseText
local UIErrorsFrame = UIErrorsFrame
local ChatEdit_UpdateHeader = ChatEdit_UpdateHeader
local UnitIsGroupLeader, UnitIsGroupAssistant = UnitIsGroupLeader, UnitIsGroupAssistant
local hooksecurefunc = hooksecurefunc

ns:RegisterDefaults({
	chat = {
		enable = true,
		background = 1, -- 1 = none, 2 = full backdrop, 3 = gradient
		styleTabs = true,
		editBoxBorder = true,
		editBoxTop = true,
		colorEditBox = true,
		hideEditBox = true,
		hideButtons = true,
		hideScrollBar = true,
		tabChannelSwitch = true,
		quickScroll = true,
		scrollDownInterval = 0, -- seconds after scroll-up before ScrollToBottom; 0 = off
		stickyWhisper = true,
		whisperSound = false,
		flashClientIcon = false,
		editShortcuts = true, -- /tt whisper target, /gr group channel prefix
		combatRepeatBlock = true,
		combatRepeatChars = 5,
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
local scrollTimers = {}
local MUTE_CACHE_WINDOW = 1

-- Forward declaration: SetupEditBox hooks each box's UpdateHeader to this.
local ColorEditBox

local function RegisterEditBox(editBox)
	if editBox.__nexRegistered then
		return
	end
	editBox.__nexRegistered = true
	chatEditBoxes[#chatEditBoxes + 1] = editBox
end

local function UpdateEditBoxAnchor(editBox)
	if not cfg or not cfg.editBoxTop or not editBox then
		return
	end

	local owner = editBox.__nexOwner
	if not owner or owner:IsForbidden() then
		return
	end

	-- Docked frames don't all sit at the same top edge. When the Combat Log
	-- (ChatFrame2) is selected, Blizzard shoves that frame DOWN by the height of
	-- its quick-button bar (Blizzard_CombatLog_AdjustCombatLogHeight). The edit
	-- box anchored to that frame rides down onto the General tab. Thanks, Blizzard.
	-- Incident (Chat/UIScale, Jun 2026): also broken by uiScale CVar + deferred apply.
	-- Fix: anchor docked edit boxes to GeneralDockManager.primary (ChatFrame1).
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
-- Chat window background. Two looks, switchable live without a reload:
--   * Full     : Blizzard tooltip border + dark fill (F.CreateTooltipBackdrop)
--   * Gradient : a horizontal dark fade with a thin brand-coloured top line
-- Both anchor to the frame's own .Background region -- Blizzard keeps that sized
-- and inset correctly via FloatingChatFrame_UpdateBackgroundAnchors, so we ride
-- along with it instead of doing any size maths. While a custom look is active we
-- hide Blizzard's faint default bg/border draw layers so they don't show through.
-- ---------------------------------------------------------------------------
local BG_NONE, BG_FULL, BG_GRADIENT = 1, 2, 3
local chatFrames = {}

local function ToggleDefaultTextures(frame)
	if cfg.background == BG_NONE then
		frame:EnableDrawLayer("BORDER")
		frame:EnableDrawLayer("BACKGROUND")
	else
		frame:DisableDrawLayer("BORDER")
		frame:DisableDrawLayer("BACKGROUND")
	end
end

local function ApplyBackground(frame)
	local mode = cfg.background or BG_NONE
	if frame.__nexBG then
		frame.__nexBG:SetShown(mode == BG_FULL)
	end
	if frame.__nexGradient then
		frame.__nexGradient:SetShown(mode == BG_GRADIENT)
	end
	ToggleDefaultTextures(frame)
end

function Chat:SetupBackground(frame)
	local region = frame.Background
	if not region or frame.__nexBG then
		return
	end

	-- Sit one level below the frame's text so messages always draw on top.
	local lvl = frame:GetFrameLevel()
	local baseLevel = lvl > 0 and lvl - 1 or 0

	local full = CreateFrame("Frame", nil, frame)
	full:SetFrameLevel(baseLevel)
	full:SetPoint("TOPLEFT", region, "TOPLEFT", 0, 0)
	full:SetPoint("BOTTOMRIGHT", region, "BOTTOMRIGHT", 0, 0)
	F.CreateTooltipBackdrop(full, { edgeSize = 12 })
	frame.__nexBG = full

	local grad = CreateFrame("Frame", nil, frame)
	grad:SetFrameLevel(baseLevel)
	grad:SetPoint("TOPLEFT", region, "TOPLEFT", 0, 0)
	grad:SetPoint("BOTTOMRIGHT", region, "BOTTOMRIGHT", 0, 0)
	local fill = F.SetGradient(grad, "H", 0, 0, 0, 0.6, 0)
	if fill then
		fill:SetAllPoints(grad)
	end
	local brand = C.Colors.brand
	local line = F.SetGradient(grad, "H", brand[1], brand[2], brand[3], 0.7, 0, nil, C.Mult)
	if line then
		line:SetPoint("BOTTOMLEFT", grad, "TOPLEFT", 0, 0)
		line:SetPoint("BOTTOMRIGHT", grad, "TOPRIGHT", 0, 0)
	end
	frame.__nexGradient = grad

	chatFrames[#chatFrames + 1] = frame
	ApplyBackground(frame)
end

function Chat:UpdateBackgrounds()
	for i = 1, #chatFrames do
		ApplyBackground(chatFrames[i])
	end
end

-- ---------------------------------------------------------------------------
-- Per-frame setup (behaviour only, no skinning)
-- ---------------------------------------------------------------------------
local function CancelScrollTimer(frame)
	local timer = scrollTimers[frame]
	if timer and timer.Cancel then
		timer:Cancel()
	end
	scrollTimers[frame] = nil
end

local function ScheduleScrollToBottom(frame)
	local interval = cfg and cfg.scrollDownInterval or 0
	if interval <= 0 then
		return
	end
	CancelScrollTimer(frame)
	scrollTimers[frame] = C_Timer_After(interval, function()
		scrollTimers[frame] = nil
		if frame and frame.ScrollToBottom then
			frame:ScrollToBottom()
		end
	end)
end

local function OnChatMouseWheel(frame, delta)
	if not cfg or not delta then
		return
	end

	-- Optional return-to-bottom after scrolling up (off when interval is 0).
	if delta > 0 and not IsShiftKeyDown() and cfg.scrollDownInterval and cfg.scrollDownInterval > 0 then
		ScheduleScrollToBottom(frame)
	end

	if not cfg.quickScroll then
		return
	end

	-- The modifier shortcuts below are invisible until someone stumbles on them,
	-- so the first time the chat is wheeled we point them out (once, account-wide).
	F.ShowHelpTip(frame, "ChatQuickScroll", L["ChatQuickScrollHelp"])

	if delta > 0 then
		if IsShiftKeyDown() then
			CancelScrollTimer(frame)
			frame:ScrollToTop()
		elseif IsControlKeyDown() then
			frame:ScrollUp()
			frame:ScrollUp()
		end
	else
		if IsShiftKeyDown() then
			CancelScrollTimer(frame)
			frame:ScrollToBottom()
		elseif IsControlKeyDown() then
			frame:ScrollDown()
			frame:ScrollDown()
		end
	end
end

function Chat:SetupChat(frame)
	if not frame or frame.__nexSetup then
		return
	end

	-- Let the chat window be dragged anywhere without being clamped to the screen edge.
	frame:SetClampRectInsets(0, 0, 0, 0)
	frame:SetClampedToScreen(false)

	if cfg.quickScroll or (cfg.scrollDownInterval and cfg.scrollDownInterval > 0) then
		frame:HookScript("OnMouseWheel", OnChatMouseWheel)
	end

	if cfg.hideButtons and frame.buttonFrame then
		frame.buttonFrame:SetAlpha(0)
	end

	-- The scroll bar and jump-to-bottom button are pure clutter: mouse-wheel
	-- scrolling (plus our quick-scroll) already covers everything they do.
	if cfg.hideScrollBar then
		if frame.ScrollBar then
			frame.ScrollBar:Kill()
		end
		if frame.ScrollToBottomButton then
			frame.ScrollToBottomButton:Kill()
		end
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

	Chat:SetupBackground(frame)
	Chat:SetupEditBox(frame)

	frame.__nexSetup = true
end

-- ---------------------------------------------------------------------------
-- Edit-box shortcuts (/tt, /gr) and combat repeat-spam guard.
-- ---------------------------------------------------------------------------
local function GetGroupChatPrefix()
	local _, instanceType = IsInInstance()
	if instanceType == "pvp" or instanceType == "arena" then
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

local function GetTargetTellName()
	if not UnitExists("target") then
		return
	end
	local name, realm = UnitName("target")
	if not name or F.IsSecret(name) then
		return
	end
	name = gsub(name, "%s", "")
	if realm and realm ~= "" and realm ~= GetNormalizedRealmName() then
		name = format("%s-%s", name, realm)
	end
	return name
end

local function SendTellToTarget(editBox)
	local name = GetTargetTellName()
	if not name then
		if UIErrorsFrame then
			UIErrorsFrame:AddMessage(L["Invalid Target"], 1, 0.2, 0.2, 1)
		end
		return
	end
	local chatFrame = editBox.chatFrame
	if ChatFrameUtil and ChatFrameUtil.SendTell then
		ChatFrameUtil.SendTell(name, chatFrame)
	elseif ChatFrame_SendTell then
		ChatFrame_SendTell(name, chatFrame)
	end
end

local function ParseEditBoxText(editBox)
	if editBox.ParseText then
		editBox:ParseText(0)
	elseif ChatEdit_ParseText then
		ChatEdit_ParseText(editBox, 0)
	end
end

local function OnEditBoxUserInput(editBox)
	local text = editBox:GetText()
	local len = strlen(text)

	if cfg.combatRepeatBlock and InCombatLockdown() then
		local minRepeat = cfg.combatRepeatChars or 5
		if len > minRepeat then
			local repeatChar = true
			for i = 1, minRepeat do
				local tail = strsub(text, -i, -i)
				local prev = strsub(text, -1 - i, -1 - i)
				if tail ~= prev then
					repeatChar = false
					break
				end
			end
			if repeatChar and not editBox.__nexRepeatHide then
				editBox.__nexRepeatHide = true
				editBox:Hide()
				editBox.__nexRepeatHide = false
				return
			end
		end
	end

	if not cfg.editShortcuts or len ~= 4 then
		return
	end

	if text == "/tt " then
		SendTellToTarget(editBox)
	elseif text == "/gr " then
		editBox:SetText(GetGroupChatPrefix() .. strsub(text, 5))
		ParseEditBoxText(editBox)
	end
end

-- ---------------------------------------------------------------------------
-- Remaining-character counter. Hyperlinks (|cFFxxxxxx|H...|h[name]|h|r) cost
-- far more bytes on the wire than they read as, so discount that escape-sequence
-- overhead to show a count closer to what actually fits.
-- ---------------------------------------------------------------------------
local function UpdateEditBoxCharCount(editBox)
	local counter = editBox.nexCharCount
	if not counter then
		return
	end

	local text = editBox:GetText()
	local textLen = strlen(text)

	local linkOverhead = 0
	for link in gmatch(text, "(|c%x-|H.-|h).-|h|r") do
		linkOverhead = linkOverhead + (strlen(link) + 4)
	end
	if linkOverhead ~= 0 then
		textLen = textLen - linkOverhead
	end

	if textLen <= 0 then
		counter:SetText("")
		return
	end

	local remaining = MAX_CHAT_BYTES - textLen
	if remaining >= 50 then
		counter:SetTextColor(0.74, 0.74, 0.74)
	elseif remaining >= 20 then
		counter:SetTextColor(1, 0.6, 0)
	else
		counter:SetTextColor(1, 0, 0)
	end
	counter:SetText(remaining)
end

-- ---------------------------------------------------------------------------
-- Edit box: replace Blizzard's chunky input border with a clean 1px border
-- and (optionally) dock it to the top of the chat window.
-- ---------------------------------------------------------------------------
function Chat:SetupEditBox(frame)
	local editBox = frame.editBox or _G[frame:GetName() .. "EditBox"]
	if not editBox then
		return
	end

	editBox.__nexOwner = frame
	RegisterEditBox(editBox)
	if editBox.__nexEditBox then
		UpdateEditBoxAnchor(editBox)
		return
	end

	-- Disable Alt+Arrow stepping through the input so those keys pass through as
	-- camera/movement modifiers, and keep the box on-screen if anchored loosely.
	editBox:SetAltArrowKeyMode(false)
	editBox:SetClampedToScreen(true)

	if cfg.editBoxBorder then
		-- Strip the default border art (Left/Mid/Right + focus glow) and give
		-- the box a proper Blizzard tooltip-style border instead. Pass 2 to keep
		-- region index 2 — the blinking text cursor is a texture region, and
		-- clearing every region (the default) leaves the caret invisible while
		-- typing. Pass 2 to StripTextures to keep it.
		F.StripTextures(editBox, 2)

		local bg = CreateFrame("Frame", nil, editBox)
		bg:SetPoint("TOPLEFT", editBox, "TOPLEFT", 0, 0)
		bg:SetPoint("BOTTOMRIGHT", editBox, "BOTTOMRIGHT", 12, 0)
		bg:SetFrameLevel(max(0, editBox:GetFrameLevel() - 1))
		-- Tooltip border + dark fill; ColorEditBox tints the border per channel.
		F.CreateTooltipBackdrop(bg, { edgeSize = 12 })
		editBox.nexBackdrop = bg.nexBackdrop
	end

	if cfg.editBoxTop then
		-- Lock the anchor at the source. Blizzard re-points the edit box from a
		-- few paths (notably selecting the Combat Log tab, which loads/sets up
		-- Blizzard_CombatLog and re-anchors the box after any tab hook would
		-- have run). Post-hooking SetPoint re-applies our anchor no matter who
		-- moves it; the re-entrancy guard stops our own SetPoint from looping.
		hooksecurefunc(editBox, "SetPoint", function(self)
			if self.__nexAnchoring or not cfg or not cfg.editBoxTop then
				return
			end
			self.__nexAnchoring = true
			UpdateEditBoxAnchor(self)
			self.__nexAnchoring = false
		end)
		UpdateEditBoxAnchor(editBox)
	end

	if cfg.hideEditBox then
		-- Keep the box hidden until it's actually in use, instead of leaving a
		-- faded "IM style" input bar lingering over the chat (and, when docked
		-- to the top, over the tabs). Show on focus, hide again when it loses
		-- focus empty, and whenever a tab is clicked.
		editBox:Hide()
		editBox:HookScript("OnEditFocusGained", function(self)
			self:Show()
		end)
		editBox:HookScript("OnEditFocusLost", function(self)
			if self:GetText() == "" then
				self:Hide()
			end
		end)

		local tab = _G[frame:GetName() .. "Tab"]
		if tab then
			tab:HookScript("OnClick", function()
				editBox:Hide()
			end)
		end
	end

	if cfg.colorEditBox and editBox.UpdateHeader then
		-- Blizzard refreshes the active channel through the edit box's own
		-- UpdateHeader in most paths, so hooking it per-box is far more reliable
		-- than the global ChatEdit_UpdateHeader wrapper (which many internal
		-- paths skip).
		hooksecurefunc(editBox, "UpdateHeader", ColorEditBox)
		ColorEditBox(editBox)
	end

	-- Remaining-character counter, parked just past the right edge of the box so
	-- it never overlaps what you're typing.
	local counter = F.CreateFS(editBox, 12, nil, "ARTWORK")
	counter:ClearAllPoints()
	counter:SetPoint("LEFT", editBox, "RIGHT", -24, 0)
	counter:SetJustifyH("CENTER")
	counter:SetWidth(40)
	counter:SetText("")
	editBox.nexCharCount = counter

	editBox:HookScript("OnTextChanged", function(self, userInput)
		if userInput then
			OnEditBoxUserInput(self)
		end
		UpdateEditBoxCharCount(self)
	end)
	editBox:HookScript("OnEditFocusLost", function(self)
		if self.nexCharCount then
			self.nexCharCount:SetText("")
		end
	end)

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
	if not chatType then
		return
	end

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

function ColorEditBox(editBox)
	if not cfg or not cfg.colorEditBox then
		return
	end
	if not editBox or editBox:IsForbidden() then
		return
	end

	local r, g, b = GetEditBoxColor(editBox)
	if not r then
		-- No channel colour (e.g. an unnumbered CHANNEL): fall back to the
		-- neutral border so a previous channel's tint doesn't linger.
		r, g, b = 1, 1, 1
	end

	if editBox.nexBackdrop then
		editBox.nexBackdrop:SetBackdropBorderColor(r, g, b)
		return
	end

	local name = editBox:GetName()
	local left, right, mid = _G[name .. "Left"], _G[name .. "Right"], _G[name .. "Mid"]
	if left then
		left:SetVertexColor(r, g, b)
	end
	if right then
		right:SetVertexColor(r, g, b)
	end
	if mid then
		mid:SetVertexColor(r, g, b)
	end
	if editBox.focusLeft then
		editBox.focusLeft:SetVertexColor(r, g, b)
	end
	if editBox.focusRight then
		editBox.focusRight:SetVertexColor(r, g, b)
	end
	if editBox.focusMid then
		editBox.focusMid:SetVertexColor(r, g, b)
	end
end

-- ---------------------------------------------------------------------------
-- Battle.net toast pop-up
--   Pin the friend/online toast to a movable anchor above the chat's
--   top-left corner and register it with Edit Mode. The toast re-points
--   itself whenever it shows, so a guarded SetPoint hook keeps it on our
--   anchor no matter what.
-- ---------------------------------------------------------------------------
local function SetupBNToast()
	local toast = _G["BNToastFrame"]
	if not toast or toast.__nexMover then
		return
	end
	toast.__nexMover = true

	local width, height = toast:GetSize()
	if not width or width < 1 then
		width, height = 244, 80
	end

	local mover = CreateFrame("Frame", nil, UIParent)
	mover:SetSize(width, height)

	-- Default just above the chat window's top-left corner, sitting a little
	-- higher than the Quick Join button so the two don't overlap. Tracked live
	-- via onPlace so it follows the chat until the user drags it in Edit Mode.
	local function placeBNToast(m)
		m:ClearAllPoints()
		local chat = _G["ChatFrame1"]
		if chat then
			m:SetPoint("BOTTOMLEFT", chat, "TOPLEFT", -4, 120)
		else
			m:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 20, 432)
		end
	end

	F.CreateMover(mover, "bnToast", L["Battle.net Pop-up"], "BOTTOMLEFT", 0, 0, placeBNToast)

	local function reanchor()
		if toast.__nexAnchoring then
			return
		end
		toast.__nexAnchoring = true
		toast:ClearAllPoints()
		toast:SetPoint("BOTTOMLEFT", mover, "BOTTOMLEFT", 0, 0)
		toast.__nexAnchoring = false
	end

	hooksecurefunc(toast, "SetPoint", reanchor)
	reanchor()
end

-- ---------------------------------------------------------------------------
-- Quick Join toast button
--   The social/quick-join notification button lives at the chat's corner by
--   default. Give it its own Edit Mode mover so it can be dragged anywhere,
--   keeping the same guarded-SetPoint trick as the BN toast since Blizzard
--   re-anchors it whenever the chat dock updates. Guarded SetPoint hook keeps
--   it on our mover.
-- ---------------------------------------------------------------------------
local function SetupQuickJoinToast()
	local button = _G["QuickJoinToastButton"]
	if not button or button.__nexMover then
		return
	end
	button.__nexMover = true

	local width, height = button:GetSize()
	if not width or width < 1 then
		width, height = 40, 40
	end

	local mover = CreateFrame("Frame", nil, UIParent)
	mover:SetSize(width, height)

	-- Default just above the chat window's top-left corner. Tracked live via
	-- onPlace so it follows the chat until the user drags it in Edit Mode.
	local function placeQuickJoin(m)
		m:ClearAllPoints()
		local chat = _G["ChatFrame1"]
		if chat then
			m:SetPoint("BOTTOMLEFT", chat, "TOPLEFT", -4, 80)
		else
			m:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 20, 356)
		end
	end

	F.CreateMover(mover, "quickJoinToast", L["Quick Join Button"], "BOTTOMLEFT", 0, 0, placeQuickJoin)

	local function reanchor()
		if button.__nexAnchoring then
			return
		end
		button.__nexAnchoring = true
		button:ClearAllPoints()
		button:SetPoint("BOTTOMLEFT", mover, "BOTTOMLEFT", 0, 0)
		button.__nexAnchoring = false
	end

	hooksecurefunc(button, "SetPoint", reanchor)
	reanchor()
end

-- ---------------------------------------------------------------------------
-- Tab-key channel switching
-- ---------------------------------------------------------------------------
local cycles = {
	{
		chatType = "SAY",
		IsActive = function(_, _)
			return true
		end,
	},
	{
		chatType = "PARTY",
		IsActive = function(_, _)
			return IsInGroup()
		end,
	},
	{
		chatType = "RAID",
		IsActive = function(_, _)
			return IsInRaid()
		end,
	},
	{
		chatType = "INSTANCE_CHAT",
		IsActive = function(_, _)
			return IsPartyLFG()
		end,
	},
	{
		chatType = "GUILD",
		IsActive = function(_, _)
			return IsInGuild()
		end,
	},
	{
		chatType = "SAY",
		IsActive = function(_, _)
			return true
		end,
	},
}

local function SwitchToChannel(editbox, chatType)
	editbox:SetAttribute("chatType", chatType)
	ChatEdit_UpdateHeader(editbox)
	ColorEditBox(editbox)
end

function Chat:UpdateTabChannelSwitch()
	if not cfg.tabChannelSwitch then
		return
	end
	if strsub(self:GetText(), 1, 1) == "/" then
		return
	end

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
			if isShiftKeyDown then
				from, to, step = i - 1, 1, -1
			end
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
	if ChatTypeInfo["WHISPER"] then
		ChatTypeInfo["WHISPER"].sticky = sticky
	end
	if ChatTypeInfo["BN_WHISPER"] then
		ChatTypeInfo["BN_WHISPER"].sticky = sticky
	end
end

local whisperEvents = {
	CHAT_MSG_WHISPER = true,
	CHAT_MSG_BN_WHISPER = true,
}

function Chat:PlayWhisperSound(event, _, author)
	if not cfg.whisperSound then
		return
	end
	if F.IsSecret(author) then
		return
	end
	if not whisperEvents[event] or not messageSoundID then
		return
	end

	local currentTime = GetTime()
	local name = Ambiguate(author, "none")
	local mutedAt = ns.ChatMuteCache and ns.ChatMuteCache[name]
	if mutedAt and currentTime - mutedAt <= MUTE_CACHE_WINDOW then
		return
	end

	if not self._soundTimer or currentTime > self._soundTimer then
		PlaySound(messageSoundID, "Master")
	end
	self._soundTimer = currentTime + 5
end

function Chat:FlashOnWhisper(event, _, author)
	if not cfg.flashClientIcon or not FlashClientIcon then
		return
	end
	if F.IsSecret(author) then
		return
	end
	if not whisperEvents[event] then
		return
	end
	FlashClientIcon()
end

-- ---------------------------------------------------------------------------
-- Keyword auto-invite
-- ---------------------------------------------------------------------------
local InviteToGroup = C_PartyInfo and C_PartyInfo.InviteUnit
local C_BattleNet_InviteFriend = C_BattleNet and C_BattleNet.InviteFriend
local CanCooperateWithGameAccount = CanCooperateWithGameAccount
local CanGroupWithAccount = CanGroupWithAccount
local C_BattleNet_GetAccountInfoByID = C_BattleNet and C_BattleNet.GetAccountInfoByID
local C_BattleNet_GetGameAccountInfoByGUID = C_BattleNet and C_BattleNet.GetGameAccountInfoByGUID
-- CHAT_MSG_WHISPER hands us a player GUID, so resolve Battle.net friendship
-- through the game-account lookup (same trust check as Automation/AutoInvite).
local C_FriendList_IsFriend = C_FriendList and C_FriendList.IsFriend
local IsGuildMember = IsGuildMember
local strtrim = _G.strtrim
local BNET_CLIENT_WOW = BNET_CLIENT_WOW

local function IsUnitInGuild(unitName)
	if not unitName then
		return
	end
	for i = 1, GetNumGuildMembers() do
		local name = GetGuildRosterInfo(i)
		if name and Ambiguate(name, "none") == Ambiguate(unitName, "none") then
			return true
		end
	end
end

local function IsTrustedInviteSender(guid, unitName, accountInfo)
	if accountInfo then
		return true -- Battle.net whisper from a known account.
	end
	if guid and not F.IsSecret(guid) then
		if IsGuildMember and IsGuildMember(guid) then
			return true
		end
		if C_FriendList_IsFriend and C_FriendList_IsFriend(guid) then
			return true
		end
		if C_BattleNet_GetGameAccountInfoByGUID and C_BattleNet_GetGameAccountInfoByGUID(guid) then
			return true
		end
	end
	return IsUnitInGuild(unitName)
end

-- CHAT_MSG_BN_WHISPER payload field 13 is bnSenderID (account id), field 12 is the
-- whispering character GUID. GetAccountInfoByID needs both or gameAccountInfo can
-- point at the wrong client / miss the sender entirely.
local function ResolveBNWhisperGameAccount(bnSenderID, senderGUID)
	if not bnSenderID or bnSenderID == 0 then
		return nil
	end

	local wowGUID = (senderGUID and F.NotSecret(senderGUID)) and senderGUID or nil
	local accountInfo = C_BattleNet_GetAccountInfoByID and C_BattleNet_GetAccountInfoByID(bnSenderID, wowGUID)
	local gameAccountInfo = accountInfo and accountInfo.gameAccountInfo

	if (not gameAccountInfo or not gameAccountInfo.gameAccountID or gameAccountInfo.gameAccountID == 0) and wowGUID and C_BattleNet_GetGameAccountInfoByGUID then
		gameAccountInfo = C_BattleNet_GetGameAccountInfoByGUID(wowGUID)
	end

	if not gameAccountInfo or not gameAccountInfo.gameAccountID or gameAccountInfo.gameAccountID == 0 then
		return nil
	end

	if BNET_CLIENT_WOW and gameAccountInfo.clientProgram and gameAccountInfo.clientProgram ~= BNET_CLIENT_WOW then
		return nil
	end

	return gameAccountInfo, accountInfo
end

local function CanInviteBNGameAccount(gameAccountInfo, accountInfo)
	if not gameAccountInfo or not gameAccountInfo.isOnline then
		return false
	end
	if not gameAccountInfo.realmID or gameAccountInfo.realmID == 0 then
		return false
	end
	-- Incident (Chat BN invite, Jul 2026): CanCooperateWithGameAccount is same-faction
	-- only and blocked valid cross-faction BN whisper invites. Prefer Blizzard's friend
	-- restriction helper when available; otherwise allow any online WoW realm character.
	if CanGroupWithAccount and accountInfo and accountInfo.bnetAccountID then
		return CanGroupWithAccount(accountInfo.bnetAccountID)
	end
	if CanCooperateWithGameAccount and accountInfo then
		return CanCooperateWithGameAccount(accountInfo)
	end
	return true
end

function Chat:OnChatWhisper(event, ...)
	if not cfg.autoInvite then
		return
	end
	local msg, author, _, _, _, _, _, _, _, _, _, guid, bnSenderID = ...
	if F.IsSecret(msg) then
		return
	end
	msg = strtrim(msg or "")
	local keyword = strlower(cfg.inviteKeyword or "")
	if keyword == "" or strlower(msg) ~= keyword then
		return
	end

	-- Only the leader/assistant can invite to an existing group.
	if IsInGroup() and not (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then
		return
	end

	if event == "CHAT_MSG_BN_WHISPER" then
		if not C_BattleNet_InviteFriend then
			return
		end
		local gameAccountInfo, accountInfo = ResolveBNWhisperGameAccount(bnSenderID, guid)
		if not gameAccountInfo or not CanInviteBNGameAccount(gameAccountInfo, accountInfo) then
			return
		end
		local fullName = (gameAccountInfo.characterName or "") .. "-" .. (gameAccountInfo.realmName or "")
		if not cfg.guildInviteOnly or IsTrustedInviteSender(guid, fullName, accountInfo) then
			C_BattleNet_InviteFriend(gameAccountInfo.gameAccountID)
		end
	elseif InviteToGroup then
		if not cfg.guildInviteOnly or IsTrustedInviteSender(guid, author) then
			InviteToGroup(author)
		end
	end
end

-- ---------------------------------------------------------------------------
-- Font-size submenu on the tab right-click menu
-- ---------------------------------------------------------------------------
local function SetupFontSizeMenu()
	if not (Menu and Menu.ModifyMenu) then
		return
	end

	local function IsSelected(height)
		local frame = FCF_GetCurrentChatFrame()
		if not frame then
			return false
		end
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
function Chat:OnSettingChanged(key)
	if not cfg then
		return
	end
	if key == "background" then
		self:UpdateBackgrounds()
		return
	end
	self:ChatWhisperSticky()
end

function Chat:OnUIScaleApplied()
	if not cfg or not cfg.enable then
		return
	end
	if cfg.editBoxTop then
		UpdateAllEditBoxAnchors()
	end
end

function Chat:OnInitialize()
	ns.Debug.BindModule(self, "chat", {
		title = L["Chat"],
		expectations = {
			{
				name = "editBoxTop uses primary dock anchor when docked",
				test = function()
					if not (ns.db and ns.db.chat and ns.db.chat.editBoxTop) then
						return true
					end
					local cf1 = _G.ChatFrame1
					local eb = cf1 and cf1.editBox
					if not (eb and cf1.isDocked) then
						return true
					end
					local dock = _G.GeneralDockManager
					if not (dock and dock.primary) then
						return true
					end
					local _, rel = eb:GetPoint(1)
					return rel == dock.primary
				end,
				detail = "edit box should anchor to dock.primary, not Combat Log frame",
			},
		},
		dump = function()
			local c = ns.db and ns.db.chat
			F.Print(format("  enable=%s editBoxTop=%s background=%s", tostring(c and c.enable), tostring(c and c.editBoxTop), tostring(c and c.background)))
			local dock = _G.GeneralDockManager
			F.Print(format("  dock primary=%s selected=%s", dock and dock.primary and dock.primary:GetName() or "nil", dock and dock.selected and dock.selected:GetName() or "nil"))
			for i = 1, min(NUM_CHAT_WINDOWS or 10, 10) do
				local f = _G["ChatFrame" .. i]
				if f and f.editBox then
					local p, rel = f.editBox:GetPoint(1)
					F.Print(format("  ChatFrame%d editBox -> %s %s", i, tostring(p), rel and rel:GetName() or "nil"))
				end
			end
		end,
	})
end

function Chat:OnEnable()
	cfg = ns.db.chat
	if not cfg.enable then
		return
	end

	ns:RegisterCallback("UIScaleApplied", "OnUIScaleApplied", self)

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

	-- The Combat Log frame is load-on-demand: selecting its tab loads
	-- Blizzard_CombatLog and sets up its quick-button bar, which re-anchors the
	-- shared edit box. Re-skin that frame (and re-apply the anchor) once it
	-- exists so the box does not snap back below the tabs.
	if cfg.editBoxTop and _G["FCF_SelectDockFrame"] then
		hooksecurefunc("FCF_SelectDockFrame", UpdateAllEditBoxAnchors)
	end

	SetupBNToast()
	SetupQuickJoinToast()

	self:ChatWhisperSticky()

	ns:RegisterEvent("CHAT_MSG_WHISPER", function(event, ...)
		Chat:PlayWhisperSound(event, ...)
		Chat:FlashOnWhisper(event, ...)
		Chat:OnChatWhisper(event, ...)
	end)
	ns:RegisterEvent("CHAT_MSG_BN_WHISPER", function(event, ...)
		Chat:PlayWhisperSound(event, ...)
		Chat:FlashOnWhisper(event, ...)
		Chat:OnChatWhisper(event, ...)
	end)

	if cfg.fontSizeMenu then
		SetupFontSizeMenu()
	end
end

function Chat:RegisterOptions(category, builder)
	local function FormatScrollDownInterval(value)
		if not value or value <= 0 then
			return L["Off"]
		end
		return tostring(value)
	end

	local _, enableInit = builder:Checkbox(category, self, "enable", L["Enable Chat"], L["Enable the chat enhancements (reload to fully disable)."])
	local _, bgInit = builder:Dropdown(category, self, "background", L["Chat Background"], L["Show a background behind the chat window."], {
		{ value = 1, label = L["None"] },
		{ value = 2, label = L["Full Background"] },
		{ value = 3, label = L["Gradient"] },
	})
	local _, tabsInit = builder:Checkbox(category, self, "styleTabs", L["Flatten Tabs"], L["Strip the busy default chat tab textures for a flat look (reload to apply)."])
	local _, boxBorderInit = builder:Checkbox(category, self, "editBoxBorder", L["Edit Box Border"], L["Give the chat input a Blizzard tooltip-style border (reload to apply)."])
	local _, boxTopInit = builder:Checkbox(category, self, "editBoxTop", L["Edit Box on Top"], L["Dock the chat edit box to the top of the chat window (reload to apply)."])
	local _, colorBoxInit = builder:Checkbox(category, self, "colorEditBox", L["Colour Edit Box"], L["Tint the edit box border to match the active chat channel (reload to apply)."])
	local _, hideEditBoxInit = builder:Checkbox(category, self, "hideEditBox", L["Hide Edit Box When Inactive"], L["Keep the chat edit box hidden until you focus it (reload to apply)."])
	local _, hideButtonsInit = builder:Checkbox(category, self, "hideButtons", L["Hide Side Buttons"], L["Hide the social/menu buttons beside the chat window."])
	local _, hideScrollInit = builder:Checkbox(category, self, "hideScrollBar", L["Hide Scroll Bar"], L["Remove the scroll bar and jump-to-bottom button (reload to restore)."])
	local _, tabSwitchInit = builder:Checkbox(category, self, "tabChannelSwitch", L["Tab Channel Switch"], L["Press Tab in an empty edit box to cycle chat channels."])
	local _, scrollInit = builder:Checkbox(category, self, "quickScroll", L["Quick Scroll"], L["Shift + wheel jumps to top/bottom; Ctrl + wheel pages faster."])
	local _, scrollDownInit = builder:Slider(category, self, "scrollDownInterval", L["Scroll-Down Interval"], L["After scrolling up, return to the bottom after this many seconds (0 = off)."], 0, 120, 5, FormatScrollDownInterval)
	local _, stickyInit = builder:Checkbox(category, self, "stickyWhisper", L["Sticky Whisper"], L["Keep the edit box in whisper mode after replying."])
	local _, whisperSoundInit = builder:Checkbox(category, self, "whisperSound", L["Whisper Sound"], L["Play a sound when you receive a whisper."])
	local _, flashInit = builder:Checkbox(category, self, "flashClientIcon", L["Flash Client Icon"], L["Flash the WoW taskbar icon when you receive a whisper."])
	local _, shortcutsInit = builder:Checkbox(category, self, "editShortcuts", L["Edit Box Shortcuts"], L["Type /tt then space to whisper your target; /gr then space for the group channel prefix."])
	local _, repeatInit = builder:Checkbox(category, self, "combatRepeatBlock", L["Combat Repeat Block"], L["Hide the edit box if you paste the same character repeatedly during combat."])
	local _, repeatCharsInit = builder:Slider(category, self, "combatRepeatChars", L["Repeat Character Count"], L["How many identical trailing characters trigger the combat repeat block."], 3, 20, 1)
	local _, fontMenuInit = builder:Checkbox(category, self, "fontSizeMenu", L["Font Size Menu"], L["Add a font-size submenu to the chat tab right-click menu (reload to apply)."])

	builder:Header(L["Keyword Auto-Invite"])
	local _, autoInviteInit = builder:Checkbox(category, self, "autoInvite", L["Enable Keyword Auto-Invite"], L["Invite players who whisper you your keyword."])
	local _, keywordInit = builder:EditBox(category, self, "inviteKeyword", L["Invite Keyword"], L["When Keyword Auto-Invite is enabled, anyone who whispers you this exact word is invited to your group."], 200, function(text)
		text = strtrim(text or "")
		if text == "" then
			F.Print(L["Invite keyword cleared."])
		else
			F.Print(L["Invite keyword set to:"], text)
		end
		return text
	end)
	local _, guildOnlyInit = builder:Checkbox(category, self, "guildInviteOnly", L["Guild/Friends Only"], L["Only auto-invite guild members and Battle.net friends."])

	-- All chat tweaks rely on the module being on.
	if bgInit then
		builder:DependsOn(bgInit, enableInit)
	end
	builder:DependsOn(tabsInit, enableInit)
	builder:DependsOn(boxBorderInit, enableInit)
	builder:DependsOn(boxTopInit, enableInit)
	builder:DependsOn(colorBoxInit, enableInit)
	builder:DependsOn(hideEditBoxInit, enableInit)
	builder:DependsOn(hideButtonsInit, enableInit)
	builder:DependsOn(hideScrollInit, enableInit)
	builder:DependsOn(tabSwitchInit, enableInit)
	builder:DependsOn(scrollInit, enableInit)
	builder:DependsOn(scrollDownInit, enableInit)
	builder:DependsOn(stickyInit, enableInit)
	builder:DependsOn(whisperSoundInit, enableInit)
	builder:DependsOn(flashInit, enableInit)
	builder:DependsOn(shortcutsInit, enableInit)
	builder:DependsOn(repeatInit, enableInit)
	builder:DependsOn(repeatCharsInit, repeatInit)
	builder:DependsOn(fontMenuInit, enableInit)

	builder:DependsOn(keywordInit, autoInviteInit)
	builder:DependsOn(guildOnlyInit, autoInviteInit)
end
