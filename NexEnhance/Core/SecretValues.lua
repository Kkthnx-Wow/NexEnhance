--[[
	NexEnhance - Secret Values
	-------------------------------------------------------------------------
	Midnight (12.0) secret-value helpers on `ns.F`. Kept in its own file so
	Functions.lua stays focused on general utilities - secrets are a distinct
	API surface (docs-tagged predicates, DurationObject / boolean widgets).

	Load after Core/Functions.lua (needs `ns.F`). Callers never boolean-test /
	compare / index a secret directly.
--]]

local _, ns = ...
local F = ns.F

do
	local issecretvalue = _G["issecretvalue"]
	local issecrettable = _G["issecrettable"]
	local canaccessvalue = _G["canaccessvalue"]
	local C_Secrets = _G["C_Secrets"]
	local ShouldUnitIdentityBeSecret = C_Secrets and C_Secrets.ShouldUnitIdentityBeSecret
	local UnitIsUnit = UnitIsUnit
	local pcall = pcall

	--- True when `value` is a secret value (always safe to call).
	function F.IsSecret(value)
		return issecretvalue and issecretvalue(value)
	end

	--- True when `value` is a normal (non-secret) value.
	function F.NotSecret(value)
		return not F.IsSecret(value)
	end

	--- True when a unit's identity is currently hidden (instances / restricted).
	--- pcall'd because the API can be absent or throw on some unit tokens.
	function F.IsSecretUnit(unit)
		if not (unit and ShouldUnitIdentityBeSecret) then
			return false
		end
		local ok, value = pcall(ShouldUnitIdentityBeSecret, unit)
		return ok and value
	end

	--- True when a unit's identity is readable.
	function F.NotSecretUnit(unit)
		return not F.IsSecretUnit(unit)
	end

	--- True when `object` is a secret table (its fields may not be indexed).
	function F.IsSecretTable(object)
		return issecrettable and issecrettable(object)
	end

	--- True when `object` is a normal (non-secret) table.
	function F.NotSecretTable(object)
		return not F.IsSecretTable(object)
	end

	--- True when tainted code may actually read `value` (some secrets are still
	--- accessible). Defaults to true where the primitive is unavailable.
	function F.CanAccessValue(value)
		return not canaccessvalue or canaccessvalue(value)
	end

	--- True when tainted code may NOT read `value`.
	function F.CanNotAccessValue(value)
		return not F.CanAccessValue(value)
	end

	--- Compare two unit tokens without secret arithmetic errors. Returns false when
	--- comparison is blocked (`C_Secrets.CanCompareUnitTokens`) or the result is secret.
	function F.SafeUnitIsUnit(a, b)
		if not (a and b and UnitIsUnit) then
			return false
		end
		if C_Secrets and C_Secrets.CanCompareUnitTokens then
			local ok, can = pcall(C_Secrets.CanCompareUnitTokens, a, b)
			if ok and not can then
				return false
			end
		end
		local ok, result = pcall(UnitIsUnit, a, b)
		if not ok or F.IsSecret(result) then
			return false
		end
		return result and true or false
	end

	--- True when a widget/frame currently holds any secret values (aspects).
	function F.HasSecretValues(object)
		return object and object.HasSecretValues and object:HasSecretValues()
	end

	--- True when a widget/frame holds no secret values.
	function F.NoSecretValues(object)
		return not F.HasSecretValues(object)
	end

	local C_CurveUtil = _G["C_CurveUtil"]
	local EvaluateColorFromBoolean = C_CurveUtil and C_CurveUtil.EvaluateColorFromBoolean

	--- Read a boolean when safe, returns `true`/`false`, or `nil` when secret/unknown.
	function F.BooleanIsTrue(value)
		if F.NotSecret(value) then
			return value and true or false
		end
		return nil
	end

	--- Pick RGB for false vs true without comparing a secret boolean in Lua.
	function F.EvaluateColorFromBoolean(bool, r0, g0, b0, r1, g1, b1)
		if F.NotSecret(bool) then
			if bool then
				return r1, g1, b1
			end
			return r0, g0, b0
		end
		if EvaluateColorFromBoolean then
			return EvaluateColorFromBoolean(bool, r0, g0, b0, r1, g1, b1)
		end
		return r0, g0, b0
	end

	--- Secret-safe frame show: uses SetShown when readable, SetAlphaFromBoolean when secret.
	function F.SetShownFromBoolean(frame, bool, shownAlpha)
		if not frame then
			return
		end
		shownAlpha = shownAlpha or 1
		if F.NotSecret(bool) then
			if bool then
				frame:SetAlpha(shownAlpha)
				frame:Show()
			else
				frame:Hide()
			end
			return
		end
		if frame.SetAlphaFromBoolean then
			frame:SetAlphaFromBoolean(bool, shownAlpha, 0)
		end
		if frame.SetShownFromBoolean then
			frame:SetShownFromBoolean(bool)
		end
	end

	--- Hide a cooldown swipe when a DurationObject is zero (permanent aura).
	--- `durObj:IsZero()` may be Secret, `SetAlphaFromBoolean` routes it safely.
	function F.MaskCooldownSwipeFromDurationObject(cooldown, durObj)
		if not (cooldown and durObj and durObj.IsZero and cooldown.SetAlphaFromBoolean) then
			return
		end
		cooldown:SetAlphaFromBoolean(durObj:IsZero(), 0, 1)
	end
end
