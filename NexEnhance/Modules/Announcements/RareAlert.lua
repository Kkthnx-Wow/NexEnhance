local _, Module = ...

-- Localize WoW API functions
local C_Map_GetBestMapForUnit = C_Map.GetBestMapForUnit
local C_Texture_GetAtlasInfo = C_Texture.GetAtlasInfo
local C_VignetteInfo_GetVignetteInfo = C_VignetteInfo.GetVignetteInfo
local C_VignetteInfo_GetVignettePosition = C_VignetteInfo.GetVignettePosition
local GetInstanceInfo = GetInstanceInfo
local UIErrorsFrame = UIErrorsFrame
local PlaySound = PlaySound

-- Cache for rare alerts and ignored zones
local RareString = "|Hworldmap:%d+:%d+:%d+|h[%s (%.1f, %.1f)%s]|h|r"
local RareAlertCache = {}
local isIgnoredZone = {
	[1153] = true, -- 部落要塞
	[1159] = true, -- 联盟要塞
	[1803] = true, -- 涌泉海滩
	[1876] = true, -- 部落激流堡
	[1943] = true, -- 联盟激流堡
	[2111] = true, -- 黑海岸前线
}
local defaultList = {
	[5485] = true, -- 海象人工具盒
	[6149] = true, -- 奥妮克希亚龙蛋
}
local isIgnoredIDs = {}

-- Function to get texture string from atlas info
local function GetTextureString(info)
	if not info or not info.file then
		return
	end

	return string.format("|T%s:0:0:0:0:%d:%d:%d:%d:%d:%d|t", info.file, info.width / (info.rightTexCoord - info.leftTexCoord), info.height / (info.bottomTexCoord - info.topTexCoord), info.width * info.leftTexCoord, info.width * info.rightTexCoord, info.height * info.topTexCoord, info.height * info.bottomTexCoord)
end

-- Helper function to determine if the vignette atlas is useful
local function isUsefulAtlas(info)
	local atlas = info.atlasName
	if atlas then
		return strfind(atlas, "[Vv]ignette") or (atlas == "nazjatar-nagaevent")
	end
end

function Module:RareAlert_UpdateIgnored()
	Module.SplitList(isIgnoredIDs, Module.db.profile.announcements.ignoredRares, true)

	for id in pairs(defaultList) do
		isIgnoredIDs[id] = true
	end
end

-- Function to handle rare alerts
function Module:RareAlert_Update(id)
	if id and not RareAlertCache[id] then
		local info = C_VignetteInfo_GetVignetteInfo(id)
		if not info or not isUsefulAtlas(info) or isIgnoredIDs[id] then
			return
		end

		local atlasInfo = C_Texture_GetAtlasInfo(info.atlasName)
		if not atlasInfo then
			return
		end

		local tex = GetTextureString(atlasInfo)
		if not tex then
			return
		end

		-- Show UI error message for rare spotting
		UIErrorsFrame:AddMessage(Module.InfoColor .. Module.L["Rare Found"] .. tex .. (info.name or ""))

		-- Chat alert if enabled
		if Module.db.profile.announcements.alertInChat then
			local mapID = C_Map_GetBestMapForUnit("player")
			local nameString
			local position = mapID and C_VignetteInfo_GetVignettePosition(info.vignetteGUID, mapID)

			if position then
				local x, y = position:GetXY()
				nameString = string.format(RareString, mapID, x * 10000, y * 10000, info.name, x * 100, y * 100, "ID:" .. info.vignetteID)
			end

			Module:Print(tex .. Module.InfoColor .. (nameString or info.name or ""))
		end

		-- Play sound if enabled and not in an instance
		if Module.db.profile.announcements.alertInWild and Module.RareInstType ~= "none" then
			PlaySound(37881, "master")
		end

		RareAlertCache[id] = true
	end

	-- Limit the size of the cache
	if #RareAlertCache > 666 then
		table.wipe(RareAlertCache)
	end
end

-- Function to check the instance type and register/unregister events
function Module:RareAlert_CheckInstance()
	local _, instanceType, _, _, maxPlayers, _, _, instID = GetInstanceInfo()
	local shouldIgnore = (instID and isIgnoredZone[instID]) or (instanceType == "scenario" and (maxPlayers == 3 or maxPlayers == 6))

	if shouldIgnore and Module.RareInstType ~= "none" then
		Module:UnregisterEvent("VIGNETTE_MINIMAP_UPDATED", Module.RareAlert_Update)
		Module.RareInstType = "none"
	elseif not shouldIgnore and Module.RareInstType ~= instanceType then
		Module:RegisterEvent("VIGNETTE_MINIMAP_UPDATED", Module.RareAlert_Update)
		Module.RareInstType = instanceType
	end
end

-- Function to set up rare alerts
function Module:PLAYER_LOGIN()
	if Module.db.profile.announcements.rareAlert then
		Module:RareAlert_UpdateIgnored()
		Module:RareAlert_CheckInstance()
		Module:RegisterEvent("UPDATE_INSTANCE_INFO", Module.RareAlert_CheckInstance)
	else
		table.wipe(RareAlertCache)
		Module:UnregisterEvent("VIGNETTE_MINIMAP_UPDATED", Module.RareAlert_Update)
		Module:UnregisterEvent("UPDATE_INSTANCE_INFO", Module.RareAlert_CheckInstance)
	end
end
