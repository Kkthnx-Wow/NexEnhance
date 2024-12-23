local AddonName, Config = ...

-- Constants
local DEFAULT_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local DEFAULT_ICON_SIZE = 16
local DEFAULT_ATLAS_ICON = "SmallQuestBang"
local DEFAULT_ATLAS_SIZE = 32

-- Functions

-- Updates options in AceConfigRegistry-3.0 if SettingsPanel is shown
local function UpdateOptions()
	if SettingsPanel:IsShown() then
		LibStub("AceConfigRegistry-3.0"):NotifyChange(AddonName)
	end
end

-- Generates texture markup for an icon
local function GetTextureMarkup(icon, height, width)
	icon = icon or DEFAULT_ICON
	height = height or DEFAULT_ICON_SIZE
	width = width or DEFAULT_ICON_SIZE
	return string.format("|T%s:%d|t", icon, width, height)
end

-- Generates atlas markup for an icon
local function GetAtlasMarkup(atlas, height, width)
	atlas = atlas or DEFAULT_ATLAS_ICON
	height = height or DEFAULT_ATLAS_SIZE
	width = width or DEFAULT_ATLAS_SIZE
	return string.format("|A:%s:%d:%d|a", atlas, width, height)
end

-- Lets users know this is a new feature
local NewFeatureIcon = GetTextureMarkup(DEFAULT_ICON, DEFAULT_ICON_SIZE, DEFAULT_ICON_SIZE)
local NewFeatureAtlas = GetAtlasMarkup("newplayerchat-chaticon-newcomer", 15, 15)

-- Function to open the config and select a specific group
function OpenConfigWithDefaultGroup(groupName)
	-- Open the main options panel
	LibStub("AceConfigDialog-3.0"):Open(AddonName)
	-- Select the specified group
	LibStub("AceConfigDialog-3.0"):SelectGroup(AddonName, groupName)
end

local function CreateOptions()
	CreateOptions = Config.Dummy -- we only want to load this once
	-- Register the options table with AceConfig
	local options = {
		type = "group",
		args = {
			intro = {
				name = "Enhance WoW with quality of life improvements and UI enhancements." .. "\n\n",
				type = "description",
				order = 0,
			},
			general = {
				order = 1,
				name = "General",
				desc = "General settings for Config.",
				icon = "463852", -- :D
				type = "group",
				args = {
					AutoScale = {
						order = 1,
						name = "Dynamic UI Scaling",
						desc = "Automatically adjusts the UI scale to fit your screen.",
						type = "toggle",
						width = "double",
						get = function()
							return Config.NexConfig.general.AutoScale
						end,
						set = function(_, value)
							Config.NexConfig.general.AutoScale = value
							Config:SetupUIScale()
						end,
					},
					UIScale = {
						order = 2,
						name = "Custom Interface Scale",
						desc = "Manually set the scale of the user interface.",
						type = "range",
						width = "double",
						min = 0.43,
						max = 1.0,
						step = 0.01,
						disabled = function()
							return Config.NexConfig.general.AutoScale
						end,
						get = function()
							return Config.NexConfig.general.UIScale
						end,
						set = function(_, value)
							Config.NexConfig.general.UIScale = value
							Config:SetupUIScale()
						end,
					},
					SuppressTutorialPrompts = {
						order = 3,
						name = "Disable Tutorial Buttons",
						desc = "Enables or disables the tutorial buttons that appear in the interface.",
						type = "toggle",
						width = "double",
						get = function()
							return Config.NexConfig.general.disableTutorialButtons
						end,
						set = function(_, value)
							Config.NexConfig.general.disableTutorialButtons = value
						end,
					},
					NumberPrefixStyle = {
						order = 4,
						name = "Number Abbreviation Style",
						desc = "Select how numerical values should be abbreviated in the UI.",
						type = "select",
						values = {
							["STANDARD"] = "Standard: b/m/k",
							["ASIAN"] = "Asian: y/w",
							["FULL"] = "Full digitals",
						},
						get = function()
							return Config.NexConfig.general.NumberPrefixStyle
						end,
						set = function(_, value)
							Config.NexConfig.general.NumberPrefixStyle = value
						end,
					},
				},
			},
			actionbars = {
				order = 2,
				name = "Actionbars",
				desc = "Configure action bar settings, including cooldown timers, range indicators, and more to enhance your gameplay experience.",
				icon = "4200123", -- :D
				type = "group",
				args = {
					description = {
						name = "Configure action bar settings, including cooldown timers, range indicators, and more to enhance your gameplay experience.\n\n",
						type = "description",
						order = 0,
						width = "double",
					},
					nameSize = {
						order = 1,
						name = "Name Font Size",
						desc = "Adjust the font size of action button names.",
						type = "range",
						width = "double",
						min = 8,
						max = 20,
						step = 1,
						get = function()
							return Config.NexConfig.actionbars.nameSize
						end,
						set = function(_, value)
							Config.NexConfig.actionbars.nameSize = value
							Config.Actionbars:UpdateStylingConfig()
						end,
						disabled = function()
							return not Config.NexConfig.actionbars.showName
						end,
					},
					countSize = {
						order = 2,
						name = "Count Font Size",
						desc = "Adjust the font size of the item count.",
						type = "range",
						width = "double",
						min = 8,
						max = 20,
						step = 1,
						get = function()
							return Config.NexConfig.actionbars.countSize
						end,
						set = function(_, value)
							Config.NexConfig.actionbars.countSize = value
							Config.Actionbars:UpdateStylingConfig()
						end,
						disabled = function()
							return not Config.NexConfig.actionbars.showCount
						end,
					},
					hotkeySize = {
						order = 3,
						name = "Hotkey Font Size",
						desc = "Adjust the font size of the hotkey text.",
						type = "range",
						width = "double",
						min = 8,
						max = 20,
						step = 1,
						get = function()
							return Config.NexConfig.actionbars.hotkeySize
						end,
						set = function(_, value)
							Config.NexConfig.actionbars.hotkeySize = value
							Config.Actionbars:UpdateStylingConfig()
						end,
						disabled = function()
							return not Config.NexConfig.actionbars.showHotkey
						end,
					},
					showName = {
						order = 4,
						name = "Show Name",
						desc = "Enable or disable the name display.",
						type = "toggle",
						width = "double",
						get = function()
							return Config.NexConfig.actionbars.showName
						end,
						set = function(_, value)
							Config.NexConfig.actionbars.showName = value
							Config.Actionbars:UpdateStylingConfig()
						end,
					},
					showCount = {
						order = 5,
						name = "Show Count",
						desc = "Enable or disable the item count display.",
						type = "toggle",
						width = "double",
						get = function()
							return Config.NexConfig.actionbars.showCount
						end,
						set = function(_, value)
							Config.NexConfig.actionbars.showCount = value
							Config.Actionbars:UpdateStylingConfig()
						end,
					},
					showHotkey = {
						order = 6,
						name = "Show Hotkey",
						desc = "Enable or disable the hotkey display.",
						type = "toggle",
						width = "double",
						get = function()
							return Config.NexConfig.actionbars.showHotkey
						end,
						set = function(_, value)
							Config.NexConfig.actionbars.showHotkey = value
							Config.Actionbars:UpdateStylingConfig()
						end,
					},
					cooldowns = {
						order = 7,
						name = "Show Cooldown Timers",
						desc = "Enable or disable cooldown timers on action buttons.",
						type = "toggle",
						width = "double",
						get = function()
							return Config.NexConfig.actionbars.cooldowns
						end,
						set = function(_, value)
							Config.NexConfig.actionbars.cooldowns = value
						end,
					},
					MmssTH = {
						order = 8,
						name = "MM:SS Threshold",
						desc = "Display cooldowns in MM:SS format below this threshold.",
						type = "range",
						width = "double",
						min = 60,
						max = 600,
						step = 1,
						disabled = function()
							return not Config.NexConfig.actionbars.cooldowns
						end,
						get = function()
							return Config.NexConfig.actionbars.MmssTH
						end,
						set = function(_, value)
							Config.NexConfig.actionbars.MmssTH = value
						end,
					},
					TenthTH = {
						order = 9,
						name = "Decimal Threshold",
						desc = "Display cooldowns in decimal format below this threshold.",
						type = "range",
						width = "double",
						min = 0,
						max = 60,
						step = 1,
						disabled = function()
							return not Config.NexConfig.actionbars.cooldowns
						end,
						get = function()
							return Config.NexConfig.actionbars.TenthTH
						end,
						set = function(_, value)
							Config.NexConfig.actionbars.TenthTH = value
						end,
					},
					OverrideWA = {
						order = 10,
						name = "Override WeakAuras",
						desc = "Hide cooldown timers on WeakAuras.",
						type = "toggle",
						width = "double",
						disabled = function()
							return not Config.NexConfig.actionbars.cooldowns
						end,
						get = function()
							return Config.NexConfig.actionbars.OverrideWA
						end,
						set = function(_, value)
							Config.NexConfig.actionbars.OverrideWA = value
						end,
					},
					range = {
						order = 11,
						name = "Range Indicator",
						desc = "Change the color of action buttons when out of range or lacking resources.",
						type = "toggle",
						width = "double",
						get = function()
							return Config.NexConfig.actionbars.range
						end,
						set = function(_, value)
							Config.NexConfig.actionbars.range = value
						end,
					},
				},
			},
			automation = {
				order = 3,
				name = "Automation",
				desc = "Streamline gameplay with automation.",
				icon = "1405803", -- :D
				type = "group",
				args = {
					description = {
						order = 0,
						name = "Customize automated actions to streamline gameplay, from removing annoying buffs to auto-repairing gear and more.\n\n",
						type = "description",
						width = "double",
					},
					AnnoyingBuffs = {
						order = 1,
						name = "Remove Annoying Buffs",
						desc = "Automatically remove specified annoying buffs.",
						type = "toggle",
						width = "double",
						get = function()
							return Config.NexConfig.automation.AnnoyingBuffs
						end,
						set = function(_, value)
							Config.NexConfig.automation.AnnoyingBuffs = value
						end,
					},
					AutoInvite = {
						order = 2,
						name = "Auto Accept Party Invites",
						desc = "Automatically accepts party invites from friends or guild members.",
						type = "toggle",
						width = "double",
						get = function()
							return Config.NexConfig.automation.AutoInvite
						end,
						set = function(_, value)
							Config.NexConfig.automation.AutoInvite = value
						end,
					},
					AutoGoodbye = {
						order = 3,
						name = "Auto Goodbye",
						desc = "Enable or disable the Auto Goodbye feature. Sends a goodbye message automatically after group activities. You can set a custom goodbye message below.",
						type = "toggle",
						width = "double",
						get = function()
							return Config.NexConfig.automation.AutoGoodbye
						end,
						set = function(_, value)
							Config.NexConfig.automation.AutoGoodbye = value
						end,
					},
					CustomGoodbyeMessage = {
						order = 4,
						name = "Custom Goodbye Message",
						desc = "Enter a custom goodbye message to override the default random messages. Leave blank to use the default ('GG, everyone!').",
						type = "input",
						width = "double",
						get = function()
							return Config.NexConfig.automation.CustomGoodbyeMessage or ""
						end,
						set = function(_, value)
							Config.NexConfig.automation.CustomGoodbyeMessage = value
						end,
						disabled = function()
							return not Config.NexConfig.automation.AutoGoodbye
						end,
					},
					SkipCinematics = {
						order = 5,
						name = "Auto-Skip Cinematics",
						desc = "Automatically skip cinematics when specific keys (ESCAPE, SPACE, ENTER) are pressed.",
						type = "toggle",
						width = "double",
						get = function()
							return Config.NexConfig.automation.SkipCinematics
						end,
						set = function(_, value)
							Config.NexConfig.automation.SkipCinematics = value
						end,
					},
					AutoKeystoneSlotting = {
						order = 6,
						name = "Auto Keystone Slotting",
						desc = "Automatically scans your bags and slots a Mythic Keystone into the Keystone Frame when opened.",
						type = "toggle",
						width = "double",
						get = function()
							return Config.NexConfig.automation.AutoKeystoneSlotting
						end,
						set = function(_, value)
							Config.NexConfig.automation.AutoKeystoneSlotting = value
						end,
					},
					AutoBestQuestReward = {
						order = 7,
						name = "Auto Best Quest Reward",
						desc = "Automatically selects the best quest reward based on sell value and usefulness.",
						type = "toggle",
						width = "double",
						get = function()
							return Config.NexConfig.automation.AutoBestQuestReward
						end,
						set = function(_, value)
							Config.NexConfig.automation.AutoBestQuestReward = value
						end,
					},
					AutoScreenshotAchieve = {
						order = 8,
						name = "Achievement Screenshot",
						desc = "Automatically take a screenshot when an achievement is earned.",
						type = "toggle",
						width = "double",
						get = function()
							return Config.NexConfig.automation.AutoScreenshotAchieve
						end,
						set = function(_, value)
							Config.NexConfig.automation.AutoScreenshotAchieve = value
							Config:ToggleAutoScreenshotAchieve()
						end,
					},
					AutoSell = {
						order = 9,
						name = "Auto-Sell Trash",
						desc = "Automatically sells junk items to vendors.",
						type = "toggle",
						width = "double",
						get = function()
							return Config.NexConfig.automation.AutoSell
						end,
						set = function(_, value)
							Config.NexConfig.automation.AutoSell = value
						end,
					},
					AutoRepair = {
						order = 10,
						name = "Auto Repair",
						desc = "Automatically repairs your gear. Choose between using Guild funds or Player gold.",
						type = "select",
						values = { [0] = "None", [1] = "Guild", [2] = "Player" },
						get = function()
							return Config.NexConfig.automation.AutoRepair
						end,
						set = function(_, value)
							Config.NexConfig.automation.AutoRepair = value
						end,
					},
					AutoResurrect = {
						order = 11,
						name = "Auto Resurrect",
						desc = "Automatically accepts resurrection requests and performs an emote after being resurrected. Choose the emote below.",
						type = "toggle",
						width = "double",
						get = function()
							return Config.NexConfig.automation.AutoResurrect
						end,
						set = function(_, value)
							Config.NexConfig.automation.AutoResurrect = value
						end,
					},
					AutoResurrectEmote = {
						order = 12,
						name = "Auto Resurrect Emote",
						desc = "Select or set a custom emote to perform automatically after resurrection.",
						type = "select",
						values = {
							["none"] = "None",
							["cheer"] = "Cheer",
							["thank"] = "Thank",
							["bow"] = "Bow",
							["salute"] = "Salute",
							["wave"] = "Wave",
							["clap"] = "Clap",
							["raise"] = "Raise",
							["apologize"] = "Apologize",
							["flex"] = "Flex",
						},
						get = function()
							return Config.NexConfig.automation.AutoResurrectEmote or "thank"
						end,
						set = function(_, value)
							Config.NexConfig.automation.AutoResurrectEmote = value
						end,
						disabled = function()
							return not Config.NexConfig.automation.AutoResurrect
						end,
					},
					IgnoreQuestNPC = {
						order = 13,
						name = "Ignore NPC IDs",
						desc = "Enter NPC IDs to exclude from automatic quest acceptance and completion. Separate multiple IDs with commas.",
						type = "input",
						width = "double",
						multiline = true,
						get = function()
							local ids = {}
							for npcID, value in pairs(Config.NexConfig.automation.IgnoreQuestNPC) do
								if value then
									table.insert(ids, tostring(npcID))
								end
							end
							return table.concat(ids, ", ")
						end,
						set = function(_, value)
							wipe(Config.NexConfig.automation.IgnoreQuestNPC)
							for npcID in value:gmatch("%d+") do
								Config.NexConfig.automation.IgnoreQuestNPC[tonumber(npcID)] = true
							end
							Config:UpdateIgnoreList()
						end,
						disabled = function()
							return not Config.NexConfig.automation.AutoQuest
						end,
					},
				},
			},
			chat = {
				order = 4,
				name = "Chat",
				desc = "Enhance chat experience with custom settings.",
				icon = "2056011", -- :D
				type = "group",
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
						desc = "Toggle background visibility for chat windows.",
						type = "toggle",
						width = "double",
						get = function()
							return Config.NexConfig.chat.Background
						end,
						set = function(_, value)
							Config.NexConfig.chat.Background = value
							Config.Chat:ToggleChatBackground()
						end,
					},
					TimestampFormat = {
						order = 2,
						name = "Timestamp Format",
						desc = "Choose the format for timestamps displayed in chat.",
						type = "select",
						values = {
							["DISABLE"] = "Disable",
							["HH_MM_AMPM"] = "03:27 PM",
							["HH_MM_SS_AMPM"] = "03:27:32 PM",
							["HH_MM_24"] = "15:27",
							["HH_MM_SS_24"] = "15:27:32",
						},
						get = function()
							return Config.NexConfig.chat.TimestampFormat
						end,
						set = function(_, value)
							Config.NexConfig.chat.TimestampFormat = value
						end,
					},
					URLCopy = {
						order = 3,
						name = "Copy Chat URLs",
						desc = "Allow copying of URLs from chat.",
						type = "toggle",
						width = "double",
						get = function()
							return Config.NexConfig.chat.URLCopy
						end,
						set = function(_, value)
							Config.NexConfig.chat.URLCopy = value
						end,
					},
					StickyChat = {
						order = 4,
						name = "Sticky Chat",
						desc = "Keeps the last-used chat channel active for new messages.",
						type = "toggle",
						width = "double",
						get = function()
							return Config.NexConfig.chat.StickyChat
						end,
						set = function(_, value)
							Config.NexConfig.chat.StickyChat = value
							Config.Chat:ChatWhisperSticky()
						end,
					},
					DefaultChannelNames = {
						order = 5,
						name = "Simplify Channel Names",
						desc = "Shorten the names of default chat channels (e.g., 'General - Zone Name' to 'General') for cleaner chat display.",
						type = "toggle",
						width = "double",
						get = function()
							return Config.NexConfig.chat.DefaultChannelNames
						end,
						set = function(_, value)
							Config.NexConfig.chat.DefaultChannelNames = value
						end,
					},
					WhisperColor = {
						order = 6,
						name = "Custom Whisper Colors",
						desc = "Apply a unique color to whisper messages to make them more distinguishable in chat.",
						type = "toggle",
						width = "double",
						get = function()
							return Config.NexConfig.chat.WhisperColor
						end,
						set = function(_, value)
							Config.NexConfig.chat.WhisperColor = value
						end,
					},
					SocialButton = {
						order = 7,
						name = "Social Button Visibility",
						desc = "Toggle the visibility of the Social button, which provides quick access to your Friends List, Quick Join, and other social features.",
						type = "toggle",
						width = "double",
						get = function()
							return Config.NexConfig.chat.SocialButton
						end,
						set = function(_, value)
							Config.NexConfig.chat.SocialButton = value
							Config.Chat:ToggleSocialButton()
						end,
					},
					MenuButton = {
						order = 8,
						name = "Chat Menu Button",
						desc = "Toggle the visibility of the chat menu button, which provides quick access to chat commands like Say, Party, Raid, and others.",
						type = "toggle",
						width = "double",
						get = function()
							return Config.NexConfig.chat.MenuButton
						end,
						set = function(_, value)
							Config.NexConfig.chat.MenuButton = value
							Config.Chat:ToggleMenuButton()
						end,
					},
					ChannelButton = {
						order = 9,
						name = "Chat Channels Button",
						desc = "Toggle the visibility of the Chat Channels button, which opens the interface to manage and join chat channels.",
						type = "toggle",
						width = "double",
						get = function()
							return Config.NexConfig.chat.ChannelButton
						end,
						set = function(_, value)
							Config.NexConfig.chat.ChannelButton = value
							Config.Chat:ToggleChannelButton()
						end,
					},
					chatfilters = {
						order = 10,
						name = "Chat Filters",
						type = "group",
						inline = true,
						args = {
							EnableFilter = {
								order = 1,
								name = "|cff00cc4cEnable Chat Filter",
								desc = "Enables or disables the chat filtering system.",
								type = "toggle",
								width = "double",
								get = function()
									return Config.NexConfig.chat.chatfilters.EnableFilter
								end,
								set = function(_, value)
									Config.NexConfig.chat.chatfilters.EnableFilter = value
								end,
							},
							FilterMatches = {
								order = 2,
								name = "Filter Matches Count",
								desc = "Enter the number of keyword matches required to filter a message.",
								type = "input",
								width = "double",
								validate = function(_, value)
									local numValue = tonumber(value)
									if numValue and numValue > 0 then
										return true
									else
										return "Please enter a valid number."
									end
								end,
								get = function()
									return Config.NexConfig.chat.chatfilters.FilterMatches
								end,
								set = function(_, value)
									Config.NexConfig.chat.chatfilters.FilterMatches = value
								end,
							},
							BlockStrangers = {
								order = 3,
								name = "Block Strangers",
								desc = "Blocks messages from unknown players who are not in your friends list or guild.",
								type = "toggle",
								width = "double",
								get = function()
									return Config.NexConfig.chat.chatfilters.BlockStrangers
								end,
								set = function(_, value)
									Config.NexConfig.chat.chatfilters.BlockStrangers = value
								end,
							},
							BlockSpammer = {
								order = 4,
								name = "Block Spammers",
								desc = "Filters out messages from players who are flagged as spammers or sending repetitive messages.",
								type = "toggle",
								width = "double",
								get = function()
									return Config.NexConfig.chat.chatfilters.BlockSpammer
								end,
								set = function(_, value)
									Config.NexConfig.chat.chatfilters.BlockSpammer = value
								end,
							},
							ChatItemLevel = {
								order = 5,
								name = "Show Item Level in Chat",
								desc = "Displays the item level of linked gear in chat.",
								type = "toggle",
								width = "double",
								get = function()
									return Config.NexConfig.chat.chatfilters.ChatItemLevel
								end,
								set = function(_, value)
									Config.NexConfig.chat.chatfilters.ChatItemLevel = value
								end,
							},
							BlockAddonAlert = {
								order = 6,
								name = "Block Addon Alerts",
								desc = "Blocks automated messages from addons, including announcements of abilities, deaths, or interrupts.",
								type = "toggle",
								width = "double",
								get = function()
									return Config.NexConfig.chat.chatfilters.BlockAddonAlert
								end,
								set = function(_, value)
									Config.NexConfig.chat.chatfilters.BlockAddonAlert = value
								end,
							},
							ChatFilterList = {
								order = 7,
								name = "Chat Filter List",
								desc = "Specify a list of patterns to filter out messages in chat. Use spaces to separate multiple patterns.",
								type = "input",
								width = "double",
								multiline = true,
								get = function()
									return Config.NexConfig.chat.chatfilters.ChatFilterList
								end,
								set = function(_, value)
									Config.NexConfig.chat.chatfilters.ChatFilterList = value
									Config.Chat:UpdateFilterList()
								end,
							},
							ChatFilterWhiteList = {
								order = 8,
								name = "Chat Filter Whitelist",
								desc = "Specify a list of allowed terms or patterns that bypass the chat filter. Use spaces to separate multiple terms.",
								type = "input",
								width = "double",
								multiline = true,
								get = function()
									return Config.NexConfig.chat.chatfilters.ChatFilterWhiteList
								end,
								set = function(_, value)
									Config.NexConfig.chat.chatfilters.ChatFilterWhiteList = value
									Config.Chat:UpdateFilterWhiteList()
								end,
							},
						},
					},
				},
			},
			experience = {
				order = 5,
				name = "Experience",
				desc = "Configure the experience and reputation bar settings.",
				icon = "894556", -- :D
				type = "group",
				args = {
					enableExp = {
						order = 1,
						name = "|cff00cc4cEnable Experience Bar|r",
						desc = "Toggle the display of NexEnhance's experience bar.",
						type = "toggle",
						width = "double",
						get = function()
							return Config.NexConfig.experience.enableExp
						end,
						set = function(_, value)
							Config.NexConfig.experience.enableExp = value
						end,
					},
					showBubbles = {
						order = 2,
						name = "Show Bubbles",
						desc = "Show bubbles on experience and reputation bars.",
						type = "toggle",
						width = "double",
						get = function()
							return Config.NexConfig.experience.showBubbles
						end,
						set = function(_, value)
							Config.NexConfig.experience.showBubbles = value
							if Config.bar then
								Config:ManageBarBubbles(Config.bar)
							end
						end,
					},
					numberFormat = {
						order = 3,
						name = "Number Format",
						desc = "Choose the format for numbers displayed on the bar.",
						type = "select",
						values = { [1] = "Standard: b/m/k", [2] = "Asian: y/w", [3] = PLAYER },
						get = function()
							return Config.NexConfig.experience.numberFormat
						end,
						set = function(_, value)
							Config.NexConfig.experience.numberFormat = value
							if Config.bar then
								Config:OnExpBarEvent(Config.bar)
							end
						end,
					},
					barTextFormat = {
						order = 4,
						name = "Bar Text Format",
						desc = "Choose the format for the text displayed on the bar.",
						type = "select",
						values = {
							["PERCENT"] = "Percent",
							["CURMAX"] = "Current - Max",
							["CURPERC"] = "Current - Percent",
							["CUR"] = "Current",
							["REM"] = "Remaining",
							["CURREM"] = "Current - Remaining",
							["CURPERCREM"] = "Current - Percent (Remaining)",
						},
						get = function()
							return Config.NexConfig.experience.barTextFormat
						end,
						set = function(_, value)
							Config.NexConfig.experience.barTextFormat = value
							if Config.bar then
								Config:OnExpBarEvent(Config.bar)
							end
						end,
					},
					barWidth = {
						order = 5,
						name = "Bar Width",
						desc = "Adjust the width of the bar. Default is 500. Minimum is 200. Maximum is the screen width.",
						type = "range",
						width = "double",
						min = 200,
						max = Config.ScreenWidth,
						step = 1,
						get = function()
							return Config.NexConfig.experience.barWidth
						end,
						set = function(_, value)
							Config.NexConfig.experience.barWidth = value
							if Config.bar then
								Config.bar:SetWidth(value)
								Config:ManageBarBubbles(Config.bar)
							end
						end,
					},
					barHeight = {
						order = 6,
						name = "Bar Height",
						desc = "Adjust the height of the bar. Default is 12. Minimum is 10. Maximum is 40.",
						type = "range",
						width = "double",
						min = 10,
						max = 40,
						step = 1,
						get = function()
							return Config.NexConfig.experience.barHeight
						end,
						set = function(_, value)
							Config.NexConfig.experience.barHeight = value
							if Config.bar then
								Config.bar:SetHeight(value)
								Config:ManageBarBubbles(Config.bar)
								Config:ForceTextScaling(Config.bar)
							end
						end,
					},
					classColorBar = {
						order = 7,
						name = "Class-colored XP Bar",
						desc = "Toggle to color the XP bar based on your class.",
						type = "toggle",
						width = "double",
						get = function()
							return Config.NexConfig.experience.classColorBar
						end,
						set = function(_, value)
							Config.NexConfig.experience.classColorBar = value
							if Config.bar then
								Config:UpdateExpBarColor(Config.bar)
							end
						end,
					},
				},
			},
			loot = {
				order = 6,
				name = "Loot",
				desc = "Configure loot-related settings for Config.",
				icon = "901746", -- :D
				type = "group",
				args = {
					FasterLoot = {
						order = 1,
						name = "Quick Looting",
						desc = "Enhances looting speed. Requires auto-loot to be enabled.",
						type = "toggle",
						width = "double",
						get = function()
							return Config.NexConfig.loot.FasterLoot
						end,
						set = function(_, value)
							Config.NexConfig.loot.FasterLoot = value
						end,
					},
				},
			},
			minimap = {
				order = 7,
				name = "Minimap",
				desc = "Configure minimap-related settings for Config.",
				icon = "1064187", -- :D
				type = "group",
				args = {
					EasyVolume = {
						order = 1,
						name = "Easy Volume Control",
						desc = "Allows easy control of the master volume using the mouse wheel on the minimap while holding the Control key.",
						type = "toggle",
						width = "double",
						get = function()
							return Config.NexConfig.minimap.EasyVolume
						end,
						set = function(_, value)
							Config.NexConfig.minimap.EasyVolume = value
						end,
					},
					recycleBin = {
						order = 2,
						name = "|A:newplayerchat-chaticon-newcomer:16:16|a Minimap Button Collection",
						desc = "Collects minimap buttons into a single pop-up menu for easier access and cleaner minimap.",
						type = "toggle",
						width = "double",
						get = function()
							return Config.NexConfig.minimap.recycleBin
						end,
						set = function(_, value)
							Config.NexConfig.minimap.recycleBin = value
						end,
						disabled = function()
							return C_AddOns.IsAddOnLoaded("MBB")
						end,
					},
					PingNotifier = {
						order = 2,
						name = "Ping Notifier",
						desc = "Displays the name and class color of players who ping the minimap.",
						type = "toggle",
						width = "double",
						get = function()
							return Config.NexConfig.minimap.PingNotifier
						end,
						set = function(_, value)
							Config.NexConfig.minimap.PingNotifier = value
						end,
					},
				},
			},
			miscellaneous = {
				order = 8,
				name = "Miscellaneous",
				desc = "Configure miscellaneous features and enhancements.",
				icon = "134169", -- :D
				type = "group",
				args = {
					hideWidgetTexture = {
						order = 1,
						name = "|A:newplayerchat-chaticon-newcomer:16:16|a Hide Vigor Wings",
						desc = "Hides the wing textures on the Dragonriding Vigor bar.",
						type = "toggle",
						width = "double",
						get = function()
							return Config.NexConfig.miscellaneous.hideWidgetTexture
						end,
						set = function(_, value)
							Config.NexConfig.miscellaneous.hideWidgetTexture = value
						end,
					},
					widgetScale = {
						order = 2,
						name = "|A:newplayerchat-chaticon-newcomer:16:16|a Vigor Bar Scale",
						desc = "Adjusts the scale of the Dragonriding Vigor bar.",
						type = "range",
						width = "double",
						min = 0.5,
						max = 1.0,
						step = 0.01,
						get = function()
							return Config.NexConfig.miscellaneous.widgetScale
						end,
						set = function(_, value)
							Config.NexConfig.miscellaneous.widgetScale = value
						end,
					},
					disableTalkingHead = {
						order = 3,
						name = "Disable TalkingHead",
						desc = "Disables the Talking Head Frame, preventing pop-up dialogues from appearing during gameplay.",
						type = "toggle",
						width = "double",
						get = function()
							return Config.NexConfig.miscellaneous.disableTalkingHead
						end,
						set = function(_, value)
							Config.NexConfig.miscellaneous.disableTalkingHead = value
						end,
					},
					enableAFKMode = {
						order = 4,
						name = "AFK Mode",
						desc = "Enable an AFK mode with dynamic features like automatic guild display, random statistics, and countdown timer.",
						type = "toggle",
						width = "double",
						get = function()
							return Config.NexConfig.miscellaneous.enableAFKMode
						end,
						set = function(_, value)
							Config.NexConfig.miscellaneous.enableAFKMode = value
							Config:ToggleAFKMode()
						end,
					},
					missingStats = {
						order = 5,
						name = "Enhanced Character Statistics",
						desc = "Enhances the default character statistics panel with improved readability and additional insights.",
						type = "toggle",
						width = "double",
						get = function()
							return Config.NexConfig.miscellaneous.missingStats
						end,
						set = function(_, value)
							Config.NexConfig.miscellaneous.missingStats = value
						end,
					},
					moveableFrames = {
						order = 6,
						name = "Enable Movable Frames",
						desc = "Allows certain Blizzard frames to be movable, giving you the flexibility to reposition them as needed.",
						type = "toggle",
						width = "double",
						get = function()
							return Config.NexConfig.miscellaneous.moveableFrames
						end,
						set = function(_, value)
							Config.NexConfig.miscellaneous.moveableFrames = value
						end,
					},
					gemsNEnchants = {
						order = 7,
						name = "Show Gems and Enchants",
						desc = "Displays gems and enchantments on the character and inspect frames for quick reference.",
						type = "toggle",
						width = "double",
						get = function()
							return Config.NexConfig.miscellaneous.gemsNEnchants
						end,
						set = function(_, value)
							Config.NexConfig.miscellaneous.gemsNEnchants = value
						end,
					},
					questXPPercent = {
						order = 8,
						name = "Enhanced Quest XP Display",
						desc = "Enhances quest XP rewards to show the percentage of total experience gained.",
						type = "toggle",
						width = "double",
						get = function()
							return Config.NexConfig.miscellaneous.questXPPercent
						end,
						set = function(_, value)
							Config.NexConfig.miscellaneous.questXPPercent = value
						end,
					},
					questRewardsMostValueIcon = {
						order = 9,
						name = "Highlight Best Quest Reward",
						desc = "Highlights the most valuable quest reward choice with a gold coin icon based on sell value.",
						type = "toggle",
						width = "double",
						get = function()
							return Config.NexConfig.miscellaneous.questRewardsMostValueIcon
						end,
						set = function(_, value)
							Config.NexConfig.miscellaneous.questRewardsMostValueIcon = value
						end,
					},
					alreadyKnown = {
						order = 10,
						name = "Highlight Already Known Items",
						desc = "Highlights items that are already known, such as mounts, pets, and recipes, in various UI elements.",
						type = "toggle",
						width = "double",
						get = function()
							return Config.NexConfig.miscellaneous.alreadyKnown
						end,
						set = function(_, value)
							Config.NexConfig.miscellaneous.alreadyKnown = value
						end,
					},
					QuestTrackerAlerts = {
						order = 11,
						name = "Quest Tracker Alerts",
						desc = "Receive alerts for quest acceptance, progress milestones, completion, and other quest-related updates.",
						type = "group",
						inline = true,
						args = {
							QuestNotification = {
								order = 1,
								name = "Enable Quest Notifications",
								desc = "Toggle notifications for quest progress, acceptance, completion, and other related events.",
								type = "toggle",
								width = "double",
								get = function()
									return Config.NexConfig.miscellaneous.QuestTrackerAlerts.QuestNotification
								end,
								set = function(_, value)
									Config.NexConfig.miscellaneous.QuestTrackerAlerts.QuestNotification = value
									Config:QuestNotification()
								end,
							},
							QuestProgress = {
								order = 2,
								name = "Notify on Quest Progress Updates",
								desc = "Enable notifications when significant quest progress milestones are achieved.",
								type = "toggle",
								width = "double",
								get = function()
									return Config.NexConfig.miscellaneous.QuestTrackerAlerts.QuestProgress
								end,
								set = function(_, value)
									Config.NexConfig.miscellaneous.QuestTrackerAlerts.QuestProgress = value
								end,
								disabled = function()
									return not Config.NexConfig.miscellaneous.QuestTrackerAlerts.QuestNotification
								end,
							},
							OnlyCompleteRing = {
								order = 3,
								name = "Play Sound for Completed Quests Only",
								desc = "Enable this option to silence all notifications and only play a sound when a quest is fully completed.",
								type = "toggle",
								width = "double",
								get = function()
									return Config.NexConfig.miscellaneous.QuestTrackerAlerts.OnlyCompleteRing
								end,
								set = function(_, value)
									Config.NexConfig.miscellaneous.QuestTrackerAlerts.OnlyCompleteRing = value
								end,
								disabled = function()
									return not Config.NexConfig.miscellaneous.QuestTrackerAlerts.QuestNotification
								end,
							},
						},
					},
					itemlevels = {
						order = 12,
						name = "Item Levels",
						type = "group",
						inline = true,
						args = {
							characterFrame = {
								order = 1,
								name = "Show Item Level on Character Frame",
								desc = "Displays item levels on the character frame.",
								type = "toggle",
								width = "double",
								get = function()
									return Config.NexConfig.miscellaneous.itemlevels.characterFrame
								end,
								set = function(_, value)
									Config.NexConfig.miscellaneous.itemlevels.characterFrame = value
								end,
							},
							inspectFrame = {
								order = 2,
								name = "Show Item Level on Inspect Frame",
								desc = "Displays item levels on the inspect frame.",
								type = "toggle",
								width = "double",
								get = function()
									return Config.NexConfig.miscellaneous.itemlevels.inspectFrame
								end,
								set = function(_, value)
									Config.NexConfig.miscellaneous.itemlevels.inspectFrame = value
								end,
							},
							merchantFrame = {
								order = 3,
								name = "Show Item Level on Merchant Frame",
								desc = "Displays item levels on the merchant frame.",
								type = "toggle",
								width = "double",
								get = function()
									return Config.NexConfig.miscellaneous.itemlevels.merchantFrame
								end,
								set = function(_, value)
									Config.NexConfig.miscellaneous.itemlevels.merchantFrame = value
								end,
							},
							tradeFrame = {
								order = 4,
								name = "Show Item Level on Trade Frame",
								desc = "Displays item levels on the trade frame.",
								type = "toggle",
								width = "double",
								get = function()
									return Config.NexConfig.miscellaneous.itemlevels.tradeFrame
								end,
								set = function(_, value)
									Config.NexConfig.miscellaneous.itemlevels.tradeFrame = value
								end,
							},
							lootFrame = {
								order = 5,
								name = "Show Item Level on Loot Frame",
								desc = "Displays item levels on the loot frame.",
								type = "toggle",
								width = "double",
								get = function()
									return Config.NexConfig.miscellaneous.itemlevels.lootFrame
								end,
								set = function(_, value)
									Config.NexConfig.miscellaneous.itemlevels.lootFrame = value
								end,
							},
							guildBankFrame = {
								order = 6,
								name = "Show Item Level on Guild Bank Frame",
								desc = "Displays item levels on the guild bank frame.",
								type = "toggle",
								width = "double",
								get = function()
									return Config.NexConfig.miscellaneous.itemlevels.guildBankFrame
								end,
								set = function(_, value)
									Config.NexConfig.miscellaneous.itemlevels.guildBankFrame = value
								end,
							},
							containers = {
								order = 7,
								name = "Show Item Level on Containers",
								desc = "Displays item levels on container items (bags).",
								type = "toggle",
								width = "double",
								get = function()
									return Config.NexConfig.miscellaneous.itemlevels.containers
								end,
								set = function(_, value)
									Config.NexConfig.miscellaneous.itemlevels.containers = value
								end,
							},
							flyout = {
								order = 8,
								name = "Show Item Level on Equipment Flyout",
								desc = "Displays item levels on equipment flyout buttons.",
								type = "toggle",
								width = "double",
								get = function()
									return Config.NexConfig.miscellaneous.itemlevels.flyout
								end,
								set = function(_, value)
									Config.NexConfig.miscellaneous.itemlevels.flyout = value
								end,
							},
							scrapping = {
								order = 9,
								name = "Show Item Level on Scrapping Machine Frame",
								desc = "Displays item levels on the scrapping machine frame.",
								type = "toggle",
								width = "double",
								get = function()
									return Config.NexConfig.miscellaneous.itemlevels.scrapping
								end,
								set = function(_, value)
									Config.NexConfig.miscellaneous.itemlevels.scrapping = value
								end,
							},
						},
					},
				},
			},
			skins = {
				order = 9,
				name = "Skins",
				desc = "Enhance the appearance and functionality of Blizzard and addon frames.",
				icon = "4620680", -- :D
				type = "group",
				args = {
					blizzskins = {
						order = 1,
						name = "Blizzard Frame Enhancements",
						type = "group",
						inline = true,
						args = {
							characterFrame = {
								order = 1,
								name = "Enhanced Character Frame",
								desc = "Improves the appearance and functionality of the character frame.",
								type = "toggle",
								width = "double",
								get = function()
									return Config.NexConfig.skins.blizzskins.characterFrame
								end,
								set = function(_, value)
									Config.NexConfig.skins.blizzskins.characterFrame = value
								end,
							},
							chatbubble = {
								order = 2,
								name = "Chat Bubble Enhancements",
								desc = "Toggle enhancements for chat bubbles, such as customized colors and textures.",
								type = "toggle",
								width = "double",
								get = function()
									return Config.NexConfig.skins.blizzskins.chatbubble
								end,
								set = function(_, value)
									Config.NexConfig.skins.blizzskins.chatbubble = value
								end,
							},
							collectionsFrame = {
								order = 1,
								name = "Enhanced Transmog Frame",
								desc = "Upgrades the transmog interface with improved visuals and functionality.",
								type = "toggle",
								width = "double",
								get = function()
									return Config.NexConfig.skins.blizzskins.collectionsFrame
								end,
								set = function(_, value)
									Config.NexConfig.skins.blizzskins.collectionsFrame = value
								end,
							},
							inspectFrame = {
								order = 3,
								name = "Enhanced Inspect Frame",
								desc = "Enhances the inspect frame for better display and usability.",
								type = "toggle",
								width = "double",
								get = function()
									return Config.NexConfig.skins.blizzskins.inspectFrame
								end,
								set = function(_, value)
									Config.NexConfig.skins.blizzskins.inspectFrame = value
								end,
							},
							objectiveTracker = {
								order = 4,
								name = "Enhanced Objective Tracker",
								desc = "Enhances the Objective Tracker for a more modern look.",
								type = "toggle",
								width = "double",
								get = function()
									return Config.NexConfig.skins.blizzskins.objectiveTracker
								end,
								set = function(_, value)
									Config.NexConfig.skins.blizzskins.objectiveTracker = value
								end,
							},
						},
					},
					addonskins = {
						order = 3,
						name = "Addon Frame Enhancements",
						type = "group",
						inline = true,
						args = {
							details = {
								order = 1,
								name = "Enhanced Details! Skin",
								desc = "Improves the appearance and functionality of the Details! addon frames.",
								type = "toggle",
								get = function()
									return Config.NexConfig.skins.addonskins.details
								end,
								set = function(_, value)
									Config.NexConfig.skins.addonskins.details = value
								end,
								disabled = function()
									return not C_AddOns.IsAddOnLoaded("Details")
								end,
							},
							applyDetails = {
								order = 2,
								name = "Reset Details! Skin",
								desc = "Resets the enhanced Details! skin settings.",
								type = "execute",
								func = function()
									print("Resetting Details! skin settings...")
									Config:ResetDetailsAnchor(true)
								end,
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
				desc = "Customize tooltip settings to enhance information display.",
				icon = "4622480", -- :D
				type = "group",
				args = {
					combatHide = {
						order = 1,
						name = "Combat Tip Hide",
						desc = "Automatically hides tooltips during combat.",
						type = "toggle",
						width = "double",
						get = function()
							return Config.NexConfig.tooltip.combatHide
						end,
						set = function(_, value)
							Config.NexConfig.tooltip.combatHide = value
						end,
					},
					factionIcon = {
						order = 2,
						name = "Faction Icons",
						desc = "Displays faction icons on tooltips.",
						type = "toggle",
						width = "double",
						get = function()
							return Config.NexConfig.tooltip.factionIcon
						end,
						set = function(_, value)
							Config.NexConfig.tooltip.factionIcon = value
						end,
					},
					hideJunkGuild = {
						order = 3,
						name = "Abbreviate Guild Names",
						desc = "Shows abbreviated guild names on tooltips.",
						type = "toggle",
						width = "double",
						get = function()
							return Config.NexConfig.tooltip.hideJunkGuild
						end,
						set = function(_, value)
							Config.NexConfig.tooltip.hideJunkGuild = value
						end,
					},
					hideRank = {
						order = 4,
						name = "Hide Guild Ranks",
						desc = "Hides player guild ranks in tooltips.",
						type = "toggle",
						width = "double",
						get = function()
							return Config.NexConfig.tooltip.hideRank
						end,
						set = function(_, value)
							Config.NexConfig.tooltip.hideRank = value
						end,
					},
					hideTitle = {
						order = 5,
						name = "Hide Player Titles",
						desc = "Hides player titles in tooltips.",
						type = "toggle",
						width = "double",
						get = function()
							return Config.NexConfig.tooltip.hideTitle
						end,
						set = function(_, value)
							Config.NexConfig.tooltip.hideTitle = value
						end,
					},
					lfdRole = {
						order = 6,
						name = "LFD Role Icons",
						desc = "Displays role icons (tank, healer, damage) in tooltips.",
						type = "toggle",
						width = "double",
						get = function()
							return Config.NexConfig.tooltip.lfdRole
						end,
						set = function(_, value)
							Config.NexConfig.tooltip.lfdRole = value
						end,
					},
					mdScore = {
						order = 7,
						name = "Mythic Dungeon Score",
						desc = "Displays the player's Mythic Dungeon score in tooltips.",
						type = "toggle",
						width = "double",
						get = function()
							return Config.NexConfig.tooltip.mdScore
						end,
						set = function(_, value)
							Config.NexConfig.tooltip.mdScore = value
						end,
					},
					qualityColor = {
						order = 8,
						name = "Item Quality Colors",
						desc = "Colors item borders by their quality in tooltips.",
						type = "toggle",
						width = "double",
						get = function()
							return Config.NexConfig.tooltip.qualityColor
						end,
						set = function(_, value)
							Config.NexConfig.tooltip.qualityColor = value
						end,
					},
					ShowID = {
						order = 9,
						name = "Show Tooltip IDs",
						desc = "Displays spell, item, quest, and other IDs in tooltips.",
						type = "toggle",
						width = "double",
						get = function()
							return Config.NexConfig.tooltip.ShowID
						end,
						set = function(_, value)
							Config.NexConfig.tooltip.ShowID = value
						end,
					},
					SpecLevelByShift = {
						order = 10,
						name = "Shift+Spec Level",
						desc = "Shows item level when holding the SHIFT key.",
						type = "toggle",
						width = "double",
						get = function()
							return Config.NexConfig.tooltip.SpecLevelByShift
						end,
						set = function(_, value)
							Config.NexConfig.tooltip.SpecLevelByShift = value
						end,
					},
					cursorPosition = {
						order = 11,
						name = "Cursor Tooltip Position",
						desc = "Selects the position of tooltips relative to the cursor.",
						type = "select",
						values = { ["DISABLE"] = "Disable", ["LEFT"] = "Left", ["TOP"] = "Top", ["RIGHT"] = "Right" },
						get = function()
							return Config.NexConfig.tooltip.cursorPosition
						end,
						set = function(_, value)
							Config.NexConfig.tooltip.cursorPosition = value
						end,
					},
				},
			},
			unitframes = {
				order = 11,
				name = "Unit Frames",
				desc = "Customize unit frames settings for Config.",
				icon = "648207", -- :D
				type = "group",
				args = {
					classColorFrames = {
						order = 1,
						name = "Enable Class-colored Health Bars",
						desc = "Enable or disable class-colored health bars for all unit frames. Class colors represent the unit's class visually in the health bar.",
						type = "toggle",
						width = "double",
						get = function()
							return Config.NexConfig.unitframes.classColorFrames
						end,
						set = function(_, value)
							Config.NexConfig.unitframes.classColorFrames = value
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
						end,
						disabled = function()
							return C_AddOns.IsAddOnLoaded("BetterBlizzFrames")
						end,
					},
					playerFrameEnhancements = {
						order = 2,
						name = "Player Frame Enhancements",
						type = "group",
						inline = true,
						args = {
							classColorFramesSkipPlayer = {
								order = 1,
								name = "Exclude Player Frame from Class Colors",
								desc = "Disable class-colored health bars specifically for the player's unit frame. This setting overrides the global class color health bar option for the player frame.",
								type = "toggle",
								width = "double",
								get = function()
									return Config.NexConfig.unitframes.playerFrameEnhancements.classColorFramesSkipPlayer
								end,
								set = function(_, value)
									Config.NexConfig.unitframes.playerFrameEnhancements.classColorFramesSkipPlayer = value
									if value then
										PlayerFrame.healthbar:SetStatusBarDesaturated(false)
										PlayerFrame.healthbar:SetStatusBarColor(1, 1, 1)
									else
										Config.updateFrameColorToggleVer(PlayerFrame.healthbar, "player")
										if CfPlayerFrameHealthBar then
											Config.updateFrameColorToggleVer(CfPlayerFrameHealthBar, "player")
										end
									end
								end,
								disabled = function()
									return not Config.NexConfig.unitframes.classColorFrames or C_AddOns.IsAddOnLoaded("BetterBlizzFrames")
								end,
							},
							colorPetAfterOwner = {
								order = 2,
								name = "Color Pets After Owner",
								desc = "Apply the owner's class color to the health bars of pets. This setting ensures pets are visually linked to their owner's class in unit frames.",
								type = "toggle",
								width = "double",
								get = function()
									return Config.NexConfig.unitframes.playerFrameEnhancements.colorPetAfterOwner
								end,
								set = function(_, value)
									Config.NexConfig.unitframes.playerFrameEnhancements.colorPetAfterOwner = value
									Config.UpdateFrames()
								end,
								disabled = function()
									return C_AddOns.IsAddOnLoaded("BetterBlizzFrames")
								end,
							},
							playerReputationColor = {
								order = 3,
								name = "Enable Player Reputation Overlay",
								desc = "Show a reputation overlay on the player's frame. The color represents the player's current standing with the selected faction.",
								type = "toggle",
								width = "double",
								get = function()
									return Config.NexConfig.unitframes.playerFrameEnhancements.playerReputationColor
								end,
								set = function(_, value)
									Config.NexConfig.unitframes.playerFrameEnhancements.playerReputationColor = value
									Config.PlayerReputationColor()
								end,
								disabled = function()
									return C_AddOns.IsAddOnLoaded("BetterBlizzFrames")
								end,
							},
							playerReputationClassColor = {
								order = 4,
								name = "Use Class Color for Reputation Overlay",
								desc = "Instead of using faction reputation colors, apply the player's class color to the reputation overlay on the player's frame.",
								type = "toggle",
								width = "double",
								get = function()
									return Config.NexConfig.unitframes.playerFrameEnhancements.playerReputationClassColor
								end,
								set = function(_, value)
									Config.NexConfig.unitframes.playerFrameEnhancements.playerReputationClassColor = value
									Config.PlayerReputationColor()
								end,
								disabled = function()
									return not Config.NexConfig.unitframes.playerFrameEnhancements.playerReputationColor or C_AddOns.IsAddOnLoaded("BetterBlizzFrames")
								end,
							},
							playerHitIndicatorHide = {
								order = 5,
								name = "Hide Player Hit Indicator",
								desc = "Hide or show the player's hit indicator dynamically during combat.",
								type = "toggle",
								width = "double",
								get = function()
									return Config.NexConfig.unitframes.playerFrameEnhancements.playerHitIndicatorHide
								end,
								set = function(_, value)
									Config.NexConfig.unitframes.playerFrameEnhancements.playerHitIndicatorHide = value
									Config.TogglePlayerHitIndicator()
								end,
								disabled = function()
									return C_AddOns.IsAddOnLoaded("BetterBlizzFrames")
								end,
							},
						},
					},
					targetFrameEnhancements = {
						order = 3,
						name = "Target Frame Enhancements",
						type = "group",
						inline = true,
						args = {
							targetReputationColorHide = {
								order = 1,
								name = "Disable Target Reputation Overlay",
								desc = "Hide the reputation overlay on the target's frame. The overlay color represents the target's reputation standing with the player.",
								type = "toggle",
								width = "double",
								get = function()
									return Config.NexConfig.unitframes.targetFrameEnhancements.targetReputationColorHide
								end,
								set = function(_, value)
									Config.NexConfig.unitframes.targetFrameEnhancements.targetReputationColorHide = value
									Config.TargetReputationColor()
								end,
								disabled = function()
									return C_AddOns.IsAddOnLoaded("BetterBlizzFrames")
								end,
							},
						},
					},
				},
			},
			worldmap = {
				order = 12,
				name = "WorldMap",
				desc = "Customize WorldMap settings for Config.",
				icon = "134269", -- :D
				type = "group",
				args = {
					AlphaWhenMoving = {
						order = 1,
						name = "Map Transparency When Moving",
						desc = "Adjust the transparency level of the world map when you are moving.",
						type = "range",
						width = "double",
						min = 0.1,
						max = 1.0,
						step = 0.1,
						get = function()
							return Config.NexConfig.worldmap.AlphaWhenMoving
						end,
						set = function(_, value)
							Config.NexConfig.worldmap.AlphaWhenMoving = value
						end,
						disabled = function()
							return not Config.NexConfig.worldmap.FadeWhenMoving
						end,
					},
					Coordinates = {
						order = 2,
						name = "Show Coordinates",
						desc = "Toggle to display coordinates on the world map.",
						type = "toggle",
						width = "double",
						get = function()
							return Config.NexConfig.worldmap.Coordinates
						end,
						set = function(_, value)
							Config.NexConfig.worldmap.Coordinates = value
						end,
					},
					FadeWhenMoving = {
						order = 3,
						name = "Fade Map When Moving",
						desc = "Toggle to make the world map fade out when you are moving.",
						type = "toggle",
						width = "double",
						get = function()
							return Config.NexConfig.worldmap.FadeWhenMoving
						end,
						set = function(_, value)
							Config.NexConfig.worldmap.FadeWhenMoving = value
						end,
					},
					SmallWorldMap = {
						order = 4,
						name = "Compact World Map",
						desc = "Toggle to use a smaller version of the world map.",
						type = "toggle",
						width = "double",
						get = function()
							return Config.NexConfig.worldmap.SmallWorldMap
						end,
						set = function(_, value)
							Config.NexConfig.worldmap.SmallWorldMap = value
						end,
					},
					SmallWorldMapScale = {
						order = 5,
						name = "Compact Map Scale",
						desc = "Adjust the scale of the smaller world map.",
						type = "range",
						width = "double",
						min = 0.5,
						max = 1.0,
						step = 0.1,
						get = function()
							return Config.NexConfig.worldmap.SmallWorldMapScale
						end,
						set = function(_, value)
							Config.NexConfig.worldmap.SmallWorldMapScale = value
						end,
						disabled = function()
							return not Config.NexConfig.worldmap.SmallWorldMap
						end,
					},
				},
			},
			kkthnxprofile = {
				order = 100,
				name = "|cff83adb5Kkthnx Profile|r",
				desc = "Load Kkthnx's personal profile for Config.",
				type = "execute",
				func = function()
					StaticPopupDialogs["KK_PROFILE_POPUP"] = {
						text = "Are you sure you want to load |cff83adb5Kkthnx's|r personal profile for |cff5bc0beNexEnhance|r?",
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

	local aboutOptions = {
		type = "group",
		name = "About",
		desc = "Information about NexEnhance.",
		args = {
			description = {
				order = 1,
				name = "|cff5bc0beNexEnhance|r\n\nCreated by [Josh 'Kkthnx' Russell]\n\nVersion: 1.0.6\n\nThank you for using NexEnhance! Your support makes this possible.",
				type = "description",
				width = "full",
			},
			logo = {
				order = 2, -- Ensures the logo is displayed at the top
				type = "description",
				name = "",
				image = function()
					-- Replace the path below with the actual logo path in your addon
					return Config.Logo256 -- Adjust to your logo's file location
				end,
				imageWidth = 256, -- Adjust size to fit nicely
				imageHeight = 256,
			},
			discordButton = {
				order = 3,
				name = "Discord",
				desc = "Join our Discord community.",
				type = "execute",
				func = function()
					StaticPopupDialogs["NE_DISCORD_POPUP"] = {
						text = "|T236688:36|t\n\nCopy the link below to join our Discord community:",
						button1 = "OK",
						OnShow = function(self)
							self.editBox:SetText("https://discord.com/invite/Rc9wcK9cAB")
							self.editBox:HighlightText()
						end,
						timeout = 0,
						whileDead = true,
						hideOnEscape = true,
						hasEditBox = true,
						editBoxWidth = 350,
						preferredIndex = 3,
					}
					StaticPopup_Show("NE_DISCORD_POPUP")
				end,
			},
			githubButton = {
				order = 4,
				name = "GitHub",
				desc = "Visit our GitHub repository.",
				type = "execute",
				func = function()
					StaticPopupDialogs["NE_GITHUB_POPUP"] = {
						text = "|T236688:36|t\n\nCopy the link below to visit our GitHub repository:",
						button1 = "OK",
						OnShow = function(self)
							self.editBox:SetText("https://github.com/Kkthnx-Wow/NexEnhance")
							self.editBox:HighlightText()
						end,
						timeout = 0,
						whileDead = true,
						hideOnEscape = true,
						hasEditBox = true,
						editBoxWidth = 350,
						preferredIndex = 3,
					}
					StaticPopup_Show("NE_GITHUB_POPUP")
				end,
			},
			paypalButton = {
				order = 5,
				name = "Donate via PayPal",
				desc = "Support our work with a donation.",
				type = "execute",
				func = function()
					StaticPopupDialogs["NE_PAYPAL_POPUP"] = {
						text = "|T236688:36|t\n\nCopy the link below to donate via PayPal:",
						button1 = "OK",
						OnShow = function(self)
							self.editBox:SetText("https://paypal.me/KkthnxTV")
							self.editBox:HighlightText()
						end,
						timeout = 0,
						whileDead = true,
						hideOnEscape = true,
						hasEditBox = true,
						editBoxWidth = 350,
						preferredIndex = 3,
					}
					StaticPopup_Show("NE_PAYPAL_POPUP")
				end,
			},
		},
	}

	LibStub("AceConfig-3.0"):RegisterOptionsTable(AddonName, options)
	LibStub("AceConfigDialog-3.0"):AddToBlizOptions(AddonName, "|cff5bc0be" .. AddonName .. "|r")

	LibStub("AceConfig-3.0"):RegisterOptionsTable(AddonName .. "_About", aboutOptions)
	LibStub("AceConfigDialog-3.0"):AddToBlizOptions(AddonName .. "_About", "About", "|cff5bc0be" .. AddonName .. "|r")

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

	Config:UnregisterEvent("ADDON_LOADED", Config.ADDON_LOADED)
end

Config:RegisterSlash("/nexe", "/ne", function()
	LibStub("AceConfigDialog-3.0"):Open("NexEnhance")
end)
