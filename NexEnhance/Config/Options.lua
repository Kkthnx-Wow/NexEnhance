local AddonName, Config = ...

local DEFAULT_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local DEFAULT_SIZE = 16

local function UpdateOptions()
	if SettingsPanel:IsShown() then
		LibStub("AceConfigRegistry-3.0"):NotifyChange(AddonName)
	end
end

local function GetTextureMarkup(icon, size)
	icon = icon or DEFAULT_ICON
	size = size or DEFAULT_SIZE
	return string.format("|T%s:%d|t", icon, size)
end

local function GetAtlasMarkup(atlas, size)
	size = size or DEFAULT_SIZE
	return string.format("|A:%s:%d:%d|a", atlas, size, size)
end

local function GetIconString(iconMarkup)
	if not iconMarkup then
		error("Invalid input parameter for GetIconString")
	end
	return iconMarkup
end

local NewFeature = GetTextureMarkup(DEFAULT_ICON, DEFAULT_SIZE)
local HeaderTag = "|cff00cc4c"

local function CreateOptions()
	CreateOptions = Config.Dummy -- we only want to load this once

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
					if info[#info] == "DeclineDuels" or info[#info] == "DeclinePetDuels" then
						Config:CreateAutoDeclineDuels()
					elseif info[#info] == "AutoScreenshotAchieve" then
						Config:ToggleAutoScreenshotAchieve()
					end
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
					CinematicSkip = {
						order = 4,
						name = "Cinematic Skipping",
						desc = "Skip cinematics by pressing a designated key (ESC, SPACE, or ENTER).",
						type = "toggle",
						width = "double",
					},
					DeclineDuels = {
						order = 5,
						name = "Auto-Decline Duels",
						desc = "Automatically declines incoming duel requests.",
						type = "toggle",
						width = "double",
					},
					DeclinePetDuels = {
						order = 6,
						name = "Auto-Decline Pet Duels",
						desc = "Automatically declines incoming battle-pet duel requests.",
						type = "toggle",
						width = "double",
					},
					AutoScreenshotAchieve = {
						order = 7,
						name = "Auto-Screenshot on Achievement",
						desc = "Automatically takes a screenshot when you earn an achievement.|n|n|A:UI-Achievement-Alert-Background:0:0:0:0|a",
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
						order = 3,
						name = "Enhanced ObjectiveTracker",
						desc = "Enhances the ObjectiveTracker for a more modern look.",
						type = "toggle",
						width = "double",
					},
				},
			},
			chat = {
				order = 3,
				name = "Chat",
				icon = "2056011", -- :D
				type = "group",
				get = function(info)
					return Config.db.profile.chat[info[#info]]
				end,
				set = function(info, value)
					Config.db.profile.chat[info[#info]] = value
					if info[#info] == "Background" then
						Config:ToggleChatBackground()
					end
				end,
				args = {
					Background = {
						order = 1,
						name = "Chat Background",
						desc = "Show or hide a background on the chat window.",
						type = "toggle",
						width = "double",
					},
					URLCopy = { -- Change the name from URL to something else. This doesnt explain much!!!
						order = 2,
						name = "Copy Chat URLs",
						desc = "Allow copying of URLs directly from the chat window.",
						type = "toggle",
						width = "double",
					},
				},
			},
			experience = {
				order = 3,
				name = "Experience",
				icon = "894556", -- :D
				type = "group",
				get = function(info)
					return Config.db.profile.experience[info[#info]]
				end,
				set = function(info, value)
					Config.db.profile.experience[info[#info]] = value
					if info[#info] == "showBubbles" then
						if Config.bar then
							Config:ManageBarBubbles(Config.bar)
						end
					elseif info[#info] == "barTextFormat" or info[#info] == "numberFormat" then
						if Config.bar then
							Config.OnExpBarEvent(Config.bar)
						end
					elseif info[#info] == "barWidth" then
						if Config.bar then
							Config.bar:SetWidth(value)
							Config:ManageBarBubbles(Config.bar)
						end
					elseif info[#info] == "barHeight" then
						if Config.bar then
							Config.bar:SetHeight(value)
							Config:ManageBarBubbles(Config.bar)
							Config:ForceTextScaling(Config.bar)
						end
					end
				end,
				args = {
					enableExp = {
						order = 1,
						name = HeaderTag .. "Enable",
						desc = "Toggle the display of NexEnhances experience bar.",
						type = "toggle",
						width = "double",
					},
					showBubbles = {
						order = 2,
						name = "Show Bubbles",
						desc = "Show bubbles on experience / rep bars.",
						type = "toggle",
						width = "double",
					},
					numberFormat = {
						order = 3,
						name = "Number Format",
						desc = "Choose the format for numbers.",
						type = "select",
						values = { [1] = "Standard: b/m/k", [2] = "Asian: y/w", [3] = PLAYER },
					},
					barTextFormat = {
						order = 4,
						name = "Bar Text Format",
						desc = "Choose the format for the text on the bar",
						type = "select",
						values = { ["PERCENT"] = "Percent", ["CURMAX"] = "Current - Max", ["CURPERC"] = "Current - Percent", ["CUR"] = "Current", ["REM"] = "Remaining", ["CURREM"] = "Current - Remaining", ["CURPERCREM"] = "Current - Percent (Remaining)" },
					},
					barWidth = {
						order = 5,
						name = "Bar Width",
						desc = "Adjust the width of the bar. Default is 500. Minimum is 200. Maximum is the screen width.",
						type = "range",
						min = 200,
						max = Config.ScreenWidth,
						step = 1,
						width = "double",
					},
					barHeight = {
						order = 6,
						name = "Bar Height",
						desc = "Adjust the height of the bar. Default is 12. Minimum is 10. Maximum is 40.",
						type = "range",
						min = 10,
						max = 40,
						step = 1,
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
			minimap = {
				order = 6,
				name = "Minimap",
				icon = "1064187", -- :D
				type = "group",
				get = function(info)
					return Config.db.profile.minimap[info[#info]]
				end,
				set = function(info, value)
					Config.db.profile.minimap[info[#info]] = value
				end,
				args = {
					EasyVolume = {
						order = 1,
						name = "Easy Volume Control",
						desc = "Easy control of the master volume using the mouse wheel on the minimap while holding the Control key.",
						type = "toggle",
						width = "double",
					},
				},
			},
			miscellaneous = {
				order = 7,
				name = "Miscellaneous",
				icon = "134169", -- :D
				type = "group",
				get = function(info)
					return Config.db.profile.miscellaneous[info[#info]]
				end,
				set = function(info, value)
					Config.db.profile.miscellaneous[info[#info]] = value
					if info[#info] == "enableAFKMode" then
						Config.ToggleAFKMode()
					end
				end,
				args = {
					enableAFKMode = {
						order = 1,
						name = "AFK Mode",
						desc = "AFK mode with dynamic features such as automatic guild display, random statistics updates, and a countdown timer, enhancing the AFK experience for players..",
						type = "toggle",
						width = "double",
					},
					missingStats = {
						order = 2,
						name = "Enhanced Character Statistics",
						desc = "Enhances the default character statistics panel by organizing stats, adjusting display data for improved readability, and integrating additional functionalities for detailed stat insights.",
						type = "toggle",
						width = "double",
					},
					questXPPercent = {
						order = 3,
						name = "Enhanced Quest XP Display",
						desc = "Enhances the display of quest XP rewards to show percentage of total experience gained.",
						type = "toggle",
						width = "double",
					},
					questRewardsMostValueIcon = {
						order = 4,
						name = "Highlight Best Quest Reward",
						desc = "Highlights the most valuable quest reward choice with a gold coin icon overlay based on potential sell value.",
						type = "toggle",
						width = "double",
					},
				},
			},
			tooltip = {
				order = 8,
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
				order = 9,
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
				order = 10,
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
			bugfixes = {
				order = 11,
				name = "BugFixes",
				icon = "134520", -- :D
				type = "group",
				get = function(info)
					return Config.db.profile.bugfixes[info[#info]]
				end,
				set = function(info, value)
					Config.db.profile.bugfixes[info[#info]] = value
					if info[#info] == "DruidFormFix" then
						Config:EnableModule(value)
					end
				end,
				args = {
					DruidFormFix = {
						order = 1,
						name = "Druid Model Display Fix",
						desc = "Resolves the Character UI model display issue caused by using the Glyph of Stars.|n|nThis bug is expected to be fixed by Blizzard in patch 10.2.0, after which this module will be removed.",
						type = "toggle",
						width = "double",
						disabled = function()
							local _, _, classID = UnitClass("player")
							return classID ~= 11
						end,
					},
				},
			},
			-- Add additional sections similarly
		},
	})

	LibStub("AceConfigDialog-3.0"):AddToBlizOptions(AddonName)

	-- handle combat updates
	local EventHandler = CreateFrame("Frame", nil, SettingsPanel)
	EventHandler:RegisterEvent("PLAYER_REGEN_ENABLED")
	EventHandler:RegisterEvent("PLAYER_REGEN_DISABLED")
	EventHandler:SetScript("OnEvent", UpdateOptions)
end

SettingsPanel:HookScript("OnShow", function()
	CreateOptions() -- Load on demand
	Config.CreateSupportGUI() -- LoD
end)

Config:RegisterSlash("/nexe", "/ne", function()
	Settings.OpenToCategory(AddonName)
end)
