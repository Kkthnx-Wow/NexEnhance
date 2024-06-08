local AddonName, Config = ...

local function CreateOptions()
	CreateOptions = nop -- we only want to load this once

	LibStub("AceConfig-3.0"):RegisterOptionsTable(AddonName, {
		type = "group",
		args = {
			actionbars = {
				order = 1,
				name = "Actionbars",
				icon = "4200123", -- :D
				type = "group",
				get = function(info)
					return Config.db.profile.actionbars[info[#info]]
				end,
				set = function(info, value)
					Config.db.profile.actionbars[info[#info]] = value
				end,
				args = {
					cooldowns = {
						order = 1,
						name = "Cooldowns",
						desc = "Show Cooldown Timers",
						type = "toggle",
						width = "double",
					},
					MmssTH = {
						order = 2,
						name = "MMSS Threshold",
						desc = "If cooldown less than current threshold, show cooldown in format MM:SS.|n|nEg. 2 mins and half presents as 2:30..",
						type = "range",
						min = 60,
						max = 600,
						step = 1,
						width = "double",
						disabled = function()
							return not Config.db.profile.actionbars.cooldowns
						end,
					},
					OverrideWA = {
						order = 3,
						name = "OverrideWA",
						desc = "Hide Cooldown on WA.",
						type = "toggle",
						width = "double",
						disabled = function()
							return not Config.db.profile.actionbars.cooldowns
						end,
					},
					range = {
						order = 4,
						name = "Range Indicator",
						desc = "Changes the color of action buttons when they are out of range or when the player is out of resources (e.g., energy, mana, focus).",
						type = "toggle",
						width = "double",
					},
					TenthTH = {
						order = 5,
						name = "Tenth Threshold",
						desc = "If cooldown less than current threshold, show cooldown in format decimal.|n|nEg. 3 secs will show as 3.0.",
						type = "range",
						min = 0,
						max = 60,
						step = 1,
						width = "double",
						disabled = function()
							return not Config.db.profile.actionbars.cooldowns
						end,
					},
				},
			},
			automation = {
				order = 2,
				name = "Automation",
				icon = "1405803", -- :D
				type = "group",
				get = function(info)
					return Config.db.profile.automation[info[#info]]
				end,
				set = function(info, value)
					Config.db.profile.automation[info[#info]] = value
				end,
				args = {
					AnnoyingBuffs = {
						order = 1,
						name = "Remove Annoying Buffs",
						desc = "Automatically remove specified annoying buffs from your character.",
						type = "toggle",
						width = "double",
					},
					AutoRepair = {
						order = 2,
						name = "Auto Repair",
						desc = "Automatically repairs your gear using the specified source: None, Guild Bank, or Player Funds.",
						type = "select",
						values = { [0] = NONE, [1] = GUILD, [2] = PLAYER },
					},
					AutoSell = {
						order = 3,
						name = "Auto-Sell Trash",
						desc = "Automatically sells junk items when visiting a vendor.",
						type = "toggle",
						width = "double",
					},
				},
			},
			blizzard = {
				order = 3,
				name = "Blizzard",
				icon = "135857", -- :D
				type = "group",
				get = function(info)
					return Config.db.profile.blizzard[info[#info]]
				end,
				set = function(info, value)
					Config.db.profile.blizzard[info[#info]] = value
				end,
				args = {
					characterFrame = {
						order = 1,
						name = "Enhanced Character Frame",
						desc = "Improves the appearance and functionality of the character frame.",
						type = "toggle",
						width = "double",
					},
					chatbubble = {
						order = 2,
						name = "Chat Bubble Enhancements",
						desc = "Toggle the enhancements for chat bubbles, such as customized colors and textures.",
						type = "toggle",
						width = "double",
					},
					inspectFrame = {
						order = 3,
						name = "Enhanced Inspect Frame",
						desc = "Enhances the inspect frame for better display and usability.",
						type = "toggle",
						width = "double",
					},
					objectiveTracker = {
						order = 4,
						name = "Clean Objective Tracker",
						desc = "Simplify and clean up the objective tracker display.",
						type = "toggle",
						width = "double",
					},
				},
			},
			general = {
				order = 4,
				name = "General",
				icon = "463852", -- :D
				type = "group",
				get = function(info)
					return Config.db.profile.general[info[#info]]
				end,
				set = function(info, value)
					Config.db.profile.general[info[#info]] = value
					if info[#info] == "AutoScale" or info[#info] == "UIScale" then
						Config:SetupUIScale()
					end
				end,
				args = {
					AutoScale = {
						order = 1,
						name = "Dynamic UI Scaling",
						desc = "Automatically adjusts the user interface scale to fit your screen resolution for optimal display.",
						type = "toggle",
						width = "double",
					},
					UIScale = {
						order = 2,
						name = "Custom Interface Scale",
						desc = "Manually set the scale of the user interface, ranging from 0.43 to 1.0, to suit your personal preference and display requirements.",
						type = "range",
						min = 0.43,
						max = 1.0,
						step = 0.01,
						width = "double",
						disabled = function()
							return Config.db.profile.general.AutoScale
						end,
					},
				},
			},
			loot = {
				order = 5,
				name = "Loot",
				icon = "901746", -- :D
				type = "group",
				get = function(info)
					return Config.db.profile.loot[info[#info]]
				end,
				set = function(info, value)
					Config.db.profile.loot[info[#info]] = value
				end,
				args = {
					FasterLoot = {
						order = 1,
						name = "Quick Looting",
						desc = "Enhances looting speed, requires auto-loot to be enabled.",
						type = "toggle",
						width = "double",
					},
				},
			},
			tooltip = {
				order = 6,
				name = "Tooltip",
				icon = "4622480", -- :D
				type = "group",
				get = function(info)
					return Config.db.profile.tooltip[info[#info]]
				end,
				set = function(info, value)
					Config.db.profile.tooltip[info[#info]] = value
				end,
				args = {
					combatHide = {
						order = 1,
						name = "Hide in Combat",
						desc = "Automatically hide the tip in combat.",
						type = "toggle",
						width = "double",
					},
					factionIcon = {
						order = 2,
						name = "Show Faction Icon",
						desc = "Display faction icons.",
						type = "toggle",
						width = "double",
					},
					hideJunkGuild = {
						order = 3,
						name = "Hide Junk Guild",
						desc = "Abbreviated GuildName.",
						type = "toggle",
						width = "double",
					},
					hideRank = {
						order = 4,
						name = "Hide Rank",
						desc = "Hide player guild ranks.",
						type = "toggle",
						width = "double",
					},
					hideTitle = {
						order = 5,
						name = "Hide Title",
						desc = "Hide player titles.",
						type = "toggle",
						width = "double",
					},
					lfdRole = {
						order = 6,
						name = "Show LFD Role Text",
						desc = "Display LFD role icons (tank, healer, damage).",
						type = "toggle",
						width = "double",
					},
					mdScore = {
						order = 7,
						name = "Show Mythic Dungeon Score",
						desc = "Display the player's Mythic Dungeon score.",
						type = "toggle",
						width = "double",
					},
					qualityColor = {
						order = 8,
						name = "Use Quality Colors",
						desc = "Color the borders of items by their quality.",
						type = "toggle",
						width = "double",
					},
					ShowID = {
						order = 9,
						name = "Display Tooltip IDs",
						desc = "Enable this option to display spell, item, quest, and other IDs in tooltips.",
						type = "toggle",
						width = "double",
					},
					SpecLevelByShift = {
						order = 10,
						name = "Spec-Level By Shift",
						desc = "Show iLvl by SHIFT.",
						type = "toggle",
						width = "double",
					},
				},
			},
			unitframes = {
				order = 7,
				name = "Unit Frames",
				icon = "648207", -- :D
				type = "group",
				get = function(info)
					return Config.db.profile.unitframes[info[#info]]
				end,
				set = function(info, value)
					Config.db.profile.unitframes[info[#info]] = value
					if info[#info] == "classColorHealth" then
						local function UpdateCVar()
							if not InCombatLockdown() then
								SetCVar("raidFramesDisplayClassColor", 1)
							else
								C_Timer.After(1, function()
									UpdateCVar()
								end)
							end
						end
						UpdateCVar()
						Config.UpdateFrames()
					end
				end,
				args = {
					classColorHealth = {
						order = 1,
						name = "Class-colored Health Bars",
						desc = "Use class colors for health bars in unit frames.\n\nNOTE: This feature will be disabled if '|A:gmchat-icon-blizz:16:16|aBetter|cff00c0ffBlizz|rFrames' is enabled.",
						type = "toggle",
						width = "double",
						disabled = function()
							return IsAddOnLoaded("BetterBlizzFrames")
						end,
					},
				},
			},
			worldmap = {
				order = 8,
				name = "WorldMap",
				icon = "134269", -- :D
				type = "group",
				get = function(info)
					return Config.db.profile.worldmap[info[#info]]
				end,
				set = function(info, value)
					Config.db.profile.worldmap[info[#info]] = value
				end,
				args = {
					AlphaWhenMoving = {
						order = 1,
						name = "Map Transparency When Moving",
						desc = "Adjust the transparency level of the world map when you are moving.",
						type = "range",
						min = 0.1,
						max = 1.0,
						step = 0.1,
						width = "double",
						disabled = function()
							return not Config.db.profile.worldmap.FadeWhenMoving
						end,
					},
					Coordinates = {
						order = 2,
						name = "Show Coordinates",
						desc = "Toggle to display coordinates on the world map.",
						type = "toggle",
						width = "double",
					},
					FadeWhenMoving = {
						order = 3,
						name = "Fade Map When Moving",
						desc = "Toggle to make the world map fade out when you are moving.",
						type = "toggle",
						width = "double",
					},
					SmallWorldMap = {
						order = 4,
						name = "Compact World Map",
						desc = "Toggle to use a smaller version of the world map.",
						type = "toggle",
						width = "double",
					},
					SmallWorldMapScale = {
						order = 5,
						name = "Compact Map Scale",
						desc = "Adjust the scale of the smaller world map.",
						type = "range",
						min = 0.5,
						max = 1.0,
						step = 0.1,
						width = "double",
						disabled = function()
							return not Config.db.profile.worldmap.SmallWorldMap
						end,
					},
				},
			},
			-- Add additional sections similarly
		},
	})

	LibStub("AceConfigDialog-3.0"):AddToBlizOptions(AddonName)
end

SettingsPanel:HookScript("OnShow", function()
	CreateOptions() -- Load on demand
end)

Config:RegisterSlash("/nexe", "/ne", function()
	Settings.OpenToCategory(AddonName)
end)
