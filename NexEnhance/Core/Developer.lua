local _, Core = ...

-- Devs list
local Developers = {
	["Kkthnx-Area 52"] = true,
	["Kkthnxx-Area 52"] = true,
	["Kkthnxbye-Area 52"] = true,
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

function Core:ToggleSocialButton()
	if Core.db.profile.chat.SocialButton then
		if QuickJoinToastButton:IsShown() then
			Core.HideObject(QuickJoinToastButton)
		end
	else
		if not QuickJoinToastButton:IsShown() then
			QuickJoinToastButton:Show()
		end
	end
end

function Core:PLAYER_LOGIN()
	self:ToggleSocialButton()
end

local _, namespace = ...

-- Helper function to create a text-based queue timer with frame skin
local function CreateQueueTimerFrame(parentDialog, duration, event)
	local frame = namespace:CreateFrame("Frame", nil, parentDialog, "BackdropTemplate")
	frame.backdropInfo = BACKDROP_DIALOG_32_32
	frame:ApplyBackdrop()
	frame:SetPoint("TOP", parentDialog, "BOTTOM", 0, 8)
	frame:SetSize(300, 64)

	-- Create the timer text
	frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	frame.text:SetPoint("CENTER")
	frame.text:SetText("QueueTimer: " .. duration .. "s")
	frame.text:SetFont("Fonts\\FRIZQT__.TTF", 14, "")

	local function GetColor(timeLeft, maxTime)
		local percentage = timeLeft / maxTime
		if percentage > 0.66 then
			return 0, 1, 0
		elseif percentage > 0.33 then
			return 1, 1, 0
		elseif percentage > 0.1 then
			return 1, 0.5, 0
		else
			return 1, 0, 0
		end
	end

	local function UpdateText()
		local startTime = GetTime()
		frame:SetScript("OnUpdate", function(_, elapsed)
			local elapsedTime = GetTime() - startTime
			local timeLeft = math.max(0, duration - elapsedTime)

			if timeLeft > 0 then
				local r, g, b = GetColor(timeLeft, duration)
				frame.text:SetText("QueueTimer: " .. string.format("%.1f", timeLeft) .. "s")
				frame.text:SetTextColor(r, g, b)
			else
				frame:SetScript("OnUpdate", nil)
				frame.text:SetText("QueueTimer: 0s")
				frame.text:SetTextColor(1, 0, 0)
			end
		end)
	end

	namespace:RegisterEvent(event, function()
		if parentDialog:IsShown() then
			frame.text:SetText("QueueTimer: " .. duration .. "s")
			frame.text:SetTextColor(0, 1, 0)
			UpdateText()
		end
	end)
end

-- Function to initialize the LFG Dungeon Ready Dialog Timer
local function InitLFGDungeonReadyDialogTimer()
	CreateQueueTimerFrame(LFGDungeonReadyDialog, 40, "LFG_PROPOSAL_SHOW")
end

-- Function to initialize the PVP Ready Dialog Timer
local function InitPVPReadyDialogTimer()
	CreateQueueTimerFrame(PVPReadyDialog, 90, "UPDATE_BATTLEFIELD_STATUS")
end

-- Use HookAddOn to ensure the code only loads when the addon is enabled
function namespace:OnLogin()
	if namespace:IsAddOnEnabled("DBM-Core") or namespace:IsAddOnEnabled("BigWigs") then
		return
	end

	-- Initialize both timers
	InitLFGDungeonReadyDialogTimer()
	InitPVPReadyDialogTimer()
end
