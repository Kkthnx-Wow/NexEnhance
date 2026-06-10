--[[
	NexEnhance - Changelog
	-------------------------------------------------------------------------
	A styled, in-game changelog window. Opens automatically once per account
	whenever the version changes, and any time via /nex changelog.

	The data table below is the single source of truth for the in-game notes;
	keep it in sync with CHANGELOG.md.
--]]

---@diagnostic disable: undefined-field
local _, ns = ...
local C, L, F = ns.C, ns.L, ns.F

local _G = _G
local ipairs = ipairs
local max = math.max
local format = string.format
local tconcat = table.concat
local CreateFrame = CreateFrame
local C_Timer = C_Timer

ns:RegisterDefaults({
	changelog = {
		enable = true,
		autoShow = true,
	},
})
ns:RegisterDefaults({ lastChangelog = false }, "global")

local Changelog = ns:NewModule("Changelog", "changelog", { group = "misc", title = L["Changelog"], order = 90 })

-- A Blizzard tooltip-style border (matches the rest of the UI).
local BACKDROP = C.Backdrops.window

-- ---------------------------------------------------------------------------
-- Notes (keep in sync with CHANGELOG.md)
-- ---------------------------------------------------------------------------
local CHANGELOG = {
	{
		version = "1.2.8",
		date = "2026-06-10",
		intro = "The Clock datatext catches up to Midnight - Stormarion Assault, Abundance and Void Incursion timers, the world boss that's up right now, Void Assault weeklies and a delve rework - with older world events tucked behind a toggle. Plus sharper rare alerts, item level and bind status on the warband bank, and more Secret-Value hardening: the rare popup is a click-to-track banner you can move in Edit Mode, faster loot is more reliable, the loot window can grow taller, known housing decor dims at vendors, and tooltip health text shows again even when health is a secret value.",
		sections = {
			{ "DataText", {
				"Clock: the lockout tooltip now tracks current Midnight world content - Stormarion Assault, Abundance (e.g. Herbalism Grotto) and Void Incursions - reading live countdowns and progress straight from the POI/event widgets and labelling impending vs. active incursions.",
				"Clock: detects the world boss that's up right now via a map POI scan, shown next to your saved world-boss lockout, and tracks the weekly Void Assault meta with a fail-safe when its quest data isn't available.",
				"Clock: tracks Midnight's headline weekly - the Choose Your Path meta (Unity Against the Void from Lady Liadrin). The meta's flag drives Complete/Incomplete, and whichever path you picked (e.g. Midnight: Delves) shows its progress underneath while it's in your log; only shown once you're engaged with it.",
				"Clock: delves are reworked for Midnight - it caps the bountiful-delve list to the four that can be up and de-duplicates them by name so a delve no longer shows twice across continent and zone maps (the old War Within coffer-key fragment line was dropped in favour of the weekly above).",
				"Clock: every countdown now uses one compact format - 6d 10h, 10h 30m, 32m, 45s - in consistent white text, keeping status colours only for special states (Available, Active, Complete, percentages).",
				"Clock: older expansion world events (Legion invasions, faction assaults, elemental storms, feasts) now sit behind a Show Legacy World Events toggle, off by default.",
			} },
			{ "Announcements", {
				"Rare Alert: the alert can now show a movable click-to-track popup with a 2D portrait (falling back to the vignette icon). Left-click to drop a TomTom/Blizzard waypoint, optionally target the rare and place a raid marker.",
				"Rare Alert: /nex rare toggles a sticky preview, and entering Edit Mode now reveals the banner automatically so you can move it without the preview command.",
				"Rare Alert: stricter, cheaper detection - treasure/lore/non-rare vignettes are filtered out, the ignore list also matches the rare's NPC ID, and a per-rare cooldown stops repeat spam when flying in and out of range.",
				"Rare Alert: the click-to-target now works even if you use key-down action casting - it forces ActionButtonUseKeyDown off for the click and restores it afterwards so /targetexact fires reliably. Cherry-picked from RareAlert.",
				"Rare Alert: optional Sound While Alt-Tabbed - the alert sound can play while WoW is minimised or in the background, briefly overriding your background-sound setting and restoring it afterwards. Off by default.",
			} },
			{ "Inventory", {
				"Loot Frame: new module that lets Blizzard's default loot window grow taller so more items fit on one page instead of scrolling, with a live toggle and a configurable max height. Inspired by Cybeloras' Improved Loot Frame.",
				"Already Known: housing decor now dims green at vendors, the Auction House and the guild bank when you already own or have placed it, via the Midnight housing catalog.",
			} },
			{ "Automation", {
				"Faster Loot: reworked into a paced slot-walker - it listens to both LOOT_READY and LOOT_OPENED, handles noisy auto-loot state, avoids duplicate work and stops cleanly when the loot window closes. Inspired by SpeedyAutoLoot by Yuyuli.",
			} },
			{ "Tooltip", {
				"Health Bar Text: the unit health bar shows current / max again (with a current-only option). It now follows ElvUI's retail-safe approach - Blizzard drives the bar and we post-hook its health update.",
				"Quality Border: dropped the old recipe item-name width tweak (fragile under Secret Values for no real gain); the item post-call now only tints Blizzard's default border by item quality.",
			} },
			{ "Fixed", {
				"Item Level: fixed item level and bind status not appearing on bank and warband bank items - the slots now update off ItemButton:UpdateCooldown (matching Unusable Items), hook both the generate and refresh-all bank paths, and install on BANKFRAME_OPENED so the load-on-demand bank UI is covered.",
				"Tooltip (secret values): fixed taint thrown from Blizzard's own tooltip widget code (GameTooltip_AddWidgetSet/ClearWidgetSet and EmbeddedItemTooltip_UpdateSize) when our hooks run while widget geometry is secret (e.g. map POI / world-event tooltips); those paths now swallow the secret-value error instead of erroring out.",
				"Tooltip (secret values): health text no longer blanks out when UnitHealth is a 12.0 secret value (in combat or instances); secret numbers are shown safely via number abbreviation instead of being discarded.",
				"Tooltip: health text no longer flickers or briefly shows the wrong values while the tooltip is refreshing (for example when jumping in-game); it now reads only the unit attached to the tooltip/status bar instead of guessing from mouseover.",
				"Tooltip (secret values): hiding the status bar no longer tests IsShown() on a bar that can inherit secret aspects after Blizzard writes secret health into it, and tooltip cleanup no longer touches Blizzard state at unsafe times (fixes map POI/event tooltip taint).",
				"Rare Alert: showing/hiding the secure click-to-target popup in combat is now safe - it skips showing in combat and defers hides until combat ends.",
				"Rare Alert: fixed Edit Mode click/drag conflicts where the secure overlay could sit above the mover and block moving the banner.",
				"Faster Loot: locked-slot handling now works across client variants of GetLootSlotInfo.",
				"Minimap (Collect Buttons): the AllTheThings button no longer shows up oversized or escapes the tray - its icon is re-clamped to the slot on every open and its self-positioning is stopped once parked.",
				"Faster Movie Skip: enabling it from the Settings panel now works live instead of needing a reload.",
				"Social Colours: the friends/who lists no longer do O(n^2) work refreshing - the scroll rows are enumerated once per refresh.",
			} },
			{ "Performance", {
				"Quick Quest now uses the shared addon event system instead of its own event frame, and only registers its quest events while enabled - so it no longer wakes on QUEST_LOG_UPDATE for players who leave it off (it defaults off).",
				"Action Bars: hotkey abbreviation is memoised per keybind, so the substitution pass runs once per unique bind instead of on every text refresh.",
				"Chat Channels: URL highlighting skips its link patterns entirely on lines with no link via a cheap pre-check.",
				"Clock & Stats: while hovered, the heavy tooltips now rebuild on a throttle (clock every 30s, addon-memory every 5s) instead of every tick; the visible time/FPS/latency keep updating, and Shift still expands the memory list instantly.",
				"Core: rebuilt the object pool (F.CreatePool) and added an internal pub/sub signal bus (adapted from Plumber's CallbackRegistry) so modules react to setting changes without hard references - the Settings landing count and minimap indicator/button-tray now update live.",
			} },
		},
	},
	{
		version = "1.2.7",
		date = "2026-06-08",
		intro = "A full Profiles system - create, copy, switch, delete and import/export your settings as a single copy-paste string - plus a ground-up AFK Camera rework: a resolution-independent cinematic screen with a companion battle pet idling at your side.",
		sections = {
			{ "Profiles", {
				"New Profiles system: create, copy, switch and delete settings profiles, and import/export any profile as a single copy-paste string for backups or sharing. New profiles and copies won't overwrite an existing name - they report an error instead. Open the Profiles settings page or use /nex profile.",
			} },
			{ "Automation", {
				"Cancel Bad Buffs: automatically removes cosmetic costume and holiday transforms (Hallow's End costumes, Mohawked!, Turkey Feathers, Noblegarden disguises, Orb of Deception and similar) while you're out of combat, with an optional chat announcement. Off by default. Reworked from ShestakUI by Wetxius / Shestak.",
			} },
			{ "Miscellaneous", {
				"AFK Camera: reworked into a resolution-independent cinematic letterbox - gradient edge fades, a hero-shot character model, a class rune backdrop, faction crest, clock and date, a 30-minute logout countdown, rotating account statistics and a whisper log - built from fixed, edge-anchored regions so it scales cleanly across all resolutions.",
				"AFK Camera: a random battle pet from your Pet Journal now idles beside your character. With no pets collected it falls back to Legionnaire Murky (Horde) or Knight-Captain Murky (Alliance).",
			} },
		},
	},
	{
		version = "1.2.6",
		date = "2026-06-07",
		intro = "A big feature drop - Rare Alert, Delves Automation and a tooltip Vendor Location, smarter Quick Quest and an Experience Bar fade - alongside the minimap squaring, queue-eye polish and a minimap Clock and Location readout, on top of a performance and stability pass: flatter memory use over long sessions, lighter chat and minimap hot paths, and a fix for Communities chat hyperlink tooltips.",
		sections = {
			{ "Maps", {
				"Minimap: squared off with a Blizzard tooltip-style border, the default chrome (ring, zoom buttons, compass, clock, zone bar) removed, and tidied mail, difficulty, calendar, streaming and queue-eye corners.",
				"Minimap: the LFG/queue eye spins a dungeon icon while queued, and a coloured glow pulses for combat / pending mail / calendar invites.",
				"Minimap - Collect Buttons: sweeps stray addon minimap buttons into a fade-in tray behind a small corner toggle, squared and bordered to match. Pick which corner it lives in. Adapted from KkthnxUI by Kkthnx.",
				"Minimap: when the Clock is enabled the new-mail icon now sits above the clock instead of overlapping the time text.",
				"Minimap: wheel zoom/volume and the middle/right-click menus now run on a dedicated overlay, so Blizzard's left-click ping, mouseover and tooltips keep working. Idea from NDui by siweia.",
			} },
			{ "DataText", {
				"Clock: a minimap clock that follows your 12/24h and local/realm time settings. Hover for the date, local & realm time, saved raid / dungeon / world-boss lockouts, daily / weekly resets, Delves, Delver key progress, Timewalking weekly checks and quest completions; hold Shift for storms, hunts, feast and invasion timers. Left-click for the calendar, middle-click for the Great Vault, right-click for the time manager. Adapted from KkthnxUI by Kkthnx.",
				"Location: zone and sub-zone text inside the top of the minimap, tinted by PvP status (sanctuary, friendly, hostile, contested). Can be shown always or only on mouseover. Adapted from KkthnxUI by Kkthnx.",
			} },
			{ "Chat", {
				"Quick Join Button: the social/quick-join chat button is now movable in Edit Mode.",
			} },
			{ "Tooltip", {
				"Vendor Location: for special barter/curio items, the bag tooltip shows which NPC to turn them in to and where; Ctrl-Click the item to set a map waypoint. Concept and item/vendor data from Plumber by Peterodox (data by gifLeo).",
			} },
			{ "Automation", {
				"Delves Automation: while inside a Delve, automatically confirms the single-choice borrowed-power popup, with an optional chat announcement of what was taken. Concept from Plumber by Peterodox.",
				"Quick Quest: smarter automation - accept quests by frequency (regular / daily / weekly), protect costly turn-ins (gold or currency), pick the most valuable reward, and a configurable override key (default Shift) to suppress automation per interaction. Refinements inspired by Leatrix Plus by Leatrix.",
			} },
			{ "Announcements", {
				"Rare Alert: announces nearby rares and world events the moment their vignette appears - a centre-screen banner, an optional sound, and an optional clickable map link in chat - with an anti-burst sound throttle and a per-rare re-announce cooldown. Reworked from NDui by siweia, with throttling ideas from Plumber by Peterodox.",
			} },
			{ "General", {
				"Cast On Key Down: action buttons can fire when a key is pressed instead of when it is released (ActionButtonUseKeyDown CVar); combat-safe and deferred if toggled mid-fight.",
			} },
			{ "Action Bars", {
				"Skin Extra Buttons: the Extra Action and Zone Ability buttons can wear the standard action-bar button frame (Blizzard's HUD icon-frame, slot and pressed art, tinted gold) instead of their oversized one-off artwork, with an adjustable scale (applied out of combat).",
				"Cooldown Text: long cooldowns now show a weeks tier above days, the seconds-to-mm:ss switch is configurable (keep raw seconds like 90 before flipping to 1:30), and an optional Scale Cooldown Text mode shrinks the numbers with the button and hides them on tiny cooldowns; on action buttons the text is also lifted above the hotkey and stack count. Refinements from tullaCTC by Tuller.",
			} },
			{ "Skins", {
				"Quest Navigation: the ETA text under the waypoint arrow now has a drop shadow so it stays readable over bright backgrounds.",
				"Missing Stats: the character sheet now surfaces the stats Blizzard hides by default while out of combat (attack power, weapon damage, attack/weapon speed, spell power, energy/rune/focus regen, movement speed) and tidies the readouts with two-decimal rating percentages, equipped + overall item level and a cleaner font. Reworked from NDui by siweia without replacing Blizzard's stat table, avoiding 12.0 Secret-value taint in combat.",
			} },
			{ "Inventory", {
				"Junk Icon: the coin overlay on Poor-quality bag items now shows all the time, not only while a merchant is open.",
				"Item Level: gem icons shown on Character and Inspect equipment slots now display the socketed gem's tooltip on hover, and enchantable slots missing an enchant show a red marker naming the slot (toggle: Warn Missing Enchants).",
				"Item Level: the item-level numbers now match the bind-status text size and are resizable with a new Item Level Font Size slider (12-14).",
				"Unusable Items: icons across bags, bank and warband bank tint red for gear your class can't use or that you're too low level for. Class data reworked from LibUnfit by Joao Cardoso.",
			} },
			{ "Auras", {
				"Buff Reminder: the reminder icons are now resizable (an Icon Size slider in both the Settings panel and the Edit Mode dialog) and wear a Blizzard tooltip-style gold border to match the minimap. A new /nex reminder command toggles sample icons so you can position the anchor and preview the look, and the anchor now appears in Edit Mode without entering test mode.",
			} },
			{ "Chat", {
				"Quick Join button and the Battle.net friend/online toast now default just above the chat's top-left corner (raised so they don't overlap), and the Battle.net toast is now movable in Edit Mode.",
			} },
			{ "Miscellaneous", {
				"Experience Bar: optional fade - the bar rests dimmed and reveals on mouseover, and can stay fully visible in combat or while you have a target. Fade behaviour adapted from ls_Monobrow by lightspark.",
			} },
			{ "Performance", {
				"Item-link caches (chat item levels, Already Known, guild news and mount-source tooltips) are now size-capped, so memory stays flat over long sessions instead of slowly growing.",
				"Buff Reminder coalesces rapid aura changes into a single end-of-frame update, cutting work when many buffs land at once.",
				"Stats: the memory tooltip refreshes its per-addon scan less often while hovered instead of rescanning every second.",
				"Chat Filter reuses its internal scratch tables, reducing garbage in spam-heavy channels.",
				"Tooltip Icons: the inline-texture resize pass now skips tooltip lines without a texture escape, avoiding needless pattern work on every line.",
				"Unusable Items: the per-item class-restriction cache is now size-capped like the other inventory caches, keeping memory flat over long sessions.",
			} },
			{ "Fixed", {
				"Tooltip Hover Tips: hovering item/spell links in the Communities (guild/community) chat no longer replaces Blizzard's own link handlers.",
				"Edit Mode - Reset Position: Reset to default position on our relative anchors (Battle.net toast, Quick Join button, Buff Reminder) no longer drops the frame at the bottom-left corner of the screen; it restores the proper live anchor.",
				"World Map fade: turning off Fade When Moving while the map is open now restores full opacity and stops the fader immediately instead of leaving it running.",
				"Chat Filter: disabling the filter now stops it filtering right away (the per-message handlers respect the master toggle) instead of staying active until reload.",
				"Tooltip Icons (secret values): hovering auras whose tooltip lines are secret (e.g. inside instances) no longer throws a string conversion on a secret value error; the secret check now runs before any string search.",
				"AFK Camera (secret values): UnitIsAFK returning a secret boolean (e.g. inside instances) no longer throws a boolean test on a secret value error; the AFK camera safely treats it as not-AFK.",
				"Tooltip Status Bar: hovering world objects with 12.0 secret values (rare vignettes, Delve doors and similar) no longer throws a Backdrop secret-number error; the status-bar border keeps Blizzard's styling but skips the resize pass on secret dimensions.",
				"Delves Automation: the borrowed-power popup is now auto-confirmed reliably - Delve status is re-checked a beat after zoning in (the walk-in flag is stale at that exact moment), so entering a Delve arms the handler.",
				"Already Known: cosmetic/transmog items now tint correctly by checking the appearance collection directly instead of the tooltip 'collected' line, which cosmetics don't use.",
				"Pet Frame: tightened the PetFrame click area and added a taint-safe hide helper for protected/managed frames, using alpha and mouse state instead of reparenting. Pattern from BetterBlizzFrames.",
			} },
			{ "Internal", {
				"Saved variables now carry a schema version so future updates can migrate stored data safely.",
				"Removed unnecessary global frame names and tidied unused locals across several modules.",
			} },
		},
	},
	{
		version = "1.2.5",
		date = "2026-06-06",
		intro = "Minimap volume and shortcut menu, a choice of number-abbreviation styles, an achievement screenshot helper and a quest navigation skin - plus a tidied Settings panel and a batch of bug fixes.",
		sections = {
			{ "Maps", {
				"Minimap - Easy Volume: hold Ctrl and scroll over the minimap to set the master volume (hold Alt for the full 0-100 range), with a fading on-minimap readout.",
				"Minimap - Menu: middle-click for a shortcut menu of Blizzard panels; right-click opens tracking.",
			} },
			{ "General", {
				"Number Format: pick how large numbers are abbreviated everywhere in NexEnhance - Standard (1.2k / 3.4m), East Asian (1.2w / 3.4y) or Full Numbers.",
				"Built on Blizzard's 12.0 AbbreviateNumbers API; abbreviation style borrowed from NDui by siweia.",
			} },
			{ "Automation", {
				"Achievement Screenshot: automatically capture a screenshot when you earn an achievement (skips ones already earned account-wide).",
			} },
			{ "Skins", {
				"Quest Navigation: clean Blizzard-style border on the super-tracked waypoint arrow. Ported from KkthnxUI by Kkthnx.",
			} },
			{ "Chat", {
				"Keyword Auto-Invite now lives inline in Chat settings under a new Auto Invite header, alongside the keyword input and Guild/Friends Only - no more separate page.",
				"The inline keyword box uses Blizzard's gray entry-box skin and highlights gold while focused; dependent options grey out when Keyword Auto-Invite is off.",
			} },
			{ "Interface", {
				"Reviewed every option and re-sorted them into the most sensible categories (for example, Achievement Screenshot now sits under Automation).",
			} },
			{ "Fixed", {
				"Auto Vendor: guild-bank repair now works for guilds that grant unlimited withdrawals.",
				"Chat Bubbles: font-size reduction is clamped to a minimum so bubble text stays legible.",
				"Chat Filter: keyword matching is now literal, so punctuation in a keyword is no longer treated as a Lua pattern.",
				"Mail: the Collect-Gold timer now stops when the mailbox closes, avoiding a stuck timer.",
				"Auto Invite: Battle.net friend checks use the correct GUID lookup, fixing Guild/Friends-Only invites.",
				"Chat - Keyword Auto-Invite: Guild/Friends Only now accepts trusted keyword whispers from guild members, character friends or Battle.net friends.",
				"Quest Navigation: uses the proper on-screen clamp check, fixing a Lua error.",
			} },
		},
	},
	{
		version = "1.2.4",
		date = "2026-06-05",
		intro = "A new Experience Bar and Camera Zoom control, chat edit box improvements, plus hotfixes for the AFK Camera animation loop and Decline Duels toggle.",
		sections = {
			{ "Miscellaneous", {
				"Experience Bar: a single movable bar that replaces Blizzard's status tracking bar, showing experience (with rested), watched reputation, honor or Azerite.",
				"The tooltip lists every applicable progress section with a Blizzard-style divider between them.",
				"Blizzard tooltip-style border; width, height and font are adjustable from both the Settings panel and Edit Mode.",
			} },
			{ "General", {
				"Camera Zoom: raise the maximum camera zoom-out distance with an adjustable slider (Blizzard limit 2.6).",
			} },
			{ "Chat", {
				"Edit box: a remaining-character counter that colour-codes as you approach the 255-byte limit.",
				"Alt + Arrow keys pass through to camera/movement instead of stepping through the input, and the box stays clamped on-screen.",
			} },
			{ "Fixed", {
				"Chat edit box: the blinking text cursor is no longer stripped when the box is reskinned, so the caret is visible again while typing.",
				"AFK Camera: fixed a Lua error after the wave emote that stopped the dance/sleep cycle from continuing.",
				"Decline Duels: turning the module off now applies live, instead of continuing to auto-decline duel and pet-battle requests until a reload.",
			} },
		},
	},
	{
		version = "1.2.3",
		date = "2026-06-05",
		intro = "Inventory clarity, an immersive AFK camera, and a proper thank-you page: bind labels on bag icons plus a class-coloured credits panel for the authors whose work helped build NexEnhance.",
		sections = {
			{ "Inventory", {
				"Bind Status: show BoE, BoA and WuE on unbound bag and bank items (top-right of the icon; item level stays bottom-left).",
				"Toggle under Item Level → Show Bind Status.",
				"Idea borrowed from Lars Norberg's BlizzardBags_BoE (GoldpawsStuff) — thank you, friend.",
			} },
			{ "Miscellaneous", {
				"AFK Camera: immersive overlay with spinning camera, character and pet models, Blizzard letterbox bars, clock, logout countdown, random stats and whisper chat.",
				"Wave, dance and sleep animation cycle on the character model. Exits on combat, LFG/battlefield popups or any key press.",
				"Toggle under Miscellaneous → AFK Camera.",
				"Based on ElvUI's AFK module; animation cycle and holder offsets from GW2 UI by Mortalknight.",
			} },
			{ "Credits", {
				"A scrollable thank-you panel with class-coloured contributor cards, feature lists and library acknowledgements.",
				"Open with /nex credits or from Settings → NexEnhance → Credits.",
			} },
			{ "Interface", {
				"/nex help and the options landing page now list the credits command.",
			} },
		},
	},
	{
		version = "1.2.2",
		date = "2026-06-05",
		intro = "A small packaging update so CurseForge and Wago can track releases correctly.",
		sections = {
			{ "Packaging", {
				"Added X-Curse-Project-ID and X-Wago-ID to the addon manifest.",
			} },
		},
	},
	{
		version = "1.2.1",
		date = "2026-06-05",
		intro = "A polish-and-extras update: colour your default frames, a Details! skin and a mount-source tooltip, plus an easier-to-read Settings panel - still improve, never reskin.",
		sections = {
			{ "General", {
				"Frame Colour: tint the default unit frames and HUD (player, pet, target, focus, boss, class resources, cast bars, totems and the minimap) with a colour of your choice.",
				"UI Scale now lives in the new General group.",
			} },
			{ "Skins", {
				"Details: frames each Details! window with the Minimalistic skin plus a clean Blizzard-style border and background.",
			} },
			{ "Tooltip", {
				"Mount Source: hold Shift over another player's mount buff to see its collection status and source.",
			} },
			{ "Chat", {
				"Chat Copy button no longer disappears when switching chat tabs.",
			} },
			{ "Interface", {
				"Each Settings subcategory now has a sidebar icon and an intro description at the top of its page.",
			} },
		},
	},
	{
		version = "1.2.0",
		date = "2026-06-05",
		intro = "A chat-focused update: a cleaner, smarter edit box, a movable Battle.net pop-up, and a new Mythic+ keystone autoslotter - plus an easier-to-navigate Settings panel.",
		sections = {
			{ "Chat", {
				"Edit box now hides when inactive and recolours reliably for the active channel as you switch.",
				"Optionally hide the chat scroll bar and jump-to-bottom button.",
				"Battle.net pop-ups now sit at the chat's top-right corner and are movable in Edit Mode.",
			} },
			{ "Automation", {
				"Auto Keystone: automatically slots your Mythic+ keystone when the Challenge Mode UI opens (defers to AngryKeystones if installed).",
				"Auto Hide Tracker: hides the Objective Tracker during boss fights and arenas, keeping objectives visible in Mythic+ by default.",
			} },
			{ "Interface", {
				"The Settings sidebar is now listed alphabetically.",
				"Dependent options grey out when their parent toggle is off across many more modules, and their labels are a touch larger.",
			} },
		},
	},
	{
		version = "1.1.0",
		date = "2026-06-05",
		intro = "A feature update: a fuller Automation suite, inventory and tooltip quality-of-life, and sharper unit-frame colours - still improve, never reskin.",
		sections = {
			{ "Unit Frames", {
				"NPCs now tint by reaction (hostile red, neutral yellow, friendly green) instead of flat green; players keep class colours.",
				"Boss frames (Boss 1-5) are now coloured alongside the target/focus frames.",
				"Fixed hostile NPCs and bosses showing a green health bar in combat and instances.",
			} },
			{ "Inventory", {
				"Already Known: learned toys, mounts, recipes and pets dim to green at vendors, the Auction House and the guild bank.",
			} },
			{ "Tooltip", {
				"Trade Target Info: marks a trade partner as stranger / friend / guild and class-colours their name.",
				"Choose whether the unit health bar sits at the top or bottom of the tooltip.",
			} },
			{ "Automation", {
				"Decline Duels: auto-declines player and pet-battle PvP duels.",
				"Auto Invite: accepts invites from trusted friends and guild members.",
				"Auto Goodbye: a friendly farewell to the group after a dungeon or Mythic+.",
				"Auto Resurrect: accepts rezzes out of combat (skips encounter pylon/brazier), with an optional /thank.",
			} },
			{ "Maps", {
				"Map Reveal: removes fog of war from the world map, toggled from the config (the on-map checkbox was removed).",
				"Wowhead Links: copyable Wowhead links on the world map (tracked quest) and the achievement frame.",
			} },
			{ "Extras", {
				"Queue Timer on the LFG eye, a one-time first-run setup screen, and this in-game changelog window (/nex changelog) that highlights the newest version and dims older ones.",
				"Quick Item Delete: optionally skip the type-DELETE prompt for good/quest items (off by default).",
				"Hardened the shared event dispatcher so modules can unregister mid-dispatch safely (fixes a rare error opening the achievements panel).",
			} },
		},
	},
	{
		version = "1.0.0",
		date = "2026-06-05",
		intro = "The first public release. A complete, event-driven engine with a full suite of toggleable modules that sharpen the default UI without reskinning it.",
		sections = {
			{ "Core Engine", {
				"Single-frame event dispatcher and a clean OnInitialize -> OnEnable lifecycle.",
				"Per-module profile database with live-apply settings (most changes need no reload).",
				"Modern, grouped Settings panel and /nex slash commands.",
				"Edit Mode movers for our own frames, plus pixel-perfect backdrop helpers.",
			} },
			{ "Action Bars", {
				"Cooldown text on action buttons with a minimum-duration threshold.",
			} },
			{ "Unit Frames", {
				"Class-coloured health for players across party, target, focus and their targets (secret-value safe).",
			} },
			{ "Auras", {
				"Buff Reminder: icons for missing buffs you can provide, on a movable anchor.",
			} },
			{ "Inventory", {
				"Item Level on the Character and Inspect panes (Shift to show).",
				"Durability tab with per-slot repair-cost tooltip and a low-durability nudge.",
				"Mail: Collect-Gold and Take-All buttons, quick-delete, attachment tooltips, GM-mail fix.",
			} },
			{ "Chat", {
				"Flattened tabs and a top-docked, full-width edit box that holds steady on every tab (including Combat Log).",
				"Channel-tinted Blizzard border, quick scroll, sticky whispers, tab channel cycling and a font-size menu.",
				"Chat Copy window and shortened channel names.",
			} },
			{ "Filters", {
				"Chat Filter: keyword spam filtering, repeat detection, stranger/spammer blocking and item-level links (/nexfilter).",
			} },
			{ "Tooltip", {
				"Improved, never reskinned: quality-coloured default borders, spell/item/aura IDs, source icons, item levels and unit hover tips.",
			} },
			{ "Skins", {
				"Objective Tracker cleanup, Character frame tidy-up, and clean channel-coloured chat bubbles.",
			} },
			{ "DataText", {
				"Stats readout under the minimap: FPS / latency with a memory + addon tooltip. Toggle FPS/MS, flip order, class-colour the numbers.",
			} },
			{ "Maps", {
				"World Map coordinates, a smaller scalable map (no blackout), fade-on-movement and a movable anchor.",
			} },
			{ "Automation", {
				"Auto Vendor + repair, Quick Quest, Faster Loot and Movie Skip.",
			} },
			{ "Announcements", {
				"Quest Notification: concise, throttled quest progress and completion messages.",
			} },
			{ "Extras", {
				"Always-on Blizzard bug fixes, UI Scale, Social Colours, Drag 'Em All, Alert Frames, a login Animation and /rl reload shortcuts.",
			} },
		},
	},
}

local frame

-- Two colour palettes so the newest version reads as "what's new" in full
-- colour while older entries are dimmed to grey "history". The first entry in
-- CHANGELOG is always the most recent.
local PALETTE_NEW = {
	version = "ffffff",
	date = "888888",
	intro = "b0b0b0",
	heading = "|c" .. C.BrandHex,
	bullet = "909090",
	body = "e6e6e6",
}
local PALETTE_OLD = {
	version = "9d9d9d",
	date = "5f5f5f",
	intro = "707070",
	heading = "|cff8a8a8a",
	bullet = "555555",
	body = "808080",
}

local function BuildText()
	local buf = {}
	for index, entry in ipairs(CHANGELOG) do
		local isLatest = index == 1
		local p = isLatest and PALETTE_NEW or PALETTE_OLD

		local tag = isLatest and format("  |c%sNEW|r", C.BrandHex) or ""
		buf[#buf + 1] = format("|cff%sVersion %s|r  |cff%s%s|r%s", p.version, entry.version, p.date, entry.date, tag)
		if entry.intro then
			buf[#buf + 1] = format("|cff%s%s|r", p.intro, entry.intro)
		end
		buf[#buf + 1] = " "
		for _, section in ipairs(entry.sections) do
			buf[#buf + 1] = format("%s%s|r", p.heading, section[1])
			local lines = section[2]
			for i = 1, #lines do
				buf[#buf + 1] = format("|cff%s-|r |cff%s%s|r", p.bullet, p.body, lines[i])
			end
			buf[#buf + 1] = " "
		end
	end
	return tconcat(buf, "\n")
end

local function Build()
	if frame then return frame end

	frame = CreateFrame("Frame", "NexEnhanceChangelog", UIParent, "BackdropTemplate")
	frame:SetSize(560, 600)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("DIALOG")
	frame:SetToplevel(true)
	frame:Hide()
	-- Prefer Blizzard's in-game tooltip NineSlice layout; fall back to the
	-- classic tooltip backdrop if the layout isn't registered.
	if not F.CreateNineSlice(frame, { layout = "TooltipDefaultLayout" }) then
		frame:SetBackdrop(BACKDROP)
		frame:SetBackdropColor(0.06, 0.06, 0.06, 0.95)
		frame:SetBackdropBorderColor(1, 1, 1)
	end

	-- Outer glow halo (raw tutorial textures; drawn one level below the panel).
	local glow = CreateFrame("Frame", nil, frame)
	glow:SetAllPoints(frame)
	glow:SetFrameLevel(max(frame:GetFrameLevel() - 1, 0))
	glow:SetAlpha(0.18)
	F.CreateGlowBorder(glow, { outset = 5, blend = "BLEND" })

	F.MakeWindowMovable(frame, "NexEnhanceChangelog") -- draggable + Escape-close

	local logo = frame:CreateTexture(nil, "ARTWORK")
	logo:SetSize(56, 56)
	logo:SetPoint("TOPLEFT", 16, -14)
	logo:SetTexture(C.Media.Textures.logo)

	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
	title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 12, -6)
	title:SetText(ns.title)

	local sub = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 1, -6)
	sub:SetFormattedText("%s |c%s%s|r", L["Version"], C.BrandHex, ns.version)

	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -6, -6)

	local divider = frame:CreateTexture(nil, "ARTWORK")
	divider:SetColorTexture(C.Colors.brand[1], C.Colors.brand[2], C.Colors.brand[3], 0.55)
	divider:SetHeight(2)
	divider:SetPoint("TOPLEFT", logo, "BOTTOMLEFT", 0, -12)
	divider:SetPoint("RIGHT", frame, "RIGHT", -16, 0)

	local scroll = CreateFrame("ScrollFrame", "NexEnhanceChangelogScroll", frame, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 0, -12)
	scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, 16)

	local child = CreateFrame("Frame", nil, scroll)
	child:SetSize(500, 1)
	scroll:SetScrollChild(child)

	local body = child:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	body:SetPoint("TOPLEFT", 0, 0)
	body:SetWidth(496)
	body:SetJustifyH("LEFT")
	body:SetJustifyV("TOP")
	body:SetSpacing(4)
	body:SetText(BuildText())

	child:SetSize(500, body:GetStringHeight() + 12)

	return frame
end

-- Public: toggle the window (used by the /nex changelog handler).
function ns:OpenChangelog()
	local f = Build()
	if f:IsShown() then
		f:Hide()
	else
		f:Show()
		if _G.UIFrameFadeIn then
			_G.UIFrameFadeIn(f, 0.25, 0, 1)
		end
	end
end

function Changelog:OnEnable()
	if not ns.db.changelog.enable then return end

	-- Auto-show once per account whenever the version changes, but only after
	-- the first-run install screen has been dealt with (so they don't overlap).
	if ns.db.changelog.autoShow and ns.global and ns.global.installed and ns.global.lastChangelog ~= ns.version then
		ns.global.lastChangelog = ns.version
		C_Timer.After(2.5, function()
			ns:OpenChangelog()
		end)
	end
end

function Changelog:RegisterOptions(category, builder)
	builder:Checkbox(category, self, "autoShow", L["Auto-Show Changelog"], L["Open the changelog automatically the first time you log in after an update."])
end
