local _, Core = ...

-- Devs list
local Developers = {
	["Kkthnx-Valdrakken"] = true,
}

-- Utility function to check if the player is a developer
local function isDeveloper()
	local playerName = gsub(Core.MyFullName, "%s", "")
	return Developers[playerName]
end

Core.isDeveloper = isDeveloper()

SlashCmdList["RELOADUI"] = ReloadUI
SLASH_RELOADUI1 = "/rl"

-- Developer settings
local DevSettings = {
	CastTime = true,
	Color = true,
	ServerName = true,
	Style = "Custom",
	HealthText = true,
}

-- Function to set font properties
local function setFont(obj, size)
	local fontName = obj:GetFont()
	obj:SetFont(fontName, size, "")
	obj:SetShadowOffset(1, -1)
end

-- Function to update health text on nameplates
local function updateNameplateHealthText(unit, healthBar)
	if not healthBar.text then
		healthBar.text = healthBar:CreateFontString(nil, "ARTWORK", nil)
		healthBar.text:SetPoint("CENTER")
		healthBar.text:SetFont(Core.Font[1], 8, "")
		healthBar.text:SetShadowOffset(1, -1)
	else
		local _, maxHealth = healthBar:GetMinMaxValues()
		local currentHealth = healthBar:GetValue()
		healthBar.text:SetText(string.format("%.0f%%", (currentHealth / maxHealth) * 100))
	end
end

-- Function to update player nameplate visuals
local function updatePlayerNameplate(self)
	if ShouldShowName(self) and self.optionTable.colorNameBySelection then
		local inInstance, instanceType = IsInInstance()
		if inInstance and not (instanceType == "arena" or instanceType == "pvp") then
			if self:IsForbidden() then
				return
			end
		end

		-- Color player name based on class
		if DevSettings.Color and self.unit then
			local _, class = UnitClass(self.unit)
			local color = RAID_CLASS_COLORS[class]
			if UnitIsPlayer(self.unit) and self.name then
				self.name:SetVertexColor(color.r, color.g, color.b)
			end
		end

		-- Hide server name
		if DevSettings.ServerName and self.name and self.unit then
			if UnitIsPlayer(self.unit) then
				local name, _ = UnitName(self.unit)
				self.name:SetText(name)
			end
		end

		-- Set font sizes for nameplates
		setFont(SystemFont_LargeNamePlate, 10)
		setFont(SystemFont_NamePlate, 10)
		setFont(SystemFont_LargeNamePlateFixed, 10)
		setFont(SystemFont_NamePlateFixed, 10)
	end
end

-- Function to update nameplate health text based on settings
local function updateNameplateHealthTextFrame(self)
	local inInstance, instanceType = IsInInstance()
	if inInstance and not (instanceType == "arena" or instanceType == "pvp") then
		if self:IsForbidden() then
			return
		end
	end

	if self.unit and self.unit:find("nameplate%d") then
		if self.healthBar and self.unit then
			if UnitName("player") ~= UnitName(self.unit) then
				updateNameplateHealthText(self.unit, self.healthBar)
			end
		end
	end
end

-- Function to handle nameplate castbar visuals
local function updateNameplateCastbar(self)
	if self.unit and self.unit:find("nameplate%d") then
		local inInstance, instanceType = IsInInstance()
		if inInstance and not (instanceType == "arena" or instanceType == "pvp") then
			if self:IsForbidden() then
				return
			end
		end

		if self and self.Icon then
			self.Text:SetFont(STANDARD_TEXT_FONT, 10, "")
			self.Text:SetShadowOffset(1, -1)

			if DevSettings.CastTime then
				if not self.timer then
					self.timer = self:CreateFontString(nil)
					self.timer:SetFont(STANDARD_TEXT_FONT, 8, "")
					self.timer:SetShadowOffset(1, -1)
					self.timer:SetPoint("CENTER", self.Icon, "BOTTOM", 0, -5)
					self.timer:SetDrawLayer("OVERLAY")
				else
					if self.casting then
						self.timer:SetText(format("%.1f", max(self.maxValue - self.value, 0)))
					elseif self.channeling then
						self.timer:SetText(format("%.1f", max(self.value, 0)))
					else
						self.timer:SetText("")
					end
				end
			end
		end
	end
end

-- Hook functions for nameplate updates
local function hookNameplateFunctions()
	-- Update health color
	hooksecurefunc("CompactUnitFrame_UpdateHealthColor", function(self)
		if not strfind(self.unit, "nameplate") then
			return
		end
		local inInstance, instanceType = IsInInstance()
		if inInstance and not (instanceType == "arena" or instanceType == "pvp") then
			if self:IsForbidden() then
				return
			end
		end

		self.myHealPrediction:SetVertexColor(16 / 255, 424 / 255, 400 / 255)
		self.otherHealPrediction:SetVertexColor(0, 325 / 255, 292 / 255)
	end)

	-- Update nameplate castbars
	hooksecurefunc(CastingBarMixin, "OnUpdate", updateNameplateCastbar)
	hooksecurefunc("DefaultCompactNamePlateFrameAnchorInternal", function(self)
		if self.castBar and self.castBar.Icon then
			if self.castBar.BorderShield then
				self.castBar.BorderShield:ClearAllPoints()
				PixelUtil.SetPoint(self.castBar.BorderShield, "CENTER", self.castBar, "LEFT", -10, 0)
			end

			self.castBar.Icon:ClearAllPoints()
			PixelUtil.SetPoint(self.castBar.Icon, "CENTER", self.castBar, "LEFT", -10, 0)
			self.castBar.Text:SetFont(STANDARD_TEXT_FONT, 10, "")
			self.castBar.Text:SetShadowOffset(1, -1)
		end
	end)

	-- Update nameplate health percentage
	if DevSettings.HealthText then
		hooksecurefunc("CompactUnitFrame_UpdateHealth", updateNameplateHealthTextFrame)
		hooksecurefunc("CompactUnitFrame_UpdateStatusText", updateNameplateHealthTextFrame)
	end

	-- Update nameplate name color
	hooksecurefunc("CompactUnitFrame_UpdateName", updatePlayerNameplate)
end

function Core:OnLogin()
	if IsAddOnLoaded("Plater") or IsAddOnLoaded("BetterBlizzPlates") or IsAddOnLoaded("TidyPlates_ThreatPlates") or IsAddOnLoaded("TidyPlates") or IsAddOnLoaded("Kui_Nameplates") then
		return
	end

	-- Apply nameplate customizations based on settings
	if DevSettings.Style ~= "Default" then
		hookNameplateFunctions()
	end
end
