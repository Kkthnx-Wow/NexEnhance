local _, Module = ...

local C_Map_GetBestMapForUnit = C_Map.GetBestMapForUnit
local C_Map_GetMapInfo = C_Map.GetMapInfo

function Module:CreateEasyWayPoints()
	if hash_SlashCmdList["/WAY"] or hash_SlashCmdList["/GO"] then
		return
	end

	local pointString = Module.InfoColor .. "|Hworldmap:%d+:%d+:%d+|h[|A:Waypoint-MapPin-ChatIcon:13:13:0:0|a%s (%s, %s)|h|r"

	local function GetCorrectCoord(coord)
		coord = tonumber(coord)
		if not coord then
			return nil
		end
		if coord > 100 then
			return 100
		elseif coord < 0 then
			return 0
		end
		return coord
	end

	local function SetWaypoint(mapID, x, y)
		local mapInfo = C_Map_GetMapInfo(mapID)
		local mapName = mapInfo and mapInfo.name
		if mapName then
			Module:Print(format(pointString, mapID, x * 100, y * 100, mapName, x, y))
			C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, x / 100, y / 100))
			C_SuperTrack.SetSuperTrackedUserWaypoint(true)
			Module:Print(format("Waypoint set to (%s, %s) on map: %s", x, y, mapName))
		end
	end

	SlashCmdList["NEXE_CUSTOM_WAYPOINT"] = function(msg)
		msg = gsub(msg, "#", "")
		msg = gsub(msg, "(%S%S+)[,%s]+(%d)", "%1 %2")
		msg = gsub(msg, "(%d),(%d)", "%1.%2")

		local mapID, x, y = strmatch(msg, "(%S*)%s*(%S+),(%s*%S+)")

		if not x then
			mapID = C_Map_GetBestMapForUnit("player")
			return
		end

		mapID = tonumber(mapID) or C_Map_GetBestMapForUnit("player")

		x = GetCorrectCoord(x)
		y = GetCorrectCoord(y)

		if not x then
			Module:Print("Invalid x coordinate. Please enter a number between 0 and 100.")
			return
		end
		if not y then
			Module:Print("Invalid y coordinate. Please enter a number between 0 and 100.")
			return
		end

		SetWaypoint(mapID, x, y)
	end

	SLASH_NEXE_CUSTOM_WAYPOINT1 = "/way"
	SLASH_NEXE_CUSTOM_WAYPOINT2 = "/go"
end

function Module:PLAYER_LOGIN()
	if not Module.db.profile.worldmap.easyWayPoints then
		return
	end

	self:CreateEasyWayPoints()
end
