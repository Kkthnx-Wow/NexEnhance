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
		-- Use the custom message if set
		message = Module.db.profile.automation.CustomGoodbyeMessage
	else
		-- Use a random message from the list
		message = AutoThanksList[math_random(#AutoThanksList)]
	end

	-- Determine the chat channel
	local channel
	if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
		channel = "INSTANCE_CHAT"
	elseif IsInGroup() then
		channel = "PARTY"
	else
		channel = "SAY"
	end

	-- Send the message
	if message then
		SendChatMessage(message, channel)
	end
end

-- Setup delayed goodbye message
local function SetupAutoGoodbye()
	C_Timer.After(math_random(2, 5), SendAutoGoodbyeMessage)
end

-- Create or disable Auto Goodbye feature
function Module:PLAYER_LOGIN()
	if Module.db.profile.automation.AutoGoodbye then
		-- Register events to trigger the goodbye message
		Module:RegisterEvent("LFG_COMPLETION_REWARD", SetupAutoGoodbye)
		Module:RegisterEvent("CHALLENGE_MODE_COMPLETED", SetupAutoGoodbye)
	else
		-- Unregister events when the feature is disabled
		Module:UnregisterEvent("LFG_COMPLETION_REWARD", SetupAutoGoodbye)
		Module:UnregisterEvent("CHALLENGE_MODE_COMPLETED", SetupAutoGoodbye)
	end
end
