local NexEnhance, Module = ...

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

function Module.FormattedTimer(s, modRate)
	if s >= day then
		return format("%d" .. Module.MyClassColor .. "d", s / day + 0.5), s % day
	elseif s > hour then
		return format("%d" .. Module.MyClassColor .. "h", s / hour + 0.5), s % hour
	elseif s >= minute then
		if s < Module.db.profile.actionbars.MmssTH then
			return format("%d:%.2d", s / minute, s % minute), s - floor(s)
		else
			return format("%d" .. Module.MyClassColor .. "m", s / minute + 0.5), s % minute
		end
	else
		local colorStr = (s < 3 and "|cffff0000") or (s < 10 and "|cffffff00") or "|cffcccc33"
		if s < Module.db.profile.actionbars.TenthTH then
			return format(colorStr .. "%.1f|r", s), (s - format("%.1f", s)) / modRate
		else
			return format(colorStr .. "%d|r", s + 0.5), (s - floor(s)) / modRate
		end
	end
end

function Module:StopTimer()
	self.enabled = nil
	self:Hide()
end

function Module:ForceUpdate()
	self.nextUpdate = 0
	self:Show()
end

function Module:OnSizeChanged(width, height)
	local fontScale = Module:Round((width + height) / 2) / ICON_SIZE
	if fontScale == self.fontScale then
		return
	end
	self.fontScale = fontScale

	if fontScale < MIN_SCALE then
		self:Hide()
	else
		self.text:SetFont(Module.Font[1], fontScale * FONT_SIZE, Module.Font[3])
		self.text:SetShadowColor(0, 0, 0, 0)

		if self.enabled then
			Module.ForceUpdate(self)
		end
	end
end

function Module:TimerOnUpdate(elapsed)
	if self.nextUpdate > 0 then
		self.nextUpdate = self.nextUpdate - elapsed
	else
		local passTime = GetTime() - self.start
		local remain = passTime >= 0 and ((self.duration - passTime) / self.modRate) or self.duration
		if remain > 0 then
			local getTime, nextUpdate = Module.FormattedTimer(remain, self.modRate)
			self.text:SetText(getTime)
			self.nextUpdate = nextUpdate
		else
			Module.StopTimer(self)
		end
	end
end

function Module:ScalerOnSizeChanged(...)
	Module.OnSizeChanged(self.timer, ...)
end

function Module:OnCreate()
	local scaler = CreateFrame("Frame", nil, self)
	scaler:SetAllPoints(self)

	local timer = CreateFrame("Frame", nil, scaler)
	timer:Hide()
	timer:SetAllPoints(scaler)
	timer:SetScript("OnUpdate", Module.TimerOnUpdate)
	scaler.timer = timer

	local text = timer:CreateFontString(nil, "BACKGROUND")
	text:SetPoint("CENTER", 1, 0)
	text:SetJustifyH("CENTER")
	timer.text = text

	Module.OnSizeChanged(timer, scaler:GetSize())
	scaler:SetScript("OnSizeChanged", Module.ScalerOnSizeChanged)

	self.timer = timer
	return timer
end

function Module:StartTimer(start, duration, modRate)
	if self:IsForbidden() then
		return
	end
	if self.noCooldownCount or hideNumbers[self] then
		return
	end

	local frameName = self.GetName and self:GetName()
	if Module.db.profile.actionbars.OverrideWA and frameName and strfind(frameName, "WeakAuras") then
		self.noCooldownCount = true
		return
	end

	local parent = self:GetParent()
	start = tonumber(start) or 0
	duration = tonumber(duration) or 0
	modRate = tonumber(modRate) or 1

	if start > 0 and duration > MIN_DURATION then
		local timer = self.timer or Module.OnCreate(self)
		timer.start = start
		timer.duration = duration
		timer.modRate = modRate
		timer.enabled = true
		timer.nextUpdate = 0

		-- wait for blizz to fix itself
		local charge = parent and parent.chargeCooldown
		local chargeTimer = charge and charge.timer
		if chargeTimer and chargeTimer ~= timer then
			Module.StopTimer(chargeTimer)
		end

		if timer.fontScale and timer.fontScale >= MIN_SCALE then
			timer:Show()
		end
	elseif self.timer then
		Module.StopTimer(self.timer)
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

function Module:HideCooldownNumbers()
	hideNumbers[self] = true
	if self.timer then
		Module.StopTimer(self.timer)
	end
end

function Module:CooldownOnShow()
	active[self] = true
end

function Module:CooldownOnHide()
	active[self] = nil
end

local function shouldUpdateTimer(self, start)
	local timer = self.timer
	if not timer then
		return true
	end
	return timer.start ~= start
end

function Module:CooldownUpdate()
	local button = self:GetParent()
	local start, duration, modRate = GetActionCooldown(button.action)

	if shouldUpdateTimer(self, start) then
		Module.StartTimer(self, start, duration, modRate)
	end
end

function Module:ActionbarUpateCooldown()
	for cooldown in pairs(active) do
		Module.CooldownUpdate(cooldown)
	end
end

function Module:RegisterActionButton()
	local cooldown = self.cooldown
	if not hooked[cooldown] then
		cooldown:HookScript("OnShow", Module.CooldownOnShow)
		cooldown:HookScript("OnHide", Module.CooldownOnHide)

		hooked[cooldown] = true
	end
end

function Module:PLAYER_LOGIN()
	if not Module.db.profile.actionbars.cooldowns then
		return
	end

	-- Hook the SetCooldown function to start the timer
	hooksecurefunc(getmetatable(ActionButton1Cooldown).__index, "SetCooldown", Module.StartTimer)

	-- Hide cooldown numbers
	hooksecurefunc("CooldownFrame_SetDisplayAsPercentage", Module.HideCooldownNumbers)

	-- -- Register for action bar cooldown updates
	Module:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN", Module.ActionbarUpateCooldown)

	-- Register action button frames
	if _G["ActionBarButtonEventsFrame"].frames then
		for _, frame in pairs(_G["ActionBarButtonEventsFrame"].frames) do
			Module.RegisterActionButton(frame)
		end
	end
	hooksecurefunc(ActionBarButtonEventsFrameMixin, "RegisterFrame", Module.RegisterActionButton)

	-- Hide default cooldown
	SetCVar("countdownForCooldowns", 0)
end
