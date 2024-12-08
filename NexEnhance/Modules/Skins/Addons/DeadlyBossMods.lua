local _, Module = ...

local _G = _G
local strfind, strmatch, gsub = string.find, string.match, string.gsub

local buttonsize = 24

local function ReskinDBMIcon(icon, frame)
	if not icon then
		return
	end
	if not icon.styled then
		icon:SetSize(buttonsize, buttonsize)
		icon.SetSize = Module.Noop

		local bg = CreateFrame("Frame", nil, frame)
		bg:SetAllPoints(icon)
		Module.CreateBackdropFrame(bg, 5, 5, 5, 5)

		bg.icon = bg:CreateTexture(nil, "BORDER", nil, -1)
		bg.icon:SetAllPoints()
		bg.icon:SetTexture(icon:GetTexture())
		bg.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

		icon.styled = true
	end

	icon:ClearAllPoints()
	icon:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", -10, 0)
end

local function ReskinDBMBar(bar, frame)
	if not bar then
		return
	end
	if not bar.styled then
		Module.StripTextures(bar)
		bar:SetStatusBarTexture(Module.NexEnhance)
		Module.CreateBackdropFrame(bar, 5, 5, 5, 5)

		bar.styled = true
	end
	bar:SetAllPoints(frame)
end

local function HideDBMSpark(self)
	local spark = _G[self.frame:GetName() .. "BarSpark"]
	spark:SetAlpha(0)
	spark:SetTexture(nil)
end

local function ApplyDBMStyle(self)
	local frame = self.frame
	local frame_name = frame:GetName()
	local tbar = _G[frame_name .. "Bar"]
	local texture = _G[frame_name .. "BarTexture"]
	local icon1 = _G[frame_name .. "BarIcon1"]
	local icon2 = _G[frame_name .. "BarIcon2"]
	local name = _G[frame_name .. "BarName"]
	local timer = _G[frame_name .. "BarTimer"]

	if self.enlarged then
		frame:SetWidth(self.owner.Options.HugeWidth)
		tbar:SetWidth(self.owner.Options.HugeWidth)
	else
		frame:SetWidth(self.owner.Options.Width)
		tbar:SetWidth(self.owner.Options.Width)
	end

	frame:SetScale(1)
	frame:SetHeight(buttonsize / 2)

	ReskinDBMIcon(icon1, frame)
	ReskinDBMIcon(icon2, frame)
	ReskinDBMBar(tbar, frame)
	if texture then
		texture:SetTexture(Module.NexEnhance)
	end

	name:ClearAllPoints()
	name:SetPoint("LEFT", frame, "LEFT", 2, 8)
	name:SetPoint("RIGHT", frame, "LEFT", tbar:GetWidth() * 0.85, 8)
	name:SetFontObject("NexEnhanceFontOutline")
	name:SetFont(select(1, name:GetFont()), 12, "OUTLINE")
	name:SetJustifyH("LEFT")
	name:SetWordWrap(false)
	name:SetShadowColor(0, 0, 0, 0)

	timer:ClearAllPoints()
	timer:SetPoint("RIGHT", frame, "RIGHT", -2, 8)
	timer:SetFontObject("NexEnhanceFontOutline")
	timer:SetFont(select(1, timer:GetFont()), 12, "OUTLINE")
	timer:SetJustifyH("RIGHT")
	timer:SetShadowColor(0, 0, 0, 0)
end

local function ReskinDeadlyBossMods()
	-- Default notice message
	local RaidNotice_AddMessage_ = RaidNotice_AddMessage
	RaidNotice_AddMessage = function(noticeFrame, textString, colorInfo)
		if strfind(textString, "|T") then
			if strmatch(textString, ":(%d+):(%d+)") then
				local size1, size2 = strmatch(textString, ":(%d+):(%d+)")
				size1, size2 = size1 + 3, size2 + 3
				textString = gsub(textString, ":(%d+):(%d+)", ":" .. size1 .. ":" .. size2 .. ":0:0:64:64:5:59:5:59")
			elseif strmatch(textString, ":(%d+)|t") then
				local size = strmatch(textString, ":(%d+)|t")
				size = size + 3
				textString = gsub(textString, ":(%d+)|t", ":" .. size .. ":" .. size .. ":0:0:64:64:5:59:5:59|t")
			end
		end
		return RaidNotice_AddMessage_(noticeFrame, textString, colorInfo)
	end

	if not C_AddOns.IsAddOnLoaded("DBM-Core") then
		return
	end

	-- if not C.db["Skins"]["DBM"] then
	-- 	return
	-- end

	hooksecurefunc(DBT, "CreateBar", function(self)
		for bar in self:GetBarIterator() do
			if not bar.injected then
				hooksecurefunc(bar, "Update", HideDBMSpark)
				hooksecurefunc(bar, "ApplyStyle", ApplyDBMStyle)
				bar:ApplyStyle()

				bar.injected = true
			end
		end
	end)

	-- Force Settings
	if not _G.DBM_AllSavedOptions["Default"] then
		_G.DBM_AllSavedOptions["Default"] = {}
	end

	_G.DBM_AllSavedOptions["Default"]["BlockVersionUpdateNotice"] = true
	_G.DBM_AllSavedOptions["Default"]["EventSoundVictory"] = "None"

	if not _G.DBT_AllPersistentOptions["Default"] then
		_G.DBT_AllPersistentOptions["Default"] = {}
	end

	_G.DBT_AllPersistentOptions["Default"]["DBM"].BarYOffset = 12
	_G.DBT_AllPersistentOptions["Default"]["DBM"].HugeBarYOffset = 12
	_G.DBT_AllPersistentOptions["Default"]["DBM"].ExpandUpwards = true
	_G.DBT_AllPersistentOptions["Default"]["DBM"].ExpandUpwardsLarge = true
end

Module:RegisterEvent("PLAYER_LOGIN", function()
	Module:Defer(ReskinDeadlyBossMods)
end)
