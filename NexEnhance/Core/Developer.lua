local _, Core = ...

-- Devs list
local Developers = {
	["Kkthnx-Area 52"] = true,
}

-- Utility function to check if the player is a developer
local function isDeveloper()
	local playerName = gsub(Core.MyFullName, "%s", "")
	return Developers[playerName]
end

Core.isDeveloper = isDeveloper()

SlashCmdList["RELOADUI"] = ReloadUI
SLASH_RELOADUI1 = "/rl"

local function modifyPowerBarFrame()
	if UIWidgetPowerBarContainerFrame then
		if UIWidgetPowerBarContainerFrame:GetScale() ~= Core.db.profile.miscellaneous.widgetScale then
			UIWidgetPowerBarContainerFrame:SetScale(Core.db.profile.miscellaneous.widgetScale)
		end

		if Core.db.profile.miscellaneous.hideWidgetTexture then -- Only hide textures if the option is enabled
			for _, child in ipairs({ UIWidgetPowerBarContainerFrame:GetChildren() }) do
				for _, region in ipairs({ child:GetRegions() }) do
					if region:GetObjectType() == "Texture" then
						if region:IsShown() and Core.db.profile.miscellaneous.hideWidgetTexture then
							region:Hide()
						end
					end
				end
			end
		end
	end
end

local frameUpdater = CreateFrame("Frame")
frameUpdater:RegisterEvent("UPDATE_UI_WIDGET")
frameUpdater:HookScript("OnEvent", modifyPowerBarFrame)
