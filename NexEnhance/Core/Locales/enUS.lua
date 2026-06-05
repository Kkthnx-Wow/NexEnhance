--[[
	NexEnhance - Localization (enUS / fallback)
	-------------------------------------------------------------------------
	`ns.L` is created in Engine.lua with a metatable that returns the key
	itself when a translation is missing, so untranslated strings still read
	sensibly. Other locales should overwrite only the keys they translate:

	    if GetLocale() ~= "deDE" then return end
	    local _, ns = ...
	    local L = ns.L
	    L["Auto Vendor"] = "Automatischer Verkauf"
--]]

local _, ns = ...
local L = ns.L

-- General
L["Commands"] = "Commands"
L["Modules"] = "Modules"
L["Version"] = "Version"
L["Author"] = "Author"
L["Getting Started"] = "Getting Started"
L["%d modules, %d enabled"] = "%d modules, %d enabled"
L["Action Bars"] = "Action Bars"
L["Unit Frames"] = "Unit Frames"
L["Auras"] = "Auras"
L["Inventory"] = "Inventory"
L["Skins"] = "Skins"
L["Filters"] = "Filters"
L["DataText"] = "DataText"
L["Maps"] = "Maps"
L["Automation"] = "Automation"
L["Announcements"] = "Announcements"
L["Miscellaneous"] = "Miscellaneous"

-- Module section titles (shown as headers in the options panel)
L["Cooldown Text"] = "Cooldown Text"
L["Class Colours"] = "Class Colours"
L["Social Colours"] = "Social Colours"
L["Character Frames"] = "Character Frames"
L["Item Level"] = "Item Level"
L["Objective Tracker"] = "Objective Tracker"
L["Chat Bubbles"] = "Chat Bubbles"
L["Tooltip"] = "Tooltip"
L["Chat"] = "Chat"
L["Chat Copy"] = "Chat Copy"
L["Chat Channels"] = "Chat Channels"

-- Tooltip (shared data words)
L["Rare"] = "Rare"
L["Trait"] = "Trait"
L["Stack Cap"] = "Stack Cap"
L["From"] = "From"
L["Section"] = "Section"
L["Mythic+ Score: %s"] = "Mythic+ Score: %s"

-- Tooltip options
L["Enable Tooltip"] = "Enable Tooltip"
L["Enhance the game tooltips with extra info (reload to fully disable)."] = "Enhance the game tooltips with extra info (reload to fully disable)."
L["Show Faction Icon"] = "Show Faction Icon"
L["Show an Alliance/Horde icon on player tooltips."] = "Show an Alliance/Horde icon on player tooltips."
L["Show Role Icon"] = "Show Role Icon"
L["Show the group role (tank/healer/dps) icon on player tooltips."] = "Show the group role (tank/healer/dps) icon on player tooltips."
L["Hide Realm Name"] = "Hide Realm Name"
L["Hide the realm name on players from other realms (hold Shift to reveal)."] = "Hide the realm name on players from other realms (hold Shift to reveal)."
L["Hide Player Title"] = "Hide Player Title"
L["Hide PvP/guild titles on player names."] = "Hide PvP/guild titles on player names."
L["Show Mythic+ Score"] = "Show Mythic+ Score"
L["Show the player's current-season Mythic+ rating."] = "Show the player's current-season Mythic+ rating."
L["Quality-Coloured Border"] = "Quality-Coloured Border"
L["Tint Blizzard's default tooltip border by item quality."] = "Tint Blizzard's default tooltip border by item quality."
L["Show Item Level"] = "Show Item Level"
L["Show the inspected player's item level on their tooltip."] = "Show the inspected player's item level on their tooltip."
L["Item Level on Shift"] = "Item Level on Shift"
L["Only show the inspected item level while holding Shift."] = "Only show the inspected item level while holding Shift."
L["Show IDs"] = "Show IDs"
L["Append spell, item, quest and other IDs to tooltips."] = "Append spell, item, quest and other IDs to tooltips."
L["Show Icons"] = "Show Icons"
L["Show an icon next to the tooltip title for spells, items and more."] = "Show an icon next to the tooltip title for spells, items and more."
L["Hyperlink Hover Tips"] = "Hyperlink Hover Tips"
L["Show a tooltip when hovering item/spell links in chat."] = "Show a tooltip when hovering item/spell links in chat."

-- ObjectiveTracker
L["Enable Objective Tracker Skin"] = "Enable Objective Tracker Skin"
L["Hide the tracker header backgrounds and tidy the minimise button (reload to disable)."] = "Hide the tracker header backgrounds and tidy the minimise button (reload to disable)."
L["Class-Coloured Bars"] = "Class-Coloured Bars"

-- ChatBubbles
L["Enable Chat Bubble Border"] = "Enable Chat Bubble Border"
L["Give chat bubbles a clean Blizzard-style border (reload to disable)."] = "Give chat bubbles a clean Blizzard-style border (reload to disable)."
L["Tint quest progress and timer bars with your class colour instead of the brand colour."] = "Tint quest progress and timer bars with your class colour instead of the brand colour."
L["Enabled"] = "Enabled"
L["Disabled"] = "Disabled"
L["Version"] = "Version"
L["Usage"] = "Usage"

-- Command help lines
L["Show this help"] = "Show this help"
L["List modules and their state"] = "List modules and their state"
L["Toggle a module: /nex toggle <module>"] = "Toggle a module: /nex toggle <module>"
L["Open the options panel"] = "Open the options panel"

-- AutoVendor
L["Auto Vendor"] = "Auto Vendor"
L["Enable Auto Vendor"] = "Enable Auto Vendor"
L["Automatically sell junk and repair when opening a merchant."] = "Automatically sell junk and repair when opening a merchant."
L["Auto Repair"] = "Auto Repair"
L["Repair equipment when opening a merchant that can repair."] = "Repair equipment when opening a merchant that can repair."
L["Use Guild Repairs"] = "Use Guild Repairs"
L["Use guild repair funds when available and allowed."] = "Use guild repair funds when available and allowed."
L["Sell Junk"] = "Sell Junk"
L["Sell Poor-quality items when opening a merchant."] = "Sell Poor-quality items when opening a merchant."
L["Repaired equipment for %s"] = "Repaired equipment for %s"
L["Repaired equipment using guild funds for %s"] = "Repaired equipment using guild funds for %s"
L["Sold junk for %s"] = "Sold junk for %s"
L["Not enough money to repair"] = "Not enough money to repair"

-- ActionBars
L["Enable Action Bars"] = "Enable Action Bars"
L["Style Blizzard action buttons and abbreviate hotkeys."] = "Style Blizzard action buttons and abbreviate hotkeys."
L["Show Macro Names"] = "Show Macro Names"
L["Show macro/action names on action buttons."] = "Show macro/action names on action buttons."
L["Show Counts"] = "Show Counts"
L["Show stack counts and charges on action buttons."] = "Show stack counts and charges on action buttons."
L["Show Hotkeys"] = "Show Hotkeys"
L["Show abbreviated keybind text on action buttons."] = "Show abbreviated keybind text on action buttons."
L["Macro Name Size"] = "Macro Name Size"
L["Font size for macro/action names."] = "Font size for macro/action names."
L["Count Size"] = "Count Size"
L["Font size for stack counts and charges."] = "Font size for stack counts and charges."
L["Hotkey Size"] = "Hotkey Size"
L["Font size for keybind text."] = "Font size for keybind text."

-- Cooldowns
L["Enable Cooldown Text"] = "Enable Cooldown Text"
L["Show formatted countdown numbers on cooldowns."] = "Show formatted countdown numbers on cooldowns."
L["Cooldown Style"] = "Cooldown Style"
L["Choose how cooldown numbers are displayed."] = "Choose how cooldown numbers are displayed."
L["Coloured (decimals)"] = "Coloured (decimals)"
L["Coloured (integers)"] = "Coloured (integers)"
L["Plain (decimals)"] = "Plain (decimals)"
L["Plain (integers)"] = "Plain (integers)"

-- CharacterFrames
L["Enable Character Frames"] = "Enable Character Frames"
L["Restyle and resize the Character and Inspect frames (reload to disable)."] = "Restyle and resize the Character and Inspect frames (reload to disable)."

-- ClassColors
L["Enable Class-Coloured Health"] = "Enable Class-Coloured Health"
L["Colour unit-frame health bars by class for players (player, target, focus, party and more)."] = "Colour unit-frame health bars by class for players (player, target, focus, party and more)."

-- SocialColors
L["Enable Social Class Colours"] = "Enable Social Class Colours"
L["Class-colour names and difficulty-colour levels in the Friends, Who and Guild panels (reload to disable)."] = "Class-colour names and difficulty-colour levels in the Friends, Who and Guild panels (reload to disable)."

-- DragEmAll
L["Drag Frames"] = "Drag Frames"
L["Enable Drag Frames"] = "Enable Drag Frames"
L["Click and drag most Blizzard windows to move them (reload to disable)."] = "Click and drag most Blizzard windows to move them (reload to disable)."

-- QuickQuest
L["Quick Quest"] = "Quick Quest"
L["Enable Quick Quest"] = "Enable Quick Quest"
L["Automatically accept and turn in quests; hold SHIFT to pause. Alt-click an NPC name to ignore it."] = "Automatically accept and turn in quests; hold SHIFT to pause. Alt-click an NPC name to ignore it."
L["Alt-click to toggle Quick Quest for this NPC."] = "Alt-click to toggle Quick Quest for this NPC."

-- UIScale
L["UI Scale"] = "UI Scale"
L["Enable UI Scale"] = "Enable UI Scale"
L["Let NexEnhance set the UIParent scale (reload-safe; ignores changes made in combat)."] = "Let NexEnhance set the UIParent scale (reload-safe; ignores changes made in combat)."
L["Auto (Pixel-Perfect)"] = "Auto (Pixel-Perfect)"
L["Automatically pick the scale that maps 1 UI pixel to 1 screen pixel for your resolution."] = "Automatically pick the scale that maps 1 UI pixel to 1 screen pixel for your resolution."
L["Manual Scale"] = "Manual Scale"
L["Scale used when Auto is disabled."] = "Scale used when Auto is disabled."

-- AlertFrames
L["Alert Frames"] = "Alert Frames"
L["Enable Alert Frames"] = "Enable Alert Frames"
L["Move achievement/loot/reward alert popups to the top of the screen (reload to disable)."] = "Move achievement/loot/reward alert popups to the top of the screen (reload to disable)."
L["Hide Talking Head"] = "Hide Talking Head"
L["Suppress the Talking Head dialog frame (reload to re-enable it)."] = "Suppress the Talking Head dialog frame (reload to re-enable it)."

-- MovieSkip
L["Faster Movie Skip"] = "Faster Movie Skip"
L["Enable Faster Movie Skip"] = "Enable Faster Movie Skip"
L["Press Space, Enter or Escape to instantly confirm the movie/cinematic skip dialog."] = "Press Space, Enter or Escape to instantly confirm the movie/cinematic skip dialog."

-- FasterLoot
L["Faster Loot"] = "Faster Loot"
L["Enable Faster Loot"] = "Enable Faster Loot"
L["Instantly clear loot when auto-loot is active."] = "Instantly clear loot when auto-loot is active."

-- Chat Filter
L["Chat Filter"] = "Chat Filter"
L["Enable Chat Filter"] = "Enable Chat Filter"
L["Filter chat spam and decorate item links (installs on enable; individual toggles below apply live)."] = "Filter chat spam and decorate item links (installs on enable; individual toggles below apply live)."
L["Spam Filter"] = "Spam Filter"
L["Hide messages matching blacklisted keywords or repeated near-identical spam. Manage keywords with /nexfilter."] = "Hide messages matching blacklisted keywords or repeated near-identical spam. Manage keywords with /nexfilter."
L["Match Threshold"] = "Match Threshold"
L["How many blacklisted keywords a message must contain before it is hidden."] = "How many blacklisted keywords a message must contain before it is hidden."
L["Block Strangers"] = "Block Strangers"
L["Hide whispers from anyone who is not a friend, guild member or group member."] = "Hide whispers from anyone who is not a friend, guild member or group member."
L["Block Spammers"] = "Block Spammers"
L["Hide all messages from a sender once they have tripped the filter repeatedly this session."] = "Hide all messages from a sender once they have tripped the filter repeatedly this session."
L["Item Level in Chat"] = "Item Level in Chat"
L["Append the item level and gem sockets to item links posted in chat."] = "Append the item level and gem sockets to item links posted in chat."
L["empty"] = "empty"
L["Added keyword"] = "Added keyword"
L["Removed keyword"] = "Removed keyword"
L["Added whitelist keyword"] = "Added whitelist keyword"
L["Chat filter keywords cleared."] = "Chat filter keywords cleared."
L["Filter keywords"] = "Filter keywords"
L["Whitelist keywords"] = "Whitelist keywords"
L["Chat filter usage:"] = "Chat filter usage:"

-- World Map
L["World Map"] = "World Map"
L["Enable World Map"] = "Enable World Map"
L["Enable the world map enhancements (some changes apply on the next map open or after a reload)."] = "Enable the world map enhancements (some changes apply on the next map open or after a reload)."
L["Show Coordinates"] = "Show Coordinates"
L["Show player and cursor coordinates along the bottom of the map."] = "Show player and cursor coordinates along the bottom of the map."
L["Smaller World Map"] = "Smaller World Map"
L["Scale the windowed map down so it no longer covers the whole screen."] = "Scale the windowed map down so it no longer covers the whole screen."
L["Map Scale"] = "Map Scale"
L["How large the windowed map is."] = "How large the windowed map is."
L["Fade When Moving"] = "Fade When Moving"
L["Fade the map out while your character is moving."] = "Fade the map out while your character is moving."
L["Alpha When Moving"] = "Alpha When Moving"
L["How transparent the map becomes while moving."] = "How transparent the map becomes while moving."

-- Buff Reminder
L["Buff Reminder"] = "Buff Reminder"
L["Enable Buff Reminder"] = "Enable Buff Reminder"
L["Show a 'Lack' icon when you are missing a buff you can provide. Move the anchor in Edit Mode."] = "Show a 'Lack' icon when you are missing a buff you can provide. Move the anchor in Edit Mode."
L["Lack"] = "Lack"

-- Animation
L["Animation"] = "Animation"
L["Login Logo"] = "Login Logo"
L["Play a logo flyby the first time you move after logging in. Replay it with /nexlogo."] = "Play a logo flyby the first time you move after logging in. Replay it with /nexlogo."
L["Combat Text"] = "Combat Text"
L["Show an animated Entering/Leaving Combat banner (reload to disable)."] = "Show an animated Entering/Leaving Combat banner (reload to disable)."

-- QuestNotification
L["Quest Notification"] = "Quest Notification"
L["Announce accepted quests and completions to your group."] = "Announce accepted quests and completions to your group."
L["Quest Progress"] = "Quest Progress"
L["Also announce objective progress updates."] = "Also announce objective progress updates."
L["Only Completion Sound"] = "Only Completion Sound"
L["Play a sound on quest completion but do not post any chat messages."] = "Play a sound on quest completion but do not post any chat messages."
L["Accepted"] = "Accepted:"

-- ItemLevel
L["Enable Item Level"] = "Enable Item Level"
L["Show item levels on equipped, bag, merchant, trade and loot items."] = "Show item levels on equipped, bag, merchant, trade and loot items."
L["Show Gems & Enchants"] = "Show Gems & Enchants"
L["Also show gem, socket and enchant info on Character and Inspect slots."] = "Also show gem, socket and enchant info on Character and Inspect slots."

-- Durability
L["Durability"] = "Durability"
L["Show Durability Information"] = "Show Durability Information"
L["Display the lowest equipped-item durability on the Character pane, with a per-slot repair-cost tooltip."] = "Display the lowest equipped-item durability on the Character pane, with a per-slot repair-cost tooltip."
L["DurabilityHelpTip"] = "Your equipment is heavily damaged. Repair it soon to avoid losing effectiveness."

-- Mail
L["Mail"] = "Mail"
L["Enable Mail"] = "Enable Mail"
L["Add Collect-Gold, Take-All and quick-delete buttons to the mailbox (reload to disable)."] = "Add Collect-Gold, Take-All and quick-delete buttons to the mailbox (reload to disable)."
L["Collect Gold"] = "Collect Gold"
L["Collecting..."] = "Collecting..."
L["Take All"] = "Take All"
L["Total Gold"] = "Total Gold"
L["Attachments"] = "Attachments"
L["This letter is cash on delivery."] = "This letter is cash on delivery."

-- DataText (FPS / latency)
L["Enable DataText"] = "Enable DataText"
L["Show a movable FPS / latency readout under the minimap, with a memory/addon tooltip (reload to disable)."] = "Show a movable FPS / latency readout under the minimap, with a memory/addon tooltip (reload to disable)."
L["Display"] = "Display"
L["Choose whether to show framerate, latency, or both."] = "Choose whether to show framerate, latency, or both."
L["FPS & Latency"] = "FPS & Latency"
L["FPS Only"] = "FPS Only"
L["Latency Only"] = "Latency Only"
L["Flip Order"] = "Flip Order"
L["Show latency before framerate."] = "Show latency before framerate."
L["Class-Coloured Numbers"] = "Class-Coloured Numbers"
L["Colour the numbers with your class colour instead of value-based colours."] = "Colour the numbers with your class colour instead of value-based colours."
L["Addons Shown"] = "Addons Shown"
L["How many addons to list in the memory tooltip before collapsing the rest under \"Hold Shift\"."] = "How many addons to list in the memory tooltip before collapsing the rest under \"Hold Shift\"."
L["Stats"] = "Stats"
L["Latency"] = "Latency"
L["Home Latency"] = "Home Latency"
L["World Latency"] = "World Latency"
L["Home Protocol"] = "Home Protocol"
L["World Protocol"] = "World Protocol"
L["Bandwidth"] = "Bandwidth"
L["Download"] = "Download"
L["System"] = "System"
L["Hidden"] = "Hidden"
L["Hold Shift"] = "Hold Shift"
L["Collect Memory"] = "Collect Memory"
L["Left-Click to collect memory"] = "Left-Click to collect memory"

-- Reload UI
L["Reload UI"] = "Reload UI"
L["Enable Reload Command"] = "Enable Reload Command"
L["Add /rl, /reloadui, // and /. slash commands to reload the interface (reload to disable)."] = "Add /rl, /reloadui, // and /. slash commands to reload the interface (reload to disable)."

-- Chat (core)
L["Enable Chat"] = "Enable Chat"
L["Enable the chat enhancements (reload to fully disable)."] = "Enable the chat enhancements (reload to fully disable)."
L["Flatten Tabs"] = "Flatten Tabs"
L["Strip the busy default chat tab textures for a flat look (reload to apply)."] = "Strip the busy default chat tab textures for a flat look (reload to apply)."
L["Edit Box Border"] = "Edit Box Border"
L["Give the chat input a Blizzard tooltip-style border (reload to apply)."] = "Give the chat input a Blizzard tooltip-style border (reload to apply)."
L["Edit Box on Top"] = "Edit Box on Top"
L["Dock the chat edit box to the top of the chat window (reload to apply)."] = "Dock the chat edit box to the top of the chat window (reload to apply)."
L["Colour Edit Box"] = "Colour Edit Box"
L["Tint the edit box border to match the active chat channel (reload to apply)."] = "Tint the edit box border to match the active chat channel (reload to apply)."
L["Hide Side Buttons"] = "Hide Side Buttons"
L["Hide the social/menu buttons beside the chat window."] = "Hide the social/menu buttons beside the chat window."
L["Tab Channel Switch"] = "Tab Channel Switch"
L["Press Tab in an empty edit box to cycle chat channels."] = "Press Tab in an empty edit box to cycle chat channels."
L["Quick Scroll"] = "Quick Scroll"
L["Shift + wheel jumps to top/bottom; Ctrl + wheel pages faster."] = "Shift + wheel jumps to top/bottom; Ctrl + wheel pages faster."
L["Sticky Whisper"] = "Sticky Whisper"
L["Keep the edit box in whisper mode after replying."] = "Keep the edit box in whisper mode after replying."
L["Whisper Sound"] = "Whisper Sound"
L["Play a sound when you receive a whisper."] = "Play a sound when you receive a whisper."
L["Font Size Menu"] = "Font Size Menu"
L["Add a font-size submenu to the chat tab right-click menu (reload to apply)."] = "Add a font-size submenu to the chat tab right-click menu (reload to apply)."
L["Keyword Auto-Invite"] = "Keyword Auto-Invite"
L["Invite players who whisper you the keyword below."] = "Invite players who whisper you the keyword below."
L["Guild/Friends Only"] = "Guild/Friends Only"
L["Only auto-invite guild members and Battle.net friends."] = "Only auto-invite guild members and Battle.net friends."

-- Chat Copy
L["Enable Chat Copy"] = "Enable Chat Copy"
L["Add a button to copy the chat window's text (reload to disable)."] = "Add a button to copy the chat window's text (reload to disable)."

-- Chat Channels
L["Enable Chat Channels"] = "Enable Chat Channels"
L["Tidy channel names, URLs and timestamps in chat (reload to fully disable)."] = "Tidy channel names, URLs and timestamps in chat (reload to fully disable)."
L["Abbreviate Channels"] = "Abbreviate Channels"
L["Shorten channel brackets, e.g. [1. General] becomes [1]."] = "Shorten channel brackets, e.g. [1. General] becomes [1]."
L["Clickable URLs"] = "Clickable URLs"
L["Make web links clickable and copyable (reload to apply)."] = "Make web links clickable and copyable (reload to apply)."
L["Timestamps"] = "Timestamps"
L["Prepend a [HH:MM] timestamp to each message."] = "Prepend a [HH:MM] timestamp to each message."
L["Copy the link below:"] = "Copy the link below:"
