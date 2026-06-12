# NexEnhance — Changelog

> A lightweight, modular framework that **enhances** the default Blizzard UI — it improves what's already there instead of replacing it.

All notable changes to this project are documented here. This project follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.2.9] — 2026-06-11

Adds a **Guild Invite Filter** that auto-declines guild invites from strangers
while letting friends and guildmates through, with live statistics shown right
in its options page, and a **Quick Join** module that smooths out Blizzard's
Group Finder. Under the hood, all of NexEnhance's Midnight Secret-Value handling
is consolidated behind one shared helper set (modelled on oUF's), so every
module guards secrets the same way. This release also cleans up profile
management with AceDB-style actions and compact compressed exports, and
standardises UI frames on Blizzard's stock tooltip border art.

### Added

- **Automation — Guild Invite Filter:** new module (off by default) that
  automatically declines guild invites from players who aren't trusted, while
  letting invites from character friends, Battle.net friends and your current
  guild members through. Each trusted source is its own toggle. Optional chat
  announcement and a short sound play when an invite is declined, and a
  **Statistics** section on its options page shows lifetime blocked/allowed
  totals and the last blocked invite (refreshing each time the page opens, and
  greying out while the module is off).
- **Automation — Quick Join:** new module (off by default) for the Premade
  Groups finder, adapted from NDui's QuickJoin:
  - **Double-click to apply** to a search result (hold **Alt** to review the
    sign-up note instead of sending it immediately), with a one-time HelpTip
    pointing the shortcut out the first time the sign-up button appears.
  - **Auto-accept** check on the applicant viewer that auto-invites applicants
    while you're the group leader (its state is remembered). The check only
    appears for the leader and stays out of the way of Blizzard's own
    auto-accept toggle.
  - **Auto-hide LFG popups** — dismisses the throwaway informational and
    expired-listing popups, and closes the Group Finder once you accept an
    invite to a listed group. (Toggle.)
  - **Show Leader Rating** — prints the group leader's Mythic+/PvP rating on
    each result with a cross-faction crest, and trims the long "Zone:" activity
    prefix. (Toggle.) The Group Finder UI is load-on-demand, so the module waits
  for it before hooking; ratings and result names are read through the shared
  Secret-Value helpers so restricted-instance secrets never error.
- **Commands — Abandon all quests:** new `/nex abandonquests` command that
  clears every abandonable quest from your log in one go (skipping world quests
  and party-sync–locked quests, which can't be abandoned). It collects the quest
  IDs first and confirms with a yes/no popup before committing, since abandoning
  also destroys any quest items.

### Changed

- **Miscellaneous — Profiles:** profile management now follows AceDB's clearer
  workflow: create a new profile, switch to an existing one, copy settings from
  another profile into the current one, copy the current profile as a new name,
  reset the current profile to defaults, or delete unused profiles.
- **UI chrome:** NexEnhance now standardises frames on Blizzard's stock
  `UI-Tooltip-Border` / `UI-Tooltip-Background` art. The custom pixel-border and
  addon NineSlice helper paths were removed, and the minimap, chat edit box,
  chat bubbles, profile/install/changelog/credits/copy windows, Details skin,
  Reminder icons, Rare Alert banner and tooltip status bar all use the same
  tooltip-border family.
- **Automation — Guild Invite Filter (Blizzard interop):** while enabled, the
  module forces Blizzard's own "Block Guild Invites" (`SetAutoDeclineGuildInvites`)
  off so invites actually reach the filter (Blizzard's option drops them
  server-side before `GUILD_INVITE_REQUEST` fires). Your prior setting is
  remembered per-character and restored when the module is disabled, even across
  a reload.

### Performance & Internals

- **Miscellaneous — Profiles:** export strings now use bundled LibSerialize and
  LibDeflate (`EncodeForPrint`) for compact printable backups, while still
  accepting older `!NEX1!` Base64 exports.
- **Core — Secret API:** consolidated all Midnight Secret-Value handling into a
  single shared helper set on `F`, modelled on oUF's (by Simpy): `F.IsSecret`/
  `F.NotSecret` (existing) plus `F.IsSecretUnit`/`F.NotSecretUnit`,
  `F.IsSecretTable`/`F.NotSecretTable`, `F.CanAccessValue`/`F.CanNotAccessValue`
  and `F.HasSecretValues`/`F.NoSecretValues`. The Tooltip module's local
  `IsSecretUnit` and the Cooldowns module's private `canaccessvalue` check now
  route through these, so there's one source of truth and no module rolls its
  own raw primitive.
- **Core — Settings builder:** added `builder:Description(text)`, a read-only
  wrapped paragraph for option pages (used for the Guild Invite Filter stats),
  and taught the shared description widget to honour `builder:DependsOn`, so
  read-only text rows grey out with the setting they belong to just like
  Blizzard's native controls.
- **Core — HelpTip helper:** added `F.ShowHelpTip(owner, key, text[, opts])` for
  one-shot, account-wide tutorial nudges on Blizzard's HelpTip frame (shown once
  per account, then remembered in the global DB). Tips raised this way are
  automatically spared by the Hide Help Tips feature. Used to surface NexEnhance's
  less-obvious interactions the first time they're relevant: Quick Join's
  double-click shortcut, the chat quick-scroll modifiers, the chat copy button,
  Edit Mode movers, the invisible minimap click/scroll gestures, and the
  bag-frame "delete cheapest" button.

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
  + overall item level and a cleaner stat font. Reworked from
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
  reworked from [LibUnfit-1.0](https://github.com/Kkthnx-Wow/KkthnxUI_Firestorm)
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

[1.2.4]: https://github.com/Kkthnx-Wow/NexEnhance/releases/tag/v1.2.4
[1.2.3]: https://github.com/Kkthnx-Wow/NexEnhance/releases/tag/v1.2.3
[1.2.2]: https://github.com/Kkthnx-Wow/NexEnhance/releases/tag/v1.2.2
[1.2.1]: https://github.com/Kkthnx-Wow/NexEnhance/releases/tag/v1.2.1
[1.2.0]: https://github.com/Kkthnx-Wow/NexEnhance/releases/tag/v1.2.0
[1.1.0]: https://github.com/Kkthnx-Wow/NexEnhance/releases/tag/v1.1.0
[1.0.0]: https://github.com/Kkthnx-Wow/NexEnhance/releases/tag/v1.0.0
