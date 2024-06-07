local NexEnhance, NE_Cooldowns = ...

-- Importing required functions
local pairs, format, floor, strfind = pairs, format, floor, strfind
local GetTime, GetActionCooldown, tonumber = GetTime, GetActionCooldown, tonumber

-- Constants for cooldown display
local FONT_SIZE = 19
local MIN_DURATION = 2.5 -- Minimum duration to show cooldown text
local MIN_SCALE = 0.2 -- Minimum scale to show cooldown counts
local ICON_SIZE = 36 -- Standard icon size

-- Time constants for formatting
local day, hour, minute = 86400, 3600, 60

-- Tables for managing cooldowns
local hideNumbers = {} -- Cooldowns to hide
local active = {} -- Active cooldowns
local hooked = {} -- Hooked cooldowns

function NE_Cooldowns.FormattedTimer(s, modRate)
	if s >= day then
		return format("%d" .. NE_Cooldowns.MyColor .. "d", s / day + 0.5), s % day
	elseif s > hour then
		return format("%d" .. NE_Cooldowns.MyColor .. "h", s / hour + 0.5), s % hour
	elseif s >= minute then
		if s < NE_Cooldowns.db.profile.actionbars.MmssTH then
			return format("%d:%.2d", s / minute, s % minute), s - floor(s)
		else
			return format("%d" .. NE_Cooldowns.MyColor .. "m", s / minute + 0.5), s % minute
		end
	else
		local colorStr = (s < 3 and "|cffff0000") or (s < 10 and "|cffffff00") or "|cffcccc33"
		if s < NE_Cooldowns.db.profile.actionbars.TenthTH then
			return format(colorStr .. "%.1f|r", s), (s - format("%.1f", s)) / modRate
		else
			return format(colorStr .. "%d|r", s + 0.5), (s - floor(s)) / modRate
		end
	end
end

function NE_Cooldowns:StopTimer()
	self.enabled = nil
	self:Hide()
end

function NE_Cooldowns:ForceUpdate()
	self.nextUpdate = 0
	self:Show()
end

function NE_Cooldowns:OnSizeChanged(width, height)
	local fontScale = NE_Cooldowns:Round((width + height) / 2) / ICON_SIZE
	if fontScale == self.fontScale then
		return
	end
	self.fontScale = fontScale

	if fontScale < MIN_SCALE then
		self:Hide()
	else
		self.text:SetFont(NE_Cooldowns.Font[1], fontScale * FONT_SIZE, NE_Cooldowns.Font[3])
		self.text:SetShadowColor(0, 0, 0, 0)

		if self.enabled then
			NE_Cooldowns.ForceUpdate(self)
		end
	end
end

function NE_Cooldowns:TimerOnUpdate(elapsed)
	if self.nextUpdate > 0 then
		self.nextUpdate = self.nextUpdate - elapsed
	else
		local passTime = GetTime() - self.start
		local remain = passTime >= 0 and ((self.duration - passTime) / self.modRate) or self.duration
		if remain > 0 then
			local getTime, nextUpdate = NE_Cooldowns.FormattedTimer(remain, self.modRate)
			self.text:SetText(getTime)
			self.nextUpdate = nextUpdate
		else
			NE_Cooldowns.StopTimer(self)
		end
	end
end

function NE_Cooldowns:ScalerOnSizeChanged(...)
	NE_Cooldowns.OnSizeChanged(self.timer, ...)
end

function NE_Cooldowns:OnCreate()
	local scaler = CreateFrame("Frame", nil, self)
	scaler:SetAllPoints(self)

	local timer = CreateFrame("Frame", nil, scaler)
	timer:Hide()
	timer:SetAllPoints(scaler)
	timer:SetScript("OnUpdate", NE_Cooldowns.TimerOnUpdate)
	scaler.timer = timer

	local text = timer:CreateFontString(nil, "BACKGROUND")
	text:SetPoint("CENTER", 1, 0)
	text:SetJustifyH("CENTER")
	timer.text = text

	NE_Cooldowns.OnSizeChanged(timer, scaler:GetSize())
	scaler:SetScript("OnSizeChanged", NE_Cooldowns.ScalerOnSizeChanged)

	self.timer = timer
	return timer
end

function NE_Cooldowns:StartTimer(start, duration, modRate)
	if self:IsForbidden() then
		return
	end
	if self.noCooldownCount or hideNumbers[self] then
		return
	end

	local frameName = self.GetName and self:GetName()
	if NE_Cooldowns.db.profile.actionbars.OverrideWA and frameName and strfind(frameName, "WeakAuras") then
		self.noCooldownCount = true
		return
	end

	local parent = self:GetParent()
	start = tonumber(start) or 0
	duration = tonumber(duration) or 0
	modRate = tonumber(modRate) or 1

	if start > 0 and duration > MIN_DURATION then
		local timer = self.timer or NE_Cooldowns.OnCreate(self)
		timer.start = start
		timer.duration = duration
		timer.modRate = modRate
		timer.enabled = true
		timer.nextUpdate = 0

		-- wait for blizz to fix itself
		local charge = parent and parent.chargeCooldown
		local chargeTimer = charge and charge.timer
		if chargeTimer and chargeTimer ~= timer then
			NE_Cooldowns.StopTimer(chargeTimer)
		end

		if timer.fontScale and timer.fontScale >= MIN_SCALE then
			timer:Show()
		end
	elseif self.timer then
		NE_Cooldowns.StopTimer(self.timer)
	end

	-- hide cooldown flash if barFader enabled
	if parent and parent.__faderParent then
		if self:GetEffectiveAlpha() > 0 then
			self:Show()
		else
			self:Hide()
		end
	end
end

function NE_Cooldowns:HideCooldownNumbers()
	hideNumbers[self] = true
	if self.timer then
		NE_Cooldowns.StopTimer(self.timer)
	end
end

function NE_Cooldowns:CooldownOnShow()
	active[self] = true
end

function NE_Cooldowns:CooldownOnHide()
	active[self] = nil
end

local function shouldUpdateTimer(self, start)
	local timer = self.timer
	if not timer then
		return true
	end
	return timer.start ~= start
end

function NE_Cooldowns:CooldownUpdate()
	local button = self:GetParent()
	local start, duration, modRate = GetActionCooldown(button.action)

	if shouldUpdateTimer(self, start) then
		NE_Cooldowns.StartTimer(self, start, duration, modRate)
	end
end

function NE_Cooldowns:ActionbarUpateCooldown()
	for cooldown in pairs(active) do
		NE_Cooldowns.CooldownUpdate(cooldown)
	end
end

function NE_Cooldowns:RegisterActionButton()
	local cooldown = self.cooldown
	if not hooked[cooldown] then
		cooldown:HookScript("OnShow", NE_Cooldowns.CooldownOnShow)
		cooldown:HookScript("OnHide", NE_Cooldowns.CooldownOnHide)

		hooked[cooldown] = true
	end
end

function NE_Cooldowns:PLAYER_LOGIN()
	if not NE_Cooldowns.db.profile.actionbars.cooldowns then
		return
	end

	-- Hook the SetCooldown function to start the timer
	hooksecurefunc(getmetatable(ActionButton1Cooldown).__index, "SetCooldown", NE_Cooldowns.StartTimer)

	-- Hide cooldown numbers
	hooksecurefunc("CooldownFrame_SetDisplayAsPercentage", NE_Cooldowns.HideCooldownNumbers)

	-- -- Register for action bar cooldown updates
	NE_Cooldowns:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN", NE_Cooldowns.ActionbarUpateCooldown)

	-- Register action button frames
	if _G["ActionBarButtonEventsFrame"].frames then
		for _, frame in pairs(_G["ActionBarButtonEventsFrame"].frames) do
			NE_Cooldowns.RegisterActionButton(frame)
		end
	end
	hooksecurefunc(ActionBarButtonEventsFrameMixin, "RegisterFrame", NE_Cooldowns.RegisterActionButton)

	-- Hide default cooldown
	SetCVar("countdownForCooldowns", 0)
end
