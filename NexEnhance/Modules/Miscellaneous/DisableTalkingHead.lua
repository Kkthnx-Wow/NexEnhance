local _, Module = ...

local function DisableTalkingHead()
	if Module.db.profile.miscellaneous.disableTalkingHead then
		_G.TalkingHeadFrame:UnregisterAllEvents()
		hooksecurefunc(_G.TalkingHeadFrame, "Show", _G.TalkingHeadFrame.Hide)
	end
end

function Module:PLAYER_LOGIN()
	if _G.TalkingHeadFrame then
		DisableTalkingHead()
	end
end
