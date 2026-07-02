--[[
	NexEnhance - Changelog
	-------------------------------------------------------------------------
	A styled, in-game changelog window. Opens automatically once per account
	whenever the version changes, and any time via /nex changelog.

	The data table below is the single source of truth for the in-game notes;
	keep it in sync with CHANGELOG.md.
--]]

---@diagnostic disable: undefined-field
-- luacheck: globals ScrollUtil
local _, ns = ...
local C, L, F = ns.C, ns.L, ns.F

local _G = _G
local ipairs = ipairs
local max = math.max
local format = string.format
local CreateFrame = CreateFrame
local C_Timer = C_Timer
local ScrollUtil = ScrollUtil

ns:RegisterDefaults({
	changelog = {
		enable = true,
		autoShow = true,
	},
})
-- Stores the version string whose notes were last auto-shown. Must default to a
-- string (not false): it always holds a version at runtime, and CopyDefaults'
-- type-repair would otherwise reset the saved string back to the boolean every
-- load - making the changelog pop on every reload.
ns:RegisterDefaults({ lastChangelog = "" }, "global")

local Changelog = ns:NewModule("Changelog", "changelog", { group = "misc", title = L["Changelog"], order = 90 })

-- A Blizzard tooltip-style border (matches the rest of the UI).
local BACKDROP = C.Backdrops.window

-- ---------------------------------------------------------------------------
-- Notes (keep in sync with CHANGELOG.md)
-- ---------------------------------------------------------------------------
local CHANGELOG = {
	{
		version = "1.5.5",
		date = "2026-06-27",
		intro = "Reference-library architecture — zero-duration cooldown masks, central cooldown bus, frame runner, hook guards.",
		sections = {
			{ "Core", {
				"Debug.lua: scoped logging, Expect checks, dumps, /nex debug export.",
				"Debug: TOC load order — Debug.lua after Database.lua (ns.Debug was nil on login).",
				"Debug export: sorted scopes, dump capture, pass/fail summary; expectations on 5 modules.",
				"Combat defer retries when regen fires under lockdown.",
				"Async loaders invoke callbacks with success=false on failed loads.",
				"F.MaskCooldownSwipeFromDurationObject hides permanent-aura swipes (SetAlphaFromBoolean + dur:IsZero).",
				"CooldownDispatch.lua: shared SPELL_UPDATE_COOLDOWN / BAG_UPDATE_COOLDOWN bus.",
				"Runner.lua: ns:CreateRunner spreads batch work across frames.",
				"ns:GuardModuleHook no-ops hook callbacks when a skin module is disabled.",
			} },
			{ "Action Bars", {
				"GCD Bar and Extra Quest Button use CooldownDispatch; item cooldown swipes masked.",
				"Cooldown Text masks zero-duration DurationObject swipes globally.",
				"Extra Quest Button: debug scope (/nex debug dump extraquestbutton).",
				"GCD Bar: hide when GCD ends — ACTIONBAR_UPDATE_COOLDOWN + poll fallback (stuck empty bar fix).",
			} },
			{ "Auras", {
				"Buff Reminder: zero-duration mask on depend/item cooldown swipes.",
			} },
			{ "Nameplates", {
				"Quest Icons: large refreshes use the frame runner.",
			} },
			{ "Skins", {
				"Quest Navigation and Objective Tracker gate hook work on IsEnabled when toggled off.",
				"Quest Navigation: ETA timer copies DistanceText shadow (not CreatePlainFS) on world-anchored arrow.",
			} },
			{ "DataText", {
				"Location: TrackEvent teardown; zone events stop when toggled off.",
				"Location: debug scope (/nex debug dump location).",
				"Guild, Friends, CharacterInfo, Currency & Gold: TrackEvent teardown on live disable.",
				"Clock: Stop() clears OnUpdate/MODIFIER; re-enable re-arms ticker.",
			} },
			{ "Automation", {
				"Auction Search History: recent browse text searches in a focus dropdown (account-wide, default 5).",
				"Quick Join, Guild Invite Filter, Auto Resurrect: TrackEvent teardown on live disable.",
			} },
			{ "Inventory", {
				"Already Known: fix nil RefreshVisibleItems on async item-data callback.",
				"Durability: module events unregister on live disable (not just the tab button).",
				"Loot Frame: TrackEvent teardown; panelMaxHeight restores on disable.",
				"Item Level: IsActive gates hooks; module events unregister on disable.",
			} },
			{ "Unit Frames", {
				"Level Colours: live disable restores Blizzard CheckLevel; events use TrackEvent teardown.",
				"Target Frame Layout: refresh events unregister when disabled.",
				"Level Colours: debug scope (/nex debug dump levelColors).",
				"Player Cast Bar: unit events unregister on disable.",
			} },
			{ "Maps", {
				"Minimap: debug scope (/nex debug dump minimap).",
			} },
			{ "Chat", {
				"Debug scope + dock edit-box expectation; Combat Log tab overlap documented with UIScale incident.",
				"BN keyword auto-invite: GetAccountInfoByID(bnSenderID, guid) + CanGroupWithAccount fix.",
				"Scroll-Down Interval defaults to 0 (off); was 15s auto return-to-bottom after scrolling up.",
			} },
			{ "General", {
				"Hide Combat Errors: PLAYER_REGEN handlers fixed (shared event arg was always nil).",
				"UI Scale: UIScaleApplied signal refreshes chat edit-box anchors on scale change.",
				"Widget Movers: SetPoint hook fix — no C stack overflow on layout/scale.",
				"Install: one-click setup — Install applies all recommended settings and reloads.",
				"Install: your character with wave and dance emotes.",
				"UI Scale: reverted to UIParent:SetScale only — CVar + deferred apply broke chat dock tabs on reload.",
				"Cast On Key Down: TrackEvent teardown + restore saved ActionButtonUseKeyDown on disable.",
				"Animation: combat/login events teardown; combat banner live-disable.",
				"Achievement Screenshot, Social Colours, Drag Frames, Alert Frames: event teardown on disable.",
			} },
		},
	},
	{
		version = "1.5.4",
		date = "2026-06-27",
		intro = "Lifecycle sweep — symmetric teardown for remaining event-driven modules and core helpers.",
		sections = {
			{ "Core", {
				"F.InheritExistingValues copies prior sibling keys for schema upgrades.",
				"TransitionAPI.lua stub for patch-day Blizzard API shims.",
				"UnregisterCombatEnterCallback / UnregisterCombatLeaveCallback on the combat bus.",
			} },
			{ "Action Bars", {
				"Range Colors: tracked UNIT_POWER_UPDATE and PLAYER_ENTERING_WORLD unregister on deactivate/disable.",
			} },
			{ "Announcements", {
				"Rare Alert, Quest Notification, Level Announcer: OnDisable unregisters events; Level Announcer enable toggle uses TrackEvent.",
			} },
			{ "Automation", {
				"Faster Loot: OnDisable unregisters loot events.",
			} },
			{ "DataText", {
				"Stats: Destroy() tears down readout, position listener, and OnUpdate on disable.",
			} },
			{ "Tooltip", {
				"Modifier, addon-load, and item-level events use TrackEvent and unregister on disable.",
			} },
			{ "Miscellaneous", {
				"Experience Bar: fade-on-combat uses the shared combat visibility bus.",
			} },
		},
	},
	{
		version = "1.5.3",
		date = "2026-06-27",
		intro = "Combat bus, lifecycle teardown, and Quick Quest data-path polish.",
		sections = {
			{ "Core", {
				"Combat visibility bus: ns:RegisterCombatEnterCallback and ns:RegisterCombatLeaveCallback share one PLAYER_REGEN_* dispatcher (also drives AfterCombatCallback flush).",
			} },
			{ "Automation", {
				"Quick Quest: reward picker uses RequestItemData for cold choice items; crafting-reagent guard warms item data; combat popup retry uses AfterCombatCallback; OnDisable clears gated events.",
				"Holiday Dungeon: RegisterAddOnLoadedCallback for Group Finder; tracked events unregister on disable.",
				"Auto Keystone: tracked ADDON_LOADED teardown on disable.",
			} },
			{ "Inventory", {
				"Unusable Items: OnDisable unregisters PLAYER_LEVEL_UP.",
			} },
			{ "Miscellaneous", {
				"Experience Bar: bar update events and fade combat/target listeners unregister when disabled.",
			} },
		},
	},
	{
		version = "1.5.2",
		date = "2026-06-27",
		intro = "Midnight data paths, sparse profiles, and action-bar DurationObject polish.",
		sections = {
			{ "Core", {
				"Sparse SavedVariables: F.CompactDefaults strips keys equal to defaults; ns:CompactActiveProfile runs on PLAYER_LOGOUT (Hydra-style sparse persistence).",
			} },
			{ "Tooltip", {
				"Item Level: cold inspect slots use ns:RequestItemData before re-scanning equipped gear.",
			} },
			{ "Inventory", {
				"Already Known: ns:RequestItemData when GetItemInfo is cold; events unregister on disable.",
				"Delete Cheapest: RequestItemData warms sell price / class data; BAG_UPDATE_DELAYED unregisters on disable.",
			} },
			{ "Action Bars", {
				"GCD Bar: C_Spell.GetSpellCooldownDuration + StatusBar:SetTimerDuration (no OnUpdate arithmetic); OnDisable teardown.",
				"Extra Quest Button: item cooldown uses DurationObject + SetCooldownFromDurationObject.",
			} },
		},
	},
	{
		version = "1.5.1",
		date = "2026-06-27",
		intro = "Lifecycle and Midnight polish — symmetric module teardown, live-disable fixes, and helper additions from the reference-library backlog.",
		sections = {
			{ "Fixed", {
				"Smart Minimap Tracking: OnDisable now unregisters events (previously kept firing after toggle-off).",
				"Loot Roll: disabling restores Blizzard START_LOOT_ROLL / CANCEL_LOOT_ROLL on UIParent, clears active bars, and unregisters module events — no /reload required.",
				"Clock: OnDisable unregisters PLAYER_ENTERING_WORLD and hides the frame when toggled off.",
				"Hide DPS Role Icon: roster/zone events unregister on disable; compact and party frames refresh so DPS icons return immediately.",
				"Auto Role: migrated to TrackEvent / TrackUnitEvent handles (symmetric teardown with other automation modules).",
				"Popup QoL: MERCHANT_SHOW uses tracked handles for clean disable.",
			} },
			{ "Changed", {
				"Class Colours: F.BooleanIsTrue for connection/player checks; OnSettingChanged gates on the enable key.",
				"Core — F.RegisterFrameForEvents: bulk Frame:RegisterEvent helper for modules that own a private event frame.",
			} },
		},
	},
	{
		version = "1.5.0",
		date = "2026-06-27",
		intro = "Midnight maintenance pass — nameplate tools, tooltip and automation improvements, settings reorg, chat quality-of-life, Character and Inspect frame reskin sync, and assorted 12.0.7 API polish.",
		sections = {
			{ "Core", {
				"Lifecycle helpers: ns:AfterCombatCallback (defer until PLAYER_REGEN_ENABLED), ns:RegisterAddOnLoadedCallback (run when a Blizzard addon loads), ns:RegisterLoadingCompleteCallback (post loading-screen), and ns:RequestQuestData (coalesced QUEST_DATA_LOAD_RESULT batching in Core/DataLoad.lua).",
				"F.SafeUnitIsUnit: compares unit tokens via C_Secrets.CanCompareUnitTokens when available; returns false when blocked or secret — used by tooltips, nameplates, menu buttons, and F.IsFriendlyControlledUnit.",
				"LOD modules (Wowhead Links, Auction Search Fallback, Hero Talent Swap, Quest Navigation) now use RegisterAddOnLoadedCallback instead of manual ADDON_LOADED one-shots.",
				"RequestItemData / RequestSpellData: coalesced ITEM_DATA_LOAD_RESULT and SPELL_DATA_LOAD_RESULT batching in Core/DataLoad.lua.",
				"CreateZoneTrigger: map-gated onEnter/onLeave helper in Core/ZoneTrigger.lua (Plumber-style zone modules).",
				"CreateStateTrigger: predicate-gated onEnter/onLeave with optional debounce (Delves Automation).",
				"F.BooleanIsTrue / F.EvaluateColorFromBoolean / F.SetShownFromBoolean: Midnight-safe boolean visuals in Core/Functions.lua.",
				"TrackEvent / UnregisterModuleEventHandles: module event teardown helpers on Engine (TrackUnitEvent for UNIT_* filters).",
			} },
			{ "Tooltip", {
				"Crafting Reagents: on usable craftable items, shows required reagents with bag/bank counts and a batch-craft hint (Plumber-inspired). Secret-safe counts.",
				"New options: Hide Unit Tooltips in Combat, Hide Guild Rank, Show Crafting Reagents.",
				"NPC Spawn Age: while holding Shift on NPC tooltips, shows how long ago the unit spawned (GUID spawn UID decode).",
				"Pawn integration: Show Icons suppresses Pawn corner icons; Quality-Coloured Border suppresses Pawn green upgrade borders (scores/upgrade text unchanged). Settings note when Pawn is installed.",
			} },
			{ "Nameplates", {
				"Nameplate Quest Icons: shows a quest icon on the nameplate of any NPC tied to one of your active quests, with optional objective progress (always on your target, on mouseover, or while holding a chosen modifier key). A party member's quest greys the icon; inside instances it falls back to the cheap relation check. Secret-value safe. Options for icon size, progress text size, side, X/Y offset, party quests, progress mode/format and the modifier key.",
				"Target Arrows: arrow indicators on your current target's nameplate (attackable units only). Horizontal side arrows or a single Azerite arrow above the plate; customizable arrow color (defaults to NexEnhance blue). Optional friendly-player nameplate preset enables name-only class-colored friendly player plates via the same Blizzard CVars (restored when turned off).",
				"Reaction Colors: tints NPC and mob nameplate health bars with the same darker reaction palette as the target frame. Player nameplates are not changed; forbidden, tap-denied, dead, and combat threat-hostile plates are skipped.",
			} },
			{ "Unit Frames", {
				"Class Colours: events unregister on disable so UNIT_THREAT_* / UNIT_FACTION refreshes stop while the module is off.",
			} },
			{ "Chat", {
				"ElvUI-style chat quality-of-life: scroll-down interval (auto return to bottom after scrolling up), flash taskbar icon on whisper, /tt and /gr edit-box shortcuts, and combat repeat-character block.",
			} },
			{ "Chat Channels", {
				"Hide Channel Tags: strip channel brackets entirely instead of abbreviating them.",
			} },
			{ "Automation", {
				"Smart Fishing: while channeling fishing, widens soft-target interact, mutes ambience, and override-binds your fishing action-bar key to INTERACTTARGET (Hold Shift when casting to skip).",
				"Auction Search Fallback: when Current Expansion Only returns zero browse results, widens the filter once and retries.",
				"Smart Minimap Tracking: auto-enables repair-vendor tracking when gear is damaged and mailbox tracking when mail is pending.",
				"Quick Quest: utility gossip auto-select for Nerub speed skip, D.R.I.V.E, Vaskarn vendor skip, and hunter stable UI (Inomena IDs).",
				"Auto Role: sets your party role from your active spec (GetSpecializationRoleEnum / UnitSetRoleEnum). Skips LFG groups, scenarios, and combat. Optional instant role-poll answer suppresses Blizzard's popup.",
				"Holiday Dungeon: when you open the Dungeon Finder for the first time each login, points out the active holiday or Timewalking queue in the Type menu if it is not already selected (including Turbulent Timeways weeks where the API omits the Timewalking flag).",
			} },
			{ "Skins", {
				"Hero Talent Swap: right-click the hero talent button on the Talents pane to swap to your inactive hero tree (Inomena-inspired).",
				"Quest Navigation: ETA text uses CreatePlainFS (12.0.7 Slug shadow workaround); loads via RegisterAddOnLoadedCallback.",
			} },
			{ "Filters", {
				"System Chat Filter: hides learn and unlearn spell system messages when changing talents.",
			} },
			{ "Miscellaneous", {
				"Popup QoL: optional auto-confirm for BoP loot and tradeable equip/sell, click-through event toasts, Enter-to-accept purchases, and Alt+right-click merchant stack buy.",
			} },
			{ "Settings", {
				"Options reorganised: new Nameplates, Camera, Alerts and Movers categories so the Miscellaneous page is no longer a catch-all.",
				"Cast On Key Down moved from General to Action Bars.",
				"Game Menu: NexEnhance button on the escape menu (after Options/Shop) opens the addon settings panel.",
				"Localization: initial German (deDE) locale — machine-translated for native review; English remains the fallback.",
			} },
			{ "General", {
				"Hide UI Elements: optional Hide Boss Banner and Hide Event Toasts (off by default). Scoreboards with a close button are kept.",
			} },
			{ "Auras", {
				"Buff Reminder: optional Reminder Glow (on by default) — soft red halo via retail tutorial-frame glow art, not Classic flipbook ants. Preview with /nex reminder.",
				"Buff Reminder: expanded alternate raid buff spell IDs (MOTW, Arcane Intellect, full Blessing of the Bronze variants), Shaman weapon depends use cast spell IDs, rogue poisons accept any known poison in the slot, GetPlayerAuraBySpellID fast path, and a pre-combat aura snapshot for secret-safe combat display.",
				"Buff Reminder: item and depend-spell cooldown swipes use DurationObject APIs (SetCooldownFromDurationObject / GetSpellCooldownDuration); item cooldown checks are secret-guarded. Lack label uses CreatePlainFS.",
			} },
				{
				"Fixed",
				{
					"Nameplates - Reaction Colors: plates no longer flash default Blizzard selection tints after combat; threat health-bar skip is combat-only, with UNIT_THREAT_*, UNIT_FACTION, and deferred regen refreshes (same event set as Class Colors). Out-of-combat plates tint immediately via bar-RGB fallback when nameplate tokens hide reaction APIs, plus deferred NAME_PLATE_UNIT_ADDED refresh.",
					"Maps - Wowhead Links: world-map quest link is a copyable edit box again (hover + Ctrl-C); stacks above title bar; fixed Setup() nil wmf.",
					"Settings: sidebar New markers and section badges now match the landing-page new-module list; canvas pages dismiss the callout; New This Update scrolls when long; Plugin Manager sits under Plugins.",
					"Profiles: per-character profile label + hint; dropdown rows no longer overlap.",
					"Profiles: create/copy name prompt uses GetEditBox/GetButton1 on 12.0.7 StaticPopup (fixes nil editBox/button1 errors).",
					"Unit Frames / Tooltips: UnitSelectionType category + FACTION_BAR tints; unfriendly orange boosted so it reads clearly vs red.",
					"Class Colours: player pets and friendly player-controlled units no longer get hostile NPC reaction red on pet/target frames.",
					"Class Colours: compact raid/party frames no longer forced — use Blizzard Edit Mode Class Colors instead.",
					"Class Colours: F.IsFriendlyControlledUnit guards UnitIsUnit — secret boolean on targettarget no longer errors when tab-targeting in combat.",
					"Class Colours: offline players on target/focus/toT/boss HUD frames get disconnect icon + desaturated portrait (party portraits still use Blizzard UpdateOnlineStatus); health already grey.",
					"Quick Quest: auto-selects <Skip Mini Game> gossip while enabled (Rommath-style ward skips); story-skip detection now requires <Skip, not any bracketed lead-in.",
					"Quick Quest: rogues and druids auto-select [Requires a Stealth Class.] gossip (invisibility quest skip) when exactly one is offered.",
					"Nameplates (Quest Icons, Target Arrows, Reaction Colors): events unregister on disable; toggling off no longer leaves NAME_PLATE_* / threat listeners active.",
					"General — Hide Combat Errors: PLAYER_REGEN_* listeners unregister when the option is off.",
					"Automation — Auto Role / Auto Hide Tracker: OnDisable symmetry for event teardown.",
					"Automation — Auto Invite, Auto Goodbye, Decline Duel, Cancel Bad Buffs, Auto Greed, Auto Vendor, Auto Warband Gold, Auto Summon, Auto PvP Release: events unregister on disable; fixed Auto Warband Gold / Auto Summon / Auto PvP Release unregistering method refs instead of dispatcher wrappers.",
					"DataText — Clock: uncached item links in tooltips use ns:RequestItemData when GetItemInfo is not ready.",
					"Guild Invite Filter: events unregister on disable (OnDisable + toggle off) so GUILD_INVITE_REQUEST no longer fires while the module is off.",
					"Auto Resurrect: OnDisable unregisters RESURRECT_REQUEST when the module is disabled.",
					"Queue Timer / Audio Sync / Hide UI Elements: OnDisable + TrackEvent teardown when toggled off.",
					"Action Bars / Extra Quest Button: events unregister on disable; Extra Quest Button hides when turned off.",
					"Class Colours + nameplates: TrackEvent + UnregisterModuleEventHandles instead of hand-rolled unregister loops.",
					"Loot Roll / Tooltip IDs / Unusable Items: ns:RequestItemData for cold GetItemInfo (item level, stack cap, required level).",
					"Buff Reminder: F.BooleanIsTrue for weapon enchants; TrackEvent + OnDisable teardown.",
					"Nameplate Reaction Colors: secret-safe skip (readable player/dead only); secret threat leaves Blizzard tint; RGB fallback when reaction APIs are secret.",
					"Delves Automation: PLAYER_CHOICE_UPDATE gated via CreateStateTrigger.",
					"Hide DPS Role Icon: also hides the DPS sword on standard party portrait frames; per-frame hooks on pooled PartyMemberFrame instances (mixin-only hook did not apply to live frames).",
					"Auto Hide Tracker: no longer hides the objective tracker when a friendly escort NPC occupies a boss frame (e.g. MoP Shado-Pan assault dailies); requires a hostile boss unit, not merely boss1..5 existing.",
					"Minimap: fixed cluster jump-then-snap when mail/crafting orders trigger Blizzard layout — footprint correction defers until after ResizeLayoutFrame.",
					"Tooltip — Mount Source: uses the aura unit (party/raid mouseover), not target.",
					"Tooltip: refreshes on LShift/RShift press and release for realm, NPC ID, and shift-gated extras.",
					"Tooltip: health-bar text live-apply no longer tests IsShown() on a secret-marked status bar.",
					"Chat: scroll-down interval and quick-scroll mouse wheel no longer error - HookScript passes (frame, delta) but the hooked colon-method shifted arguments so delta was nil.",
					"Character Frames: synced with CharInspectPlus v2.0.0 for 12.0.7 - widened gear layout only when CharacterFrame.Expanded, Reputation/Currency tabs keep Blizzard inset anchors, Inspect PVP/Guild tabs restore ButtonFrameTemplate insets, Secret guards on inspect class and item level.",
					"Character Frames: Pawn button clickable and hoverable again - CharacterStatsPane was drawing above PaperDollFrame and blocking the wrist/trinket anchor; lift the button to HIGH frame strata so it stays on the gear tab only.",
					"Missing Stats: wrap CharacterStatsPane in a scroll frame so extra attribute rows and the full Enhancements list stay inside the stats sidebar (mouse-wheel scroll, hidden scrollbar).",
					"Holiday Dungeon: no longer calls LFDQueueFrame_SetType from addon code; that tainted LFG session globals and could block AcceptProposal with ADDON_ACTION_BLOCKED.",
					"Chat Channels: ElvUI-style full-line abbreviation and timestamps via a LibChatAnims-safe AddMessage wrapper; URLs stay on ChatFrame_AddMessageEventFilter. Fixes [Guild] to [G] and restores [HH:MM] before the channel tag. Embeds LibChatAnims.",
					"Minimap: SetTexCoord on masked HUD/housing textures no longer errors on enable - strip mask textures first (12.0 rejects texcoord changes on masked textures).",
					"Missing Stats: scroll extent no longer compares secret scroll positions in combat; stats-pane scroll updates defer until PLAYER_REGEN_ENABLED.",
					"Action Bars: defer styling refreshes while in combat so SetShown and overlay repositioning on secure action buttons no longer trigger ADDON_ACTION_BLOCKED on ACTIONBAR_PAGE_CHANGED or UPDATE_BINDINGS; pending work runs on PLAYER_REGEN_ENABLED. Equipped-item glow and hotkey abbreviation post-hooks also skip combat so hovering action buttons no longer taints SetShown/SetAttribute.",
					"Chat Channels: secret chat message bodies (instances/combat) pass through the AddMessage wrapper unchanged instead of erroring on compare/match.",
					"Plugin Manager: canvas labels no longer show a duplicate black shadow behind the text (standard GameFont strings instead of manual shadow duplicates).",
					"Durability: the Character-pane durability tab now populates on first login without /reload (UPDATE_INVENTORY_ALERTS + PLAYER_ENTERING_WORLD bootstrap, deferred refresh, PaperDoll OnShow hook). Tooltip shows per-slot and total repair costs via TooltipData.repairCost and GetRepairAllCost().",
					"Quick Quest: gossip/greeting handlers select one quest per interaction and chain the next after each accept or turn-in. Gossip offers use C_GossipInfo quest data instead of quest-log difficulty (was 0 before accept). Warband/account-completed quests on an explicit NPC list are accepted even when account-completed tracking is hidden on the minimap. /nex quickquest toggles debug logging.",
					"Queue Timer: listens for LFG_PROPOSAL_UPDATE, refreshes after LFGDungeonReadyPopup_Update, bootstraps an active pop after /reload, clears PvP confirm state correctly, and stops the OnUpdate ticker when the queue ends (12.0.7 has no default LFG countdown bar).",
					"Player Cast Bar: backs off while Blizzard's OverlayPlayerCastingBarFrame replaces the player bar (talent/spec commits, crafting, etc.) so our read-only mirror does not fight SetAndUpdateShowCastbar(false) on the Edit Mode frame.",
					"12.0.7 Slug text shadows (UI pass): minimap zone text, Ctrl+wheel volume readout, and LFG queue timer use F.CreatePlainFS like Stats/Clock. AFK Camera overlay strings migrated the same way; logout countdown no longer shows a leading minus and starts when AFK begins. Inspect average item level uses PlainFS; character-sheet ilvl no longer forces SetShadowOffset. Quest Navigation ETA copies Blizzard DistanceText shadow on BACKGROUND layer to avoid ghosting on world-anchored 3D text. Buff Reminder glow tracks the red border ring, not the icon.",
					"Inomena-inspired QoL: Smart Fishing (soft-target interact rebind while channeling), Auction House current-expansion search fallback, smart repair/mailbox minimap tracking, hero talent right-click swap, Popup QoL sub-toggles, system chat talent-learn filter, NPC spawn age on Shift tooltips, utility gossip auto-select in Quick Quest.",
				},
			},
		},
	},
	{
		version = "1.4.0",
		date = "2026-06-16",
		intro = "Third-party plugin support lets other authors extend NexEnhance as separate addons, with a Plugin Manager page in settings and a starter template in the repo.",
		sections = {
			{ "Core", {
				"Plugins: third-party authors can ship separate addons that call NexEnhance:RegisterPlugin(...) to use the same profile DB, lifecycle, events, and settings builder as built-in modules. Settings live under Plugins (per-extension options) and Plugin Manager (overview cards). /nex plugins lists installed extensions. Starter template: Examples/NexEnhancePluginTemplate/.",
			} },
		},
	},
	{
		version = "1.3.0",
		date = "2026-06-13",
		intro = "Three new micro-button datatexts - guild, friends and a wealth tooltip - turn the menu bar into an information hub, plus a loot quality-of-life pass: auto-greeding low-rarity drops and a compact, skinned replacement for Blizzard's group-loot roll bars. The world map and your bags can now be dragged straight off their title bars without entering Edit Mode.",
		sections = {
			{ "DataText", {
				"Guild: the Guild micro button shows your online member count, and hovering it opens an ElvUI-style roster tooltip - name, level (difficulty coloured), class colour, zone and online/AFK/mobile status, sorted by name (hold Shift for rank and public/officer notes). The guild message of the day shows up top (toggle) and the list collapses past a configurable member count. The button's native click is untouched, and reads are Secret-value safe.",
				"Friends: hovering the social / Quick Join button opens a friends roster tooltip that mirrors ElvUI's grouping - Battle.net friends bucketed by the game they're in (WoW characters class-coloured and zoned) above your in-game friends. Purely additive; the button keeps its native click.",
				"Currency & Gold: a wealth tooltip on the Character micro button showing session gold gained/lost, a per-character gold rollup (stored account-wide, class-coloured and sorted), faction and server totals, Warband bank gold, the live WoW Token price and your backpack-tracked currencies. Reads are Midnight Secret-aware - GetMoney() and currency amounts that turn secret in combat or instances are skipped rather than stored or compared. Adapted from ElvUI's Gold and Currencies datatexts.",
				"Experience Bar: now tracks Midnight Housing Experience. With a tracked house the bar fills toward the next house level, uses the same Experience / Remaining tooltip formatting as the normal XP bar, and shows in a gold tone matching the housing UI. The Housing Experience tooltip also includes neighborhood Endeavor Progress from Blizzard's initiative API. Priority is XP first (levelling is unaffected), then Housing Experience, then reputation/honor/Azerite. Built on Blizzard's C_Housing and C_NeighborhoodInitiative APIs.",
			} },
			{ "Action Bars", {
				"Extra Quest Button: an optional, keybindable button that surfaces the closest usable quest item from your log (the one Blizzard buries in the objective tracker), so one bind uses whatever the current objective needs. It wears the same gold HUD action-bar art as the rest of the bars, shows the item's cooldown, stack count, hotkey and a red range tint, and sits on its own draggable Edit Mode anchor with configurable size, zone/tracked-only filters and distance. Bound to your Extra Action Button 1 keybind and hides itself when nothing applies. Off by default. Ported from p3lim's ExtraQuestButton (with NDui's earlier plugin as a reference): includes p3lim's target-item, replacement, priority and current quest data, while keeping NexEnhance's secure-frame and Secret-value guards.",
				"Equipped Item Border: the faint green border Blizzard puts on an action button holding an equipped item is replaced with a brighter green copy of the same IconFrame border art, sized to match our skinned frame. It follows live action changes and equips, reads the equipped state from Blizzard's own API with a Secret-value guard, and is on by default - turn it off under Action Bars to restore Blizzard's default border.",
			} },
			{ "Automation", {
				"Auto Greed: automatically rolls Greed (or Disenchant) on low-rarity group-loot drops so you're not clicking the same buttons all night. Defaults to max level only, Uncommon (green) Bind-on-Equip items, and prefers Disenchant when available; optional toggles cover rares, BoP items and auto-confirming the soulbound/disenchant prompts. It only confirms rolls it started itself. Off by default. Refactored from ShestakUI's AutoGreed (originally by Tekkub). Item quality that reads secret in instances is left for the player rather than guessed.",
			} },
			{
				"Miscellaneous",
				{
					"Loot Roll: replaces Blizzard's group-loot roll frames with NexEnhance's own compact, skinned bars - an item icon (item tooltip with Shift-compare), a quality-coloured timer bar showing item level and stack count, and Need / Greed / Disenchant / Transmog / Pass buttons that grey out when unavailable. Bars stack from a draggable Edit Mode anchor, recycle through a pool, and queue when there are more rolls than your configured bar count. Width, height and max bars are configurable, and /nex lootroll spawns demo bars so you can position and preview them. Re-implemented from ElvUI's LootRoll.",
					"Drag Frames: your bags are now draggable too - grab the combined bag, or the backpack in the separate-bag layout (which moves the whole cluster). Bag positions intentionally snap back to Blizzard's default on the next bag open rather than persisting, matching the rest of Drag Frames.",
					"Achievement Back Button: a browser-style Back button on the Achievements frame header. As you click through categories and achievements it records where you've been, and the button retraces that history one step at a time - restoring the category, the selected achievement and both scroll positions. It greys out when there's nowhere left to go back to. Adapted from LudiusMaximus' Achievements Back Button.",
					"Hide UI Elements: optional toggles (all off by default) for default UI bits people often want gone - the buff collapse/expand arrow, the bottom-right Micro Menu & Bags cluster (the micro-menu buttons and the bag bar), and the incoming damage / healing numbers that flash over your player portrait (separate toggles). Visibility only - nothing is destroyed - kept hidden against Edit Mode re-showing them, and the micro/bags hide is deferred out of combat. The target frame has no combat feedback to hide.",
					"Menu Buttons: the unit right-click menu gains quick social actions as real, brand-coloured entries - Add Friend, Guild Invite (labelled with your guild's name), Copy Name and Whisper - adding only the options Blizzard's menu for that unit type is missing (self, target, party, friend, raid, ...). Built on the supported Menu.ModifyMenu API so entries are injected taint-free, and uses the live C_GuildInfo.Invite; names that read secret in instances simply omit the entries. Adapted from KkthnxUI/NDui.",
				},
			},
			{ "Announcements", {
				"Rare Alert: right-click the rare popup to share the rare and a clickable map-pin link in chat - your group when grouped (instance/raid/party), otherwise General chat. The shared message uses a default-named map pin so the server doesn't drop it, and a short cooldown keeps repeated clicks from flooding the channel. Left-click still targets/tracks; the new toggle is on by default and editable in the panel or Edit Mode dialog. Cherry-picked from Plumber's rare announcement by Peterodox.",
				"Quest Notification: objective-progress announcements now diff Blizzard's structured quest objectives (C_QuestLog.GetQuestObjectives) off the debounced QUEST_LOG_UPDATE scan instead of pattern-matching localized UI_INFO_MESSAGE text. It's locale-independent, no longer parses a string that can be a Midnight Secret value in instances, fires for every quest regardless of tracking, and posts the quest name alongside each objective. High-count objectives still report roughly every 20%, and percent-style progress-bar quests are announced too. The module stays idle while you're solo, and the old Dragonflight-only dragon-glyph notice was removed.",
			} },
			{ "Maps", {
				"World Map: the windowed map can now be dragged directly by its title bar with no Edit Mode required, and the position is saved across reloads. The old Edit Mode mover for the map was removed in favour of this; the maximized map stays centred and is left to Blizzard.",
			} },
			{ "Filters", {
				"Chat Filter: settings panel now includes scrollable keyword lists for the blacklist and the trade-channel whitelist — one keyword per line, with a Restore Default Keywords button for the built-in spam set. /nexfilter still works for quick edits.",
				"Chat Filter: ships a curated default keyword list for current services/trade boosting spam (WTS carries, Mythic+, raid bundles, gold-only payment lines, commercial links like WowVendor/Trustpilot/discord.gg, and copy-paste booking CTAs). Keywords merge in automatically on first load; matching is now case-insensitive. A message still needs to hit your configured match threshold (default 3) before it is hidden, so short LF/LFW craft lines stay safe. Restore the built-ins anytime with /nexfilter defaults.",
			} },
			{
				"Fixed",
				{
					"Chat / Chat Filter: migrated 12.0.7-deprecated globals to namespace APIs - C_BattleNet.InviteFriend (keyword auto-invite) and C_PartyInfo.IsGUIDInGroup (friend/group exemption in the spam filter).",
					"Unit Frames - Class Colours: audited against 12.0.7 FrameXML - added UNIT_FACTION / UNIT_CONNECTION refresh, party vehicle UpdateArt re-tint hook, compact-frame threat-colour deferral, and UnitTreatAsPlayerForDisplay class colouring to match Blizzard's compact path.",
					"DataText - Stats & Clock: minimap FPS/latency and clock text now use a manual drop-shadow duplicate instead of SetShadowOffset. On 12.0.7 the API still reports 1,-1 and Slug CVars do not change the look, but the engine draws Slug-rendered shadow flush on the glyphs anyway; offsetting a solid-black copy behind the main string restores a readable shadow.",
					"Extra Quest Button: the cooldown swipe swept over the gold IconFrame border. The border is the button's OVERLAY normal texture while the Cooldown is a child frame (which always renders above the parent's textures), so the swipe and its bright leading edge drew on top of the chrome. The swipe is now inset to the frame's inner opening and the leading edge is disabled, so it stays neatly inside the gold border.",
					"DataText - Time: the world-map quest-timer tooltip read a widget through a misnamed Blizzard API (GetTextureAndTextWidgetVisualizationInfo) that never resolved; corrected to the real GetTextureAndTextVisualizationInfo so texture-and-text widget timers display again.",
					"Auto Vendor: now yields to Bagforge's Vendor module when Bagforge has the matching automation enabled. If Bagforge is handling auto-repair or auto-sell junk, NexEnhance skips that same action at runtime instead of double repairing/selling, without changing your NexEnhance settings.",
					"Item Level: item quality and the inspected unit's GUID can read as Secret inside instances on 12.0, and the loot/bag/inspect paths compared them directly, which could throw a Lua error mid-loot. Every quality and GUID read is now Secret-guarded (matching Auto Greed and Loot Roll), and loot slots with no hyperlink yet are ignored until Blizzard finishes populating them. If a value can't be read, the overlay is simply skipped instead of erroring.",
					"Tooltip: the status-bar skin no longer uses BackdropTemplate children. Blizzard's backdrop mixin divides by GetWidth()/GetHeight() in Lua, which can be Secret while the world-cursor tooltip updates under Midnight. The bar now uses plain texture strips, avoiding the tainted secret arithmetic crash.",
					"Quick Quest: Auto-Skip Story Gossip now actually fires. It only matched a red <Skip ...> marker pinned to the very start of an option in the legacy hex-red colour, so it missed campaign skips with white lead-in text (like the Argus <Skip the Argus Campaign> option), the modern RED_FONT_COLOR markup Blizzard now uses, and plain uncoloured skips like the Legion <Skip the scenario and begin your journey on Broken Shore.> option. Detection now keys off the angle-bracket marker itself anywhere in the option text, which is colour- and locale-independent, with a Secret-value guard on the option name. The follow-up 'Skip ahead?' confirmation popup these skips raise is now auto-accepted too (mirroring Blizzard's GOSSIP_CONFIRM handling), but only for free skips - a confirmation that costs money, or whose cost reads Secret, is left for you to confirm. Each skip now prints a chat line naming the NPC so you know it happened. Verified against Blizzard's 12.0 gossip resources.",
				},
			},
			{ "Performance", {
				"Extra Quest Button: quest, zone-change and player aura events each triggered a full closest-quest-item scan, so an aura-heavy pull ran it many times a second. They're now coalesced through a 0.1s debounce into one scan, while target and bag updates stay immediate so the button still feels instant.",
				"Audited the whole addon against Blizzard's 12.0 Resources for Secret-value/taint correctness, API drift and hot-path costs - no further issues found beyond the two above.",
				"Full-UI consistency pass: localised the only C_Item call left in the Extra Quest Button's per-frame range check, aliased the Tooltip Item Level scan's C_Item lookups and dropped its per-artifact relic table allocation, and added explanatory comments to cryptic constants and sparse hooks in the tooltip modules. Behaviour unchanged.",
			} },
		},
	},
	{
		version = "1.2.9",
		date = "2026-06-11",
		intro = "A new Guild Invite Filter auto-declines guild invites from strangers while letting friends and guildmates through, with live statistics right on its options page, plus a Quick Join module that smooths out Blizzard's Group Finder. Under the hood, all of NexEnhance's Midnight Secret-Value handling now lives behind one shared helper set (modelled on oUF's) so every module guards secrets the same way. Profiles gained AceDB-style actions with compact compressed exports, and frames now standardise on Blizzard's stock tooltip border art.",
		sections = {
			{ "Automation", {
				"Guild Invite Filter: new module (off by default) that auto-declines guild invites from players who aren't trusted, while letting character friends, Battle.net friends and your current guild members through. Each trusted source is its own toggle, with an optional chat announcement and sound when an invite is declined.",
				"Guild Invite Filter: a Statistics section on its options page shows lifetime blocked/allowed totals and the last blocked invite, refreshing whenever you open the page and greying out while the module is off.",
				"Guild Invite Filter: while enabled it forces Blizzard's own Block Guild Invites off so invites actually reach the filter (Blizzard's option drops them before the addon sees them), remembers your prior setting per-character, and restores it when you disable the module - even across a reload.",
				"Quick Join: new module (off by default) for the Premade Groups finder, adapted from NDui. Double-click a search result to apply (hold Alt to review the sign-up note instead of sending it), with a one-time tip pointing the shortcut out.",
				"Quick Join: an Auto-accept check on the applicant viewer auto-invites applicants while you're the group leader; it only appears for the leader, stays out of the way of Blizzard's own auto-accept toggle, and remembers its state.",
				"Quick Join: Auto-hide LFG Popups dismisses the throwaway informational and expired-listing popups and closes the Group Finder once you accept an invite to a listed group (toggle).",
				"Quick Join: Show Leader Rating prints the group leader's Mythic+/PvP rating on each result with a cross-faction crest and trims the long activity prefix (toggle).",
			} },
			{ "Miscellaneous", {
				"Profiles: profile management now follows AceDB's clearer workflow - create, switch, copy from another profile into the current one, copy current as a new name, reset current to defaults, or delete unused profiles.",
				"Profiles: export strings now use bundled LibSerialize and LibDeflate for compact printable backups, while still accepting older !NEX1! Base64 exports.",
				"UI chrome: frames now standardise on Blizzard's stock UI-Tooltip-Border / UI-Tooltip-Background art. The custom pixel-border and addon NineSlice helper paths were removed, covering the minimap, chat edit box, chat bubbles, profile/install/changelog/credits/copy windows, Details, Reminder, Rare Alert and tooltip status bar.",
				"Commands: /nex abandonquests clears every abandonable quest from your log at once (skipping world quests and party-sync-locked quests), confirming with a yes/no popup first since abandoning also destroys quest items.",
			} },
			{ "Performance", {
				"Core: consolidated all Midnight Secret-Value handling into one shared helper set on F (modelled on oUF's by Simpy) - IsSecretUnit, IsSecretTable, CanAccessValue and HasSecretValues alongside the existing IsSecret/NotSecret. The Tooltip and Cooldowns modules now route through these, so there's a single source of truth and no module rolls its own raw secret check.",
				"Core: option pages gained a read-only description row that can grey out with the setting it belongs to (used for the Guild Invite Filter statistics).",
				"Core: added a one-shot HelpTip helper (F.ShowHelpTip) for account-wide tutorial nudges shown once and then remembered; tips raised this way are automatically spared by the Hide Help Tips feature. Used to point out Quick Join's double-click, chat quick-scroll, the chat copy button, Edit Mode movers, the hidden minimap click/scroll gestures, and the bag delete-cheapest button.",
			} },
		},
	},
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
			{ "Action Bars", {
				"Range Coloring: new tullaRange-style module tints action-button icons and hotkeys when an action is out of range, out of power, or unusable. Driven by Blizzard's event-based range check (no per-frame polling) and Midnight-hardened - secret usability/range values in combat fall back to the neutral tint instead of erroring. Colors, hotkey tinting and pet-bar coverage are configurable; off by default.",
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
				"Delete Cheapest: new module adds a goblin-head button to the bag frame (left of the search box, styled like Blizzard's cleanup button). Left-click finds and (after a confirmation showing the item) destroys the lowest vendor-value item in your bags; right-click previews it in chat. Per-item-class protection toggles guard whole categories, with quest items protected by default.",
				"Already Known: housing decor now dims green at vendors, the Auction House and the guild bank when you already own or have placed it, via the Midnight housing catalog.",
			} },
			{ "Automation", {
				"Faster Loot: reworked into a paced slot-walker - it listens to both LOOT_READY and LOOT_OPENED, handles noisy auto-loot state, avoids duplicate work and stops cleanly when the loot window closes. Inspired by SpeedyAutoLoot by Yuyuli.",
			} },
			{ "Skins", {
				"Enhanced Color Picker: Blizzard's color picker gains R/G/B input boxes (0-255) that drive the wheel and update live as you drag, plus a row of click-to-apply class-color swatches with name tooltips. The native hex box is reskinned and aligned as the 4th row of the column (swatch / R / G / B / #), and the stacked swatch becomes a single box-styled header. Reworked from NDui against the current frame.",
			} },
			{ "General", {
				"Hide Help Tips: new toggle (off by default) that suppresses Blizzard's tutorial and help-tip pop-ups (micro-button alerts, new-player pointers, panel hints) and the tutorial CVars, while leaving NexEnhance's own tips (such as the low-durability nudge) intact.",
				"Widget Movers: new toggle (off by default) that makes Blizzard's below-minimap and top-center widget displays draggable in Edit Mode via our mover, opting them out of the legacy frame-position manager so they stay where you put them. The power-bar widget is intentionally left to Blizzard's native Encounter Bar Edit Mode system. Ported from NDui's UIWidgetFrameMover.",
			} },
			{ "Unit Frames", {
				"Player Cast Bar: new toggle (off by default) that mirrors Blizzard's player cast bar icon above the bar and cast time beneath it, with a configurable icon size. Purely cosmetic: Blizzard keeps full ownership of cast state and timing, so there are no Secret-value concerns; the overlay hides during Edit Mode.",
				"Level Colours: new module that colours the Target / Focus / Boss level number by classic creature difficulty (red to grey vs your level) via GetCreatureDifficultyColor, instead of Blizzard's newer trivial/easy buckets. An Always Show Level sub-toggle replaces Blizzard's skull on high-level targets with the actual number (or a red ?? when the game hides it) and appends classification markers (Boss / R+ / + / R). Post-hooks CheckLevel without writing onto the Edit Mode-managed frames, touches only the level FontString/skull cosmetically, and is Secret-value hardened - it leaves Blizzard's display when level reads are restricted in combat or instances.",
			} },
			{ "Tooltip", {
				"Health Bar Text: the unit health bar shows current / max again (with a current-only option). It now follows ElvUI's retail-safe approach - Blizzard drives the bar and we post-hook its health update.",
				"Quality Border: dropped the old recipe item-name width tweak (fragile under Secret Values for no real gain); the item post-call now only tints Blizzard's default border by item quality.",
				"Internal rewrite: the core was reworked against ElvUI's Midnight Secret-Value model. The pile of workarounds is gone (global tooltip-function pcall wrappers and OnSizeChanged backdrop guards removed), unit resolution and health text are simplified, and the status-bar border is now a stock tooltip backdrop. Same look and options.",
			} },
			{
				"Fixed",
				{
					"Minimap: the instance-difficulty flag now reskins with our Flag texture again - it was targeting a non-existent .Instance child, but the current InstanceDifficultyMixin exposes the normal flag as .Default (alongside .Guild and .ChallengeMode).",
					"Item Level: fixed item level and bind status not appearing on bank and warband bank items - the slots now update off ItemButton:UpdateCooldown (matching Unusable Items), hook both the generate and refresh-all bank paths, and install on BANKFRAME_OPENED so the load-on-demand bank UI is covered.",
					"Tooltip (secret values): fixed taint thrown from Blizzard's own tooltip widget code (GameTooltip_AddWidgetSet/ClearWidgetSet and EmbeddedItemTooltip_UpdateSize) when our hooks run while widget geometry is secret (e.g. map POI / world-event tooltips). The guard now detects secret-value errors case-insensitively (covering both SetWidth(secret) and secret height math), and GameTooltip_AddWidgetSet preserves Blizzard's numeric overflow return contract when suppressing them.",
					"Tooltip (secret values): health text no longer blanks out when UnitHealth is a 12.0 secret value (in combat or instances); secret numbers are shown safely via number abbreviation instead of being discarded.",
					"Tooltip: health text no longer flickers or briefly shows the wrong values while the tooltip is refreshing (for example when jumping in-game); it now reads only the unit attached to the tooltip/status bar instead of guessing from mouseover.",
					"Tooltip (secret values): hiding the status bar no longer tests IsShown() on a bar that can inherit secret aspects after Blizzard writes secret health into it, and tooltip cleanup no longer touches Blizzard state at unsafe times (fixes map POI/event tooltip taint).",
					"Rare Alert: showing/hiding the secure click-to-target popup in combat is now safe - it skips showing in combat and defers hides until combat ends.",
					"Rare Alert: fixed Edit Mode click/drag conflicts where the secure overlay could sit above the mover and block moving the banner.",
					"Faster Loot: locked-slot handling now works across client variants of GetLootSlotInfo.",
					"Minimap (Collect Buttons): the AllTheThings button no longer shows up oversized or escapes the tray - its icon is re-clamped to the slot on every open and its self-positioning is stopped once parked.",
					"Faster Movie Skip: enabling it from the Settings panel now works live instead of needing a reload.",
					"Social Colours: the friends/who lists no longer do O(n^2) work refreshing - the scroll rows are enumerated once per refresh.",
				},
			},
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
			{
				"Fixed",
				{
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
				},
			},
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
	date = "8a8a8a",
	intro = "c8c8c8",
	heading = "|c" .. C.BrandHex,
	bullet = "8a8a8a",
	body = "e2e2e2",
}
-- History is still dimmed so the newest entry reads as "what's new", but lifted
-- well above the old near-black greys so older notes stay legible.
local PALETTE_OLD = {
	version = "bcbcbc",
	date = "6a6a6a",
	intro = "8e8e8e",
	heading = "|cffa6a6a6",
	bullet = "6f6f6f",
	body = "9c9c9c",
}

local CONTENT_WIDTH = 496

-- Vertical rhythm (pixels) between stacked rows.
local GAP_AFTER_TITLE = 6
local GAP_AFTER_INTRO = 12
local GAP_AFTER_HEADER = 6
local GAP_BETWEEN_BULLETS = 6
local GAP_AFTER_SECTION = 14
local GAP_BETWEEN_VERSIONS = 16

-- Bullets are two columns - a "•" glyph and the wrapping text body - so every
-- wrapped line hangs under the text instead of falling back to the margin.
-- (A single FontString with indented word wrap does NOT hang reliably here.)
local BULLET_GLYPH_X = 2
local BULLET_TEXT_X = 16

-- A left-justified, word-wrapped row in the given font object at the given width.
local function NewRow(parent, fontObject, width)
	local fs = parent:CreateFontString(nil, "OVERLAY", fontObject)
	fs:SetWidth(width)
	fs:SetJustifyH("LEFT")
	fs:SetJustifyV("TOP")
	fs:SetSpacing(5)
	return fs
end

-- Render one version entry into `parent` as a stack of FontStrings, top-anchored
-- at vertical offset `y`. Returns the new cursor position below the block.
-- Section headers use a larger font than the body so the hierarchy reads at a
-- glance instead of relying on colour alone.
local function RenderVersion(parent, entry, isLatest, y)
	local p = isLatest and PALETTE_NEW or PALETTE_OLD

	local title = NewRow(parent, "GameFontNormalLarge", CONTENT_WIDTH)
	local tag = isLatest and format("  |c%sNEW|r", C.BrandHex) or ""
	title:SetText(format("|cff%sVersion %s|r  |cff%s%s|r%s", p.version, entry.version, p.date, entry.date, tag))
	title:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -y)
	y = y + title:GetStringHeight() + GAP_AFTER_TITLE

	if entry.intro then
		local intro = NewRow(parent, "GameFontHighlight", CONTENT_WIDTH)
		intro:SetText(format("|cff%s%s|r", p.intro, entry.intro))
		intro:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -y)
		y = y + intro:GetStringHeight() + GAP_AFTER_INTRO
	end

	for _, section in ipairs(entry.sections) do
		local header = NewRow(parent, "GameFontNormalMed1", CONTENT_WIDTH)
		header:SetText(format("%s%s|r", p.heading, section[1]))
		header:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -y)
		y = y + header:GetStringHeight() + GAP_AFTER_HEADER

		local lines = section[2]
		for i = 1, #lines do
			local glyph = NewRow(parent, "GameFontHighlight", 12)
			glyph:SetText(format("|cff%s•|r", p.bullet))
			glyph:SetPoint("TOPLEFT", parent, "TOPLEFT", BULLET_GLYPH_X, -y)

			local text = NewRow(parent, "GameFontHighlight", CONTENT_WIDTH - BULLET_TEXT_X)
			text:SetText(format("|cff%s%s|r", p.body, lines[i]))
			text:SetPoint("TOPLEFT", parent, "TOPLEFT", BULLET_TEXT_X, -y)
			y = y + text:GetStringHeight() + GAP_BETWEEN_BULLETS
		end
		y = y + (GAP_AFTER_SECTION - GAP_BETWEEN_BULLETS)
	end

	return y
end

local function Build()
	if frame then
		return frame
	end

	frame = CreateFrame("Frame", "NexEnhanceChangelog", UIParent, "BackdropTemplate")
	frame:SetSize(560, 600)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("DIALOG")
	frame:SetToplevel(true)
	frame:Hide()
	-- Classic tooltip backdrop (UI-Tooltip-Border + dark fill).
	frame:SetBackdrop(BACKDROP)
	frame:SetBackdropColor(0.06, 0.06, 0.06, 0.95)
	frame:SetBackdropBorderColor(1, 1, 1)

	-- Outer glow halo (raw tutorial textures; drawn one level below the panel),
	-- tinted to the NexEnhance brand blue to match the window's accents.
	local glow = CreateFrame("Frame", nil, frame)
	glow:SetAllPoints(frame)
	glow:SetFrameLevel(max(frame:GetFrameLevel() - 1, 0))
	glow:SetAlpha(0.90)
	F.CreateGlowBorder(glow, { outset = 6, blend = "BLEND", color = C.Colors.brand })

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

	-- A plain ScrollFrame paired with Blizzard's modern MinimalScrollBar, instead
	-- of UIPanelScrollFrameTemplate's dated square-arrow bar. InitScrollFrameWithScrollBar
	-- wires the two together (mouse wheel + bidirectional sync) for free-form
	-- content - the ScrollBox/list API doesn't fit our single tall child.
	local scroll = CreateFrame("ScrollFrame", "NexEnhanceChangelogScroll", frame)
	scroll:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 0, -12)
	scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -28, 16)

	local scrollBar = CreateFrame("EventFrame", nil, frame, "MinimalScrollBar")
	scrollBar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 6, 0)
	scrollBar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 6, 0)
	ScrollUtil.InitScrollFrameWithScrollBar(scroll, scrollBar)

	local child = CreateFrame("Frame", nil, scroll)
	child:SetSize(CONTENT_WIDTH, 1)
	scroll:SetScrollChild(child)

	-- Latest version is always rendered and expanded.
	local y = RenderVersion(child, CHANGELOG[1], true, 0)

	-- Older versions live in a collapsible container, hidden by default so the
	-- window opens on "what's new" instead of the whole history wall.
	local older = CreateFrame("Frame", nil, child)
	older:SetWidth(CONTENT_WIDTH)
	older:Hide()

	local oy = 0
	for i = 2, #CHANGELOG do
		if i > 2 then
			oy = oy + GAP_BETWEEN_VERSIONS
		end
		oy = RenderVersion(older, CHANGELOG[i], false, oy)
	end
	older:SetHeight(max(oy, 1))

	local toggle, collapsedHeight
	if oy > 0 then
		toggle = CreateFrame("Button", nil, child)
		toggle:SetSize(CONTENT_WIDTH, 24)
		toggle:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -(y + 2))

		local label = toggle:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		label:SetPoint("LEFT")
		toggle.label = label

		-- Blizzard's minimal-scrollbar arrow atlas instead of a text glyph; it
		-- points down when collapsed and is rotated to point up when expanded.
		local arrow = toggle:CreateTexture(nil, "OVERLAY")
		arrow:SetAtlas("minimal-scrollbar-arrow-bottom-down", true)
		arrow:SetPoint("LEFT", label, "RIGHT", 6, -2)
		toggle.arrow = arrow

		older:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -(y + 2 + 24 + 6))
		collapsedHeight = y + 2 + 24 + 12

		local br = C.Colors.brand
		-- Plain text + SetTextColor (no embedded |c codes) so the hover-to-white
		-- highlight actually takes effect - embedded colour escapes would win.
		local function Tint(r, g, b)
			toggle.label:SetTextColor(r, g, b)
			toggle.arrow:SetVertexColor(r, g, b)
		end
		local function Refresh()
			local shown = older:IsShown()
			toggle.label:SetText(shown and L["Hide previous versions"] or L["Show previous versions"])
			toggle.arrow:SetRotation(shown and math.pi or 0)
			Tint(br[1], br[2], br[3])
			child:SetHeight((shown and (collapsedHeight + oy) or collapsedHeight) + 8)
		end

		toggle:SetScript("OnEnter", function()
			Tint(1, 1, 1)
		end)
		toggle:SetScript("OnLeave", function()
			Tint(br[1], br[2], br[3])
		end)
		toggle:SetScript("OnClick", function()
			older:SetShown(not older:IsShown())
			Refresh()
		end)
		Refresh()
	else
		child:SetHeight(y + 8)
	end

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
	if not ns.db.changelog.enable then
		return
	end

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
