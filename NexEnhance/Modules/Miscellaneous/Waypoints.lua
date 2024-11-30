local _, Module = ...

function Module:PLAYER_LOGIN()
	if hash_SlashCmdList["/WAY"] or hash_SlashCmdList["/GO"] then
		return
	end

	local debugMode = false
	local pointString = Module.InfoColor .. "|Hworldmap:%d:%d:%d|h[|A:Waypoint-MapPin-ChatIcon:13:13:0:0|a%s (%s, %s) %s]|h|r"

	local function DebugPrint(...)
		if debugMode then
			print("|cFF00FF00[DEBUG]:|r", ...)
		end
	end

	local function GetCorrectCoord(coord)
		DebugPrint("Validating coordinate:", coord)
		coord = tonumber(coord)
		if coord then
			return math.max(0, math.min(100, coord))
		end
	end

	local function FormatClickableWaypoint(mapID, x, y, mapName, desc)
		local formatted = format(pointString, mapID, x * 100, y * 100, mapName, x, y, desc or "")
		DebugPrint("Formatted clickable waypoint message:", formatted)
		return formatted
	end

	local function SetWaypoint(mapID, x, y, desc)
		local mapName = C_Map.GetMapInfo(mapID) and C_Map.GetMapInfo(mapID).name or "Unknown"
		DebugPrint("Setting waypoint - MapID:", mapID, "X:", x, "Y:", y, "Description:", desc)
		local message = FormatClickableWaypoint(mapID, x, y, mapName, desc)
		print(message)
		C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, x / 100, y / 100))
		C_SuperTrack.SetSuperTrackedUserWaypoint(true)
	end

	local function ParseInput(msg)
		DebugPrint("Parsing input:", msg)
		local mapID, x, y, desc = msg:match("#(%d+)%s*([%d%.]+),%s*([%d%.]+)%s*(.*)")

		if not mapID or not x or not y then
			print("Invalid input. Usage: /way #<mapID> <x>,<y> [description]")
			DebugPrint("Input validation failed. MapID:", mapID, "X:", x, "Y:", y)
			return
		end

		x = GetCorrectCoord(x)
		y = GetCorrectCoord(y)
		mapID = tonumber(mapID)
		if not (x and y and mapID) then
			print("Coordinates must be between 0 and 100, and mapID must be valid.")
			DebugPrint("Coordinate validation failed. MapID:", mapID, "X:", x, "Y:", y)
			return
		end

		DebugPrint("Parsed values - MapID:", mapID, "X:", x, "Y:", y, "Description:", desc)
		return mapID, x, y, desc
	end

	local function HandleSlashCommand(msg, command)
		DebugPrint("Handling /" .. command .. " command with input:", msg)
		local mapID, x, y, desc = ParseInput(msg)
		if not mapID then
			DebugPrint("Parsing failed for input:", msg)
			return
		end

		SetWaypoint(mapID, x, y, desc)
	end

	local function RegisterSlashCommands()
		DebugPrint("Registering /way and /go slash commands")

		SlashCmdList["NEXE_WAY"] = function(msg)
			HandleSlashCommand(msg, "way")
		end
		SLASH_NEXE_WAY1 = "/way"

		SlashCmdList["NEXE_GO"] = function(msg)
			HandleSlashCommand(msg, "go")
		end
		SLASH_NEXE_GO1 = "/go"
	end

	RegisterSlashCommands()
end
