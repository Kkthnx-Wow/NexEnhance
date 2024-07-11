local _, Module = ...

local function SetupInstance(instance)
	if instance.styled then
		return
	end

	-- if window is hidden on init, show it and hide later
	if not instance.baseframe then
		instance:ShowWindow()
		instance.wasHidden = true
	end

	-- reset texture if using Details default texture
	-- print(instance.row_info.texture)
	local needReset = instance.row_info.texture == "Details Hyanda"
	instance:ChangeSkin("Minimalistic")
	instance:InstanceWallpaper(false)
	instance:DesaturateMenu(true)
	instance:HideMainIcon(false)
	instance:SetBackdropTexture("None") -- if block window from resizing, then back to "Details Ground", needs review
	instance:MenuAnchor(16, 3)
	instance:ToolbarMenuButtonsSize(1)
	instance:AttributeMenu(true, 0, 3, needReset and NexEnhanceFont, needReset and 13, { 1, 1, 1 }, 1, false)
	instance:SetBarSettings(needReset and 20, needReset and "Blizzard")
	instance:SetBarTextSettings(needReset and 12, NexEnhanceFont, nil, nil, nil, false, false, nil, nil, nil, nil, nil, nil, true, { 0, 0, 0, 1 }, true, { 0, 0, 0, 1 })
	Module.CreateBackdropFrame(instance.baseframe, 4, 22, 4, 3)

	instance.styled = true
end

local function EmbedWindow(instance, x, y, width, height)
	if not instance.baseframe then
		return
	end

	instance.baseframe:ClearAllPoints()
	instance.baseframe:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", x, y)
	instance:SetSize(width, height)
	instance:SaveMainWindowPosition()
	instance:RestoreMainWindowPosition()
	instance:LockInstance(true)
end

local function isDefaultOffset(offset)
	return offset and abs(offset) < 10
end

local function IsDefaultAnchor(instance)
	local frame = instance and instance.baseframe
	if not frame then
		return
	end

	local relF, _, relT, x, y = frame:GetPoint()
	return (relF == "CENTER" and relT == "CENTER" and isDefaultOffset(x) and isDefaultOffset(y))
end

function Module:ResetDetailsAnchor(force)
	local Details = Details
	if not Details then
		return
	end

	local height = 126
	local instance1 = Details:GetInstance(1)
	local instance2 = Details:GetInstance(2)
	if instance1 and (force or IsDefaultAnchor(instance1)) then
		if instance2 then
			height = 112
			EmbedWindow(instance2, -6, 140, 260, height)
		end
		EmbedWindow(instance1, -500, 4, 260, height)
	end

	return instance1
end

local function ReskinDetails()
	if not IsAddOnLoaded("Details") then
		return
	end

	if not Module.db.profile.skins.addonskins.details then
		return
	end

	local Details = Details
	-- instance table can be nil sometimes
	Details.tabela_instancias = Details.tabela_instancias or {}
	Details.instances_amount = Details.instances_amount or 5

	local index = 1
	local instance = Details:GetInstance(index)
	while instance do
		SetupInstance(instance)
		index = index + 1
		instance = Details:GetInstance(index)
	end

	-- Reanchor
	local instance1 = Module:ResetDetailsAnchor()
	local listener = Details:CreateEventListener()
	listener:RegisterEvent("DETAILS_INSTANCE_OPEN")
	function listener:OnDetailsEvent(event, instance)
		if event == "DETAILS_INSTANCE_OPEN" then
			if not instance.styled and instance:GetId() == 2 then
				instance1:SetSize(260, 112)
				EmbedWindow(instance, -3, 140, 250, 112)
			end
			SetupInstance(instance)
		end
	end

	-- Numberize
	local current = Module.db.profile.general.numberPrefixStyle
	if current < "FULL" then
		Details.numerical_system = current
		Details:SelectNumericalSystem()
	end

	-- Reset to one window
	Details.OpenWelcomeWindow = function()
		if instance1 then
			EmbedWindow(instance1, -370, 4, 260, 126)
			instance1:SetBarSettings(20, "Blizzard")
			instance1:SetBarTextSettings(12, "NexEnhanceFont", nil, nil, nil, false, false, nil, nil, nil, nil, nil, nil, true, { 0.04, 0.04, 0.04, 0.9 }, true, { 0.04, 0.04, 0.04, 0.9 })
		end
	end
end

Module:RegisterEvent("PLAYER_LOGIN", ReskinDetails)
