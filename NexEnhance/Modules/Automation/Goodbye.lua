local _, Module = ...

-- Local references for global functions
local math_random = math.random
local IsInGroup = IsInGroup
local SendChatMessage = SendChatMessage
local LE_PARTY_CATEGORY_INSTANCE = LE_PARTY_CATEGORY_INSTANCE

-- Table to store the custom message and the list
local AutoThanksList = {
	"GG, everyone!",
}

-- Send a goodbye message
local function SendAutoGoodbyeMessage()
	local message
	if Module.db.profile.automation.CustomGoodbyeMessage and Module.db.profile.automation.CustomGoodbyeMessage ~= "" then
		message = Module.db.profile.automation.CustomGoodbyeMessage
	else
		message = AutoThanksList[math_random(#AutoThanksList)]
	end

	local channel
	if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
		channel = "INSTANCE_CHAT"
	elseif IsInGroup() then
		channel = "PARTY"
	else
		channel = "SAY"
	end

	if message then
		SendChatMessage(message, channel)
	end
end

-- Setup delayed goodbye message
local function SetupAutoGoodbye()
	Module:Defer(function()
		C_Timer.After(math_random(2, 5), SendAutoGoodbyeMessage)
	end)
end

-- Create or disable Auto Goodbye feature
function Module:PLAYER_LOGIN()
	if Module.db.profile.automation.AutoGoodbye then
		Module:RegisterEvent("LFG_COMPLETION_REWARD", SetupAutoGoodbye)
		Module:RegisterEvent("CHALLENGE_MODE_COMPLETED", SetupAutoGoodbye)
	else
		Module:UnregisterEvent("LFG_COMPLETION_REWARD", SetupAutoGoodbye)
		Module:UnregisterEvent("CHALLENGE_MODE_COMPLETED", SetupAutoGoodbye)
	end
end
