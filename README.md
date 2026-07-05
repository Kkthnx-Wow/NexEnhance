<div align="center">

# NexEnhance

**A lightweight, modular framework that enhances the default Blizzard UI — it improves, it doesn't replace.**

[![Last Commit](https://img.shields.io/github/last-commit/Kkthnx-Wow/NexEnhance)](https://github.com/Kkthnx-Wow/NexEnhance/commits/main)
[![Issues](https://img.shields.io/github/issues/Kkthnx-Wow/NexEnhance/issues)](https://github.com/Kkthnx-Wow/NexEnhance/issues)
[![CurseForge](https://img.shields.io/badge/CurseForge-Download-orange)](https://www.curseforge.com/wow/addons/nexenhance)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://github.com/Kkthnx-Wow/NexEnhance/blob/main/LICENSE)

![NexEnhance Logo](https://github.com/Kkthnx-Wow/NexEnhance/assets/40672673/f335ef6a-c4da-4ede-a850-dd6400c0a6da)

</div>

---

## Overview

**NexEnhance** supercharges the stock World of Warcraft interface without throwing it away. Instead of replacing Blizzard's UI with a heavy custom skin, it layers **90+ small, opt-in modules** on top of the default frames — class-coloured health, item levels, smart automation, tooltip data, chat cleanup, minimap tools, micro-button datatexts, and more.

Every feature is **self-contained and toggleable**, so you can run the full suite or cherry-pick exactly what you want. The whole thing is built event-driven and tuned for performance, with **Midnight (12.0) Secret-value guards** throughout so combat and instance restrictions are handled safely.

- **Enhance, don't replace** — your UI still looks and behaves like Blizzard's, just better.
- **Modular** — 90+ independent modules, each with its own settings and live-apply toggles.
- **Extensible** — a **plugin API** lets other authors ship separate addons that plug into NexEnhance profiles, events, and settings.
- **Native settings** — a clean options panel built on Blizzard's own Settings API, plus Edit Mode movers for repositionable elements.
- **Performance-first** — local caches, throttled updates, frame runners, and combat-safe deferrals throughout.

**Current version:** 1.5.7 · **Interface:** 120007 (Midnight / Revelations)

---

## Installation

**Via an addon manager (recommended)**
- [CurseForge](https://www.curseforge.com/wow/addons/nexenhance) — search for **NexEnhance** and install.

**Manual**
1. Download the latest release from the [Releases](https://github.com/Kkthnx-Wow/NexEnhance/releases) page.
2. Extract the `NexEnhance` folder into `World of Warcraft\_retail_\Interface\AddOns`.
3. Restart the game (or `/reload` if already in-game).

On first login you'll get a short **setup screen** (`/nex install`) that applies recommended Blizzard CVars (auto-loot, locked action bars, class-coloured raid frames, and more), sets up a sensible **chat window layout** with channel colours for General / Trade / Local Defense, and reloads. Everything else is left untouched.

---

## Getting Started

| Command | Description |
| --- | --- |
| `/nex` or `/nexenhance` | Open the options panel |
| `/nex config` | Open the options panel |
| `/nex modules` | List every module and whether it's enabled |
| `/nex plugins` | List installed third-party NexEnhance plugins |
| `/nex toggle <module>` | Toggle a module (or plugin) on/off |
| `/nex editmode` / `/nex em` | Open Edit Mode (same as `/editmode`) |
| `/nex keybinds` / `/nex kb` | Open Key Bindings in Settings |
| `/nex install` | Re-run the first-time setup screen |
| `/nex profile` | Open the profile import/export window |
| `/nex changelog` | Open the in-game changelog |
| `/nex credits` | Open the credits panel |
| `/nex reminder` | Preview the Buff Reminder icons |
| `/nex afk` | Preview the AFK Camera screen |
| `/nex lootroll` | Preview the Loot Roll bars |
| `/nex rare` | Preview the Rare Alert popup |
| `/nex alerttest` | Preview achievement / loot / money alert toasts |
| `/nex questnotify` | Self-test Quest Notification announcements |
| `/nex way <coords>` | Set a user map waypoint (TomTom-style; also `/way`, `/pin`, `/nexway`) |
| `/nex abandonquests` | Abandon every quest in your log (with confirmation) |
| `/nexjunk add <item>` | Manage your custom Auto Vendor junk list |
| `/nexfilter` | Manage Chat Filter keywords |
| `/nex debug` | Debug logging, dumps, and export help |
| `/nex poiscan [mapID]` | Dump area POIs on your current map (event setup) |
| `/nexlogo` | Replay the login logo flyby |
| `/rl`, `/reloadui`, `//`, `/.` | Reload the interface |

---

## Configuration

Open the panel with **`/nex`** (or **Esc → Options → AddOns → NexEnhance**).

### Landing page

The top-level NexEnhance page shows the logo, version, live **module count**, and a quick slash-command reference. Modules added in a recent update show a **New!** badge until you open their section.

### Per-option reset

Hover any option whose value differs from default — a small **revert icon** appears beside the label. Click it to reset that one setting live (no `/reload`). Section headers get the same treatment to reset an entire module at once (with confirmation).

### Themed groups

Modules are sorted into sidebar categories that match the options panel:

| Group | What lives here |
| --- | --- |
| **General** | UI scale, number format, hide help tips / combat errors / UI clutter |
| **Action Bars** | Button styling, cooldown text, GCD bar, range colouring, cast-on-key-down, extra/zone buttons, quest item button |
| **Unit Frames** | Class/level colours, target layout, player cast bar, hide DPS role icon |
| **Nameplates** | Quest icons on plates, target arrows, NPC reaction bar colours |
| **Auras** | Buff reminder |
| **Inventory** | Item level, mail, durability, loot frame, vendor tints, delete helpers |
| **Chat** | Chat tweaks, copy button, emojis, channel rename / URLs / timestamps |
| **Filters** | Chat Filter spam controls, system chat talent-learn filter |
| **Tooltip** | Tooltip styling, IDs, icons, item level, hover tips, mount source, vendor location, crafting reagents, Pawn integration |
| **Skins** | Light restyles — objective tracker, character sheet, chat bubbles, color picker, Details!, hero talent swap, missing stats |
| **DataText** | Minimap stats/clock/location, experience bar, guild/friends/gold micro-button tooltips |
| **Maps** | Minimap, world map, fog reveal, Wowhead links, map pin navigation |
| **Plugins** | Settings for third-party NexEnhance extensions (when installed) |
| **Automation** | Vendor, quest, loot, invite, fishing, auction house, delves, and other hands-off helpers |
| **Announcements** | Quest progress, rare/world-event alerts, level-up announcer |
| **Camera** | Max zoom distance, AFK cinematic screen |
| **Alerts** | Achievement/loot toasts, loot roll UI, LFG/PvP queue timer |
| **Movers** | Drag frames, widget movers (Edit Mode) |
| **Miscellaneous** | Social colours, menu buttons, popup QoL, animation, audio sync, profiles canvas, and more |

Most toggles apply **live**; a few that restyle protected frames note "reload to apply." Repositionable elements (Buff Reminder, Experience Bar, Rare Alert, Loot Roll, Extra Quest Button, Alert Frames, Map Pin Navigation, and others) integrate with **Edit Mode**.

### Canvas pages

These sit alongside the themed groups in the NexEnhance sidebar:

| Page | Description |
| --- | --- |
| **Profiles** | Create, copy, switch, reset, delete, import, and export settings profiles (compressed export supported) |
| **Plugin Manager** | Overview of installed third-party plugins with enable toggles and install guidance |
| **Credits** | Authors and projects NexEnhance builds on |
| **Changelog** | In-game release notes (auto-shown once after each update) |

---

## Plugins & extensions

Since **1.4.0**, other addon authors can extend NexEnhance without merging code into the main package.

1. Ship a **separate addon** with `## Dependencies: NexEnhance` in its `.toc`.
2. Call `NexEnhance:RegisterPlugin({ ... })` after NexEnhance loads.
3. Plugin settings appear under **Plugins**; use **Plugin Manager** for a quick overview.

A starter template lives in [`Examples/NexEnhancePluginTemplate/`](Examples/NexEnhancePluginTemplate/). See that folder's README for the full contract (`NexEnhance.API_VERSION`, profile DB keys, lifecycle hooks, and `RegisterOptions`).

---

## Features

NexEnhance groups its modules into the same themed categories you'll find in the options panel.

### General
- **UI Scale** — pixel-perfect (1 UI pixel = 1 screen pixel) auto-scaling, or a manual scale of your choice. Reload-safe and combat-aware.
- **Number Format** — choose how large numbers abbreviate everywhere: Standard (`1.2k`/`3.4m`), East Asian (`1.2w`/`3.4y`), or full numbers.
- **Hide Help Tips** — suppress Blizzard's one-time tutorial popups (NexEnhance's own tips are spared).
- **Hide Combat Errors** — silence the red combat-error spam in the default UI error frame.
- **Hide UI Elements** — optional toggles for the buff collapse arrow, micro menu & bag bar cluster, and portrait combat feedback numbers.

### Action Bars
- **Action Bars** — style Blizzard action buttons, abbreviate hotkeys, toggle macro names, stack counts and keybind text (with adjustable font sizes), and skin the Extra Action / Zone Ability buttons.
- **Cooldown Text** — formatted countdown numbers on cooldowns, with coloured/plain and decimal/integer styles, a configurable mm:ss threshold, a weeks tier, optional scaling that hides text on tiny cooldowns, and Midnight-safe duration objects.
- **GCD Bar** — a class-coloured sweep bar during the global cooldown (Edit Mode anchor).
- **Range Coloring** — tint action-button icons and hotkeys when out of range, out of power, or unusable (event-driven, Secret-safe).
- **Cast On Key Down** — fire action buttons on key press instead of release.
- **Extra Quest Button** — a keybindable button for the closest usable quest item from your log, with Edit Mode positioning and HUD-matching art.

### Unit Frames
- **Class Colours** — colour unit-frame health by class (players) or reaction (NPCs) across player, target, focus, boss, party and more.
- **Target Frame Layout** — optional player-style target frame: hide the reaction strip on Target/Focus/Boss and move the target name beside the portrait.
- **Level Colours** — classic difficulty-coloured level text; optional "always show level" instead of the skull icon.
- **Player Cast Bar** — cosmetic overlay: icon above the bar, cast time below; optional **latency SafeZone** (red band) and latency text.
- **Hide DPS Role Icon** — hide the DPS sword on party/raid frames (tank/healer icons stay).

### Nameplates
- **Nameplate Quest Icons** — quest icon on NPC nameplates tied to your active quests, with optional objective progress text.
- **Target Arrows** — left/right or top arrow indicators on your current target's nameplate; optional friendly nameplate CVars.
- **Reaction Colors** — darker NPC reaction tints on nameplate health bars (players left to Blizzard class colours).

### Auras
- **Buff Reminder** — show a "Lack" icon when you're missing a buff you can provide. Resizable icons, a Blizzard-style border, and an Edit Mode mover (preview with `/nex reminder`).

### Inventory
- **Item Level** — item levels on equipped, bag, merchant, trade and loot items, with optional gem/socket/enchant info, missing-enchant warnings, BoE/BoA/WuE bind labels, and an adjustable font size.
- **Durability** — lowest equipped-item durability on the Character pane with a per-slot repair-cost tooltip.
- **Mail** — Collect-Gold, Take-All and quick-delete buttons on the mailbox.
- **Already Known** — tint already-known recipes, pets, toys, cosmetics, and housing decor green at vendors, the Auction House and Guild Bank.
- **Junk Icon** — always show the coin icon on Poor-quality bag items, not just at a merchant.
- **Unusable Items** — tint bag/bank icons red for gear your class can't use or that you're too low level for.
- **Quick Item Delete** — a simple Yes/No prompt instead of typing DELETE for high-quality and quest items.
- **Delete Cheapest** — a bag button that finds and destroys the lowest vendor-value item (with confirmation and class protection toggles).
- **Loot Frame** — let Blizzard's default loot window grow taller so more items fit on one page.

### Chat
- **Chat** — flat tabs, edit-box border/positioning/colouring, hide-when-inactive, side-button and scroll-bar hiding, Tab channel switching, quick scroll, sticky whispers, whisper sound, a font-size menu, repositionable Battle.net pop-up and Quick Join button, and **Keyword Auto-Invite**.
- **Chat Copy** — a button to copy the chat window's text (preserves emoji source text via hidden links).
- **Chat Emojis** — replace text emoticons (`:D`, `:smile:`, `<3`, …) with inline textures; optional speech-bubble emojis.
- **Chat Channels** — abbreviate or hide channel tags (`[Party Leader]` → `[PL]`), clickable/copyable URLs, and optional timestamps.

### Filters
- **Chat Filter** — hide spam by keyword or repeated near-identical messages, block strangers/repeat spammers, and append item level + sockets to item links in chat. Manage keywords in the settings panel or with `/nexfilter`.
- **System Chat Filter** — hide the learn/unlearn spell spam when changing talents.

### Tooltip
- **Tooltip** — faction/role icons, hidden realm names and titles, Mythic+ score, quality-coloured border, configurable health-bar position/height, and Secret-safe guards.
- **Tooltip IDs** — append spell, item, quest and other IDs.
- **Tooltip Icons** — show an icon next to the tooltip title.
- **Tooltip Item Level** — average item level on inspected player tooltips (optionally Shift-only).
- **Hover Tips** — tooltips when hovering item/spell links in chat.
- **Mount Source** — a mount's collection status and source on aura tooltips.
- **Vendor Location** — for special barter/curio items, show where to turn them in and Ctrl-Click to drop a map waypoint.
- **Crafting Reagents** — on usable craftable items, show required reagents with bag/bank counts.
- **Pawn Integration** — optional coordination with Pawn (suppress duplicate icons/borders when both are enabled).

### Skins
Light, targeted restyling of select Blizzard frames — improved, not replaced.
- **Objective Tracker** — hide header backgrounds, tidy the minimise button, optional class-coloured bars.
- **Character Frames** — restyle and resize the Character and Inspect frames.
- **Missing Stats** — surface hidden character-sheet stats (attack power, weapon speed, spell power, regen, movement) and tidy the readouts.
- **Chat Bubbles** — tooltip-style border and channel-tinted text on speech bubbles.
- **Details!** — skin Details! Damage Meter windows with a minimalistic look and Blizzard-style border.
- **Color Picker** — R/G/B inputs, class-colour swatches, and a reskinned hex row on Blizzard's colour picker.
- **Hero Talent Swap** — right-click the hero talent button on the Talents pane to swap to your inactive hero tree.

### DataText
- **Stats** — a movable FPS/latency readout under the minimap, with a memory/addon tooltip, flip order, and class-coloured numbers.
- **Experience Bar** — a movable replacement for Blizzard's status tracking bar (XP, **housing XP**, reputation, honor, Azerite) with fade options and Edit Mode sizing.
- **Clock** — a minimap clock with a lockout/reset tooltip (daily/weekly resets, saved instances, Midnight world events, delves, and more).
- **Location** — zone and sub-zone text at the top of the minimap, optionally on mouseover.
- **Guild** — online count on the Guild micro button plus a roster tooltip on hover.
- **Friends** — a grouped friends/Battle.net roster tooltip on the social / Quick Join button.
- **Currency & Gold** — a wealth tooltip on the Character micro button (session gold, per-character totals, Warband bank, token price, tracked currencies).

### Maps
- **Minimap** — square shape, clean border, status pulse (combat/mail/invites), Easy Volume (Ctrl-scroll), a middle-click shortcut menu, and a button-collecting tray.
- **World Map** — player/cursor coordinates, draggable windowed map (position saved), and fade-while-moving.
- **Map Reveal** — reveal unexplored areas by removing fog of war, with optional dimming of revealed tiles.
- **Wowhead Links** — copyable Wowhead links on the world map (tracked quest) and achievement frame.
- **Map Pin Navigation** — unlimited super-track range, custom distance text, arrival ETA, auto-track new waypoints, and `/way` / `/pin` / `/nexway` commands.

### Automation
Hands-off quality-of-life.
- **Auto Vendor** — auto-sell junk and repair (with guild funds) at merchants, plus a custom junk list (`/nexjunk`). Yields to Bagforge when it owns the same automation.
- **Auto Greed** — automatically roll Greed or Disenchant on low-rarity group-loot drops (off by default).
- **Quick Quest** — auto accept/turn-in quests by frequency, protect costly turn-ins, auto-skip story gossip and utility NPCs, with a configurable override key and per-NPC ignore.
- **Faster Loot** — paced auto-loot when the loot window opens.
- **Faster Movie Skip** — instantly confirm the cinematic skip dialog.
- **Smart Fishing** — while channeling: soft-target interact bind, muted ambience, one-key bobber looting (hold Shift when casting to skip).
- **Auction Search Fallback** — on the AH browse tab, retry without "Current Expansion Only" when a search returns zero results.
- **Auction Search History** — recent browse searches in a dropdown when you focus the search box.
- **Smart Minimap Tracking** — auto-enable repair-vendor tracking when gear is damaged, mailbox tracking when mail is pending.
- **Quick Join** — Premade Groups QoL: double-click to apply, auto-accept applicants, hide LFG popups, show leader rating.
- **Decline Duels** — auto-decline player and pet-battle duel requests.
- **Cancel Bad Buffs** — remove cosmetic costume and holiday transforms out of combat (off by default).
- **Auto Accept Invites** — accept group invites from friends and/or guild.
- **Guild Invite Filter** — auto-decline guild invites from strangers (with statistics on its options page). Off by default.
- **Auto Resurrect** — accept resurrections out of combat, with an optional thank-you emote.
- **Auto Goodbye** — send a friendly farewell after a dungeon or Mythic+ run.
- **Auto Keystone** — slot your Mythic+ keystone when the Challenge Mode UI opens.
- **Holiday Dungeon** — nudge you toward the active holiday or Timewalking queue when opening the Dungeon Finder.
- **Auto Hide Tracker** — hide the Objective Tracker during bosses, arenas and (optionally) Mythic+.
- **Auto Role** — keep your party/raid role synced with your spec; optionally auto-answer role polls.
- **Auto Summon** — summon your pet or mount when you start moving (configurable).
- **Auto PvP Release** — release spirit in battlegrounds/arenas when you die.
- **Delves Automation** — auto-confirm the single-choice borrowed-power popup, with optional chat announcement.
- **Auto Warband Gold** — deposit surplus gold to (or withdraw from) the Warband bank when you open the bank.
- **Achievement Screenshot** — auto-screenshot when you earn a new achievement.

### Announcements
- **Quest Notification** — announce accepted quests, objective progress, and completions to your group, with optional progress updates and a completion sound.
- **Rare Alert** — announce nearby rares and world events when their vignette appears, with a movable click-to-track popup, anti-burst sound throttle, and optional map-pin sharing in chat.
- **Level Announcer** — announce level-ups (with time-to-level) to a channel of your choice.

### Camera
- **Camera Zoom** — raise the maximum camera zoom-out distance beyond the default.
- **AFK Camera** — an immersive cinematic AFK screen: rotating camera, your character (with class rune and faction crest) alongside a random collected battle pet, clock, logout countdown, rotating account stats and a whisper log. Preview with `/nex afk`.

### Alerts
- **Alert Frames** — move achievement/loot/reward popups to the top of the screen, optionally hide the Talking Head, configurable stack spacing (`/nex alerttest`).
- **Loot Roll** — compact, skinned group-loot roll bars with a draggable anchor (preview with `/nex lootroll`).
- **Queue Timer** — a larger, colour-coded LFG/PvP ready countdown with a warning sound.

### Movers
- **Drag Frames** — click-and-drag most Blizzard windows (including bags and the world map title bar) to move them.
- **Widget Movers** — Edit Mode integration for Blizzard's below-minimap and top-center widget containers.

### Miscellaneous
- **Social Colours** — class-coloured names and difficulty-coloured levels in the Friends, Who and Guild panels.
- **Menu Buttons** — quick social actions (Add Friend, Guild Invite, Copy Name, Whisper) on unit right-click menus.
- **Trade Target Info** — show whether your trade partner is a stranger, friend or guild member.
- **Achievement Back Button** — a back button on the achievement frame to return to the previous category.
- **Popup QoL** — auto-confirm BoP loot, Enter on purchases, Alt-right-click full merchant stacks, click-through event toasts, and more (each sub-option off by default).
- **Animation** — a login logo flyby (`/nexlogo`) and an animated entering/leaving combat banner.
- **Audio Sync** — restart the sound subsystem when Windows changes your audio output device (fixes the "no sound until reload" bug).
- **Reload UI** — `/rl`, `/reloadui`, `//` and `/.` reload commands.

### Always-On
- **BlizzFix** — a collection of quiet bug fixes for default-UI quirks (no settings; just works).

---

## Contributing

Contributions, bug reports and ideas are welcome! Open an [issue](https://github.com/Kkthnx-Wow/NexEnhance/issues) or a pull request. When filing a bug, including your client version and a `/reload`-able repro helps a ton. For deeper diagnosis, `/nex debug export` copies a scoped log you can paste into a report.

**Building a plugin?** Start from [`Examples/NexEnhancePluginTemplate/`](Examples/NexEnhancePluginTemplate/) and read `Core/Plugins.lua` for the registration contract.

---

## Credits

NexEnhance stands on the shoulders of incredible addon authors — borrowed with respect, adapted to fit the default UI, and shared back with gratitude. Full attributions live in-game under **`/nex credits`**, including:

- **Elv & the Tukui team** (ElvUI) — AFK module foundation, datatexts, loot roll
- **Mortalknight** (GW2 UI) — AFK model animation cycle
- **Siweia** (NDui) and **yleaf** — chat, automation, tooltip, inventory and item-level groundwork
- **p3lim** — QuickQuest, ExtraQuestButton, Dashi helpers, and **LibEditMode**
- **Peterodox** (Plumber), **Leatrix** (Leatrix Plus), **lightspark** (ls_Monobrow), **Lars Norberg**, **Shestak**, **Cloudy**, **emelio**, and **Alteredcross**
- **Yuyuli** (Speedy AutoLoot) — Faster Loot rewrite, **Cybeloras** (Improved Loot Frame) — Loot Frame, **maqjav & Maciza-Tyrande** (RareScanner) — Rare Alert popup, **LudiusMaximus** — Achievement Back Button

Thank you all. NexEnhance would not exist without you.

---

## Support

Appreciate the work that goes into NexEnhance? Consider showing your support:

- **PayPal** — [paypal.me/KkthnxTV](https://www.paypal.com/paypalme/kkthnxtv)
- **Patreon** — [patreon.com/Kkthnx](https://www.patreon.com/Kkthnx)
- **Battle.net / Balance** — `Kkthnx#1105` or `JRussell20@gmail.com`
- **In-game gold** — Kkthnx on Area 52 (US)

---

## License

Released under the **MIT License**. See [LICENSE](https://github.com/Kkthnx-Wow/NexEnhance/blob/main/LICENSE) for details.

<div align="center">

Developed and maintained by **Josh "Kkthnx" Russell**. Built with love for the default UI.

</div>
