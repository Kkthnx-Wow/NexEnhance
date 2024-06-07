local NexEnhance, NE_Options = ...
local L = NE_Options.L

local NEW = [[|TInterface\OptionsFrame\UI-OptionsFrame-NewFeatureIcon:0:0:0:-1|t ]]

local function CreateOptions()
	CreateOptions = nop -- we only want to load this once

	LibStub("AceConfig-3.0"):RegisterOptionsTable(NexEnhance, {
		type = "group",
		args = {
			actionbars = {
				order = 1,
				name = "Actionbars",
				icon = "4200123", -- :D
				type = "group",
				get = function(info)
					return NE_Options.db.profile.actionbars[info[#info]]
				end,
				set = function(info, value)
					NE_Options.db.profile.actionbars[info[#info]] = value
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
						desc = "If cooldown less than current threhold, show cooldown in format MM:SS.|n|nEg. 2 mins and half presents as 2:30..",
						type = "range",
						min = 60,
						max = 600,
						step = 1,
						width = "double",
						disabled = function()
							return not NE_Options.db.profile.actionbars.cooldowns
						end,
					},
					TenthTH = {
						order = 3,
						name = "Tenth Threshold",
						desc = "If cooldown less than current threhold, show cooldown in format decimal.|n|nEg. 3 secs will show as 3.0.",
						type = "range",
						min = 0,
						max = 60,
						step = 1,
						width = "double",
						disabled = function()
							return not NE_Options.db.profile.actionbars.cooldowns
						end,
					},
					OverrideWA = {
						order = 4,
						name = "OverrideWA",
						desc = "Hide Cooldown on WA.",
						type = "toggle",
						width = "double",
						disabled = function()
							return not NE_Options.db.profile.actionbars.cooldowns
						end,
					},
				},
			},
			blizzard = {
				order = 2,
				name = "Blizzard",
				icon = "135857", -- :D
				type = "group",
				get = function(info)
					return NE_Options.db.profile.blizzard[info[#info]]
				end,
				set = function(info, value)
					NE_Options.db.profile.blizzard[info[#info]] = value
				end,
				args = {
					objectiveTracker = {
						order = 1,
						name = "Clean Objective Tracker",
						desc = "Simplify and clean up the objective tracker display.",
						type = "toggle",
						width = "double",
					},
					characterFrame = {
						order = 2,
						name = "Enhanced Character Frame",
						desc = "Improves the appearance and functionality of the character frame.",
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
				},
			},
			unitframes = {
				order = 3,
				name = "Unit Frames",
				icon = "648207", -- :D
				type = "group",
				get = function(info)
					return NE_Options.db.profile.unitframes[info[#info]]
				end,
				set = function(info, value)
					NE_Options.db.profile.unitframes[info[#info]] = value
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
						NE_Options.UpdateFrames()
					end
				end,
				args = {
					classColorHealth = {
						order = 1,
						name = "Class-colored Health Bars",
						desc = "Use class colors for health bars in unit frames.",
						type = "toggle",
						width = "double",
					},
				},
			},
			tooltip = {
				order = 4,
				name = "Tooltip",
				icon = "4622480", -- :D
				type = "group",
				get = function(info)
					return NE_Options.db.profile.tooltip[info[#info]]
				end,
				set = function(info, value)
					NE_Options.db.profile.tooltip[info[#info]] = value
				end,
				args = {
					hideRank = {
						order = 1,
						name = "Hide Rank",
						desc = "Hide player guild ranks.",
						type = "toggle",
						width = "double",
					},

					hideJunkGuild = {
						order = 2,
						name = "Hide Junk Guild",
						desc = "Abbreviated GuildName.",
						type = "toggle",
						width = "double",
					},

					factionIcon = {
						order = 3,
						name = "Show Faction Icon",
						desc = "Display faction icons.",
						type = "toggle",
						width = "double",
					},

					lfdRole = {
						order = 4,
						name = "Show LFD Role Text",
						desc = "Display LFD role icons (tank, healer, damage).",
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

					combatHide = {
						order = 6,
						name = "Hide in Combat",
						desc = "Automatically hide the tip in combat.",
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

					SpecLevelByShift = {
						order = 9,
						name = "Spec-Level By Shift",
						desc = "Show iLvl by SHIFT.",
						type = "toggle",
						width = "double",
					},
				},
			},
			worldmap = {
				order = 5,
				name = "WorldMap",
				icon = "134269", -- :D
				type = "group",
				get = function(info)
					return NE_Options.db.profile.worldmap[info[#info]]
				end,
				set = function(info, value)
					NE_Options.db.profile.worldmap[info[#info]] = value
				end,
				args = {
					SmallWorldMap = {
						order = 1,
						name = "Compact World Map",
						desc = "Toggle to use a smaller version of the world map.",
						type = "toggle",
						width = "double",
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

					SmallWorldMapScale = {
						order = 4,
						name = "Compact Map Scale",
						desc = "Adjust the scale of the smaller world map.",
						type = "range",
						min = 0.5,
						max = 1.0,
						step = 0.1,
						width = "double",
						disabled = function()
							return not NE_Options.db.profile.worldmap.SmallWorldMap
						end,
					},

					AlphaWhenMoving = {
						order = 5,
						name = "Map Transparency When Moving",
						desc = "Adjust the transparency level of the world map when you are moving.",
						type = "range",
						min = 0.1,
						max = 1.0,
						step = 0.1,
						width = "double",
						disabled = function()
							return not NE_Options.db.profile.worldmap.FadeWhenMoving
						end,
					},
				},
			},
			automation = {
				order = 6,
				name = "Automation",
				icon = "1405803", -- :D
				type = "group",
				get = function(info)
					return NE_Options.db.profile.automation[info[#info]]
				end,
				set = function(info, value)
					NE_Options.db.profile.automation[info[#info]] = value
				end,
				args = {
					AutoSell = {
						order = 1,
						name = "Auto-Sell Trash",
						desc = "Automatically sells junk items when visiting a vendor.",
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
				},
			},
			general = {
				order = 7,
				name = NEW .. "General",
				icon = "463852", -- :D
				type = "group",
				get = function(info)
					return NE_Options.db.profile.general[info[#info]]
				end,
				set = function(info, value)
					NE_Options.db.profile.general[info[#info]] = value
					if info[#info] == "AutoScale" or info[#info] == "UIScale" then
						NE_Options:SetupUIScale()
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
							return NE_Options.db.profile.general.AutoScale
						end,
					},
				},
			},
			loot = {
				order = 8,
				name = "Loot",
				icon = "", -- :D
				type = "group",
				get = function(info)
					return NE_Options.db.profile.loot[info[#info]]
				end,
				set = function(info, value)
					NE_Options.db.profile.loot[info[#info]] = value
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
			-- Add additional sections similarly
		},
	})

	LibStub("AceConfigDialog-3.0"):AddToBlizOptions(NexEnhance)
end

SettingsPanel:HookScript("OnShow", function()
	CreateOptions() -- Load on demand
end)

-- NE_Options:RegisterSlash("/nexe", "/ne", function()
-- 	Settings.OpenToCategory(NexEnhance)
-- end)
