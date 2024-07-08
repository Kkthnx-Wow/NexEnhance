local _, Module = ...

local TextureUVs = {
	"TopLeftCorner",
	"TopRightCorner",
	"BottomLeftCorner",
	"BottomRightCorner",
	"TopEdge",
	"BottomEdge",
	"LeftEdge",
	"RightEdge",
}

function Module:FormatBubbles(frame, fontString)
	local r, g, b, a = fontString:GetTextColor()
	for _, edge in ipairs(TextureUVs) do
		frame[edge]:SetVertexColor(r, g, b, a)
	end
	frame.Tail:SetVertexColor(r, g, b, a)
	frame.Tail:SetTexture("")
end

function Module:IterateChatBubbles(callback)
	for _, chatBubbleObj in ipairs(C_ChatBubbles.GetAllChatBubbles(false)) do
		local chatBubble = chatBubbleObj:GetChildren()
		if chatBubble and chatBubble.String and chatBubble.String:GetObjectType() == "FontString" then
			if type(callback) == "function" then
				callback(self, chatBubble, chatBubble.String)
			end
		end
	end
end

local BUBBLE_SCAN_THROTTLE = 0.1

function Module:PLAYER_LOGIN()
	if not Module.db.profile.skins.blizzskins.chatbubble then
		return
	end

	self.update = self.update or CreateFrame("Frame")
	self.throttle = BUBBLE_SCAN_THROTTLE

	self.update:SetScript("OnUpdate", function(frame, elapsed)
		self.throttle = self.throttle - elapsed
		if frame:IsShown() and self.throttle < 0 then
			self.throttle = BUBBLE_SCAN_THROTTLE
			self:IterateChatBubbles(self.FormatBubbles)
		end
	end)

	-- Restore defaults
	for _, chatBubbleObj in ipairs(C_ChatBubbles.GetAllChatBubbles(false)) do
		local chatBubble = chatBubbleObj:GetChildren()
		if chatBubble and chatBubble.String and chatBubble.String:GetObjectType() == "FontString" then
			self:FormatBubbles(chatBubble, chatBubble.String)
		end
	end
end
