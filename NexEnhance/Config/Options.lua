local AddonName, Config = ...

-- Constants
local DEFAULT_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local DEFAULT_SIZE = 16
local HeaderTag = "|cff00cc4c"

-- Variables
local reloadUIPending = false -- Flag to track if a UI reload popup is already shown or pending

-- Functions

-- Updates options in AceConfigRegistry-3.0 if SettingsPanel is shown
local function UpdateOptions()
	if SettingsPanel:IsShown() then
		LibStub("AceConfigRegistry-3.0"):NotifyChange(AddonName)
	end
end

-- Generates texture markup for an icon
local function GetTextureMarkup(icon, width, height)
	icon = icon or DEFAULT_ICON
	width = width or DEFAULT_SIZE
	height = height or DEFAULT_SIZE
	return string.format("|T%s:%d|t", icon, width, height)
end

-- Generates atlas markup for an icon
local function GetAtlasMarkup(atlas, width, height)
	-- atlas = atlas or DEFAULT_ATLAS
	width = width or DEFAULT_SIZE
	height = height or DEFAULT_SIZE
	return string.format("|A:%s:%d:%d|a", atlas, width, height)
end

-- Retrieves icon string; validation check included
local function GetIconString(iconMarkup)
	if not iconMarkup then
		error("Invalid input parameter for GetIconString")
	end
	return iconMarkup
end

-- Helper function to show a reload UI confirmation popup
local function ShowReloadUIPopup()
	if not reloadUIPending then
		reloadUIPending = true
		StaticPopupDialogs["RELOAD_UI_CONFIRM"] = {
			text = "Reloading " .. AddonName .. " is necessary to apply this setting.\nDo you want to reload now?",
			button1 = "Reload UI",
			button2 = "Remind Me Later",
			OnAccept = function()
				reloadUIPending = false
				ReloadUI()
			end,
			OnCancel = function()
				reloadUIPending = false
				Config:Print("We'll remind you again right away when you change another option that requires this reload! :D")
			end,
			timeout = 0,
			whileDead = true,
			hideOnEscape = true,
			preferredIndex = 3,
		}
		StaticPopup_Show("RELOAD_UI_CONFIRM")
	end
end

-- Tooltip notice for reload requirement
-- Only to be placed on settings we need to have a reload to take effect
local AddReloadNotice = "|n|n|cff5bc0beChanging this option requires a UI reload.|r"

-- Lets users know this is a new feature
local NewFeatureIcon = GetTextureMarkup(DEFAULT_ICON, DEFAULT_SIZE)
local NewFeatureAtlas = GetAtlasMarkup("CharacterCreate-NewLabel", 32, 48)

-- Function to open the config and select a specific group
function OpenConfigWithDefaultGroup(groupName)
	-- Open the main options panel
	LibStub("AceConfigDialog-3.0"):Open(AddonName)
	-- Select the specified group
	LibStub("AceConfigDialog-3.0"):SelectGroup(AddonName, groupName)
end

local function CreateOptions()
	CreateOptions = Config.Dummy -- we only want to load this once

	--LibStub("AceConfig-3.0"):RegisterOptionsTable(AddonName, {
	-- Register the options table with AceConfig
	local options = {
		type = "group",
		args = {
			intro = {
				name = "Enhance WoW with quality of life improvements and UI enhancements." .. "\n\n",
				type = "description",
				order = 0,
			},
			actionbars = {
				order = 1,
				name = "Actionbars",
				desc = "Configure action bar settings, including cooldown timers, range indicators, and more to enhance your gameplay experience.",
				icon = "4200123", -- :D
				type = "group",
				get = function(info)
					return Config.db.profile.actionbars[info[#info]]
				end,
				set = function(info, value)
					Config.db.profile.actionbars[info[#info]] = value
				end,
				args = {
					description = {
						name = "Configure action bar settings, including cooldown timers, range indicators, and more to enhance your gameplay experience.\n\n",
						type = "description",
						order = 0,
						width = "double",
					},
					cooldowns = {
						order = 1,
						name = "Show Cooldown Timers",
						desc = "Enable or disable cooldown timers on action buttons.",
						type = "toggle",
						width = "double",
					},
					MmssTH = {
						order = 2,
						name = "MM:SS Threshold",
						desc = "Display cooldowns in MM:SS format if below this threshold. For example, 2 minutes and 30 seconds will be shown as 2:30.",
						type = "range",
						min = 60,
						max = 600,
						step = 1,
						width = "double",
						disabled = function()
							return not Config.db.profile.actionbars.cooldowns
						end,
					},
					TenthTH = {
						order = 3,
						name = "Decimal Threshold",
						desc = "Display cooldowns in decimal format if below this threshold. For example, 3 seconds will be shown as 3.0.",
						type = "range",
						min = 0,
						max = 60,
						step = 1,
						width = "double",
						disabled = function()
							return not Config.db.profile.actionbars.cooldowns
						end,
					},
					OverrideWA = {
						order = 4,
						name = "Override WeakAuras",
						desc = "Hide cooldown timers on WeakAuras.",
						type = "toggle",
						width = "double",
						disabled = function()
							return not Config.db.profile.actionbars.cooldowns
						end,
					},
					range = {
						order = 5,
						name = "Range Indicator",
						desc = "Change the color of action buttons when they are out of range or when the player lacks the resources (e.g., energy, mana) to use them.",
						type = "toggle",
						width = "double",
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
					elseif info[#info] == "AutoInvite" then
						Config:CreateAutoInvite()
					end
				end,
				args = {
					description = {
						name = "Customize automated actions to streamline gameplay, from removing annoying buffs to auto-repairing gear and more." .. "\n\n",
						type = "description",
						order = 0,
						width = "double",
					},
					AnnoyingBuffs = {
						order = 1,
						name = "Remove Annoying Buffs",
						desc = "Automatically remove specified annoying buffs from your character.",
						type = "toggle",
						width = "double",
					},
					AutoInvite = {
						order = 2,
						name = "Auto Accept Party Invites",
						desc = "Automatically accepts party invites from friends, guild members, or Battle.net friends.",
						type = "toggle",
						width = "double",
					},
					AutoRepair = {
						order = 3,
						name = "Auto Repair",
						desc = "Automatically repairs your gear using the specified source: None, Guild Bank, or Player Funds.",
						type = "select",
						values = { [0] = NONE, [1] = GUILD, [2] = PLAYER },
					},
					AutoSell = {
						order = 4,
						name = "Auto-Sell Trash",
						desc = "Automatically sells junk items when visiting a vendor.",
						type = "toggle",
						width = "double",
					},
					CinematicSkip = {
						order = 5,
						name = "Cinematic Skipping",
						desc = "Skip cinematics by pressing a designated key (ESC, SPACE, or ENTER).",
						type = "toggle",
						width = "double",
					},
					DeclineDuels = {
						order = 6,
						name = "Auto-Decline Duels",
						desc = "Automatically declines incoming duel requests.",
						type = "toggle",
						width = "double",
					},
					DeclinePetDuels = {
						order = 7,
						name = "Auto-Decline Pet Duels",
						desc = "Automatically declines incoming battle-pet duel requests.",
						type = "toggle",
						width = "double",
					},
					AutoScreenshotAchieve = {
						order = 8,
						name = "Auto-Screenshot on Achievement",
						desc = "Automatically takes a screenshot when you earn an achievement.",
						type = "toggle",
						width = "double",
					},
				},
			},
			chat = {
				order = 3,
				name = "Chat",
				desc = "Customize chat settings to enhance your communication experience, including background visibility, URL copying, and sticky chat behavior.",
				icon = "2056011", -- :D
				type = "group",
				get = function(info)
					return Config.db.profile.chat[info[#info]]
				end,
				set = function(info, value)
					Config.db.profile.chat[info[#info]] = value
					if info[#info] == "Background" then
						Config.Chat:ToggleChatBackground()
					elseif info[#info] == "StickyChat" then
						Config.Chat:ChatWhisperSticky()
					end
				end,
				args = {
					description = {
						name = "Customize chat settings to enhance your communication experience, including background visibility, URL copying, and sticky chat behavior." .. "\n\n",
						type = "description",
						order = 0,
						width = "double",
					},
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
					StickyChat = {
						order = 3,
						name = "StickyChat",
						desc = "StickyChat.",
						type = "toggle",
						width = "double",
					},
					chatfilters = {
						order = 4,
						name = "Chat Filters",
						type = "group",
						inline = true,
						get = function(info)
							return Config.db.profile.chat.chatfilters[info[#info]]
						end,
						set = function(info, value)
							Config.db.profile.chat.chatfilters[info[#info]] = value
							if info[#info] == "ChatFilterList" then
								Config.Chat:UpdateFilterList()
							elseif info[#info] == "ChatFilterWhiteList" then
								Config.Chat:UpdateFilterWhiteList()
							end
						end,
						args = {
							EnableFilter = {
								order = 1,
								name = HeaderTag .. "Enable Chat Filter",
								desc = "Enables or disables the chat filtering system.",
								type = "toggle",
								width = "normal",
							},
							FilterMatches = {
								order = 2,
								name = "Filter Matches Count",
								desc = "Enter the number of keyword matches required to filter a message.",
								type = "input",
								width = "normal",
								-- validate input as a number
								validate = function(info, value)
									local numValue = tonumber(value)
									if numValue and numValue > 0 then
										return true
									else
										return "Please enter a valid number."
									end
								end,
							},
							BlockStrangers = {
								order = 3,
								name = "Block Strangers",
								desc = "Blocks messages from unknown players who are not in your friends list or guild.",
								type = "toggle",
								width = "double",
							},
							BlockSpammer = {
								order = 4,
								name = "Block Spammers",
								desc = "Filters out messages from players who are flagged as spammers or sending repetitive messages.",
								type = "toggle",
								width = "double",
							},
							ChatItemLevel = {
								order = 5,
								name = "Show Item Level in Chat",
								desc = "Displays the item level of linked gear in chat.",
								type = "toggle",
								width = "double",
							},
							BlockAddonAlert = {
								order = 6,
								name = "Block Addon Alerts",
								desc = "Blocks automated messages from addons, including announcements of abilities, deaths, or interrupts.",
								type = "toggle",
								width = "double",
							},
							ChatFilterList = {
								order = 7,
								name = "Chat Filter List",
								desc = "Specify a list of patterns to filter out messages in chat. Use spaces to separate multiple patterns.",
								type = "input",
								width = "full",
								multiline = true, -- Allows multiple lines for ease of input
							},
							ChatFilterWhiteList = {
								order = 8,
								name = "Chat Filter Whitelist",
								desc = "Specify a list of allowed terms or patterns that bypass the chat filter. Use spaces to separate multiple terms.",
								type = "input",
								width = "full",
								multiline = true, -- Allows multiple lines for ease of input
							},
						},
					},
				},
			},
			experience = {
				order = 4,
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
				order = 5,
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
					elseif info[#info] == "numberPrefixStyle" then
						Config:ForceUpdatePrefixStyle()
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
					numberPrefixStyle = {
						order = 3,
						name = "Number Abbreviation Style",
						desc = "Select how numerical values should be abbreviated in the UI.",
						type = "select",
						values = { ["STANDARD"] = "Standard: b/m/k", ["ASIAN"] = "Asian: y/w", ["FULL"] = "Full digitals" },
					},
				},
			},
			loot = {
				order = 6,
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
				order = 7,
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
					recycleBin = {
						order = 2, -- Changed to 2 to maintain order with EasyVolume
						name = "Minimap Button Collection",
						desc = "Collects minimap buttons into a single pop-up menu for easier access and cleaner minimap.",
						type = "toggle",
						width = "double",
						disabled = function()
							if C_AddOns.IsAddOnLoaded("MBB") then
								-- Set recycleBin to false if the addon is loaded
								Config.db.profile.minimap.recycleBin = false
								return true
							end
							return false
						end,
					},
				},
			},
			miscellaneous = {
				order = 8,
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
					disableTalkingHead = {
						order = 1,
						name = "Disable TalkingHead",
						desc = "Disables the Talking Head Frame, preventing pop-up dialogues from appearing during gameplay.",
						type = "toggle",
						width = "double",
					},
					enableAFKMode = {
						order = 2,
						name = "AFK Mode",
						desc = "AFK mode with dynamic features such as automatic guild display, random statistics updates, and a countdown timer, enhancing the AFK experience for players..",
						type = "toggle",
						width = "double",
					},
					missingStats = {
						order = 3,
						name = "Enhanced Character Statistics",
						desc = "Enhances the default character statistics panel by organizing stats, adjusting display data for improved readability, and integrating additional functionalities for detailed stat insights.",
						type = "toggle",
						width = "double",
					},
					gemsNEnchants = {
						order = 4,
						name = NewFeatureAtlas .. "Show Gems and Enchants",
						desc = "Displays gems and enchantments on the character frame and inspect frame, allowing quick access to view gear enhancements without additional tooltips.",
						type = "toggle",
						width = "double",
					},
					questXPPercent = {
						order = 6,
						name = "Enhanced Quest XP Display",
						desc = "Enhances the display of quest XP rewards to show percentage of total experience gained.",
						type = "toggle",
						width = "double",
					},
					questRewardsMostValueIcon = {
						order = 7,
						name = "Highlight Best Quest Reward",
						desc = "Highlights the most valuable quest reward choice with a gold coin icon overlay based on potential sell value.",
						type = "toggle",
						width = "double",
					},
					alreadyKnown = {
						order = 8,
						name = NewFeatureAtlas .. "Highlight Already Known Items",
						desc = "Highlights items that are already known (e.g., mounts, pets, recipes) in various UI elements like quest rewards, buyback items, and guild bank.",
						type = "toggle",
						width = "double",
					},
					itemlevels = {
						order = 9,
						name = "ItemLevels",
						type = "group",
						inline = true,
						get = function(info)
							return Config.db.profile.miscellaneous.itemlevels[info[#info]]
						end,
						set = function(info, value)
							Config.db.profile.miscellaneous.itemlevels[info[#info]] = value
						end,
						args = {
							characterFrame = {
								order = 1,
								name = NewFeatureAtlas .. "Show Item Level on Character Frame",
								desc = "Shows item levels on the character frame.",
								type = "toggle",
								width = "double",
							},
							inspectFrame = {
								order = 2,
								name = NewFeatureAtlas .. "Show Item Level on Inspect Frame",
								desc = "Shows item levels on the inspect frame.",
								type = "toggle",
								width = "double",
							},
							merchantFrame = {
								order = 3,
								name = NewFeatureAtlas .. "Show Item Level on Merchant Frame",
								desc = "Shows item levels on the merchant frame.",
								type = "toggle",
								width = "double",
							},
							tradeFrame = {
								order = 4,
								name = NewFeatureAtlas .. "Show Item Level on Trade Frame",
								desc = "Shows item levels on the trade frame.",
								type = "toggle",
								width = "double",
							},
							lootFrame = {
								order = 5,
								name = NewFeatureAtlas .. "Show Item Level on Loot Frame",
								desc = "Shows item levels on the loot frame.",
								type = "toggle",
								width = "double",
							},
							guildBankFrame = {
								order = 6,
								name = NewFeatureAtlas .. "Show Item Level on Guild Bank Frame",
								desc = "Shows item levels on the guild bank frame.",
								type = "toggle",
								width = "double",
							},
							containers = {
								order = 7,
								name = NewFeatureAtlas .. "Show Item Level on Containers",
								desc = "Shows item levels on default containers (bags).",
								type = "toggle",
								width = "double",
							},
							flyout = {
								order = 8,
								name = NewFeatureAtlas .. "Show Item Level on Equipment Flyout",
								desc = "Shows item levels on equipment flyout buttons.",
								type = "toggle",
								width = "double",
							},
							scrapping = {
								order = 9,
								name = NewFeatureAtlas .. "Show Item Level on Scrapping Machine Frame",
								desc = "Shows item levels on the scrapping machine frame.",
								type = "toggle",
								width = "double",
							},
						},
					},
				},
			},
			skins = {
				order = 9,
				name = "Skins",
				icon = "4620680", -- :D
				type = "group",
				get = function(info)
					return Config.db.profile.skins[info[#info]]
				end,
				set = function(info, value)
					Config.db.profile.skins[info[#info]] = value
				end,
				args = {
					blizzskins = {
						order = 1,
						name = "Blizzard Frame Enhancements",
						type = "group",
						inline = true,
						get = function(info)
							return Config.db.profile.skins.blizzskins[info[#info]]
						end,
						set = function(info, value)
							Config.db.profile.skins.blizzskins[info[#info]] = value
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
								name = "Enhanced Objective Tracker",
								desc = "Enhances the Objective Tracker for a more modern look.",
								type = "toggle",
								width = "double",
							},
						},
					},
					addonskins = {
						order = 3,
						name = "Addon Frame Enhancements",
						type = "group",
						inline = true,
						get = function(info)
							return Config.db.profile.skins.addonskins[info[#info]]
						end,
						set = function(info, value)
							Config.db.profile.skins.addonskins[info[#info]] = value
						end,
						args = {
							details = {
								order = 1,
								name = "Enhanced Details! Skin",
								desc = "Improves the appearance and functionality of the Details! addon frames.",
								type = "toggle",
								width = "normal",
								disabled = function()
									return not C_AddOns.IsAddOnLoaded("Details")
								end,
							},
							applyDetails = { -- Add popup one day. Too lazy to do it. I need to add a file to hold popups.
								order = 2,
								name = "Reset Details! Skin",
								desc = "Resets the enhanced Details! skin settings.",
								type = "execute",
								func = function()
									print("Resetting Details! skin settings...")
									Config:ResetDetailsAnchor(true)
								end,
								width = "normal",
								disabled = function()
									return not C_AddOns.IsAddOnLoaded("Details")
								end,
							},
						},
					},
				},
			},
			tooltip = {
				order = 10,
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
						name = "Combat Tip Hide",
						desc = "Automatically hide tooltips during combat.",
						type = "toggle",
						width = "double",
					},
					factionIcon = {
						order = 3,
						name = "Faction Icons",
						desc = "Display faction icons on tooltips.",
						type = "toggle",
						width = "double",
					},
					hideJunkGuild = {
						order = 4,
						name = "Abbreviate Guild Names",
						desc = "Show abbreviated guild names.",
						type = "toggle",
						width = "double",
					},
					hideRank = {
						order = 5,
						name = "Hide Guild Ranks",
						desc = "Hide player guild ranks in tooltips.",
						type = "toggle",
						width = "double",
					},
					hideTitle = {
						order = 6,
						name = "Hide Player Titles",
						desc = "Hide player titles in tooltips.",
						type = "toggle",
						width = "double",
					},
					lfdRole = {
						order = 7,
						name = "LFD Role Icons",
						desc = "Display role icons for tank, healer, and damage.",
						type = "toggle",
						width = "double",
					},
					mdScore = {
						order = 8,
						name = "Mythic Dungeon Score",
						desc = "Display the player's Mythic Dungeon score.",
						type = "toggle",
						width = "double",
					},
					qualityColor = {
						order = 9,
						name = "Item Quality Colors",
						desc = "Color item borders by their quality.",
						type = "toggle",
						width = "double",
					},
					ShowID = {
						order = 10,
						name = "Show Tooltip IDs",
						desc = "Display spell, item, quest, and other IDs in tooltips.",
						type = "toggle",
						width = "double",
					},
					SpecLevelByShift = {
						order = 11,
						name = "Shift+Spec Level",
						desc = "Show item level when holding SHIFT.",
						type = "toggle",
						width = "double",
					},
					cursorPosition = {
						order = 12,
						name = "Cursor Tooltip Position",
						desc = "Choose the position of tooltips in relation to the cursor.",
						type = "select",
						values = { ["DISABLE"] = "Disable", ["LEFT"] = "Left", ["TOP"] = "Top", ["RIGHT"] = "Right" },
					},
				},
			},
			unitframes = {
				order = 11,
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
							return C_AddOns.IsAddOnLoaded("BetterBlizzFrames")
						end,
					},
				},
			},
			worldmap = {
				order = 12,
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
			-- bugfixes = {
			-- 	order = 13,
			-- 	name = "BugFixes",
			-- 	icon = "134520", -- :D
			-- 	type = "group",
			-- 	get = function(info)
			-- 		return Config.db.profile.bugfixes[info[#info]]
			-- 	end,
			-- 	set = function(info, value)
			-- 		Config.db.profile.bugfixes[info[#info]] = value
			-- 		if info[#info] == "DruidFormFix" then
			-- 			Config:EnableModule(value)
			-- 		end
			-- 	end,
			-- },
			discordlink = {
				name = "|CFFf6f8faDiscord|r",
				desc = "Open the Discord link for Nexenhance",
				order = 98,
				type = "execute",
				func = function()
					StaticPopupDialogs["NE_DISCORD_POPUP"] = {
						text = "|T236688:36|t\n\n" .. "Copy the link below and thank you for using NexEnhance!",
						button1 = "OK",
						OnShow = function(self, data)
							self.editBox:SetText("https://discord.com/invite/Rc9wcK9cAB")
							self.editBox:HighlightText()
						end,
						OnCancel = function(_, _, reason)
							if reason == "timeout" then
								Config:Print("Your Discord link edit box timed out. If this was a mistake, please try again. Thank you.")
							end
						end,
						timeout = 20,
						whileDead = false,
						hideOnEscape = true,
						enterClicksFirstButton = true,
						hasEditBox = true,
						editBoxWidth = 350, -- Adjust the width as needed
						preferredIndex = 3,
					}
					StaticPopup_Show("NE_DISCORD_POPUP")
				end,
			},
			githublink = {
				name = "|CFFf6f8faGitHub|r",
				desc = "Open the GitHub repository for Nexenhance",
				order = 99,
				type = "execute",
				func = function()
					StaticPopupDialogs["NE_GITHUB_POPUP"] = {
						text = "|T236688:36|t\n\n" .. "Copy the link below and thank you for using NexEnhance!",
						button1 = "OK",
						OnShow = function(self, data)
							self.editBox:SetText("https://github.com/Kkthnx-Wow/NexEnhance")
							self.editBox:HighlightText()
						end,
						OnCancel = function(_, _, reason)
							if reason == "timeout" then
								Config:Print("Your GitHub link edit box timed out. If this was a mistake, please try again. Thank you.")
							end
						end,
						timeout = 20,
						whileDead = false,
						hideOnEscape = true,
						enterClicksFirstButton = true,
						hasEditBox = true,
						editBoxWidth = 350, -- Adjust the width as needed
						preferredIndex = 3,
					}
					StaticPopup_Show("NE_GITHUB_POPUP")
				end,
			},
			kkthnxprofile = {
				name = GetAtlasMarkup("BuildanAbomination-32x32", 18) .. " |CFFf6f8faKkthnx Profile|r",
				desc = "Brace yourself for Kkthnx's epic setup! Unleash the power...or just enjoy a better UI.",
				order = 100,
				type = "execute",
				func = function()
					StaticPopupDialogs["KK_PROFILE_POPUP"] = {
						text = "Are you sure you would like to load |cff669DFFKkthnx's|r personal profile for |cff5bc0beNexEnhance|r?",
						button1 = "Yes, bring it on!",
						button2 = "No, maybe later...",
						OnAccept = function()
							Config:ForceLoadKkthnxProfile()
							ReloadUI()
						end,
						OnCancel = function() end,
						timeout = 0,
						whileDead = false,
						hideOnEscape = true,
						enterClicksFirstButton = true,
						preferredIndex = 3,
					}
					StaticPopup_Show("KK_PROFILE_POPUP")
				end,
			},
		},
	}

	LibStub("AceConfig-3.0"):RegisterOptionsTable(AddonName, options)
	LibStub("AceConfigDialog-3.0"):AddToBlizOptions(AddonName, "|cff5bc0be" .. AddonName .. "|r")

	-- handle combat updates
	local EventHandler = CreateFrame("Frame", nil, SettingsPanel)
	EventHandler:RegisterEvent("PLAYER_REGEN_ENABLED")
	EventHandler:RegisterEvent("PLAYER_REGEN_DISABLED")
	EventHandler:SetScript("OnEvent", UpdateOptions)
end

function Config:ADDON_LOADED(addon)
	if addon ~= "NexEnhance" then
		return
	end

	CreateOptions() -- Load on demand
	Config:SetupUIScale(true)
end

Config:RegisterSlash("/nexe", "/ne", function()
	OpenConfigWithDefaultGroup("general")
end)
