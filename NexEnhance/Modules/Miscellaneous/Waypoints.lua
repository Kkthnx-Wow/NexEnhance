local _, Module = ...

function Module:PLAYER_LOGIN()
	if hash_SlashCmdList["/WAY"] or hash_SlashCmdList["/GO"] then
		return
	end

	local debugMode = false
	local pointString = Module.InfoColor .. "|Hworldmap:%d:%d:%d|h[|A:Waypoint-MapPin-ChatIcon:13:13:0:0|a%s (%s, %s)%s]|h|r"

	-- Debugging function
	local function DebugPrint(...)
		if debugMode then
			print("|cFF00FF00[DEBUG]:|r", ...)
		end
	end

	-- Ensures coordinates are valid and within bounds
	local function GetCorrectCoord(coord)
		DebugPrint("Validating coordinate:", coord)
		coord = tonumber(coord)
		if coord then
			return math.max(0, math.min(100, coord))
		end
	end

	-- Formats the clickable waypoint message
	local function FormatClickableWaypoint(mapID, x, y, mapName, desc)
		local descriptionPart = desc and (" " .. desc) or ""
		local formatted = format(pointString, mapID, x * 100, y * 100, mapName, x, y, descriptionPart)
		DebugPrint("Formatted clickable waypoint message:", formatted)
		return formatted
	end

	-- Sets the waypoint and supertracks it
	local function SetWaypoint(mapID, x, y, desc)
		local mapName = C_Map.GetMapInfo(mapID) and C_Map.GetMapInfo(mapID).name or "Unknown"
		DebugPrint("Setting waypoint - MapID:", mapID, "X:", x, "Y:", y, "Description:", desc or "No description")

		local message = FormatClickableWaypoint(mapID, x, y, mapName, desc)
		print(message)

		C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, x / 100, y / 100))
		C_SuperTrack.SetSuperTrackedUserWaypoint(true)
	end

	-- Parses the input message for mapID, coordinates, and description
	local function ParseInput(msg)
		DebugPrint("Parsing input:", msg)

		-- Match input with map ID format
		local mapID, x, y, desc = msg:match("#(%d+)%s*([%d%.]+),?%s*([%d%.]+)%s*(.*)")
		if not mapID then
			-- Match input without map ID
			x, y, desc = msg:match("([%d%.]+),?%s*([%d%.]+)%s*(.*)")
			if x and y then
				-- Default to player's current map
				mapID = C_Map.GetBestMapForUnit("player")
				if not mapID then
					print("Unable to determine the current map. Please try again.")
					DebugPrint("Failed to retrieve map ID")
					return
				end
			end
		end

		if not x or not y then
			print("Invalid input. Usage: /way [#<mapID>] <x>,<y> [description]")
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

		DebugPrint("Parsed values - MapID:", mapID, "X:", x, "Y:", y, "Description:", desc or "No description")
		return mapID, x, y, desc
	end

	-- Handles slash command inputs
	local function HandleSlashCommand(msg, command)
		DebugPrint("Handling /" .. command .. " command with input:", msg)
		local mapID, x, y, desc = ParseInput(msg)
		if mapID then
			SetWaypoint(mapID, x, y, desc)
		else
			DebugPrint("Parsing failed for input:", msg)
		end
	end

	-- Registers the /way and /go slash commands
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
