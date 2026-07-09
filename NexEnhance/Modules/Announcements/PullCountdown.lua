--[[
	NexEnhance - Pull Countdown
	-------------------------------------------------------------------------
	Group chat pull timer via /pc [seconds] (alias /jenkins). Chat-only — no
	Blizzard DoCountdown / DBM sync in v1 (Midnight-safe, no combat APIs).

	Second /pc while a countdown is running aborts it. Requires a group and
	out of combat. Target name is optional and secret-guarded in instances.
--]]

local _, ns = ...
local F, L = ns.F, ns.L

local tonumber = tonumber
local tostring = tostring
local format = string.format
local floor = math.floor
local IsInGroup = IsInGroup
local IsInRaid = IsInRaid
local IsPartyLFG = IsPartyLFG
local UnitAffectingCombat = UnitAffectingCombat
local UnitName = UnitName
local C_ChatInfo = C_ChatInfo
local C_Timer = C_Timer

ns:RegisterDefaults({
	pullCountdown = {
		enable = true,
		defaultSeconds = 10,
	},
})

local PullCountdown = ns:NewModule("PullCountdown", "pullCountdown", {
	group = "announcements",
	title = L["Pull Countdown"],
	order = 40,
	since = "1.6.0",
})

local ticker
local remaining
local slashRegistered = false

local function db()
	return ns.db.pullCountdown
end

-- Same routing RareAlert / LevelAnnouncer use for group chat.
local function GetGroupChannel()
	if IsPartyLFG and IsPartyLFG() then
		return "INSTANCE_CHAT"
	elseif IsInRaid() then
		return "RAID"
	elseif IsInGroup() then
		return "PARTY"
	end
end

local function SendGroup(msg)
	local channel = GetGroupChannel()
	if not channel then
		return
	end
	C_ChatInfo.SendChatMessage(msg, channel)
end

local function ResetTicker()
	if ticker then
		ticker:Cancel()
		ticker = nil
	end
	remaining = nil
end

local function SafeTargetName()
	local name = UnitName("target")
	if not name or F.IsSecret(name) then
		return ""
	end
	return name
end

function PullCountdown:Start(seconds)
	if not db().enable then
		F.Print(L["Pull Countdown is disabled."])
		return
	end

	if not IsInGroup() then
		F.Print(L["You must be in a group to start a pull countdown."])
		return
	end

	if UnitAffectingCombat("player") then
		F.Print(L["You can't start a pull countdown in combat."])
		return
	end

	-- Toggle-cancel: second /pc aborts the active ticker.
	if ticker then
		ResetTicker()
		SendGroup(L["Pull ABORTED!"])
		return
	end

	local delay = tonumber(seconds)
	if not delay or delay < 1 then
		delay = db().defaultSeconds or 10
	end
	-- Cap so a typo doesn't spam chat for minutes.
	if delay > 60 then
		delay = 60
	end
	delay = floor(delay)

	remaining = delay
	local target = SafeTargetName()
	if target ~= "" then
		SendGroup(format(L["Pulling %s in %d.."], target, delay))
	else
		SendGroup(format(L["Pulling in %d.."], delay))
	end

	-- 1s ticks so "10" means ~10 seconds wall time (Kkthnx used 1.5s — we don't).
	ticker = C_Timer.NewTicker(1, function()
		if not remaining then
			ResetTicker()
			return
		end
		remaining = remaining - 1
		if remaining > 0 then
			SendGroup(tostring(remaining) .. "..")
		else
			SendGroup(L["Pull!"])
			ResetTicker()
		end
	end)
end

local function RegisterSlash()
	if slashRegistered then
		return
	end
	slashRegistered = true
	_G.SLASH_NEXPULL1 = "/pc"
	_G.SLASH_NEXPULL2 = "/jenkins"
	_G.SlashCmdList["NEXPULL"] = function(msg)
		local mod = ns:GetModule("PullCountdown")
		if mod then
			mod:Start(msg)
		end
	end
end

function PullCountdown:OnEnable()
	-- Slash is registered at file load so /pc always responds (prints if disabled).
end

function PullCountdown:OnDisable()
	ResetTicker()
end

-- Register once at load — same pattern as /rl in ReloadUI.
RegisterSlash()

function PullCountdown:OnSettingChanged(key, value)
	if key == "enable" and not value then
		ResetTicker()
	end
end

function PullCountdown:RegisterOptions(category, builder)
	local _, enableInit = builder:Checkbox(
		category,
		self,
		"enable",
		L["Enable Pull Countdown"],
		L["Announce a pull timer in party/raid chat with /pc [seconds]. Second /pc cancels. Requires a group and out of combat."]
	)

	local _, secondsInit = builder:Slider(
		category,
		self,
		"defaultSeconds",
		L["Default Pull Seconds"],
		L["Seconds used when you type /pc with no number."],
		3,
		30,
		1
	)

	builder:DependsOn(secondsInit, enableInit)
end
