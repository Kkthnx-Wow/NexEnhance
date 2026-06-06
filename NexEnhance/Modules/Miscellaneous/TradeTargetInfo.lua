--[[
	NexEnhance - Trade Target Info
	-------------------------------------------------------------------------
	Adds a small line to the Trade window telling you at a glance whether the
	person you are trading with is a stranger, a friend or a guild member, and
	class/reaction-colours their name.

	Adapted from NDui by siweia:
	  https://github.com/siweia/NDui

	The GUID read is secret-value gated (Patch 12.0 safe).
--]]

---@diagnostic disable: undefined-field
local _, ns = ...
local F, L = ns.F, ns.L

local _G = _G
local hooksecurefunc = hooksecurefunc
local UnitGUID = UnitGUID
local IsGuildMember = IsGuildMember
local C_BattleNet_GetGameAccountInfoByGUID = C_BattleNet.GetGameAccountInfoByGUID
local C_FriendList_IsFriend = C_FriendList.IsFriend

local FRIEND = _G.FRIEND
local GUILD = _G.GUILD

ns:RegisterDefaults({
	tradeTarget = {
		enable = true,
	},
})

local TradeTarget = ns:NewModule("TradeTargetInfo", "tradeTarget", { group = "misc", title = L["Trade Target Info"], order = 20 })

local infoText

local function UpdateColor()
	local nameText = _G.TradeFrameRecipientNameText
	if not nameText then return end

	nameText:SetTextColor(F.UnitColor("NPC"))

	local guid = UnitGUID("NPC")
	if not guid or F.IsSecret(guid) then return end

	local text = "|cffff0000" .. L["Stranger"]
	if C_BattleNet_GetGameAccountInfoByGUID(guid) or C_FriendList_IsFriend(guid) then
		text = "|cffffff00" .. FRIEND
	elseif IsGuildMember(guid) then
		text = "|cff00ff00" .. GUILD
	end
	infoText:SetText(text)
end

function TradeTarget:Setup()
	if self.done or not _G.TradeFrame then return end
	self.done = true

	infoText = F.CreateFS(_G.TradeFrame, 16, "")
	infoText:ClearAllPoints()
	infoText:SetPoint("TOP", _G.TradeFrameRecipientNameText, "BOTTOM", 0, -5)

	hooksecurefunc("TradeFrame_Update", UpdateColor)
end

function TradeTarget:OnEnable()
	if not ns.db.tradeTarget.enable then return end
	self:Setup()
end

function TradeTarget:RegisterOptions(category, builder)
	builder:Checkbox(category, self, "enable", L["Enable Trade Target Info"], L["Show whether your trade partner is a stranger, friend or guild member, and colour their name (reload to disable)."])
end
