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
L["General"] = "General"
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

-- Subcategory page descriptions (shown as an intro blurb at the top of each)
L["DESC_GENERAL"] = "Core, addon-wide settings such as UI scale and frame colouring that don't belong to any single feature."
L["DESC_ACTIONBARS"] = "Tweaks for your action bars, including cooldown count text on your abilities."
L["DESC_UNITFRAMES"] = "Adjustments to the default player, target, focus and group frames, like class-coloured health."
L["DESC_AURAS"] = "Buff and debuff helpers, including reminders for missing auras."
L["DESC_INVENTORY"] = "Bag and item quality-of-life: item levels, durability warnings, faster mail and known-item dimming."
L["DESC_CHAT"] = "Chat window improvements such as copying text, renaming channels and a cleaner look."
L["DESC_FILTERS"] = "Filter unwanted spam and repetitive messages out of your chat."
L["DESC_TOOLTIP"] = "Extra information and styling for game tooltips, like IDs, item levels and role icons."
L["DESC_SKINS"] = "Light, targeted restyling of select default Blizzard frames - improved, not replaced."
L["DESC_DATATEXT"] = "Compact information panels such as performance stats."
L["DESC_MAPS"] = "World map enhancements, coordinates and exploration helpers."
L["DESC_AUTOMATION"] = "Hands-off quality-of-life: auto-vendoring, quest turn-ins, faster looting and more."
L["DESC_ANNOUNCEMENTS"] = "Optional notifications for events like quest progress and completion."
L["DESC_MISC"] = "Everything else - smaller tweaks that don't fit neatly into the other sections."

-- Module section titles (shown as headers in the options panel)
L["Cooldown Text"] = "Cooldown Text"
L["Class Colours"] = "Class Colours"
L["Frame Colour"] = "Frame Colour"
L["Social Colours"] = "Social Colours"
L["Character Frames"] = "Character Frames"
L["Missing Stats"] = "Missing Stats"
L["Item Level"] = "Item Level"
L["Objective Tracker"] = "Objective Tracker"
L["Chat Bubbles"] = "Chat Bubbles"
L["Details"] = "Details"
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
L["Health Bar Position"] = "Health Bar Position"
L["Place the unit health bar at the top or bottom of the tooltip."] = "Place the unit health bar at the top or bottom of the tooltip."
L["Health Bar Height"] = "Health Bar Height"
L["Set the thickness of the unit health bar."] = "Set the thickness of the unit health bar."
L["Bottom"] = "Bottom"
L["Top"] = "Top"
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
L["Show Mount Source"] = "Show Mount Source"
L["Show a mount's collection status and source on aura tooltips (hold Shift over another player's mount buff)."] = "Show a mount's collection status and source on aura tooltips (hold Shift over another player's mount buff)."

-- ObjectiveTracker
L["Enable Objective Tracker Skin"] = "Enable Objective Tracker Skin"
L["Hide the tracker header backgrounds and tidy the minimise button (reload to disable)."] = "Hide the tracker header backgrounds and tidy the minimise button (reload to disable)."
L["Class-Coloured Bars"] = "Class-Coloured Bars"

-- Quest Navigation
L["Quest Navigation"] = "Quest Navigation"
L["Enable Quest Navigation"] = "Enable Quest Navigation"
L["Show an estimated arrival time under the waypoint arrow (reload to disable)."] = "Show an estimated arrival time under the waypoint arrow (reload to disable)."

-- ChatBubbles
L["Enable Chat Bubble Border"] = "Enable Chat Bubble Border"
L["Give chat bubbles a clean Blizzard-style border (reload to disable)."] = "Give chat bubbles a clean Blizzard-style border (reload to disable)."

-- Details
L["Enable Details Border"] = "Enable Details Border"
L["Skin Details! Damage Meter windows with the Minimalistic skin plus a Blizzard-style border and background (reload to fully revert)."] = "Skin Details! Damage Meter windows with the Minimalistic skin plus a Blizzard-style border and background (reload to fully revert)."
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
L["Toggle buff reminder test icons"] = "Toggle buff reminder test icons"
L["Module unavailable."] = "Module unavailable."

-- AutoVendor
L["Auto Vendor"] = "Auto Vendor"
L["Enable Auto Vendor"] = "Enable Auto Vendor"
L["Automatically sell junk and repair when opening a merchant."] = "Automatically sell junk and repair when opening a merchant."
L["Auto Repair"] = "Auto Repair"
L["Repair equipment when opening a merchant that can repair."] = "Repair equipment when opening a merchant that can repair."
L["Use Guild Repairs"] = "Use Guild Repairs"
L["Use guild repair funds when available and allowed."] = "Use guild repair funds when available and allowed."
L["Use guild repair funds when available, falling back to your own gold."] = "Use guild repair funds when available, falling back to your own gold."
L["Sell Junk"] = "Sell Junk"
L["Sell Poor-quality items when opening a merchant."] = "Sell Poor-quality items when opening a merchant."
L["Sell Poor-quality items, plus anything on your /nexjunk list, one at a time."] = "Sell Poor-quality items, plus anything on your /nexjunk list, one at a time."
L["Protect Pet Trash"] = "Protect Pet Trash"
L["Never auto-sell the handful of grey items that double as a currency."] = "Never auto-sell the handful of grey items that double as a currency."
L["Repaired equipment for %s"] = "Repaired equipment for %s"
L["Repaired equipment using guild funds for %s"] = "Repaired equipment using guild funds for %s"
L["Sold junk for %s"] = "Sold junk for %s"
L["Not enough money to repair"] = "Not enough money to repair"
L["Custom Junk List"] = "Custom Junk List"
L["Added %s to the junk list."] = "Added %s to the junk list."
L["Removed %s from the junk list."] = "Removed %s from the junk list."
L["Cleared the junk list."] = "Cleared the junk list."
L["The junk list is empty."] = "The junk list is empty."
L["Usage: /nexjunk add <item link or id>"] = "Usage: /nexjunk add <item link or id>"

-- Decline Duels
L["Decline Duels"] = "Decline Duels"
L["Enable Decline Duels"] = "Enable Decline Duels"
L["Automatically decline duel and pet-battle PvP duel requests."] = "Automatically decline duel and pet-battle PvP duel requests."
L["Decline Player Duels"] = "Decline Player Duels"
L["Decline standard player duel requests."] = "Decline standard player duel requests."
L["Decline Pet Duels"] = "Decline Pet Duels"
L["Decline pet-battle PvP duel requests."] = "Decline pet-battle PvP duel requests."
L["Declined a duel request from %s."] = "Declined a duel request from %s."
L["Declined a pet battle duel request from %s."] = "Declined a pet battle duel request from %s."

-- Auto Accept Invites
L["Auto Accept Invites"] = "Auto Accept Invites"
L["Enable Auto Accept Invites"] = "Enable Auto Accept Invites"
L["Automatically accept group invites from trusted sources."] = "Automatically accept group invites from trusted sources."
L["Accept From Friends"] = "Accept From Friends"
L["Auto-accept invites from Battle.net and character friends."] = "Auto-accept invites from Battle.net and character friends."
L["Accept From Guild"] = "Accept From Guild"
L["Auto-accept invites from guild members."] = "Auto-accept invites from guild members."

-- Auto Goodbye
L["Auto Goodbye"] = "Auto Goodbye"
L["Enable Auto Goodbye"] = "Enable Auto Goodbye"
L["Send a random friendly farewell to the group after finishing a dungeon or Mythic+ run."] = "Send a random friendly farewell to the group after finishing a dungeon or Mythic+ run."
-- Short, casual, context-free farewells. These fire after ANY group instance
-- (LFD dungeon, LFR raid, or M+ key), so nothing here may assume a key, a carry,
-- a raid, or multiple runs - just generic "that was a group, thanks/gg" energy,
-- typed the way a real player would (mostly lowercase, quick).
L["AutoGoodbyeMessages"] = {
	"gg",
	"gg all",
	"ggs",
	"gg wp",
	"gg everyone",
	"ty all",
	"thanks!",
	"thanks all",
	"ty, gg",
	"gg, ty!",
	"nice one, ty",
	"good run, thanks!",
	"cheers all",
	"ty for the group",
	"gg, take care!",
	"thanks team, gg",
}

-- Auto Resurrect
L["Auto Resurrect"] = "Auto Resurrect"
L["Enable Auto Resurrect"] = "Enable Auto Resurrect"
L["Automatically accept resurrection requests while you are out of combat (ignores item-cast soul stones like the encounter pylon and brazier)."] = "Automatically accept resurrection requests while you are out of combat (ignores item-cast soul stones like the encounter pylon and brazier)."
L["Thank the Resurrecter"] = "Thank the Resurrecter"
L["Send a /thank emote to whoever resurrected you, a few seconds after you are back up."] = "Send a /thank emote to whoever resurrected you, a few seconds after you are back up."

-- Auto Keystone
L["Auto Keystone"] = "Auto Keystone"
L["Enable Auto Keystone"] = "Enable Auto Keystone"
L["Automatically slot your Mythic+ keystone when the Challenge Mode UI opens."] = "Automatically slot your Mythic+ keystone when the Challenge Mode UI opens."
L["Keystone automatically placed."] = "Keystone automatically placed."

-- Delves Automation
L["Delves Automation"] = "Delves Automation"
L["Enable Delves Automation"] = "Enable Delves Automation"
L["While inside a Delve, automatically confirm the single-choice borrowed power popup."] = "While inside a Delve, automatically confirm the single-choice borrowed power popup."
L["Announce Auto-Selection"] = "Announce Auto-Selection"
L["Print the borrowed power you auto-selected to chat."] = "Print the borrowed power you auto-selected to chat."
L["Auto-selected:"] = "Auto-selected:"

-- Tooltip Vendor Location
L["Vendor Location"] = "Vendor Location"
L["Enable Vendor Location"] = "Enable Vendor Location"
L["For special barter/curio items, show where to turn them in and Ctrl-Click the item to set a map waypoint."] = "For special barter/curio items, show where to turn them in and Ctrl-Click the item to set a map waypoint."
L["Open Map on Waypoint"] = "Open Map on Waypoint"
L["Open the world map when you Ctrl-Click to set a vendor waypoint."] = "Open the world map when you Ctrl-Click to set a vendor waypoint."
L["<Ctrl-Click to set a waypoint>"] = "<Ctrl-Click to set a waypoint>"
L["Inside the Cave"] = "Inside the Cave"
L["Second Floor"] = "Second Floor"
L["Mount"] = "Mount"
L["Pet"] = "Pet"

-- Auto Hide Tracker
L["Auto Hide Tracker"] = "Auto Hide Tracker"
L["Enable Auto Hide Tracker"] = "Enable Auto Hide Tracker"
L["Hide the Objective Tracker during boss encounters and arena matches."] = "Hide the Objective Tracker during boss encounters and arena matches."
L["Hide in Mythic+"] = "Hide in Mythic+"
L["Also hide the tracker during Mythic+ keystone runs (otherwise your objectives stay visible)."] = "Also hide the tracker during Mythic+ keystone runs (otherwise your objectives stay visible)."

-- ActionBars
L["Enable Action Bars"] = "Enable Action Bars"
L["Style Blizzard action buttons and abbreviate hotkeys."] = "Style Blizzard action buttons and abbreviate hotkeys."
L["Show Macro Names"] = "Show Macro Names"
L["Show macro/action names on action buttons."] = "Show macro/action names on action buttons."
L["Show Counts"] = "Show Counts"
L["Show stack counts and charges on action buttons."] = "Show stack counts and charges on action buttons."
L["Show Hotkeys"] = "Show Hotkeys"
L["Show abbreviated keybind text on action buttons."] = "Show abbreviated keybind text on action buttons."
L["Skin Extra Buttons"] = "Skin Extra Buttons"
L["Give the Extra Action and Zone Ability buttons the standard action-bar button frame (reload to restore Blizzard's art)."] = "Give the Extra Action and Zone Ability buttons the standard action-bar button frame (reload to restore Blizzard's art)."
L["Extra Button Scale"] = "Extra Button Scale"
L["Scale of the Extra Action and Zone Ability buttons, as a percent (applied out of combat)."] = "Scale of the Extra Action and Zone Ability buttons, as a percent (applied out of combat)."
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
L["Minutes Format Threshold"] = "Minutes Format Threshold"
L["Below this many seconds the countdown shows raw seconds; at or above it switches to mm:ss."] = "Below this many seconds the countdown shows raw seconds; at or above it switches to mm:ss."
L["Scale Cooldown Text"] = "Scale Cooldown Text"
L["Scale the countdown text with the button size and hide it on very small cooldowns."] = "Scale the countdown text with the button size and hide it on very small cooldowns."
L["Minimum Text Scale"] = "Minimum Text Scale"
L["Hide the countdown text once its scale drops below this fraction of a normal button (needs Scale Cooldown Text)."] = "Hide the countdown text once its scale drops below this fraction of a normal button (needs Scale Cooldown Text)."

-- CharacterFrames
L["Enable Character Frames"] = "Enable Character Frames"
L["Restyle and resize the Character and Inspect frames (reload to disable)."] = "Restyle and resize the Character and Inspect frames (reload to disable)."

-- MissingStats
L["Enable Missing Stats"] = "Enable Missing Stats"
L["Show the hidden character-sheet stats (attack power, weapon speed, spell power, regen, movement) and tidy the readouts (reload to disable)."] = "Show the hidden character-sheet stats (attack power, weapon speed, spell power, regen, movement) and tidy the readouts (reload to disable)."

-- ClassColors
L["Enable Class-Coloured Health"] = "Enable Class-Coloured Health"
L["Colour unit-frame health bars by class for players and by reaction for NPCs (player, target, focus, boss, party and more)."] = "Colour unit-frame health bars by class for players and by reaction for NPCs (player, target, focus, boss, party and more)."
L["Neutral Target Strip"] = "Neutral Target Strip"
L["Remove the reaction-coloured tint on the Target/Focus status strip so it matches the clean, dark player-frame look."] = "Remove the reaction-coloured tint on the Target/Focus status strip so it matches the clean, dark player-frame look."

-- FrameColors
L["Enable Frame Colour"] = "Enable Frame Colour"
L["Tint the default unit frames and HUD elements (player, pet, target, focus, boss, class resources, cast bars, totems and the minimap) with a colour of your choice."] = "Tint the default unit frames and HUD elements (player, pet, target, focus, boss, class resources, cast bars, totems and the minimap) with a colour of your choice."
L["Border Colour"] = "Border Colour"
L["The colour applied to the unit-frame borders. Pick black for a clean dark look, or any colour you like."] = "The colour applied to the unit-frame borders. Pick black for a clean dark look, or any colour you like."

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
L["Automatically accept and turn in quests; hold the override key to pause. Alt-click an NPC name to ignore it."] = "Automatically accept and turn in quests; hold the override key to pause. Alt-click an NPC name to ignore it."
L["Accept Regular Quests"] = "Accept Regular Quests"
L["Automatically accept regular (one-time) quests."] = "Automatically accept regular (one-time) quests."
L["Accept Daily Quests"] = "Accept Daily Quests"
L["Automatically accept daily quests."] = "Automatically accept daily quests."
L["Accept Weekly Quests"] = "Accept Weekly Quests"
L["Automatically accept weekly quests."] = "Automatically accept weekly quests."
L["Protect Costly Turn-Ins"] = "Protect Costly Turn-Ins"
L["Skip turn-ins that would consume gold, currency, crafting reagents, or account-bound items."] = "Skip turn-ins that would consume gold, currency, crafting reagents, or account-bound items."
L["Require Override Key"] = "Require Override Key"
L["Only automate while the override key is held, instead of using it to pause."] = "Only automate while the override key is held, instead of using it to pause."
L["Override Key"] = "Override Key"
L["The modifier that pauses (or, with Require Override Key, enables) automation."] = "The modifier that pauses (or, with Require Override Key, enables) automation."
L["SHIFT"] = "Shift"
L["ALT"] = "Alt"
L["CONTROL"] = "Control"
L["Block in Raids & Instances"] = "Block in Raids & Instances"
L["Skip single-option gossip auto-selection while in raids and certain instances."] = "Skip single-option gossip auto-selection while in raids and certain instances."
L["Alt-click to toggle Quick Quest for this NPC."] = "Alt-click to toggle Quick Quest for this NPC."

-- UIScale
L["UI Scale"] = "UI Scale"
L["Enable UI Scale"] = "Enable UI Scale"
L["Let NexEnhance set the UIParent scale (reload-safe; ignores changes made in combat)."] = "Let NexEnhance set the UIParent scale (reload-safe; ignores changes made in combat)."
L["Auto (Pixel-Perfect)"] = "Auto (Pixel-Perfect)"
L["Automatically pick the scale that maps 1 UI pixel to 1 screen pixel for your resolution."] = "Automatically pick the scale that maps 1 UI pixel to 1 screen pixel for your resolution."
L["Manual Scale"] = "Manual Scale"
L["Scale used when Auto is disabled."] = "Scale used when Auto is disabled."

-- Number Format
L["Number Format"] = "Number Format"
L["Choose how large numbers are abbreviated throughout NexEnhance."] = "Choose how large numbers are abbreviated throughout NexEnhance."
L["Standard (1.2k / 3.4m)"] = "Standard (1.2k / 3.4m)"
L["East Asian (1.2w / 3.4y)"] = "East Asian (1.2w / 3.4y)"
L["Full Numbers (No Abbreviation)"] = "Full Numbers (No Abbreviation)"
L["Abbrev Number One"] = "w"
L["Abbrev Number Two"] = "y"
L["Abbrev Number Three"] = "z"

-- Camera Zoom
L["Camera Zoom"] = "Camera Zoom"
L["Enable Camera Zoom"] = "Enable Camera Zoom"
L["Raise the maximum camera zoom-out distance."] = "Raise the maximum camera zoom-out distance."
L["Max Zoom Distance"] = "Max Zoom Distance"
L["How far out the camera can zoom (Blizzard limit is 2.6)."] = "How far out the camera can zoom (Blizzard limit is 2.6)."

-- Cast On Key Down
L["Cast On Key Down"] = "Cast On Key Down"
L["Action buttons fire when a key is pressed instead of when it is released."] = "Action buttons fire when a key is pressed instead of when it is released."

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

-- Wowhead Links
L["Wowhead Links"] = "Wowhead Links"
L["Enable Wowhead Links"] = "Enable Wowhead Links"
L["Add a copyable Wowhead link to the world map (tracked quest) and the achievement frame."] = "Add a copyable Wowhead link to the world map (tracked quest) and the achievement frame."
L["Press To Copy"] = "Press To Copy"

-- Map Reveal
L["Map Reveal"] = "Map Reveal"
L["Enable Map Reveal"] = "Enable Map Reveal"
L["Reveal unexplored areas on the world map by removing fog of war."] = "Reveal unexplored areas on the world map by removing fog of war."
L["Dim Revealed Areas"] = "Dim Revealed Areas"
L["Slightly darken the revealed tiles so explored areas still stand out."] = "Slightly darken the revealed tiles so explored areas still stand out."

-- Minimap
L["Minimap"] = "Minimap"
L["Enable Minimap"] = "Enable Minimap"
L["Adds optional minimap conveniences (reload to apply)."] = "Adds optional minimap conveniences (reload to apply)."
L["Easy Volume"] = "Easy Volume"
L["Hold Ctrl and scroll over the minimap to adjust the master volume (hold Alt for full range)."] = "Hold Ctrl and scroll over the minimap to adjust the master volume (hold Alt for full range)."
L["Minimap Menu"] = "Minimap Menu"
L["Middle-click the minimap to open a shortcut menu of Blizzard panels."] = "Middle-click the minimap to open a shortcut menu of Blizzard panels."
L["Square the minimap, add a clean border and tidy its buttons (reload to apply)."] = "Square the minimap, add a clean border and tidy its buttons (reload to apply)."
L["Minimap Border"] = "Minimap Border"
L["Frame the minimap with a Blizzard tooltip-style border (reload to apply)."] = "Frame the minimap with a Blizzard tooltip-style border (reload to apply)."
L["Status Pulse"] = "Status Pulse"
L["Pulse the minimap border in combat (red) or for pending mail / calendar invites (yellow)."] = "Pulse the minimap border in combat (red) or for pending mail / calendar invites (yellow)."
L["Collect Buttons"] = "Collect Buttons"
L["Sweep stray addon minimap buttons into a pop-out tray behind a small corner toggle (reload to disable)."] = "Sweep stray addon minimap buttons into a pop-out tray behind a small corner toggle (reload to disable)."
L["Button Tray Position"] = "Button Tray Position"
L["Which minimap corner the button tray toggle hugs."] = "Which minimap corner the button tray toggle hugs."
L["Top Left"] = "Top Left"
L["Top Right"] = "Top Right"
L["Bottom Left"] = "Bottom Left"
L["Bottom Right"] = "Bottom Right"
L["Minimap Buttons"] = "Minimap Buttons"
L["Collect addon minimap buttons into a pop-out tray."] = "Collect addon minimap buttons into a pop-out tray."
L["Calendar"] = "Calendar"
L["Right Click to switch Summaries"] = "Right Click to switch Summaries"

-- Achievement Screenshot
L["Achievement Screenshot"] = "Achievement Screenshot"
L["Automatically take a screenshot when you earn a new achievement."] = "Automatically take a screenshot when you earn a new achievement."

-- Buff Reminder
L["Buff Reminder"] = "Buff Reminder"
L["Enable Buff Reminder"] = "Enable Buff Reminder"
L["Show a 'Lack' icon when you are missing a buff you can provide. Move the anchor in Edit Mode."] = "Show a 'Lack' icon when you are missing a buff you can provide. Move the anchor in Edit Mode."
L["Lack"] = "Lack"
L["Test mode on - drag the anchor in Edit Mode."] = "Test mode on - drag the anchor in Edit Mode."
L["Test mode off."] = "Test mode off."
L["Icon Size"] = "Icon Size"
L["Size of the buff reminder icons. Preview with /nex reminder."] = "Size of the buff reminder icons. Preview with /nex reminder."

-- Animation
L["Animation"] = "Animation"
L["Login Logo"] = "Login Logo"
L["Play a logo flyby the first time you move after logging in. Replay it with /nexlogo."] = "Play a logo flyby the first time you move after logging in. Replay it with /nexlogo."
L["Combat Text"] = "Combat Text"
L["Show an animated Entering/Leaving Combat banner (reload to disable)."] = "Show an animated Entering/Leaving Combat banner (reload to disable)."

-- AFK Camera
L["AFK Camera"] = "AFK Camera"
L["Enable AFK Camera"] = "Enable AFK Camera"
L["Immersive AFK overlay with camera spin, character model, clock and random stats."] = "Immersive AFK overlay with camera spin, character model, clock and random stats."
L["AFK Random Stats"] = "Random Stats"
L["AFK Logout Timer"] = "Logout Timer:"

-- Experience / Reputation Bar
L["Experience Bar"] = "Experience Bar"
L["Enable Experience Bar"] = "Enable Experience Bar"
L["Replace Blizzard's experience/reputation tracker with a movable bar (reload to restore Blizzard's)."] = "Replace Blizzard's experience/reputation tracker with a movable bar (reload to restore Blizzard's)."
L["Show Bar Text"] = "Show Bar Text"
L["Show the progress text on the bar."] = "Show the progress text on the bar."
L["Show Rested"] = "Show Rested"
L["Show the rested-experience overlay while levelling."] = "Show the rested-experience overlay while levelling."
L["Bar Width"] = "Bar Width"
L["Width of the experience bar."] = "Width of the experience bar."
L["Bar Height"] = "Bar Height"
L["Height of the experience bar."] = "Height of the experience bar."
L["Font Size"] = "Font Size"
L["Size of the bar text."] = "Size of the bar text."
L["Fade Bar"] = "Fade Bar"
L["Fade the bar out and reveal it on mouseover."] = "Fade the bar out and reveal it on mouseover."
L["Faded Opacity"] = "Faded Opacity"
L["Opacity of the bar when faded out (0 = fully hidden)."] = "Opacity of the bar when faded out (0 = fully hidden)."
L["Show in Combat"] = "Show in Combat"
L["Keep the bar fully visible while in combat."] = "Keep the bar fully visible while in combat."
L["Show with Target"] = "Show with Target"
L["Keep the bar fully visible while you have a target or focus."] = "Keep the bar fully visible while you have a target or focus."
L["XP"] = "Experience"
L["Remaining"] = "Remaining"
L["Rested"] = "Rested"
L["Bars"] = "Bars"
L["Paragon"] = "Paragon"
L["Honor XP"] = "Honor"
L["Alt + Right-Click to report to party chat."] = "Alt + Right-Click to report to party chat."

-- QuestNotification
L["Quest Notification"] = "Quest Notification"
L["Announce accepted quests and completions to your group."] = "Announce accepted quests and completions to your group."
L["Quest Progress"] = "Quest Progress"
L["Also announce objective progress updates."] = "Also announce objective progress updates."
L["Only Completion Sound"] = "Only Completion Sound"
L["Play a sound on quest completion but do not post any chat messages."] = "Play a sound on quest completion but do not post any chat messages."
L["Accepted"] = "Accepted:"

-- RareAlert
L["Rare Alert"] = "Rare Alert"
L["Announce nearby rare creatures and world events the moment they appear on the minimap."] = "Announce nearby rare creatures and world events the moment they appear on the minimap."
L["Rare Alert Sound"] = "Rare Alert Sound"
L["Play an alert sound when a rare is detected."] = "Play an alert sound when a rare is detected."
L["Sound In World Only"] = "Sound In World Only"
L["Only play the alert sound in the open world, not inside instances."] = "Only play the alert sound in the open world, not inside instances."
L["Rare Alert To Chat"] = "Rare Alert To Chat"
L["Post a clickable map link to chat when a rare is detected."] = "Post a clickable map link to chat when a rare is detected."
L["Ignored Rare IDs"] = "Ignored Rare IDs"
L["Space or comma separated vignette IDs to never announce."] = "Space or comma separated vignette IDs to never announce."
L["Rare Found"] = "Rare Found: "

-- ItemLevel
L["Enable Item Level"] = "Enable Item Level"
L["Show item levels on equipped, bag, merchant, trade and loot items."] = "Show item levels on equipped, bag, merchant, trade and loot items."
L["Show Gems & Enchants"] = "Show Gems & Enchants"
L["Also show gem, socket and enchant info on Character and Inspect slots."] = "Also show gem, socket and enchant info on Character and Inspect slots."
L["Warn Missing Enchants"] = "Warn Missing Enchants"
L["Show a red icon on Character and Inspect slots that can be enchanted but aren't."] = "Show a red icon on Character and Inspect slots that can be enchanted but aren't."
L["Missing Enchant: %s"] = "Missing Enchant: %s"
L["Show Bind Status"] = "Show Bind Status"
L["Show BoE, BoA and WuE labels on bag and bank items that are not yet bound."] = "Show BoE, BoA and WuE labels on bag and bank items that are not yet bound."
L["Item Level Font Size"] = "Item Level Font Size"
L["Font size for the item level numbers on equipped, bag, merchant, trade and loot items."] = "Font size for the item level numbers on equipped, bag, merchant, trade and loot items."

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

-- Already Known
L["Already Known"] = "Already Known"
L["Enable Already Known"] = "Enable Already Known"
L["Tint already-known recipes, pets, toys and cosmetics green at vendors, the Auction House and Guild Bank (reload to disable)."] = "Tint already-known recipes, pets, toys and cosmetics green at vendors, the Auction House and Guild Bank (reload to disable)."

-- Junk Icon
L["Junk Icon"] = "Junk Icon"
L["Enable Junk Icon"] = "Enable Junk Icon"
L["Always show the coin icon on Poor-quality bag items, not just when a merchant is open (reload to disable)."] = "Always show the coin icon on Poor-quality bag items, not just when a merchant is open (reload to disable)."

-- Unusable Items
L["Unusable Items"] = "Unusable Items"
L["Colour Unusable Items"] = "Colour Unusable Items"
L["Tint bag and bank icons red for items your class can't use or that you're too low level for (reload to disable)."] = "Tint bag and bank icons red for items your class can't use or that you're too low level for (reload to disable)."

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
L['How many addons to list in the memory tooltip before collapsing the rest under "Hold Shift".'] = 'How many addons to list in the memory tooltip before collapsing the rest under "Hold Shift".'
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

L["Clock"] = "Clock"
L["Enable Clock"] = "Enable Clock"
L["Show a clock on the minimap with a lockout / reset tooltip (reload to disable)."] = "Show a clock on the minimap with a lockout / reset tooltip (reload to disable)."
L["Colour the clock with your class colour."] = "Colour the clock with your class colour."
L["Local Time"] = "Local Time"
L["Realm Time"] = "Realm Time"
L["Daily Reset"] = "Daily Reset"
L["Weekly Reset"] = "Weekly Reset"
L["Saved Raid(s)"] = "Saved Raid(s)"
L["Saved Dungeon(s)"] = "Saved Dungeon(s)"
L["Delves"] = "Delves"
L["Restored Coffer Key"] = "Restored Coffer Key"
L["Feast of Winter Veil"] = "Feast of Winter Veil"
L["Blingtron Daily Gift"] = "Blingtron Daily Gift"
L["500 Timewarped Badges"] = "500 Timewarped Badges"
L["Grand Hunt"] = "Grand Hunt"
L["Community Feast"] = "Community Feast"
L["The Big Dig"] = "The Big Dig"
L["The Superbloom"] = "The Superbloom"
L["Legion Invasion"] = "Legion Invasion"
L["Faction Assault"] = "Faction Assault"
L["Current Invasion"] = "Current Invasion: "
L["Next Invasion"] = "Next Invasion: "
L["Hold SHIFT for info"] = "Hold SHIFT for more event info."
L["Left-Click: Calendar"] = "Left-Click: Calendar"
L["Middle-Click: Great Vault"] = "Middle-Click: Great Vault"
L["Right-Click: Time Manager"] = "Right-Click: Time Manager"

L["Location"] = "Location"
L["Enable Location"] = "Enable Location"
L["Show zone and sub-zone text at the top of the minimap (reload to disable)."] = "Show zone and sub-zone text at the top of the minimap (reload to disable)."
L["Show on Mouseover"] = "Show on Mouseover"
L["Only show the zone text while hovering the minimap."] = "Only show the zone text while hovering the minimap."

-- Reload UI
L["Reload UI"] = "Reload UI"
L["Enable Reload Command"] = "Enable Reload Command"
L["Add /rl, /reloadui, // and /. slash commands to reload the interface (reload to disable)."] = "Add /rl, /reloadui, // and /. slash commands to reload the interface (reload to disable)."

-- Install / First-Run
L["Welcome to NexEnhance"] = "Welcome to NexEnhance"
L["Open the setup screen"] = "Open the setup screen"
L["Install"] = "Install"
L["Not Now"] = "Not Now"
L["Loaded. Type /nex for options."] = "Loaded. Type /nex for options."
L["Set up NexEnhance with a handful of recommended Blizzard settings:"] = "Set up NexEnhance with a handful of recommended Blizzard settings:"
L["Auto-loot, compare items on hover and self-cast on right-click."] = "Auto-loot, compare items on hover and self-cast on right-click."
L["Locked action bars that are always shown, with cleaner combat text."] = "Locked action bars that are always shown, with cleaner combat text."
L["Moving nameplates that show all enemies."] = "Moving nameplates that show all enemies."
L["Class-coloured raid frames with power bars and no clutter."] = "Class-coloured raid frames with power bars and no clutter."
L["Your other settings are left untouched. You can re-run this anytime with /nex install."] = "Your other settings are left untouched. You can re-run this anytime with /nex install."
L["Choosing Install will reload your interface."] = "Choosing Install will reload your interface."

-- Queue Timer
L["Queue Timer"] = "Queue Timer"
L["Enable Queue Timer"] = "Enable Queue Timer"
L["Replace the small LFG/PvP ready countdown with a larger, colour-coded timer (reload to disable)."] = "Replace the small LFG/PvP ready countdown with a larger, colour-coded timer (reload to disable)."
L["Queue Warning Sound"] = "Queue Warning Sound"
L["Play a triple beep when the queue is about to expire."] = "Play a triple beep when the queue is about to expire."
L["Hide Default Timers"] = "Hide Default Timers"
L["Hide Blizzard's default queue status bars while the custom timer is shown."] = "Hide Blizzard's default queue status bars while the custom timer is shown."
L["Queue expires in"] = "Queue expires in"

-- Trade Target Info
L["Trade Target Info"] = "Trade Target Info"
L["Enable Trade Target Info"] = "Enable Trade Target Info"
L["Show whether your trade partner is a stranger, friend or guild member, and colour their name (reload to disable)."] = "Show whether your trade partner is a stranger, friend or guild member, and colour their name (reload to disable)."
L["Stranger"] = "Stranger"

-- Quick Item Delete
L["Quick Item Delete"] = "Quick Item Delete"
L["Enable Quick Item Delete"] = "Enable Quick Item Delete"
L["Skip the type-DELETE confirmation for high-quality and quest items, showing a simple Yes/No prompt instead. Reduces accidental-deletion protection."] = "Skip the type-DELETE confirmation for high-quality and quest items, showing a simple Yes/No prompt instead. Reduces accidental-deletion protection."

-- Changelog
L["Changelog"] = "Changelog"
L["Open the changelog"] = "Open the changelog"
L["Auto-Show Changelog"] = "Auto-Show Changelog"
L["Open the changelog automatically the first time you log in after an update."] = "Open the changelog automatically the first time you log in after an update."

-- Credits
L["Credits"] = "Credits"
L["Open the credits panel"] = "Open the credits panel"
L["CREDITS_HEADING"] = "Thank You"
L["CREDITS_SUBTITLE"] = "NexEnhance stands on the shoulders of incredible addon authors."
L["CREDITS_INTRO"] = "So much of what you see here began elsewhere — borrowed with respect, adapted to fit the default UI, and shared back with gratitude. To every author below: thank you for the ideas, the code, and the years of polish that made this project possible."
L["CREDITS_LIBRARIES"] = "Libraries"
L["CREDITS_FOOTER"] = "Built with love for the default UI. NexEnhance would not exist without you."

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
L["Hide Edit Box When Inactive"] = "Hide Edit Box When Inactive"
L["Keep the chat edit box hidden until you focus it (reload to apply)."] = "Keep the chat edit box hidden until you focus it (reload to apply)."
L["Hide Side Buttons"] = "Hide Side Buttons"
L["Hide the social/menu buttons beside the chat window."] = "Hide the social/menu buttons beside the chat window."
L["Hide Scroll Bar"] = "Hide Scroll Bar"
L["Remove the scroll bar and jump-to-bottom button (reload to restore)."] = "Remove the scroll bar and jump-to-bottom button (reload to restore)."
L["Battle.net Pop-up"] = "Battle.net Pop-up"
L["Quick Join Button"] = "Quick Join Button"
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
L["Enable Keyword Auto-Invite"] = "Enable Keyword Auto-Invite"
L["Invite players who whisper you your keyword."] = "Invite players who whisper you your keyword."
L["Guild/Friends Only"] = "Guild/Friends Only"
L["Only auto-invite guild members and Battle.net friends."] = "Only auto-invite guild members and Battle.net friends."
L["When Keyword Auto-Invite is enabled, anyone who whispers you this exact word is invited to your group."] = "When Keyword Auto-Invite is enabled, anyone who whispers you this exact word is invited to your group."
L["Invite Keyword"] = "Invite Keyword"
L["Invite keyword set to:"] = "Invite keyword set to:"
L["Invite keyword cleared."] = "Invite keyword cleared."

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
