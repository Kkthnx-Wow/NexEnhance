--@curseforge-project-slug: libchatanims@
-- Embedded from https://www.wowace.com/projects/libchatanims (Funkydude).
local MAJOR, MINOR = "LibChatAnims", 6 -- Bump minor on changes
local LCA = LibStub:NewLibrary(MAJOR, MINOR)
if not LCA then
	return
end -- No upgrade needed

LCA.animations = LCA.animations or {} -- Animation storage
LCA.alerting = LCA.alerting or {} -- Chat tab alerting storage
local anims = LCA.animations
local alerting = LCA.alerting

function LCA:IsAlerting(tab)
	if alerting[tab] then
		return true
	end
end

----------------------------------------------------
-- Note, most of this code is simply replicated from
-- Blizzard's FloatingChatFrame.lua file.
-- The only real changes are the creation and use
-- of animations vs the use of UIFrameFlash.
--

local issecretvalue = issecretvalue or function()
	return false
end
FCF_StartAlertFlash = function(chatFrame)
	if issecretvalue(chatFrame) then
		return
	end

	local chatTab = _G[chatFrame:GetName() .. "Tab"]

	if chatFrame.minFrame then
		if not anims[chatFrame.minFrame] then
			anims[chatFrame.minFrame] = chatFrame.minFrame.glow:CreateAnimationGroup()

			local fade1 = anims[chatFrame.minFrame]:CreateAnimation("Alpha")
			fade1:SetDuration(1)
			fade1:SetFromAlpha(0)
			fade1:SetToAlpha(1)
			fade1:SetOrder(1)

			local fade2 = anims[chatFrame.minFrame]:CreateAnimation("Alpha")
			fade2:SetDuration(1)
			fade2:SetFromAlpha(1)
			fade2:SetToAlpha(0)
			fade2:SetOrder(2)
		end
		chatFrame.minFrame.glow:Show()
		chatFrame.minFrame.glow:SetAlpha(0)
		anims[chatFrame.minFrame]:SetLooping("REPEAT")
		anims[chatFrame.minFrame]:Play()
		alerting[chatFrame.minFrame] = true
	end

	if not anims[chatTab.glow] then
		anims[chatTab.glow] = chatTab.glow:CreateAnimationGroup()

		local fade1 = anims[chatTab.glow]:CreateAnimation("Alpha")
		fade1:SetDuration(1)
		fade1:SetFromAlpha(0)
		fade1:SetToAlpha(1)
		fade1:SetOrder(1)

		local fade2 = anims[chatTab.glow]:CreateAnimation("Alpha")
		fade2:SetDuration(1)
		fade2:SetFromAlpha(1)
		fade2:SetToAlpha(0)
		fade2:SetOrder(2)
	end
	chatTab.glow:Show()
	chatTab.glow:SetAlpha(0)
	anims[chatTab.glow]:SetLooping("REPEAT")
	anims[chatTab.glow]:Play()
	alerting[chatTab] = true

	local mouseOverAlpha, noMouseAlpha = 0, 0
	if not chatFrame.isDocked or chatFrame == FCFDock_GetSelectedWindow(GENERAL_CHAT_DOCK) then
		mouseOverAlpha = 1.0
		noMouseAlpha = 0.4
	else
		mouseOverAlpha = 1.0
		noMouseAlpha = 1.0
	end
	if chatFrame.hasBeenFaded then
		chatTab:SetAlpha(mouseOverAlpha)
	else
		chatTab:SetAlpha(noMouseAlpha)
	end
end

FCF_StopAlertFlash = function(chatFrame)
	if issecretvalue(chatFrame) then
		return
	end

	local chatTab = _G[chatFrame:GetName() .. "Tab"]

	if chatFrame.minFrame then
		if anims[chatFrame.minFrame] then
			anims[chatFrame.minFrame]:Stop()
		end
		chatFrame.minFrame.glow:Hide()
		alerting[chatFrame.minFrame] = nil
	end

	if anims[chatTab.glow] then
		anims[chatTab.glow]:Stop()
	end
	chatTab.glow:Hide()
	alerting[chatTab] = nil

	local mouseOverAlpha, noMouseAlpha = 0, 0
	if not chatFrame.isDocked or chatFrame == FCFDock_GetSelectedWindow(GENERAL_CHAT_DOCK) then
		mouseOverAlpha = 1.0
		noMouseAlpha = 0.4
	else
		mouseOverAlpha = 0.6
		noMouseAlpha = 0.2
	end
	if chatFrame.hasBeenFaded then
		chatTab:SetAlpha(mouseOverAlpha)
	else
		chatTab:SetAlpha(noMouseAlpha)
	end
end

if WOW_PROJECT_ID == 1 then -- Retail only, dealing with a "secret" bug
	LCA.dedicatedWindows = LCA.dedicatedWindows or {}

	local function FCFManager_GetToken(chatType, chatTarget)
		return string.lower(chatType) .. (chatTarget and ";;" .. string.lower(chatTarget) or "")
	end

	function LCA:FCFManager_RegisterDedicatedFrame(chatFrame, chatType, chatTarget)
		if issecretvalue(chatTarget) then
			return
		end

		local token = FCFManager_GetToken(chatType, chatTarget)
		if not LCA.dedicatedWindows[token] then
			LCA.dedicatedWindows[token] = {}
		end

		if not LCA.dedicatedWindows[token][chatFrame] then
			LCA.dedicatedWindows[token][chatFrame] = true
		end
	end

	function LCA:FCFManager_UnregisterDedicatedFrame(chatFrame, chatType, chatTarget)
		if issecretvalue(chatTarget) then
			return
		end

		local token = FCFManager_GetToken(chatType, chatTarget)
		local windowList = LCA.dedicatedWindows[token]
		if windowList then
			LCA.dedicatedWindows[token][chatFrame] = nil
		end
	end

	function FCFManager_StopFlashOnDedicatedWindows(chatType, chatTarget)
		if issecretvalue(chatTarget) then
			return
		end

		local token = FCFManager_GetToken(chatType, chatTarget)
		local windowList = LCA.dedicatedWindows[token]
		if windowList then
			for chatFrame in next, windowList do
				FCF_StopAlertFlash(chatFrame)
			end
		end
	end

	if not LCA.FCFHooked then
		LCA.FCFHooked = true
		hooksecurefunc("FCFManager_RegisterDedicatedFrame", function(...)
			LCA:FCFManager_RegisterDedicatedFrame(...)
		end)
		hooksecurefunc("FCFManager_UnregisterDedicatedFrame", function(...)
			LCA:FCFManager_UnregisterDedicatedFrame(...)
		end)
	end
end
