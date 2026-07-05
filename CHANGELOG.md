# NexEnhance — Changelog

---

## [1.5.7] — 2026-07-05

ElvUI-style chat emoji textures.

### Added

- **Chat — Emojis:** new **Chat Emojis** module replaces text emoticons (`:D`, `:smile:`,
  `<3`, `xD`, etc.) with 16×16 textures from `Media/Emojis` (ElvUI-compatible names).
  Uses the 12.0 `ChatFrame_AddMessageEventFilter` path with Midnight secret guards.
  Hidden `nexmoji:` hyperlinks preserve the original text for **Chat Copy**.
  Optional **Show in Chat Bubbles** (default off) applies 12×12 textures to
  say/yell/party speech bubbles via `C_ChatBubbles` polling.
- **Install:** chat layout step sets ElvUI-style colors for General (`CHANNEL1`),
  Trade (`CHANNEL2`), and Local Defense (`CHANNEL3`).
- **Core — Media:** `C.Media.Emojis` table maps all shipped emoji texture paths.
- **Core — `F.ChatTexture`:** shared inline |T| helper for chat icons and emojis.

### Fixed

- **Chat — Emojis:** gsub replacement no longer treats hex-encoded `nexmoji` keys
  (e.g. `%3A%29` for `:)` ) as invalid capture indices.
- **Chat — Emojis:** speech bubbles reflow width after emoji textures replace plain
  text (no more oversized empty bubble padding).
- **Chat — Emojis:** bubble emoji transform no longer skips on repeat messages;
  recycled bubbles reset to plain text while the old source cache still matched.
- **Skins — Chat Bubbles:** instance/raid/party bubble borders and text now use
  the correct channel colour from `ChatTypeInfo` instead of stale recycled
  `GetTextColor()` (e.g. party blue on instance chat).
- **Chat — Channels:** fix channel abbreviation for leader tags (`[Party Leader]`
  → `[PL]`, `[Instance Leader]` → `[IL]`, etc.); gsub callback had captures swapped.

---

## [1.5.6] — 2026-07-03

Per-option and per-section reset controls in the Settings panel.

### Added

- **Core — Options reset:** hover any NexEnhance option whose value differs from
  its default and a small revert icon (`transmog-icon-revert`) appears just left
  of the label; click it to reset that single option to default. Options already
  at their default show nothing, so the panel stays clean.
- **Core — Section reset:** each module's section header shows a revert icon when
  any of its options are non-default; clicking it (with a confirm popup) resets
  every option in that section to default. Both paths live-apply through the same
  `SetValueToDefault` → `OnSettingChanged` callback, so no `/reload` is needed.

### Fixed

- **Chat — Clickable URLs:** `https://…` links no longer get wrapped twice (the `www.`
  pass was re-matching inside the link label, producing broken `|Hurl:` garbage in
  whispers and chat).
- **Automation — Auto Warband Gold:** skip sync when `GetMoney()` or warband bank
  balance is a Midnight secret value (avoids combat/in-instance arithmetic errors).
- **Skins — Objective Tracker:** deferred `ADDON_LOADED` listener unregisters on
  disable; styling no longer runs when the module is off.
- **Locales:** Character Frames, Clock, and Location option tips no longer show raw
  English keys (enUS + deDE).

## [1.5.5] — 2026-06-27

Reference-library architecture — zero-duration cooldown masks, central cooldown bus, frame runner, hook guards.

### Added

- **Core — UI shortcuts:** `/nex editmode` / `/nex em` (mirrors Blizzard `/editmode`),
  `/nex keybinds` / `/nex kb` (opens Settings → Key Bindings).
- **Automation — Auction Search History:** recent AH browse text searches (account-
  wide, default 5) appear in a dropdown when you focus the search box; click to
  re-run. Text only — filters and level range are not stored.
- **Unit Frames — Player Cast Bar:** optional **Show Cast Latency** SafeZone on
  Blizzard's player cast bar (`UI-Frame-Bar-Fill-Red`); read-only overlay, oUF
  ratio pattern; works on overlay replacement bar too.
- **Alert Frames:** configurable **Stack Spacing** slider (default 2; was hard-coded
  10); `/nex alerttest` previews achievements, loot, money, and Trading Post toasts;
  stack spacing re-applies after anchor direction sync; default 0 with art trim (migrates saved 10).
- **Maps — Map Pin Navigation:** NexEnhance rewrite of Unlimited Map Pin Distance
  plus the former Quest Navigation ETA skin — unlimited super-track range,
  distance/alpha controls, arrival ETA, `/way`/`/pin`/`/nexway`, and auto-track
  for new user waypoints. Replaces the **Quest Navigation** skin module.
- **Core — `Debug.lua`:** scoped logging, expectation checks (`Expect`), state dumps,
  ring-buffer log, and `/nex debug export` for copy-paste bug reports.
- **Core — `F.MaskCooldownSwipeFromDurationObject`:** hides permanent-aura cooldown
  swipes via `SetAlphaFromBoolean(dur:IsZero(), 0, 1)` (Midnight-safe).
- **Core — `CooldownDispatch.lua`:** one `SPELL_UPDATE_COOLDOWN` /
  `BAG_UPDATE_COOLDOWN` frame; modules subscribe with
  `RegisterCooldownDispatchCallback`.
- **Core — `Runner.lua`:** `ns:CreateRunner` spreads batch work across frames with
  a per-frame time budget (ATT pattern).
- **Core — `ns:GuardModuleHook`:** wrap hook callbacks so they no-op when a
  skin module is disabled (`hooksecurefunc` cannot be removed).

### Changed

- **General — Install:** one-click setup screen — bullet list of recommended
  settings, **Install** reloads and applies everything, **Not Now** dismisses.
- **General — Install:** your character on the setup screen with wave → dance emotes.
- **Cooldown Text:** applies zero-duration mask on `SetCooldownFromDurationObject`.
- **Buff Reminder / Extra Quest Button:** mask cooldown swipes after DurationObject
  updates.
- **GCD Bar / Extra Quest Button:** spell and bag cooldown refresh via
  `CooldownDispatch` instead of duplicate event registrations.
- **Nameplate Quest Icons:** large quest-log refreshes use the frame runner.
- **Quest Navigation / Objective Tracker skins:** `IsEnabled` gates hook work on
  live disable (visual revert still needs `/reload`).
- **Quest Navigation** removed — use **Map Pin Navigation** under Maps (settings
  migrate automatically).
- **DataText — Guild / Friends / CharacterInfo / Currency & Gold:** module events
  use `TrackEvent` + `OnDisable` teardown (`MODIFIER_STATE_CHANGED` no longer
  fires when disabled; CharacterInfo token ticker cancels on `Stop`).
- **DataText — Clock:** `Stop()` clears OnUpdate and hover `MODIFIER` listener;
  ticker re-arms on re-enable; lockouts refresh on `UPDATE_INSTANCE_INFO` while hovered.
- **Inventory — Loot Frame:** display/scale events unregister on disable;
  `panelMaxHeight` restores to Blizzard default.
- **Unit Frames — Player Cast Bar:** unit cast events + `PLAYER_ENTERING_WORLD`
  unregister on disable.
- **Unit Frames — Player Cast Bar:** latency SafeZone inset inside the bar fill,
  semi-transparent BLEND overlay (no bleed past the border); ms readout above
  the bar's top-right corner.
- **Inventory — Item Level:** `IsActive()` gates permanent hooks; module events
  unregister on live disable.
- **Miscellaneous — Animation / Achievement Screenshot / Social Colours / Drag
  Frames / Alert Frames:** `TrackEvent` teardown on disable (hooks no-op when off).
- **Automation — Quick Join / Guild Invite Filter / Auto Resurrect:** module
  events unregister on disable (`TrackEvent` teardown).
- **Skins — Quest Navigation:** ETA timer no longer uses `CreatePlainFS`; copies
  `DistanceText` shadow so the countdown is not double-drawn on the waypoint arrow.

### Fixed

- **Tooltip — Pawn:** no longer calls `GameTooltip:RefreshData` on unit tooltips
  (avoids `UnitPlayerControlled` secret-unit error when Pawn loads or icon/border
  settings change).
- **Unit Frames — Player Cast Bar:** latency ms text no longer leaves a ghost
  shadow after the cast ends (`CreatePlainFS` shadow duplicate now hides with the
  label); shadow draw layer fixed so black duplicate renders behind white text.
- **DataText — Clock:** saved raids (e.g. Battle of Dazar'alor) no longer appear under
  **Saved Dungeon(s)** — uses map InstanceID + EJ classification and renders raids
  before dungeons regardless of API list order.
- **Inventory — Already Known:** item-data async callback no longer errors on nil
  `RefreshVisibleItems` (forward declaration); skips refresh when load fails.
- **Chat:** Scroll-Down Interval defaults to **0** (off); was 15s and pulled chat back to
  the bottom after scrolling up unless disabled in settings.
- **Core — combat defer:** `AfterCombatCallback` retries when `PLAYER_REGEN_ENABLED`
  fires under lockdown (next-frame + delayed attempt).
- **Core — async loaders:** failed quest/item/spell loads invoke callbacks with
  `success == false` instead of hanging waiters silently.
- **Chat:** debug scope + dock edit-box expectation; documents Combat Log tab overlap
  incident alongside UIScale.
- **General — UI Scale:** fires `UIScaleApplied` after scale changes so Chat
  edit-box anchors refresh live.
- **Level Colours:** toggling off now calls `CheckLevel()` to restore Blizzard's
  skull/level display; zone/combat refresh events unregister via tracked handles.
- **Target Frame Layout:** refresh events unregister when disabled (TrackEvent teardown).
- **Hide Combat Errors:** split `PLAYER_REGEN_*` handlers — shared
  `OnCombatRegen(event)` never received the event name (module bus omits it),
  so error suppression did not toggle reliably.
- **General — UI Scale:** reverted to NDui-style `UIParent:SetScale` only (no
  `uiScale` CVar writes, no deferred `C_Timer.After(0)` apply). The CVar +
  next-frame apply ran after `Blizzard_CombatLog` init and broke docked chat tabs
  on `/reload`.
- **General — Widget Movers:** `SetPoint` hook compared the point string to the
  anchor frame instead of `relativeTo`, causing infinite recursion / C stack overflow
  when UI scale or layout changed.
- **Inventory — Durability:** live disable now unregisters module-level bootstrap
  events (not only the tab button's durability listener).
- **DataText — Location:** zone-change events unregister when toggled off; `Update()`
  no longer runs on a hidden frame.
- **General — Cast On Key Down:** restores the saved `ActionButtonUseKeyDown` CVar
  and unregisters the combat-deferred listener on disable.
- **Action Bars — GCD Bar:** fixed bar stuck visible after GCD ends — added
  `ACTIONBAR_UPDATE_COOLDOWN` + throttled poll while shown (`SPELL_UPDATE_COOLDOWN`
  alone does not always fire at GCD finish).
- **Chat — BN keyword invite:** pass whisper `guid` into `GetAccountInfoByID`; resolve
  game account via `GetGameAccountInfoByGUID` fallback; use `CanGroupWithAccount` instead
  of same-faction-only `CanCooperateWithGameAccount`.

### Debug

- New scopes: `durability`, `location`, `levelColors` (`/nex debug dump <scope>`).
- **Core — TOC load order fix:** `Debug.lua` now loads after `Database.lua` so `ns.Debug`
  is published (was nil on login; every `BindModule` errored).
- **Debug export:** sorted scope list, per-scope dumps in export, pass/fail summary; scopes
  without expectations/dumps omitted. Expectations added for location, durability,
  levelColors, widgetMovers, minimap.

## [1.5.4] — 2026-06-27

Lifecycle sweep — symmetric teardown for remaining event-driven modules and core helpers.

### Added

- **Core — `F.InheritExistingValues`:** copy prior sibling keys when a new setting is
  absent (DialogueUI-style schema upgrades).
- **Core — `TransitionAPI.lua`:** patch-day shim file for renamed Blizzard APIs.
- **Core — combat bus:** `UnregisterCombatEnterCallback` /
  `UnregisterCombatLeaveCallback` pair with the enter/leave registrars.

### Changed

- **Experience Bar:** fade-on-combat uses the shared combat visibility bus instead of
  a private `PLAYER_REGEN_*` frame.
- **Range Colors:** `UNIT_POWER_UPDATE` / `PLAYER_ENTERING_WORLD` use tracked handles;
  events unregister when coloring is deactivated or the module is disabled.
- **Tooltip:** modifier, addon-load, and item-level events use `TrackEvent`; item-level
  inspect events unregister on disable.
- **DataText (Stats):** `Destroy()` tears down the readout, position listener, and
  `OnUpdate` when disabled.

### Fixed

- **Rare Alert / Faster Loot / Quest Notification / Level Announcer:** explicit
  `OnDisable` unregisters events without `/reload`.
- **Level Announcer:** enable toggle registers/unregisters events via `TrackEvent`.

---

## [1.5.3] — 2026-06-27

Combat bus, lifecycle teardown, and Quick Quest data-path polish.

### Added

- **Core — combat visibility bus:** `ns:RegisterCombatEnterCallback` and
  `ns:RegisterCombatLeaveCallback` share one `PLAYER_REGEN_*` dispatcher
  (also drives `ns:AfterCombatCallback` flush).

### Changed

- **Quick Quest:** reward picker uses `RequestItemData` for cold choice items;
  crafting-reagent guard warms item data; combat popup retry uses
  `ns:AfterCombatCallback` instead of a private `PLAYER_REGEN_ENABLED` hook.
- **Holiday Dungeon:** `RegisterAddOnLoadedCallback` for Group Finder; tracked
  events unregister on disable.
- **Auto Keystone:** tracked `ADDON_LOADED` teardown on disable.

### Fixed

- **Unusable Items:** `OnDisable` unregisters `PLAYER_LEVEL_UP`.
- **Experience Bar:** bar update events and fade combat/target listeners unregister
  when the module is disabled.
- **Quick Quest:** explicit `OnDisable` clears gated quest events.

---

## [1.5.2] — 2026-06-27

Midnight data paths, sparse profiles, and action-bar DurationObject polish.

### Added

- **Core — sparse SavedVariables:** `F.CompactDefaults` strips keys equal to defaults;
  `ns:CompactActiveProfile` runs on `PLAYER_LOGOUT` so profiles stay small
  (Hydra-style sparse persistence).
- **RequestItemData:** Tooltip Item Level (inspect cache), Already Known (vendor/AH
  tint), Delete Cheapest (sell-price / class filters).

### Changed

- **GCD Bar:** uses `C_Spell.GetSpellCooldownDuration` + `StatusBar:SetTimerDuration`
  instead of per-frame `OnUpdate` arithmetic; `OnDisable` unregisters events.
- **Extra Quest Button:** item cooldown swipe uses `DurationObject` +
  `SetCooldownFromDurationObject` (Reminder pattern).

### Fixed

- **Already Known / Delete Cheapest:** tracked event teardown on disable.

---

## [1.5.1] — 2026-06-27

Lifecycle and Midnight polish — symmetric module teardown, live-disable fixes, and
helper additions from the reference-library backlog.

### Fixed

- **Smart Minimap Tracking:** `OnDisable` now unregisters events (previously kept
  firing after toggle-off).
- **Loot Roll:** disabling restores Blizzard `START_LOOT_ROLL` / `CANCEL_LOOT_ROLL`
  on `UIParent`, clears active bars, and unregisters module events — no `/reload`
  required.
- **Clock:** `OnDisable` unregisters `PLAYER_ENTERING_WORLD` and hides the frame
  when toggled off.
- **Hide DPS Role Icon:** roster/zone events unregister on disable; compact and
  party frames refresh so DPS icons return immediately.
- **Auto Role:** migrated to `TrackEvent` / `TrackUnitEvent` handles (symmetric
  teardown with other automation modules).
- **Popup QoL:** `MERCHANT_SHOW` uses tracked handles for clean disable.

### Changed

- **Class Colours:** `F.BooleanIsTrue` for connection/player checks; `OnSettingChanged`
  gates on the `enable` key.
- **Core — `F.RegisterFrameForEvents`:** bulk `Frame:RegisterEvent` helper for
  modules that own a private event frame.

---

## [1.5.0] — 2026-06-27

Midnight maintenance pass — nameplate tools, tooltip and automation improvements,
settings reorg, chat quality-of-life, Character and Inspect frame reskin sync,
and assorted 12.0.7 API polish.

### Added

- **Core — lifecycle helpers:** `ns:AfterCombatCallback` (defer until
  `PLAYER_REGEN_ENABLED`), `ns:RegisterAddOnLoadedCallback` (run when a Blizzard
  addon loads), `ns:RegisterLoadingCompleteCallback` (post loading-screen), and
  `ns:RequestQuestData` (coalesced `QUEST_DATA_LOAD_RESULT` batching in
  `Core/DataLoad.lua`).
- **Core — `F.SafeUnitIsUnit`:** compares unit tokens via
  `C_Secrets.CanCompareUnitTokens` when available; returns false when blocked or
  secret. Used by tooltips, nameplates, menu buttons, and
  `F.IsFriendlyControlledUnit`.
- **Core — event teardown:** `module:TrackEvent` / `TrackUnitEvent` and
  `ns:UnregisterModuleEventHandles` for symmetric `OnDisable` registration.
- **Core — async loaders:** `ns:RequestItemData` and `ns:RequestSpellData` (coalesced
  `ITEM_DATA_LOAD_RESULT` / `SPELL_DATA_LOAD_RESULT` in `Core/DataLoad.lua`).
- **Core — zone gating:** `ns:CreateZoneTrigger(zoneSet, onEnter, onLeave)` in
  `Core/ZoneTrigger.lua` for map-only event registration; `ns:CreateStateTrigger`
  for predicate gates (Delves walk-in with debounced boundary sync).
- **Core — boolean helpers:** `F.BooleanIsTrue`, `F.EvaluateColorFromBoolean`, and
  `F.SetShownFromBoolean` for Midnight-safe boolean visuals.
- **Core — LOD callbacks:** Wowhead Links, Auction Search Fallback, Hero Talent
  Swap, and Quest Navigation use `ns:RegisterAddOnLoadedCallback` instead of
  manual `ADDON_LOADED` one-shots.
- **Auras — Buff Reminder:** item and depend-spell cooldown swipes use
  DurationObject APIs; item cooldown eligibility is secret-guarded. Lack label
  uses `CreatePlainFS`.
- **Skins — Quest Navigation:** ETA text uses `CreatePlainFS` (12.0.7 Slug
  shadow workaround).
- **General — Hide Combat Errors:** suppresses red center-screen error spam during
  combat by unregistering `UI_ERROR_MESSAGE` on `UIErrorsFrame` (same approach
  as ElvUI and Blizzard's `/uierrorsoff`). Yellow info messages still show.
- **Automation — Smart Fishing:** while channeling fishing, temporarily widens
  soft-target interact, mutes music/ambience, and override-binds your fishing
  action-bar key to `INTERACTTARGET` (Hold Shift when casting to skip).
- **Automation — Auction Search Fallback:** when Current Expansion Only returns
  zero browse results, widens the filter once and retries automatically.
- **Automation — Smart Minimap Tracking:** auto-enables repair-vendor tracking
  when gear is damaged and mailbox tracking when mail is pending.
- **Skins — Hero Talent Swap:** right-click the hero talent button on the
  Talents pane to swap to your inactive hero tree.
- **Miscellaneous — Popup QoL:** optional auto-confirm for BoP loot and
  tradeable equip/sell, click-through event toasts, and Enter-to-accept purchases.
  Alt+right-click on a merchant item buys a full stack (one confirm per item per
  session; routes token/high-cost purchases through Blizzard's own dialogs).
- **Filters — System Chat Filter:** hides learn/unlearn spell system messages
  when changing talents.
- **Tooltip — NPC Spawn Age:** while holding Shift on NPC tooltips, shows how
  long ago the unit spawned (GUID spawn UID decode).
- **Nameplates — Nameplate Quest Icons:** a quest icon on the nameplate of any
  NPC tied to one of your active quests, with optional objective progress
  (always on your target, on mouseover, or while holding a chosen modifier key).
  Greys the icon for a party member's quest, falls back to the cheap relation
  check inside instances, and is Secret-value safe. Options for icon size,
  progress text size, side, X/Y offset, party quests, progress mode/format, and
  the modifier key. A NexEnhance-native take on Plumber's NameplateQuestIndicator.
- **Nameplates — Target Arrows:** left/right arrow indicators on your current
  target's nameplate (attackable units only). Optional friendly-player nameplate
  preset sets `nameplateShowFriendlyPlayers`,
  `nameplateShowOnlyNameForFriendlyPlayerUnits`, and
  `nameplateUseClassColorForFriendlyPlayerUnitNames` — the same CVars Blizzard's
  nameplate UI reads via `CVarCallbackRegistry`; originals are restored when the
  option is turned off. Arrow style dropdown: horizontal side arrows or a single
  `Azerite-PointingArrow` above the nameplate. Custom arrow color (defaults to
  NexEnhance brand blue `#5C8BCF`).
- **Nameplates — Reaction Colors:** tints NPC and mob nameplate health bars with
  the same darker reaction palette as the target frame (`F.GetNpcReactionColor`).
  Player nameplates are untouched (Blizzard class-color CVars). Skips forbidden
  plates, tap-denied/dead gray, and combat threat-hostile red.
- **Tooltip — Crafting Reagents:** on usable craftable items, appends required
  reagents with bag/bank counts and a batch-craft hint when you have enough for
  multiple outputs (Plumber-inspired). Secret-safe count display.
- **Tooltip options:** **Hide Unit Tooltips in Combat**, **Hide Guild Rank**, and
  **Show Crafting Reagents** — settings that existed in code but had no UI row.
- **Tooltip — Pawn integration:** when Pawn is installed, **Show Icons** suppresses
  Pawn's corner tooltip icon frames and **Quality-Coloured Border** suppresses
  Pawn's green upgrade border (via `PawnRegisterThirdPartyTooltip`). Pawn scores
  and upgrade text are unchanged. Settings note this when Pawn is enabled.
- **Automation — Auto Role:** keeps your party/raid role aligned with your active
  specialization via Blizzard's `GetSpecializationRoleEnum` / `UnitSetRoleEnum`
  APIs. Skips LFG-restricted groups, scenarios, and combat. Optionally answers
  role polls instantly and suppresses Blizzard's popup.
- **Chat:** ElvUI-style chat quality-of-life — scroll-down interval (auto return to
  bottom after scrolling up), flash taskbar icon on whisper, `/tt`/`/gr` edit-box
  shortcuts, and combat repeat-character block.
- **Chat — Chat Channels:** optional hide channel tags entirely (strips `[Guild]`
  brackets instead of abbreviating).
- **Automation — Holiday Dungeon:** when you open the Dungeon Finder for the
  first time each login, points out the active holiday or Timewalking random
  queue in the Type menu if it is not already selected (does not call
  `LFDQueueFrame_SetType`, which taints LFG globals and can block
  `AcceptProposal`.
- **General — Hide UI Elements:** optional **Hide Boss Banner** and **Hide Event
  Toasts** toggles (off by default). Boss banner suppression unregisters
  `BOSS_KILL` / `ENCOUNTER_LOOT_RECEIVED` on Blizzard's `BossBanner` frame;
  event toasts dismiss auto-hiding pop-ups while keeping scoreboards that ship
  with a close button.
- **Auras — Buff Reminder:** optional **Reminder Glow** (on by default) draws a
  soft red halo around missing-buff icons using the retail tutorial-frame glow
  art — no Classic flipbook ants. Expanded alternate raid buff spell IDs (MOTW,
  AI, full Bronze variants), fixed Shaman weapon-enchant `depend` to cast spell
  IDs, rogue poison eligibility checks any known poison in the slot, faster
  `GetPlayerAuraBySpellID` lookup, and a pre-combat aura snapshot for
  secret-safe display in combat.

### Changed

- **Settings:** reorganised the options into clearer categories — new
  **Nameplates**, **Camera**, **Alerts**, and **Movers** groups so the
  Miscellaneous page is no longer a catch-all. **Cast On Key Down** moved from
  General to Action Bars.
- **Game Menu:** **NexEnhance** button on the escape menu (after Options/Shop)
  opens the addon settings panel.
- **Localization:** initial German (`deDE`) locale — machine-translated for native
  review; English remains the fallback.

### Fixed

- **Nameplates — Reaction Colors:** plates no longer flash default Blizzard
  selection colors after combat — threat health-bar skip is combat-only, and
  `UNIT_THREAT_*` / `UNIT_FACTION` / deferred regen refreshes match ClassColors.
  Out-of-combat plates now tint immediately (bar-RGB fallback when nameplate
  unit tokens hide reaction APIs; deferred `NAME_PLATE_UNIT_ADDED` refresh).
- **Maps — Wowhead Links:** world-map quest link restored as a copyable edit box
  (hover highlights, Ctrl-C); stacks above the title bar so map drag does not
  block it; fixed nil `wmf` in `Setup()`.
- **Unit Frames — Class Colours:** disconnected party members (target/focus/boss
  HUD bars) now grey out like Blizzard's party frame instead of staying class
  coloured — `GetUnitHealthColor` was returning nil for offline units, which
  re-saturated the green atlas; now applies 0.5 grey with desaturation.
- **Unit Frames — Class Colours:** player pets and other friendly
  player-controlled units (pet frame, targeting your pet) no longer tint as
  hostile NPCs — they use class colour when available, otherwise friendly green
  (`F.IsFriendlyControlledUnit`; matches Blizzard's green pet HUD atlas).
- **Unit Frames — Class Colours:** no longer overrides compact raid/party frame
  colours — those use Blizzard's Edit Mode "Class Colors" raid-profile option
  (`CompactUnitFrame_GetOptionUseClassColors`) instead of a post-hook on
  `CompactUnitFrame_UpdateHealthColor`.
- **Unit Frames — Class Colours:** `F.IsFriendlyControlledUnit` no longer tests
  `UnitIsUnit` directly — the result can be a secret boolean on units like
  `targettarget` during combat (fixes taint error when tab-targeting).
- **Unit Frames — Class Colours:** offline players on target, focus, target-of-target,
  and boss HUD frames now show the disconnect lightning icon and desaturated
  portrait (matching standard party frames). Health was already grey/desaturated;
  party portraits remain on Blizzard's `UpdateOnlineStatus`.
- **Automation — Quick Quest:** auto-selects `<Skip Mini Game>` gossip (e.g.
  Rommath ward mini-game) whenever Quick Quest is enabled — no need to turn on
  Auto-Skip Story Gossip. Story-skip detection now keys off `<Skip` rather than
  any angle-bracket segment so lead-ins like `<Convince Rommath...>` are not
  mistaken for campaign skips.
- **Automation — Quick Quest:** rogues and druids auto-select gossip options
  tagged `[Requires a Stealth Class.]` when exactly one is offered.
- **General — UI Scale:** pixel-perfect scaling now follows Blizzard's 768-unit
  model (`768 / screen height`): uses the `uiScale` CVar when scale is at or
  above 0.64 (up to ~1200p), and `UIParent:SetScale` below that for 1440p/4K+.
  Fixes auto-scale being clamped to 0.40 on high resolutions; refreshes on
  `DISPLAY_SIZE_CHANGED` and `PLAYER_ENTERING_WORLD`; defers applies out of combat.
  Fixed a freeze from `UI_SCALE_CHANGED` re-entering after every `SetCVar("uiScale")`.
- **Automation — Guild Invite Filter:** events unregister on disable (`OnDisable` and
  toggle off) so `GUILD_INVITE_REQUEST` no longer fires while the module is off.
- **Nameplates:** Quest Icons, Target Arrows, and Reaction Colors unregister events
  when disabled — no idle `NAME_PLATE_*` / threat listeners while off.
- **Unit Frames — Class Colours:** threat/faction refresh events unregister on disable.
- **General — Hide Combat Errors:** `PLAYER_REGEN_*` listeners unregister when off.
- **Automation — Auto Role / Auto Hide Tracker:** `OnDisable` symmetry for teardown.
- **Automation:** Auto Invite, Auto Goodbye, Decline Duel, Cancel Bad Buffs, Auto
  Greed, Auto Vendor, Auto Warband Gold, Auto Summon, and Auto PvP Release unregister
  events on disable; fixed broken unregister on Warband Gold / Summon / PvP
  Release (method refs instead of dispatcher wrappers).
- **DataText — Clock:** uncached item links use `ns:RequestItemData` when
  `GetItemInfo` is not ready.
- **Automation — Auto Resurrect:** `OnDisable` unregisters `RESURRECT_REQUEST` when
  the module is disabled.
- **General — Queue Timer / Audio Sync / Hide UI Elements:** `OnDisable` and
  `TrackEvent` teardown when toggled off.
- **Action Bars / Extra Quest Button:** events unregister on disable; Extra Quest
  Button hides the secure control when turned off.
- **Unit Frames — Class Colours / Nameplates:** event registration uses
  `TrackEvent` + `UnregisterModuleEventHandles` (no hand-rolled unregister loops).
- **Loot Roll / Tooltip IDs / Unusable Items:** cold `GetItemInfo` paths use
  `ns:RequestItemData` for item level, stack cap, and required-level caches.
- **Auras — Buff Reminder:** weapon-enchant checks use `F.BooleanIsTrue` (no false
  "Lack" when `GetWeaponEnchantInfo` is secret); `TrackEvent` + `OnDisable` teardown.
- **Nameplates — Reaction Colors:** skip player/dead/treat-as-player only when
  readable; secret threat during combat leaves Blizzard tint; RGB fallback when
  unit reaction APIs are secret.
- **Automation — Delves Automation:** `PLAYER_CHOICE_UPDATE` gated via
  `ns:CreateStateTrigger` (replaces hand-rolled gate events).
- **Unit Frames — Hide DPS Role Icon:** also hides the DPS sword on standard
  party portrait frames; pooled `PartyMemberFrame` instances are hooked per
  frame (mixin-only hooks did not run on acquired pool frames).
- **Settings — New badges:** sidebar group labels use the
  `UI-HUD-MicroMenu-Communities-Icon-Notification` dot on the category icon
  instead of a trailing "New" suffix (fixes truncated names like Announcements).
- **Settings — landing page:** “New This Update” scrolls when the list is long
  instead of overflowing the panel.
- **Settings — Plugin Manager** appears directly under **Plugins** in the sidebar.
- **Profiles:** clearer per-character profile label and hint text; dropdown row
  layout no longer overlaps when menus open.
- **Profiles:** create/copy name prompt no longer errors on 12.0.7 — StaticPopup
  edit boxes and buttons use `GetEditBox()` / `GetButton1()` instead of legacy
  `editBox` / `button1` fields.
- **Unit Frames / Tooltips — unfriendly (orange) NPCs:** reaction category from
  `UnitSelectionType` (nameplate source), tinted with darker `FACTION_BAR_COLORS`;
  unfriendly orange is boosted toward nameplate orange so it reads clearly vs
  hostile red on desaturated HUD bars. `UnitReaction` fallback when secret.
- **Auto Hide Tracker:** no longer hides the objective tracker when a friendly
  escort NPC occupies a boss frame (e.g. MoP Shado-Pan assault dailies). Boss
  slots are populated via `INSTANCE_ENCOUNTER_ENGAGE_UNIT`; we now require a
  hostile boss unit, not merely `@bossN,exists`.
- **Minimap:** fixed the cluster briefly jumping then snapping back when mail,
  crafting orders, or Edit Mode layout runs — footprint correction now defers
  until after Blizzard's `ResizeLayoutFrame` pass and ignores layout children
  we removed or repinned.
- **Tooltip — Mount Source:** mount collection/source lines now use the aura's
  unit (party/raid mouseover), not `target`.
- **Tooltip:** unit tooltips refresh when either Shift key is pressed or
  released so realm, NPC ID, and item-level-on-shift update live.
- **Tooltip:** health-bar text setting no longer calls `IsShown()` on a bar that
  may carry secret aspects after Midnight health writes.
- **Chat:** fix scroll-down interval and quick-scroll mouse wheel handler —
  `HookScript` passes `(frame, delta)` but the hooked method used a colon
  signature, so `delta` was nil and wheel scrolling errored.
- **Skins — Character Frames:** synced with [CharInspectPlus](https://github.com/Kkthnx-Wow/CharInspectPlus)
  v2.0.0 for 12.0.7 — widened gear layout only when `CharacterFrame.Expanded`,
  Reputation/Currency tabs keep Blizzard inset anchors, Inspect PVP/Guild tabs
  restore `ButtonFrameTemplate` insets, Secret guards on inspect class and item
  level, live enable/disable for layout (slot strip art still needs `/reload`).
- **Skins — Missing Stats:** wrap `CharacterStatsPane` in a scroll frame so the
  extra attribute rows and full Enhancements list stay inside the stats sidebar
  (mouse-wheel scroll; hidden scrollbar).
- **Skins — Character Frames:** fix Pawn paper-doll button not clickable or
  hoverable — `CharacterStatsPane` sits above `PaperDollFrame` and was eating
  clicks; lift the button to `HIGH` frame strata so it stays on the gear tab
  only (no reparent, no bleed onto Reputation/Currency).
- **Automation — Holiday Dungeon:** no longer calls `LFDQueueFrame_SetType` from
  addon code; that tainted `LFGLockList` / `LFDDungeonList` / `LFGEnabledList`
  and could trigger `ADDON_ACTION_BLOCKED` when accepting a dungeon-ready popup.
- **Chat — Chat Channels:** ElvUI-style full-line abbreviation and timestamps
  via a LibChatAnims-safe `AddMessage` wrapper; URLs stay on
  `ChatFrame_AddMessageEventFilter`. Fixes `[Guild]` → `[G]` and restores
  `[HH:MM]` before the channel tag. Embeds Funkydude's LibChatAnims.
- **Maps — Minimap:** `SetTexCoord` on masked HUD/housing textures no longer
  errors on enable — strip mask textures first (12.0 rejects texcoord changes
  on masked textures).
- **Action Bars:** defer action-button styling refreshes while in combat so
  `SetShown` / repositioning overlay text on secure buttons (e.g.
  `MultiBarBottomLeftButton1`) no longer triggers `ADDON_ACTION_BLOCKED` on
  `ACTIONBAR_PAGE_CHANGED` or `UPDATE_BINDINGS`; pending work runs on
  `PLAYER_REGEN_ENABLED`. Equipped-item glow and hotkey abbreviation post-hooks
  also skip combat so they do not taint secure buttons (fixes
  `SetShown`/`SetAttribute` blocks on bar hover).
- **Core — Plugin Manager:** canvas labels no longer show a duplicate black
  shadow behind the text (standard GameFont strings instead of manual shadow
  duplicates).
- **Inventory — Durability:** the Character-pane durability tab now populates on
  first login without `/reload`, using the same bootstrap events as Blizzard's
  durability frame (`UPDATE_INVENTORY_ALERTS`, `PLAYER_ENTERING_WORLD`) plus a
  deferred refresh when the inventory API is not ready yet. Tooltip repair costs
  now read `TooltipData.repairCost` and `GetRepairAllCost()` per 12.0.7 APIs,
  with per-slot costs shown beside each durability percentage.
- **Automation — Quick Quest:** gossip and greeting handlers now select one quest
  per interaction and chain the next after each accept or turn-in, fixing NPCs
  that offer multiple quests (e.g. two available quests on the same gossip list).
  Gossip offers no longer wait on `C_QuestLog.GetQuestDifficultyLevel` (returns 0
  before accept); they use `GossipQuestUIInfo` from `C_GossipInfo` instead.
  Warband/account-completed quests on an explicit gossip or greeting list are no
  longer skipped when account-completed tracking is hidden on the minimap.
  `/nex quickquest` toggles chat debug for gossip/accept tracing.
- **Queue Timer:** aligned with Blizzard 12.0.7 LFG/PvP ready popups — listens for
  `LFG_PROPOSAL_UPDATE`, refreshes after `LFGDungeonReadyPopup_Update`, bootstraps
  an active pop after `/reload`, clears PvP state when confirm ends, and stops the
  OnUpdate ticker properly when the queue ends (hidden frames still ticked before).
- **Unit Frames — Player Cast Bar:** backs off while Blizzard's
  `OverlayPlayerCastingBarFrame` replaces the player bar (talent/spec commits,
  crafting, override action bar) so our read-only mirror does not fight
  `SetAndUpdateShowCastbar(false)` on the Edit Mode-managed frame.
- **12.0.7 — Slug text shadows (UI pass):** minimap zone text, Ctrl+wheel volume
  readout, and LFG queue timer now use `F.CreatePlainFS` like Stats/Clock so
  drop shadows stay visible on Slug-rendered text. AFK Camera overlay strings
  migrated the same way; the 30-minute logout countdown no longer shows a leading
  minus and starts when AFK begins, not when the overlay opens. Inspect average
  item level uses PlainFS; the character-sheet ilvl value no longer forces a broken
  `SetShadowOffset`. Quest Navigation ETA copies Blizzard's `DistanceText` shadow
  on a `BACKGROUND` layer instead of PlainFS to avoid ghosting on world-anchored
  3D text. Buff Reminder glow now tracks the red border ring, not the icon.
- **Inomena-inspired QoL (Tier 1):** Smart Fishing (soft-target + interact rebind
  while channeling), Auction House current-expansion search fallback, smart repair/
  mailbox minimap tracking, hero talent right-click swap, Popup QoL (sub-toggles),
  system chat talent-learn filter, NPC spawn age on Shift tooltips, and utility
  gossip auto-select IDs in Quick Quest (Nerub skip, D.R.I.V.E, etc.).

---

## [1.4.0] — 2026-06-16

Third-party plugin support lets other authors extend NexEnhance as separate
addons, with a Plugin Manager page in settings and a starter template in the
repo.

### Added

- **Core — Plugins:** third-party authors can ship separate addons that call
  `NexEnhance:RegisterPlugin(...)` to hook into the same profile DB, lifecycle,
  events, and settings builder as built-in modules. A **Plugins** settings group
  and **Plugin Manager** canvas list installed extensions; `/nex plugins` lists
  them in chat. Starter template: `Examples/NexEnhancePluginTemplate/`.

---

## [1.3.0] — 2026-06-13

Three new micro-button datatexts — guild, friends and a wealth tooltip — turn the
menu bar into an information hub, plus a loot quality-of-life pass: auto-greeding
low-rarity drops and a compact, skinned replacement for Blizzard's group-loot
roll bars. The world map and your bags can now be dragged straight off their
title bars without entering Edit Mode.

### Fixed

- **Chat / Chat Filter:** migrated 12.0.7-deprecated globals to namespace APIs —
  `C_BattleNet.InviteFriend` (keyword auto-invite) and
  `C_PartyInfo.IsGUIDInGroup` (friend/group exemption in the spam filter).
- **Unit Frames — Class Colours:** audited against 12.0.7 FrameXML — added
  `UNIT_FACTION` / `UNIT_CONNECTION` refresh, party vehicle `UpdateArt` re-tint
  hook, compact-frame threat-colour deferral, and `UnitTreatAsPlayerForDisplay`
  class colouring to match Blizzard's compact path.

### Added

- **Filters — Chat Filter:** settings panel now includes scrollable keyword lists
  for the blacklist and the trade-channel whitelist — one keyword per line, with
  a **Restore Default Keywords** button for the built-in spam set. `/nexfilter`
  still works for quick edits.
- **Filters — Chat Filter:** ships a curated default keyword list for current
  services/trade boosting spam (WTS carries, Mythic+, raid bundles, gold-only
  payment lines, commercial links like WowVendor/Trustpilot/discord.gg, and
  copy-paste booking CTAs). Keywords merge in automatically on first load;
  matching is now case-insensitive. A message still needs to hit your configured
  match threshold (default 3) before it is hidden, so short LF/LFW craft lines
  stay safe. Restore the built-ins anytime with `/nexfilter defaults`.
- **DataText — Guild:** the Guild micro button now shows your online member count,
  and hovering it opens an ElvUI-style roster tooltip — name, level (difficulty
  coloured), class colour, zone and online/AFK/mobile status, sorted by name
  (hold **Shift** for rank and public/officer notes). The guild message of the day
  shows up top (toggle), and the list collapses past a configurable member count.
  The button's native click behaviour is untouched, and every roster read is
  secret-value safe.
- **DataText — Friends:** hovering the social / Quick Join button opens a friends
  roster tooltip that mirrors ElvUI's grouping — Battle.net friends bucketed by
  the game they're playing (WoW characters class-coloured and zoned) above your
  in-game friends. Purely additive; the button keeps its native click.
- **DataText — Currency & Gold:** a wealth tooltip on the Character micro button
  showing session gold gained/lost, a per-character gold rollup (stored
  account-wide, class-coloured and sorted by amount), faction and server totals,
  Warband bank gold, the live WoW Token price and your backpack-tracked
  currencies. Reads are Midnight secret-aware — `GetMoney()` and currency amounts
  that turn secret in combat/instances are skipped instead of being stored or
  compared. Adapted from ElvUI's Gold and Currencies datatexts.
- **Automation — Auto Greed:** automatically rolls Greed (or Disenchant) on
  low-rarity group-loot drops so you're not clicking the same buttons all night.
  Defaults to max level only, Uncommon (green) Bind-on-Equip items, and prefers
  Disenchant when available; optional toggles cover rares, BoP items and
  auto-confirming the soulbound/disenchant prompts. It only confirms rolls it
  started itself. Off by default. Refactored from
  [ShestakUI](https://github.com/Wetxius/ShestakUI)'s AutoGreed (originally by
  Tekkub). Item quality that reads secret in instances is left for the player
  rather than guessed.
- **Miscellaneous — Loot Roll:** replaces Blizzard's group-loot roll frames with
  NexEnhance's own compact, skinned bars — an item icon (item tooltip with
  Shift-compare), a quality-coloured timer bar showing item level and stack count,
  and Need / Greed / Disenchant / Transmog / Pass buttons that grey out when
  unavailable. Bars stack from a draggable Edit Mode anchor, recycle through a
  pool, and queue when there are more rolls than your configured bar count. Width,
  height and max bars are configurable, and `/nex lootroll` spawns demo bars so
  you can position and preview them. Re-implemented from
  [ElvUI](https://github.com/tukui-org/ElvUI)'s LootRoll. Secret-value safe.
- **Action Bars — Extra Quest Button:** an optional, keybindable button that
  surfaces the closest usable quest item from your log (the one Blizzard buries in
  the objective tracker), so a single bind uses whatever the current objective
  needs. It wears the same gold HUD action-bar art as the rest of the bars, shows
  the item's cooldown, stack count, hotkey and a red range tint, and lives on its
  own draggable Edit Mode anchor with configurable size, zone/tracked-only filters
  and distance. The button is bound to your **Extra Action Button 1** keybind and
  hides itself when nothing applies. Off by default. Ported from p3lim's
  [ExtraQuestButton](https://github.com/p3lim-wow/ExtraQuestButton) (with NDui's
  earlier plugin as a reference): includes p3lim's target-item, replacement,
  priority and current quest data, while keeping NexEnhance's secure-frame and
  Secret-value guards.
- **Miscellaneous — Achievement Back Button:** a browser-style **Back** button on
  the Achievements frame header. As you click through categories and achievements
  it quietly records where you've been, and the button retraces that history one
  step at a time — restoring the category, the selected achievement and both scroll
  positions. It greys out when there's nowhere left to go back to. Adapted from
  LudiusMaximus' [Achievements Back Button](https://www.curseforge.com/wow/addons/achievements-back-button)
  onto NexEnhance's framework (load-on-demand handling, pure `hooksecurefunc`, no
  stray globals).
- **Miscellaneous — Hide UI Elements:** optional toggles (all **off** by default)
  for default UI bits people often want gone — the buff **collapse/expand arrow**
  (`BuffFrame.CollapseAndExpandButton`), the bottom-right **Micro Menu & Bags**
  cluster (`MicroMenuContainer` + `BagsBar`), and the incoming **damage / healing
  numbers** that flash over your **player portrait** (separate toggles, via a
  post-hook on Blizzard's `CombatFeedback_OnCombatEvent`). All only change
  visibility — nothing is destroyed — and are kept hidden against Blizzard/Edit Mode
  re-showing them. The micro/bags hide is deferred out of combat since the bag
  buttons can be protected. (The target frame has no combat feedback to hide.)
- **Miscellaneous — Menu Buttons:** the unit right-click menu gains quick social
  actions as real, brand-coloured entries — **Add Friend**, **Guild Invite**
  (labelled with your guild's name), **Copy Name** and **Whisper** — adding only
  the options Blizzard's menu for that unit type is missing (self, target, party,
  friend, raid, …). Built on the supported `Menu.ModifyMenu` API so entries are
  injected taint-free, and uses the live `C_GuildInfo.Invite`; names that read
  secret in instances simply omit the entries. Adapted from KkthnxUI/NDui.

### Changed

- **Action Bars — Equipped Item Border:** the faint green border Blizzard puts on an
  action button holding an equipped item is replaced with a brighter green copy of the
  same IconFrame border art (`UI-HUD-ActionBar-IconFrame-Border`), sized to match our
  skinned frame. Driven by a `hooksecurefunc` post-hook on `ActionBarActionButtonMixin:Update`,
  so it follows live action drag/drop and equips, and it reads the equipped state from
  `C_ActionBar.IsEquippedAction` with a Secret-value guard. New toggle (on by default)
  under Action Bars; turning it off restores Blizzard's default border.
- **Announcements — Rare Alert:** you can now **right-click** the rare popup to
  share the rare and a clickable map-pin link in chat — your group when grouped
  (instance/raid/party), otherwise General chat. The shared message uses a
  default-named map pin so the server doesn't drop it, and a short cooldown keeps
  repeated clicks from flooding the channel. Left-click still targets/tracks; the
  new toggle (on, under the popup) can be edited in the panel or Edit Mode dialog.
  Cherry-picked from [Plumber](https://www.curseforge.com/wow/addons/plumber)'s
  rare announcement by Peterodox.
- **Announcements — Quest Notification:** objective-progress announcements now diff
  Blizzard's structured quest objectives (`C_QuestLog.GetQuestObjectives`) off the
  debounced `QUEST_LOG_UPDATE` scan instead of pattern-matching localized
  `UI_INFO_MESSAGE` text. It's locale-independent, no longer parses a string that
  can be a Midnight Secret value in instances, fires for every quest regardless of
  whether it's tracked, and posts the quest name alongside each objective.
  High-count objectives still report roughly every 20%, and percent-style "progress
  bar" quests are announced too. The module stays idle while you're solo (it only
  announces when there's a group). The old Dragonflight-only dragon-glyph
  collection notice was removed.
- **Maps — World Map:** the windowed map can now be dragged directly by its title
  bar — no Edit Mode required — and the position is saved across reloads. The old
  Edit Mode mover for the map was removed in favour of this; the maximized map
  stays centred and is left to Blizzard. Drag pattern inspired by
  [NDui](https://github.com/siweia/NDui) by siweia.
- **Miscellaneous — Drag Frames:** your bags are now draggable too — grab the
  combined bag, or the backpack in the separate-bag layout (which moves the whole
  cluster). Bag positions intentionally **snap back** to Blizzard's default on the
  next bag open rather than persisting, matching the rest of Drag Frames.
- **DataText — Experience Bar:** now tracks Midnight **Housing Experience**. When you
  have a tracked house the bar fills toward the next house level, uses the same
  `Experience` / `Remaining` tooltip formatting as the normal XP bar, and shows in a
  gold tone matching the housing UI. The Housing Experience tooltip also includes
  neighborhood **Endeavor Progress** from Blizzard's initiative API. Priority is XP
  first (so levelling is unaffected), then Housing Experience — it's an explicit
  opt-in via your tracked house — then reputation/honor/Azerite. Built on Blizzard's
  own `C_Housing` and `C_NeighborhoodInitiative` APIs.

### Fixed

- **DataText — Stats & Clock:** minimap FPS/latency and clock text now use a
  manual drop-shadow duplicate instead of `SetShadowOffset`. On 12.0.7 the API
  still reports `1, -1` and Slug CVars do not change the look, but the engine
  draws Slug-rendered shadow flush on the glyphs anyway; offsetting a solid-black
  copy behind the main string restores a readable shadow.
- **Action Bars — Extra Quest Button:** the cooldown swipe swept over the gold
  IconFrame border. The border is the button's `OVERLAY` normal texture while the
  Cooldown is a child frame (which always renders above the parent's textures), so
  the swipe and its bright leading edge drew on top of the chrome. The swipe is now
  inset to the frame's inner opening and the leading edge is disabled, so it stays
  neatly inside the gold border.
- **DataText — Time:** the world-map quest-timer tooltip read a widget through a
  misnamed Blizzard API (`GetTextureAndTextWidgetVisualizationInfo`), which silently
  never resolved. Corrected to the real `GetTextureAndTextVisualizationInfo` so
  "texture-and-text" widget timers (verified against Blizzard's own widget code)
  display again.
- **Automation — Auto Vendor:** now yields to Bagforge's Vendor module when Bagforge
  has the matching automation enabled. If Bagforge is handling auto-repair or
  auto-sell junk, NexEnhance skips that same action at runtime instead of double
  repairing/selling, without changing your NexEnhance settings.
- **Inventory — Item Level:** item quality and the inspected unit's GUID can read as
  Secret inside instances on 12.0, and the loot/bag/inspect paths compared them
  directly, which could throw a Lua error mid-loot. Every quality and GUID read is
  now Secret-guarded (matching Auto Greed and Loot Roll), and loot slots with no
  hyperlink yet are ignored until Blizzard finishes populating them. If a value
  can't be read, the overlay is simply skipped instead of erroring.
- **Tooltip:** the status-bar skin no longer uses `BackdropTemplate` children.
  Blizzard's backdrop mixin divides by `GetWidth()` / `GetHeight()` in Lua, which
  can be Secret while the world-cursor tooltip updates under Midnight. The bar now
  uses plain texture strips, avoiding the tainted secret arithmetic crash.
- **Automation — Quick Quest:** "Auto-Skip Story Gossip" now actually fires. It
  only matched a red `<Skip ...>` marker pinned to the very start of an option in
  the legacy hex-red colour, so it missed campaign skips with white lead-in text
  (e.g. the Argus "<Skip the Argus Campaign>" option), the modern `RED_FONT_COLOR`
  markup Blizzard now uses, and plain (uncoloured) skips like the Legion
  "<Skip the scenario and begin your journey on Broken Shore.>" option. Detection
  now keys off the angle-bracket marker itself anywhere in the option text, which
  is both colour- and locale-independent, with a Secret-value guard on the option
  name. The follow-up "Skip ahead?" confirmation popup these skips raise is
  also auto-accepted now (mirroring Blizzard's `GOSSIP_CONFIRM` handling) so the
  skip completes hands-free — but only for free skips: a confirmation that costs
  money, or whose cost reads Secret, is still left for you to confirm. Each skip
  now prints a chat line naming the NPC ("Skipped story dialogue from …") so you
  know it happened. Verified against Blizzard's 12.0 gossip resources.

### Performance & Internals

- **Action Bars — Extra Quest Button:** quest, zone-change and player `UNIT_AURA`
  events were each triggering a full closest-quest-item scan, so an aura-heavy pull
  could run that scan many times a second. They're now coalesced through a 0.1s
  debounce into a single scan, while target changes and bag updates keep their own
  immediate handlers so the button still feels instant.
- Audited the whole addon against Blizzard's 12.0 Resources for Secret-value and
  taint correctness, API drift and hot-path costs (no further issues found beyond
  the two above); cleaned up a couple of harmless linter false-positives.
- Full-UI consistency pass: localised the only `C_Item` call left in the Extra
  Quest Button's per-frame range check, aliased the Tooltip Item Level scan's
  `C_Item` lookups and dropped its per-artifact relic table allocation, and tidied
  cryptic constants and sparse hooks in the tooltip modules with explanatory
  comments. Behaviour unchanged.

---

## [1.2.9] — 2026-06-11

A new Guild Invite Filter auto-declines guild invites from strangers while letting
friends and guildmates through, with live statistics on its options page, plus a
Quick Join module that smooths out Blizzard's Group Finder. Under the hood, all of
NexEnhance's Midnight Secret-Value handling now lives behind one shared helper set
(modelled on oUF's), Profiles gained AceDB-style actions with compact compressed
exports, and frames now standardise on Blizzard's stock tooltip border art.

### Added

- **Automation — Guild Invite Filter:** new module (off by default) that
  auto-declines guild invites from players who aren't trusted, while letting
  character friends, Battle.net friends and your current guild members through.
  Each trusted source is its own toggle, with an optional chat announcement and
  sound when an invite is declined. While enabled it forces Blizzard's own *Block
  Guild Invites* off (Blizzard's option drops invites before the addon sees them),
  remembers your prior setting per-character, and restores it when you disable the
  module — even across a reload. A Statistics section on its options page shows
  lifetime blocked/allowed totals and the last blocked invite.
- **Automation — Quick Join:** new module (off by default) for the Premade Groups
  finder, adapted from [NDui](https://github.com/siweia/NDui). Double-click a
  search result to apply (hold **Alt** to review the sign-up note instead of
  sending it), with a one-time tip pointing the shortcut out. An **Auto-accept**
  check on the applicant viewer auto-invites applicants while you're the group
  leader. **Auto-hide LFG Popups** dismisses throwaway informational and
  expired-listing popups and closes the finder once you accept a listed-group
  invite. **Show Leader Rating** prints the leader's Mythic+/PvP rating on each
  result with a cross-faction crest and trims the long activity prefix.
- **Miscellaneous — `/nex abandonquests`:** clears every abandonable quest from
  your log at once (skipping world quests and party-sync-locked quests),
  confirming with a yes/no popup first since abandoning also destroys quest items.

### Changed

- **Miscellaneous — Profiles:** profile management now follows AceDB's clearer
  workflow — create, switch, copy from another profile into the current one, copy
  current as a new name, reset current to defaults, or delete unused profiles.
  Export strings now use bundled LibSerialize and LibDeflate for compact printable
  backups, while still accepting older `!NEX1!` Base64 exports.
- **UI chrome:** frames now standardise on Blizzard's stock
  UI-Tooltip-Border / UI-Tooltip-Background art. The custom pixel-border and addon
  NineSlice helper paths were removed, covering the minimap, chat edit box, chat
  bubbles, the profile/install/changelog/credits/copy windows, Details, Reminder,
  Rare Alert and the tooltip status bar.

### Fixed

- **Maps — Minimap:** the instance-difficulty flag reskins with our Flag texture
  again — it was targeting a non-existent `.Instance` child, but the current
  `InstanceDifficultyMixin` exposes the normal flag as `.Default` (alongside
  `.Guild` and `.ChallengeMode`).
- **Inventory — Item Level:** fixed item level and bind status not appearing on
  bank and warband bank items — the slots now update off `ItemButton:UpdateCooldown`
  (matching Unusable Items), hook both the generate and refresh-all bank paths,
  and install on `BANKFRAME_OPENED` so the load-on-demand bank UI is covered.
- **Tooltip (secret values):** fixed taint thrown from Blizzard's own tooltip
  widget code (`GameTooltip_AddWidgetSet`/`ClearWidgetSet` and
  `EmbeddedItemTooltip_UpdateSize`) when our hooks run while widget geometry is
  secret (e.g. map POI / world-event tooltips). The guard now detects secret-value
  errors case-insensitively, and `GameTooltip_AddWidgetSet` preserves Blizzard's
  numeric overflow return contract when suppressing them.
- **Tooltip (secret values):** health text no longer blanks out when `UnitHealth`
  is a 12.0 secret value (in combat or instances); secret numbers are shown safely
  via number abbreviation instead of being discarded.
- **Tooltip:** health text no longer flickers or briefly shows the wrong values
  while the tooltip is refreshing (for example when jumping in-game); it now reads
  only the unit attached to the tooltip/status bar instead of guessing from
  mouseover.
- **Tooltip (secret values):** hiding the status bar no longer tests `IsShown()`
  on a bar that can inherit secret aspects after Blizzard writes secret health into
  it, and tooltip cleanup no longer touches Blizzard state at unsafe times.
- **Announcements — Rare Alert:** showing/hiding the secure click-to-target popup
  in combat is now safe — it skips showing in combat and defers hides until combat
  ends. Also fixed Edit Mode click/drag conflicts where the secure overlay could
  sit above the mover and block moving the banner.
- **Automation — Faster Loot:** locked-slot handling now works across client
  variants of `GetLootSlotInfo`.
- **Maps — Minimap (Collect Buttons):** the AllTheThings button no longer shows up
  oversized or escapes the tray — its icon is re-clamped to the slot on every open
  and its self-positioning is stopped once parked.
- **Automation — Faster Movie Skip:** enabling it from the Settings panel now
  works live instead of needing a reload.
- **Miscellaneous — Social Colours:** the friends/who lists no longer do O(n²) work
  refreshing — the scroll rows are enumerated once per refresh.

### Performance & Internals

- **Core — Secret Values:** consolidated all Midnight Secret-Value handling into
  one shared helper set on `F` (modelled on oUF's by Simpy) — `IsSecretUnit`,
  `IsSecretTable`, `CanAccessValue` and `HasSecretValues` alongside the existing
  `IsSecret`/`NotSecret`. The Tooltip and Cooldowns modules route through these, so
  there's a single source of truth and no module rolls its own raw secret check.
- **Core — Options:** option pages gained a read-only description row that can grey
  out with the setting it belongs to (used for the Guild Invite Filter statistics).
- **Core — Help tips:** added a one-shot `F.ShowHelpTip` helper for account-wide
  tutorial nudges shown once and then remembered; tips raised this way are
  automatically spared by the Hide Help Tips feature. Used to point out Quick
  Join's double-click, chat quick-scroll, the chat copy button, Edit Mode movers,
  the hidden minimap click/scroll gestures, and the bag delete-cheapest button.

---

## [1.2.8] — 2026-06-10

Brings the Clock (Time) datatext up to Midnight — Stormarion Assault, Abundance
and Void Incursion timers, active world-boss tracking, Void Assault weeklies and
a delve rework — with older world events tucked behind a toggle. Also sharper
rare alerts, item level and bind status on the warband bank, and more Midnight
secret-value hardening across tooltips. The rare popup is now a proper
click-to-track banner with Edit Mode settings, faster loot is more reliable, the
loot frame can grow taller, known housing decor is detected, and tooltip health
text works with secret health values instead of blanking out.

### Added

- **DataText — Clock (Midnight world events):** the lockout tooltip now tracks
  current Midnight world content — Stormarion Assault, Abundance (e.g. Herbalism
  Grotto) and Void Incursions — reading live countdowns and progress from the
  POI/event widgets instead of guessing, and labelling impending vs. active
  incursions.
- **DataText — Clock (active world boss):** detects the world boss that is up
  right now via a map POI scan, shown alongside the existing saved world-boss
  lockout.
- **DataText — Clock (Void Assaults):** weekly Void Assault meta and its sub-
  objectives are tracked with a fail-safe so the line is skipped when the quest
  data isn't available.
- **DataText — Clock (weekly "Choose Your Path"):** the lockout tooltip now
  tracks Midnight's headline weekly — the Unity Against the Void meta from Lady
  Liadrin. The meta's completed flag drives the Complete/Incomplete status, and
  whichever path you picked (e.g. Midnight: Delves) shows its objective progress
  underneath while it's in your log. Only shown once you're engaged with it, so
  it never nags low-level alts.
- **DataText — Clock (legacy world events):** older expansion world events
  (Legion invasions, faction assaults, elemental storms, feasts and the like)
  now sit behind a "Show Legacy World Events" toggle, off by default.
- **Inventory — Loot Frame:** new module that lets Blizzard's default loot
  window grow taller so more loot fits on one page without scrolling. Includes a
  live toggle and a configurable max height percentage.
- **Inventory — Delete Cheapest:** new module that adds a goblin-head button to
  the bag frame (left of the search box, styled to match Blizzard's cleanup
  button). Left-click finds and (after a confirmation showing the item) destroys
  the lowest vendor-value item in your bags; right-click just previews it in
  chat. Per-item-class protection toggles guard whole categories, with quest
  items protected by default.
- **Action Bars — Range Coloring:** new module (tullaRange-style) that tints
  action-button icons and hotkeys when an action is out of range, out of power,
  or unusable. Driven by Blizzard's event-based range check (no per-frame
  polling) and hardened for Midnight — secret usability/range values in combat
  fall back to the neutral tint instead of erroring. Colors, hotkey tinting and
  pet-bar coverage are all configurable; off by default.
- **Skins — Enhanced Color Picker:** Blizzard's color picker gains R/G/B input
  boxes (0-255) that drive the wheel and update live as you drag, plus a row of
  click-to-apply class-color swatches with name tooltips. The native hex box is
  reskinned and slotted in as the aligned 4th row of the column (swatch / R / G /
  B / #), and the stacked color swatch becomes a single box-styled header.
  Reworked from NDui against the current frame.
- **General — Hide Help Tips:** new toggle (off by default) that suppresses
  Blizzard's tutorial and help-tip pop-ups (micro-button alerts, new-player
  pointers, panel hints) and the tutorial CVars, while leaving NexEnhance's own
  tips (e.g. the low-durability nudge) intact.
- **General — Widget Movers:** new toggle (off by default) that makes Blizzard's
  below-minimap and top-center widget displays draggable in Edit Mode via our
  mover, opting them out of the legacy frame-position manager so they stay where
  you put them. The power-bar widget is intentionally left to Blizzard's native
  Encounter Bar Edit Mode system. Ported from NDui's `UIWidgetFrameMover`.
- **Unit Frames — Player Cast Bar:** new toggle (off by default) that mirrors
  Blizzard's player cast bar icon above the bar and cast time beneath it, with a
  configurable icon size. Purely cosmetic (Blizzard keeps ownership of cast
  state/timing, so no secret-value concerns) and hides during Edit Mode.
- **Unit Frames — Level Colours:** new module that colours the Target / Focus /
  Boss level number by classic creature difficulty (red → grey vs your level)
  via `GetCreatureDifficultyColor`, instead of Blizzard's newer trivial/easy
  buckets. An **Always Show Level** sub-toggle replaces Blizzard's skull on
  high-level targets with the actual number (or a red `??` when the game hides
  it) and appends classification markers (`Boss` / `R+` / `+` / `R`), so you
  always get info. Post-hooks `CheckLevel` (no fields written onto
  the Edit Mode-managed frames), only touches the level FontString/skull
  cosmetically, and is secret-value hardened — it leaves Blizzard's display when
  level reads are restricted in combat or instances.
- **Inventory — Already Known:** housing decor items now tint green when already
  owned. The check uses the Midnight housing catalog API when available and
  counts both stored decor and decor already placed in a house.
- **Announcements — Rare Alert popup:** rare alerts can now show a movable
  popup with a 2D portrait when the rare is visible, falling back to the
  vignette atlas icon otherwise. Left-click can target the rare, optionally mark
  it with a raid marker, and set a TomTom or Blizzard waypoint.
- **Announcements — Rare Alert preview:** `/nex rare` still toggles a sticky
  preview banner, while Edit Mode now shows the banner automatically so it can be
  moved without running the preview command first.
- **Announcements — Rare Alert (sound while alt-tabbed):** an optional toggle
  makes the alert sound audible while WoW is minimised or in the background,
  briefly overriding your background-sound setting and restoring it afterwards.
  Mechanism cherry-picked from RareAlert. Off by default.

### Changed

- **DataText — Clock (timer format):** every countdown in the lockout tooltip
  (daily/weekly resets, saved instances, delves and world events) now uses one
  compact format — `6d 10h`, `10h 30m`, `32m`, `45s` — in consistent white text,
  with status colours kept only for special states (Available, Active, Complete,
  percentages).
- **DataText — Clock (delves):** delve tracking is reworked for Midnight — it
  caps the bountiful-delve list to the four that can be up and de-duplicates
  entries by delve name so the same delve no longer appears twice across
  continent and zone maps. The old War Within coffer-key fragment line was
  dropped (the weekly is now tracked via the Choose Your Path meta above).
- **Announcements — Rare Alert (click-to-target):** hardened the secure target
  click so it works for players who use key-down action casting. The popup now
  forces `ActionButtonUseKeyDown` off for the duration of the click and restores
  it afterwards, so `/targetexact` fires reliably. Cherry-picked from RareAlert.
- **Tooltip — quality border:** the old recipe item-name width tweak has been
  removed; reading and writing tooltip line geometry is fragile under Midnight
  Secret Values and the cosmetic gain wasn't worth the taint risk. The item
  post-call now only tints Blizzard's default border by item quality.
- **Automation — Faster Loot:** reworked the fast-loot path into a paced
  slot-walker inspired by SpeedyAutoLoot. It listens to both `LOOT_READY` and
  `LOOT_OPENED`, handles noisy auto-loot state more reliably, avoids duplicate
  event work and stops cleanly on `LOOT_CLOSED`.
- **Announcements — Rare Alert:** detection is stricter and cheaper. Treasure,
  lore and non-rare vignette atlas types are filtered out, NPC IDs can be parsed
  from vignette GUIDs for the ignore list, and per-rare cooldowns prevent repeat
  spam when flying in and out of range.
- **Announcements — Rare Alert:** Edit Mode integration is cleaner. The
  LibEditMode selection frame is raised above the secure popup overlay while in
  Edit Mode, so the banner can be dragged without disabling click behavior or
  special-casing popup clicks.
- **Tooltip:** the health/status bar text now follows ElvUI's retail-safe model:
  Blizzard updates the bar, NexEnhance post-hooks the health refresh and displays
  secret health values through whitelisted number abbreviation instead of trying
  to inspect them.
- **Tooltip (internal rewrite):** the core module was reworked against ElvUI's
  Midnight Secret-Value model. The accumulated workarounds are gone — the global
  `GameTooltip_AddWidgetSet`/`ClearWidgetSet`/`EmbeddedItemTooltip_UpdateSize`
  pcall wrappers and the `OnSizeChanged`/`canaccessvalue` backdrop guards have
  been removed (untainted Blizzard code may read secrets; we just stopped tainting
  its layout path). Triple unit resolution collapsed to `GetDisplayedUnit` +
  `GetUnitToken`, the health-text path was simplified, and the status-bar border
  is now a stock tooltip backdrop with no Lua size maths. The look and options are
  unchanged.
- **Miscellaneous — Credits:** updated credits for recent inspiration and
  cherry-picks, including SpeedyAutoLoot, Improved Loot Frame and RareScanner.

### Fixed

- **Maps — Minimap:** the instance-difficulty flag reskins with our Flag texture
  again. It was targeting a non-existent `.Instance` child; the current
  `InstanceDifficultyMixin` exposes the normal flag as `.Default` (alongside
  `.Guild` and `.ChallengeMode`).
- **Inventory — Item Level:** fixed item level and bind status not appearing on
  bank and warband bank items. The bag/bank slots now update off
  `ItemButton:UpdateCooldown` (matching Unusable Items), hook both the
  generate- and refresh-all paths for bank tabs, and install their hooks on
  `BANKFRAME_OPENED` so the load-on-demand bank UI is covered.
- **Tooltip (secret values):** fixed Secret-Value taint thrown from Blizzard's
  own tooltip widget code (`GameTooltip_AddWidgetSet`, `GameTooltip_ClearWidgetSet`
  and `EmbeddedItemTooltip_UpdateSize`) when our hooks run while widget geometry
  is secret — for example on map POI / world-event tooltips. These paths now
  swallow only secret-value errors (case-insensitive, covering both
  `SetWidth(secret)` and secret height math), and `GameTooltip_AddWidgetSet`
  preserves Blizzard's numeric overflow return contract so `AreaPoiUtil` does
  not crash doing arithmetic on an error string.
- **Tooltip:** fixed missing health text on `GameTooltipStatusBar`, including
  secret health values returned by Midnight combat/instance APIs. Secret values
  are displayed safely instead of being discarded by `F.NotSecret` guards.
- **Tooltip:** fixed health text flickering or briefly showing the wrong values
  while the tooltip is refreshing (for example when jumping in-game). The health
  text now follows Blizzard/ElvUI's `UpdateUnitHealth` path and only reads the
  unit attached to the tooltip/status bar instead of guessing from a fresh
  `mouseover` lookup.
- **Tooltip:** fixed secret-value taint caused by tooltip cleanup paths touching
  Blizzard tooltip/widget state at unsafe times, including map POI/event tooltip
  hide/clear paths.
- **Tooltip:** hid the tooltip status bar without branching on `IsShown()`, since
  the bar can inherit secret aspects after Blizzard writes secret health values
  into it.
- **Announcements — Rare Alert:** fixed combat-blocked popup show/hide paths for
  the secure targeting overlay by skipping show in combat and deferring hides
  until `PLAYER_REGEN_ENABLED`.
- **Announcements — Rare Alert:** fixed Edit Mode click/drag conflicts where the
  secure overlay could sit above LibEditMode's mover and prevent moving the
  popup.
- **Automation — Faster Loot:** fixed locked-slot handling across client return
  variants for `GetLootSlotInfo`.
- **Maps — Minimap (Collect Buttons):** fixed the AllTheThings minimap button
  showing up oversized and escaping the tray. Its icon is re-clamped to the slot
  on every tray open (so addons that resize their own button after our skin
  can't overflow the grid), and its self-positioning is neutralised once parked
  so it stops re-anchoring itself to the minimap.
- **Automation — Faster Movie Skip:** fixed the module not turning on live —
  enabling it from the Settings panel now installs its hooks immediately instead
  of requiring a reload.
- **Miscellaneous — Social Colours:** fixed the friends/who list refresh doing
  O(n²) work (it re-walked the whole row list for every row); it now enumerates
  the scroll rows once per refresh.

### Performance & Internals

- **Core — Object pool:** rebuilt `F.CreatePool` into a Plumber-style pool that
  tracks active/free objects, injects an `obj:Release()` helper, and adds
  `ReleaseAll()`/`EnumerateActive()` with optional acquire/release hooks.
- **Core — Signal bus:** added an internal pub/sub callback bus
  (`ns:RegisterCallback` / `TriggerCallback` / `UnregisterCallback`) adapted from
  Plumber's CallbackRegistry, so modules can react to one another (e.g. setting
  changes) without holding hard references. Every settings change now broadcasts
  a `SettingChanged.<module>.<key>` signal, and several read-outs (the Settings
  landing-page module count, the minimap mail/clock indicator and button-tray
  position) update live in response.
- **Automation — Quick Quest:** now uses the shared addon event dispatcher
  instead of its own private event frame, and only registers its quest events
  while the module is enabled (it defaults off, so it no longer wakes on
  `QUEST_LOG_UPDATE` and friends for players who never turn it on).
- **Action Bars:** the hotkey-abbreviation pass is now memoised per keybind
  string, so the ~19-rule substitution runs once per unique bind instead of on
  every `SetText` (bar page changes, binding updates, vehicle swaps).
- **Chat — Channels:** URL highlighting now does a cheap plain-text probe before
  running its three link patterns, skipping the expensive passes on the common
  case of a line with no link.
- **DataText — Clock & Stats:** while hovered, the heavy tooltips now rebuild on
  a throttle (clock lockout/world-event scan every 30s; the addon-memory scan
  every 5s) instead of every timer tick, while the visible clock/FPS/latency text
  keeps updating as before. The Stats memory list still expands instantly when
  you hold Shift.

---

## [1.2.7] — 2026-06-08

Adds a full **Profiles** system — create, copy, switch, delete and import/export
your settings as a single copy-paste string — and a ground-up **AFK Camera**
rework: a resolution-independent cinematic screen with a companion battle pet
idling at your side.

### Added

- **Automation — Cancel Bad Buffs:** automatically removes cosmetic costume and
  holiday transforms (Hallow's End costumes, Mohawked!, Turkey Feathers,
  Noblegarden disguises, Orb of Deception and similar) while you're out of
  combat, with an optional chat announcement. Matches by spellID and only acts
  out of combat. Off by default. Reworked from
  [ShestakUI](https://github.com/Wetxius/ShestakUI) by Wetxius / Shestak.
- **Miscellaneous — Profiles:** create, copy, switch and delete settings
  profiles, and import/export any profile as a single copy-paste string for
  backups or sharing. New profiles and copies won't overwrite an existing name —
  they report an error instead. Available on the new Profiles settings page or
  via `/nex profile`.
- **Miscellaneous — AFK Camera companion pet:** a random battle pet from your
  Pet Journal now idles beside your character on the AFK screen. If you haven't
  collected any pets, it falls back to Legionnaire Murky (Horde) or
  Knight-Captain Murky (Alliance).

### Changed

- **Miscellaneous — AFK Camera:** reworked into a resolution-independent
  cinematic letterbox — gradient edge fades, a hero-shot character model, a
  class rune backdrop, faction crest, clock and date, a 30-minute logout
  countdown, rotating account statistics and a whisper log — built from fixed,
  edge-anchored layout regions so it scales cleanly across all resolutions.

---

## [1.2.6] — 2026-06-07

A big feature drop — **Rare Alert**, **Delves Automation** and a tooltip
**Vendor Location**, smarter **Quick Quest** and an **Experience Bar fade** —
alongside the minimap squaring, queue-eye polish and a minimap Clock and Location
readout, on top of a performance and stability pass: flatter memory use over long
sessions, lighter chat and minimap hot paths, and a fix for Communities chat
hyperlink tooltips.

### Added

- **Maps — Minimap overhaul:** the minimap is now squared off with a **Blizzard
  tooltip-style border** matching our chat bubbles. The default chrome is fully removed
  (ring, zoom buttons, compass, clock and zone bar), and the mail/indicator,
  instance difficulty, calendar, streaming and queue-status regions are tidied
  into the corners. The LFG/queue eye spins a dungeon icon while queued, and a
  coloured glow pulses for combat (red) or pending mail / calendar invites
  (yellow).
  Adapted from [KkthnxUI](https://github.com/Kkthnx-Wow) by Kkthnx. Positioning
  is left to Blizzard's Edit Mode.
- **Maps — Collect Buttons:** sweeps stray addon minimap buttons into a fade-in
  tray behind a small corner toggle, squared and bordered to match the UI. The
  scan runs a few times after login (so late-loading LibDBIcon buttons get
  picked up), Blizzard frames and our own widgets are left alone, and you can
  choose which corner the toggle hugs. Adapted from
  [KkthnxUI](https://github.com/Kkthnx-Wow) by Kkthnx.
- **DataText — Clock:** a minimap clock that follows your 12/24-hour and
  local/realm time CVars (turns red when you have pending calendar invites).
  Hover for the full date, local & realm time, saved raid / dungeon / world-boss
  lockouts, daily / weekly resets, Delves, Delver key progress, Timewalking
  weekly checks and quest completions; hold Shift for storms, hunts, feast and
  invasion timers. Left-click opens the calendar, middle-click the Great Vault,
  right-click the time manager. Adapted from [KkthnxUI](https://github.com/Kkthnx-Wow)
  by Kkthnx.
- **DataText — Location:** zone and sub-zone text pinned inside the top of the
  minimap, tinted by the zone's PvP status (sanctuary blue, friendly green,
  hostile/contested red/yellow). Can be shown always or only on mouseover.
  Adapted from [KkthnxUI](https://github.com/Kkthnx-Wow) by Kkthnx.
- **Chat — Quick Join Button:** the social/quick-join notification button is now
  registered with Edit Mode, so it can be dragged anywhere instead of being
  pinned to the chat corner. Idea from [NDui](https://github.com/siweia/NDui) by
  siweia.
FOr the item level- **Tooltip — Vendor Location:** for special barter/curio items (curios, barter
  tokens and the like), the bag tooltip shows which NPC to turn them in to and the
  zone they're in, and **Ctrl-Click** the item sets a map waypoint on the vendor.
  Concept and item/vendor data from [Plumber](https://github.com/Peterodox/Plumber)
  by Peterodox (data by gifLeo).
- **Automation — Delves Automation:** while inside a Delve, automatically confirms
  the single-choice "borrowed power" popup, with an optional chat announcement of
  the power that was taken. Concept from
  [Plumber](https://github.com/Peterodox/Plumber) by Peterodox.
- **Announcements — Rare Alert:** announces nearby rares and world events the
  moment their vignette appears on the minimap — a centre-screen banner, an
  optional alert sound, and an optional clickable map link in chat — with an
  anti-burst sound throttle and a per-rare re-announce cooldown. Reworked from
  [NDui](https://github.com/siweia/NDui) by siweia, with throttling ideas from
  [Plumber](https://github.com/Peterodox/Plumber) by Peterodox.
- **General — Cast On Key Down:** action buttons can now fire the moment a key is
  pressed instead of when it is released, via the `ActionButtonUseKeyDown` CVar
  (combat-safe; deferred until you leave combat if toggled mid-fight).
- **Action Bars — Skin Extra Buttons:** the Extra Action and Zone Ability
  buttons can now wear the standard action-bar button frame (Blizzard's HUD
  icon-frame, slot and pressed art, tinted gold) instead of their oversized
  one-off artwork, so they match the rest of your bars, with an adjustable
  scale (applied out of combat).
- **Auras — Buff Reminder controls:** the reminder icons are now resizable (an
  **Icon Size** slider in both the Settings panel and the Edit Mode dialog) and
  wear a Blizzard tooltip-style gold border to match the minimap. A new
  `/nex reminder` command toggles sample icons so you can position the anchor and
  preview the look, and the anchor now appears in Edit Mode without entering test
  mode.
- **Chat — Battle.net Pop-up:** the Battle.net friend/online toast is now
  registered with Edit Mode (like the Quick Join button) so it can be dragged
  anywhere.

### Changed

- **Automation — Quick Quest:** smarter automation — accept quests by frequency
  (regular / daily / weekly), protect costly turn-ins (those with a gold or
  currency cost), pick the most valuable reward, and a configurable override key
  (default **Shift**) to suppress automation for a single interaction (or flip it
  to *require* the key). Refinements inspired by
  [Leatrix Plus](https://www.curseforge.com/wow/addons/leatrix-plus) by Leatrix.
- **Miscellaneous — Experience Bar fade:** the bar can now rest dimmed and reveal
  on mouseover, and optionally stay fully visible in combat or while you have a
  target/focus. Fade behaviour adapted from
  [ls_Monobrow](https://github.com/ls-/ls_Monobrow) by lightspark.
- **Performance — Bounded caches:** the link/ID caches behind chat item levels,
  Already Known, guild-news item levels and mount-source tooltips are now
  size-capped, so memory stays flat across long sessions instead of slowly
  growing with every unique item seen.
- **Performance — Buff Reminder:** rapid `UNIT_AURA` changes are now coalesced
  into a single end-of-frame update, cutting redundant scans when many buffs
  land at once.
- **Performance — Stats:** while the readout is hovered, the per-addon memory
  scan refreshes on an interval instead of rescanning and re-sorting every
  second.
- **Performance — Chat Filter:** the repeat-detection rows and socket-text
  builder now reuse internal scratch tables, reducing garbage in spam-heavy
  channels.
- **Maps — Minimap mail icon:** when the Clock DataText is enabled the new-mail
  indicator now sits above the clock instead of overlapping the time text.
- **Maps — Minimap mouse input:** wheel zoom/volume and the middle/right-click
  menus now run on a dedicated overlay instead of being scripted onto the
  minimap directly. Left-click passes through for Blizzard's default ping and
  mouse motion propagates, so pings, mouseover and tooltips keep working. Idea
  from [NDui](https://github.com/siweia/NDui) by siweia.
- **Action Bars — Cooldown Text:** long cooldowns now roll over to a **weeks**
  tier above days, the seconds-to-`mm:ss` switch is configurable (keep showing
  raw seconds like `90` before flipping to `1:30`), and an optional **Scale
  Cooldown Text** mode shrinks the numbers with the button and hides them on
  very small cooldowns. On action buttons the countdown text is also lifted
  above the hotkey and stack count. Refinements from
  [tullaCTC](https://github.com/tullamods/tullaCTC) by Tuller.
- **Skins — Quest Navigation:** the ETA text under the waypoint arrow now has a
  drop shadow so it stays readable over bright backgrounds.
- **Skins — Missing Stats:** the character sheet now surfaces the stats Blizzard
  hides by default — attack power, weapon damage, attack/weapon speed, spell
  power, energy/rune/focus regen and movement speed — while out of combat, and
  tidies the existing readouts with two-decimal rating percentages, an equipped
  - overall item level and a cleaner stat font. Reworked from
  [NDui](https://github.com/siweia/NDui) by siweia against the current retail
  paperdoll without replacing Blizzard's stat table, avoiding 12.0 Secret-value
  taint in combat.
- **Inventory — Junk Icon:** the coin overlay on Poor-quality bag items now
  shows all the time, not just while a merchant window is open.
- **Inventory — Item Level:** gem icons shown on Character and Inspect equipment
  slots now display the socketed gem's tooltip on hover. Enchantable slots that
  are missing an enchant now show a red marker whose tooltip names the slot
  (toggle: *Warn Missing Enchants*).
- **Inventory — Unusable Items:** item icons across bags, bank and warband bank
  tint red for gear your class can't use (wrong weapon/armor type or off-hand
  dual-wield) or that you're below the required level for. Class-restriction data
  reworked from [LibUnfit-1.0](https://github.com/Kkthnx-Wow/KkthnxUI)
  by João Cardoso, resolved to your class once at login.
- **Inventory — Item Level:** the item-level numbers now match the bind-status
  text size and are resizable with a new **Item Level Font Size** slider (12–14).
- **Chat — Quick Join & Battle.net toast:** both now default just above the
  chat's **top-left** corner (raised so they don't overlap), and "Reset to
  default position" returns them there.
- **Performance — Tooltip Icons:** the inline-texture resize pass now skips
  tooltip lines without a texture escape, avoiding needless pattern work on every
  line.
- **Performance — Unusable Items:** the per-item class-restriction cache is now
  size-capped like the other inventory caches, keeping memory flat over long
  sessions.

### Fixed

- **Tooltip — Hover Tips:** hovering item/spell links in the Communities
  (guild/community) chat no longer overwrites Blizzard's own
  `OnHyperlinkEnter`/`OnHyperlinkLeave` handlers; the originals are now
  preserved and chained.
- **Tooltip — Status bar border:** hovering world objects whose tooltip carries
  12.0 secret values (rare vignettes, Delve doors and similar) no longer throws
  a `Backdrop.lua` "arithmetic on a secret number" error. Our status-bar border
  keeps Blizzard's backdrop styling but now skips the resize pass when the bar
  reports secret dimensions.
- **Automation — Delves Automation:** the borrowed-power popup is now auto-
  confirmed reliably. Delve status is read a beat after the
  `WALK_IN_DATA_UPDATE` / world-change events (the walk-in flag is stale at the
  exact moment you zone in), so entering a Delve correctly arms the handler.
- **Inventory — Already Known:** cosmetic/transmog items now tint correctly. We
  resolve the item's transmog source and query the appearance collection
  directly instead of relying on the tooltip "collected" line, which cosmetics
  don't use.
- **Blizzard — Pet Frame:** tightened the PetFrame click area and added a
  taint-safe hide helper for protected/managed frames, using alpha and mouse
  state instead of reparenting. Pattern from BetterBlizzFrames.
- **Edit Mode — Reset Position:** "Reset to default position" on our relative
  anchors (Battle.net toast, Quick Join button, Buff Reminder) no longer drops
  the frame at the bottom-left corner of the screen; it restores the proper live
  anchor.
- **Maps — World Map fade:** turning off *Fade When Moving* while the map is open
  now restores full opacity and stops the fader immediately, instead of leaving
  it running.
- **Chat — Chat Filter:** disabling the filter now stops it filtering right away
  (the per-message handlers respect the master toggle) instead of staying active
  until reload.
- **Tooltip — Tooltip Icons (secret values):** hovering auras whose tooltip lines
  are secret (e.g. inside instances) no longer throws a "string conversion on a
  secret value" error; the secret check now runs before any string search.
- **Miscellaneous — AFK Camera (secret values):** `UnitIsAFK` returning a secret
  boolean (e.g. inside instances) no longer throws a "boolean test on a secret
  value" error; the AFK camera safely treats it as not-AFK.

### Internal

- Saved variables now carry a schema version, enabling safe migrations of stored
  data in future updates.
- Removed unnecessary global frame names and tidied unused locals across several
  modules.

---

## [1.2.5] — 2026-06-06

Minimap volume and a shortcut menu, a choice of number-abbreviation styles, an
achievement screenshot helper and a quest navigation skin — plus a tidied
Settings panel and a batch of bug fixes.

### Added

- **Maps — Minimap Easy Volume:** hold **Ctrl** and scroll over the minimap to
  set the master volume (`Sound_MasterVolume`); hold **Alt** to jump across the
  full 0–100 range. A colour-coded readout fades in over the minimap. Ported
  from [KkthnxUI](https://github.com/Kkthnx-Wow) by Kkthnx.
- **Maps — Minimap Menu:** middle-click the minimap for a shortcut menu of
  common Blizzard panels; right-click opens the tracking menu.
- **General — Number Format:** choose how large numbers are abbreviated
  throughout NexEnhance — **Standard** (`1.2k` / `3.4m` / `5.6b` / `7.8t`),
  **East Asian** (`1.2w` / `3.4y` / `5.6z`), or **Full Numbers**. Built on
  Blizzard's 12.0 `AbbreviateNumbers` API; abbreviation style borrowed from
  [NDui](https://github.com/siweia/NDui) by siweia.
- **Automation — Achievement Screenshot:** automatically capture a screenshot
  when you earn an achievement (skips achievements already earned account-wide).
- **Skins — Quest Navigation:** a clean Blizzard-style border on the
  super-tracked waypoint arrow. Ported from [KkthnxUI](https://github.com/Kkthnx-Wow)
  by Kkthnx.

### Changed

- **Chat — Auto Invite:** Keyword Auto-Invite now lives inline in the Chat
  settings under a new **Auto Invite** header, alongside the keyword input and
  the Guild/Friends Only toggle — the separate page is gone. The inline keyword
  box uses Blizzard's gray entry-box skin and highlights gold while focused, and
  its dependent options grey out when Keyword Auto-Invite is off.
- **Interface:** reviewed every option and re-sorted them into the most sensible
  categories (for example, Achievement Screenshot now sits under Automation).

### Fixed

- **Auto Vendor:** guild-bank repair now works for guilds that grant unlimited
  withdrawals (`GetGuildBankWithdrawMoney() == -1`).
- **Chat Bubbles:** font-size reduction is clamped to a minimum so bubble text
  stays legible.
- **Chat Filter:** keyword matching is now literal, so punctuation in a keyword
  is no longer treated as a Lua pattern.
- **Mail:** the Collect-Gold timer now stops when the mailbox closes, avoiding a
  stuck timer.
- **Auto Invite:** Battle.net friend checks use `C_BattleNet.GetGameAccountInfoByGUID`,
  fixing Guild/Friends-Only invites.
- **Chat — Keyword Auto-Invite:** Guild/Friends Only now accepts trusted keyword
  whispers from guild members, character friends, or Battle.net friends.
- **Quest Navigation:** uses `C_Navigation.WasClampedToScreen()` for the
  on-screen clamp check, fixing a Lua error.

---

## [1.2.4] — 2026-06-05

A new Experience Bar and Camera Zoom control, chat edit box improvements, plus
hotfixes for the AFK Camera animation loop and Decline Duels toggle.

### Added

- **Miscellaneous — Experience Bar:** a single movable bar that replaces
  Blizzard's status tracking bar. It shows the most relevant mode (experience
  while levelling — with a rested overlay — otherwise watched reputation, honor,
  or Azerite), while the tooltip lists **every** applicable progress section with
  a Blizzard-style divider between them. Blizzard tooltip-style border, and sizing
  (width/height/font) adjustable from both the Settings panel and Edit Mode.
- **General — Camera Zoom:** raise the maximum camera zoom-out distance
  (`cameraDistanceMaxZoomFactor`, Blizzard limit 2.6) with an adjustable slider.
- **Chat — Edit Box Character Count:** a remaining-character counter parked at the
  right of the edit box that colour-codes as you approach the 255-byte limit and
  discounts hyperlink overhead.

### Changed

- **Chat — Edit Box:** Alt + Arrow keys now pass through to camera/movement
  instead of stepping through the input, and the box is clamped on-screen.

### Fixed

- **Chat — Edit Box:** the blinking text cursor is no longer stripped away when
  the box is reskinned, so the caret is visible again while typing.
- **AFK Camera:** fixed a Lua error after the wave emote (`attempt to call a nil
  value`) that stopped the dance/sleep animation cycle from continuing.
- **Decline Duels:** turning the module off now applies live — previously the
  master toggle only re-enabled on the way back on, so disabling it left duel
  and pet-battle requests being auto-declined until a reload.

---

## [1.2.3] — 2026-06-05

Inventory clarity, an immersive AFK camera, and a proper thank-you page: bind labels on
bag icons plus a class-coloured credits panel for the authors whose work helped build
NexEnhance.

### Added

- **Inventory — Bind Status:** show **BoE**, **BoA**, and **WuE** on unbound bag
  and bank items (top-right of the icon; item level stays bottom-left). Toggle
  under **Item Level → Show Bind Status**. Idea borrowed from Lars Norberg's
  [BlizzardBags_BoE](https://github.com/GoldpawsStuff/BlizzardBags_BoE)
  (GoldpawsStuff) — thank you, friend.
- **Credits:** a scrollable thank-you panel with class-coloured contributor
  cards, feature lists, and library acknowledgements. Open with **`/nex credits`**
  or from **Settings → NexEnhance → Credits**.
- **AFK Camera:** immersive AFK overlay with a spinning camera, character (and
  pet) model with wave/dance/sleep animation cycle, live clock and calendar date,
  30-minute logout countdown, rotating account statistics, and a whisper chat log.
  Blizzard tooltip-style top and bottom letterbox bars. Exits on combat, LFG/battlefield
  popups, or any key press. Toggle under **Miscellaneous → AFK Camera**.
  Based on [ElvUI's AFK module](https://github.com/tukui-org/ElvUI/blob/main/ElvUI/Game/Shared/Modules/Misc/AFK.lua);
  model animation cycle and holder offsets from [GW2 UI](https://github.com/Mortalknight/GW2_UI/blob/main/Games/Shared/Misc/afk.lua)
  by Mortalknight.

### Changed

- **`/nex help`** and the options landing page now list the credits command.

---

## [1.2.2] — 2026-06-05

Distribution metadata update for CurseForge and Wago.

### Changed

- **Packaging:** added `X-Curse-Project-ID` and `X-Wago-ID` to the addon manifest
  so CurseForge and Wago can track updates correctly.

---

## [1.2.1] — 2026-06-05

A polish-and-extras update: colour your default frames, a Details! skin and a
mount-source tooltip, plus an easier-to-read Settings panel — still "improve,
don't reskin," all toggleable from the Settings panel.

### Added

- **General — Frame Colour:** tint the default unit frames and HUD elements
  (player, pet, target, focus, the Boss 1–5 frames, class resources, cast bars,
  totems and the minimap compass) with a colour of your choice. Driven by
  targeted hooks/events rather than a per-frame update, and taint-safe. Lives in
  a new **General** settings group.
- **Skins — Details:** frames each Details! Damage Meter window with the
  Minimalistic skin plus a clean Blizzard-style border and background, catching
  newly opened windows through Details' own event listener.
- **Tooltip — Mount Source:** hold Shift over another player's mount buff to see
  the mount's collection status and where it comes from. Defers to the standalone
  MountsSource addon if you run it.
- **Settings panel — icons & descriptions:** each subcategory now shows an icon
  in the sidebar and an intro description at the top of its page.

### Changed

- **Settings panel:** UI Scale moved into the new **General** group, and the
  sub-title divider sits a little lower for breathing room.

### Fixed

- **Chat — Chat Copy:** the copy button no longer disappears when you switch
  chat tabs; it now follows the active chat window.

---

## [1.2.0] — 2026-06-05

A chat-focused update: a cleaner, smarter edit box, a movable Battle.net pop-up,
and a new Mythic+ keystone autoslotter — plus an easier-to-navigate Settings panel.
Still "improve, don't reskin," all toggleable from the Settings panel.

### Added

- **Automation — Auto Keystone:** automatically slots your Mythic+ keystone when
  the Challenge Mode UI opens. Uses an instant item-type check (no item-cache
  dependency) and bows out entirely if AngryKeystones is installed.
- **Automation — Auto Hide Tracker:** hides the Objective Tracker during boss
  encounters and arena matches via a secure state driver, restoring it afterwards.
  Keeps objectives visible in Mythic+ by default (toggleable), defers reparenting
  out of combat when needed, and steps aside for boss mods and third-party trackers.
- **Chat — Hide Edit Box When Inactive:** keeps the input box hidden until you
  focus it, instead of leaving a faded bar lingering over the chat (and tabs).
- **Chat — Hide Scroll Bar:** removes the chat scroll bar and jump-to-bottom
  button for a cleaner window.
- **Chat — Battle.net pop-up mover:** the friend/online toast is re-anchored to
  the chat window's top-right corner and is now movable in Edit Mode.

### Changed

- **Settings panel:** the subcategory sidebar is now listed alphabetically
  (by localised title) instead of a hand-curated order.
- **Settings panel:** dependent (child) options now grey out when their parent
  toggle is off across many more modules (Tooltip, DataText, Auto Vendor, Chat,
  Queue Timer, Decline Duels and more), and their labels are bumped up a point
  for legibility.

### Fixed

- **Chat — channel colouring:** the edit box border now recolours reliably for
  the active channel by hooking each edit box's own `UpdateHeader` (modern client
  paths bypassed the old global hook), and resets to a neutral border when a
  channel has no colour so a previous tint doesn't linger.

---

## [1.1.0] — 2026-06-05

A feature update that fills out the Automation suite, adds inventory and tooltip
quality-of-life, and sharpens unit-frame colouring — all still "improve, don't
reskin," and all toggleable from the Settings panel.

### Added

- **Unit Frames — boss coverage:** the raid boss frames (Boss 1–5) are now
  coloured alongside the player/target/focus frames.
- **Inventory — Already Known:** toys, mounts, recipes and battle pets you've
  already learned dim to green at vendors, the Auction House and the guild bank.
- **Tooltip — Trade Target Info:** when trading, shows whether the other player
  is a stranger, a friend or a guild member, with their name class-coloured.
- **Tooltip — health-bar position:** choose whether the unit health bar sits at
  the top or the bottom of the tooltip.
- **Automation — Decline Duels:** auto-declines player and pet-battle PvP duel
  requests and hides the popup, with separate toggles for each.
- **Automation — Auto Invite:** auto-accepts group invites from trusted sources
  (Battle.net friends, character friends, guild members), each toggleable.
- **Automation — Auto Goodbye:** sends a random, friendly farewell to the group
  after a dungeon or Mythic+ finishes, on a short human-feeling delay.
- **Automation — Auto Resurrect:** accepts resurrection requests while you're out
  of combat (ignoring encounter item-rezzes like the pylon and brazier), with an
  optional /thank emote to your reviver.
- **Maps — Map Reveal:** removes fog of war from the world map using your own
  map data, toggled entirely from the config.
- **Maps — Wowhead Links:** adds a copyable Wowhead link to the world map (for
  the tracked/opened quest) and the achievement frame.
- **Miscellaneous — Queue Timer:** shows elapsed time on the LFG/queue eye.
- **Miscellaneous — Quick Item Delete:** optionally skips the type-"DELETE"
  confirmation for high-quality and quest items, using a simple Yes/No prompt
  with a timeout (off by default).
- **First-run setup:** a one-time install screen applies recommended CVars and
  raid-frame settings, then never auto-shows again.
- **In-game changelog:** a styled changelog window that auto-shows once after an
  update, plus `/nex changelog` to open it any time. The newest version is shown
  in full colour while older entries are dimmed, so it's clear what's new.

### Changed

- **Unit Frames — NPC reaction colouring:** non-player units now tint by reaction
  (hostile red, neutral yellow, friendly green) instead of the flat green atlas,
  matching the tooltip's reaction colours. Players still use class colours.
- **Maps — Map Reveal** is now driven purely from the config (the on-map checkbox
  was removed) and applies live, like the rest of the UI.

### Fixed

- **Unit Frames:** hostile NPCs and bosses no longer show a green health bar; the
  bar correctly desaturates the atlas before tinting and falls back to Blizzard's
  default only when a unit's identity is secret (in combat/instances).
- **Core:** the shared event dispatcher is now safe against a module
  unregistering an event mid-dispatch, fixing a rare Lua error (e.g. when opening
  the achievements panel) and a related case where the next handler was skipped.

---

## [1.0.0] — 2026-06-05

**The first public release.** NexEnhance launches with a complete, event-driven
engine and a full suite of modules, each one toggleable from a modern, grouped
Settings panel. Nothing is reskinned for the sake of it — every module sharpens
the default UI and gets out of your way.

### Core Engine

- **Single-frame event dispatcher** — one shared event frame fans out to every
  module, so there are no duplicate registrations and no per-module frames.
- **Clean lifecycle** — `OnInitialize` (database ready) → `OnEnable` (world ready),
  with idempotent paths that handle load-on-demand addons gracefully.
- **Profile database** — defaults are declared per-module and merged without
  clobbering your saved choices; account-wide and per-character scopes supported.
- **Modern Settings panel** — themed subcategories (Action Bars, Unit Frames,
  Auras, Inventory, Chat, Filters, Tooltip, Skins, DataText, Maps, Automation,
  Announcements, Miscellaneous) with live-apply settings — most changes take
  effect instantly, no reload required.
- **Slash commands** — `/nex` (open options), `/nex modules`, `/nex toggle <module>`,
  `/nex help`.
- **Pixel-perfect helpers** — a shared backdrop/border system, font-string and
  money formatters, an object pool, a debounce utility, and 12.0-safe "secret
  value" guards baked into the framework.
- **Edit Mode movers** — custom frames register with Blizzard's Edit Mode (via
  the bundled LibEditMode) so they drag like native elements and remember where
  you put them.

### Action Bars

- **Cooldown text** on action buttons, with a threshold for which cooldowns
  show numbers.

### Unit Frames

- **Class-coloured health** for players (and units that become players) across
  party, target, focus, and their targets — secret-value safe so it never errors
  under tainted execution.

### Auras

- **Buff Reminder** — surfaces icons for missing buffs you can provide, with a
  movable anchor and modern retail class data.

### Inventory

- **Item Level** — paints item levels (and optional gem/enchant info) on the
  Character and Inspect panes, shown on Shift like the default tooltips.
- **Durability** — a quiet tab on the Character pane showing your lowest
  equipped durability, a per-slot repair-cost tooltip, and a low-durability nudge.
- **Mail** — Collect-Gold and Take-All buttons, a quick-delete button per inbox
  row, an attachment list in the row tooltip, and a fix for the default Open-All
  routine stalling on GM mail.

### Chat

- **Refined chat** — flattened tabs, an edit box docked to the top with a clean
  Blizzard tooltip-style border that tints to the active channel, full-width and
  rock-steady when switching tabs (including the Combat Log), quick mouse-wheel
  scrolling, sticky whispers, a tab-key channel cycle, and a font-size submenu.
- **Chat Copy** — a one-click button to pop a copyable transcript of the active
  window, framed in a matching Blizzard border.
- **Channel Rename** — tidy, shortened channel labels.

### Filters

- **Chat Filter** — keyword spam filtering with black/whitelists, repeat-message
  detection (Levenshtein distance), stranger/spammer blocking, and item-level
  decoration on chat links. Managed via `/nexfilter`.

### Tooltip

- **Improved — never reskinned.** Quality-coloured default borders (kept in place),
  spell/item/aura IDs, source icons, item levels, and hover tips for units —
  all on the existing Blizzard tooltip.

### Skins

- **Objective Tracker** — hides the busy header art, tidies the minimise button,
  and recolours progress/timer bars to a single calm colour.
- **Character Frames** — subtle cleanup of the character pane.
- **Chat Bubbles** — a clean Blizzard tooltip-style border whose colour follows
  the message's channel.

### DataText

- **Stats** — a movable FPS / latency readout that lives under the minimap by
  default. Hover for latency detail (home/world, IP protocol, streaming
  bandwidth) followed by a per-addon memory breakdown; left-click collects
  memory. Options to show FPS only, latency only, or both, flip their order, and
  class-colour the numbers.

### Maps

- **World Map** — player/cursor coordinates, a smaller scalable map that doesn't
  black out the world behind it, fade-on-movement, and a movable anchor.

### Automation

- **Auto Vendor** — sells junk and (optionally) auto-repairs at a merchant.
- **Quick Quest** — auto-accepts and turns in quests, with combat-safe deferral.
- **Faster Loot** — speeds up auto-loot.
- **Movie Skip** — skips in-game cinematics and movies.

### Announcements

- **Quest Notification** — concise quest progress/completion messages, throttled
  to avoid event-storm spam.

### Always-On Fixes

- **Blizzard fixes** — a curated set of default-UI bug fixes (talent-group spam,
  addon-list and guild-news tooltip errors, money-string spacing, and more).

### Miscellaneous

- **UI Scale** — pixel-perfect scaling so 1px borders stay 1px.
- **Social Colours** — class-coloured names in the friends/guild lists.
- **Drag 'Em All** — makes more Blizzard frames movable.
- **Alert Frames** — relocates achievement/loot toasts to a tidy spot.
- **Animation** — a login logo flyby and a combat-state banner using the addon's
  own logo.
- **Reload UI** — `/rl`, `/reloadui`, `//` and `/.` shortcuts.

---

[1.5.0]: https://github.com/Kkthnx-Wow/NexEnhance/releases/tag/v1.5.0
[1.4.0]: https://github.com/Kkthnx-Wow/NexEnhance/releases/tag/v1.4.0
[1.3.0]: https://github.com/Kkthnx-Wow/NexEnhance/releases/tag/v1.3.0
[1.2.9]: https://github.com/Kkthnx-Wow/NexEnhance/releases/tag/v1.2.9
[1.2.8]: https://github.com/Kkthnx-Wow/NexEnhance/releases/tag/v1.2.8
[1.2.4]: https://github.com/Kkthnx-Wow/NexEnhance/releases/tag/v1.2.4
[1.2.3]: https://github.com/Kkthnx-Wow/NexEnhance/releases/tag/v1.2.3
[1.2.2]: https://github.com/Kkthnx-Wow/NexEnhance/releases/tag/v1.2.2
[1.2.1]: https://github.com/Kkthnx-Wow/NexEnhance/releases/tag/v1.2.1
[1.2.0]: https://github.com/Kkthnx-Wow/NexEnhance/releases/tag/v1.2.0
[1.1.0]: https://github.com/Kkthnx-Wow/NexEnhance/releases/tag/v1.1.0
[1.0.0]: https://github.com/Kkthnx-Wow/NexEnhance/releases/tag/v1.0.0
