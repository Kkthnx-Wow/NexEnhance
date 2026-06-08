<div align="center">

# NexEnhance

**A lightweight, modular framework that enhances the default Blizzard UI — it improves, it doesn't replace.**

[![Last Commit](https://img.shields.io/github/last-commit/Kkthnx-Wow/NexEnhance)](https://github.com/Kkthnx-Wow/NexEnhance/commits/main)
[![Issues](https://img.shields.io/github/issues/Kkthnx-Wow/NexEnhance)](https://github.com/Kkthnx-Wow/NexEnhance/issues)
[![CurseForge](https://img.shields.io/badge/CurseForge-Download-orange)](https://www.curseforge.com/wow/addons/nexenhance)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://github.com/Kkthnx-Wow/NexEnhance/blob/main/LICENSE)

![NexEnhance Logo](https://github.com/Kkthnx-Wow/NexEnhance/assets/40672673/f335ef6a-c4da-4ede-a850-dd6400c0a6da)

</div>

---

## Overview

**NexEnhance** supercharges the stock World of Warcraft interface without throwing it away. Instead of replacing Blizzard's UI with a heavy custom skin, it layers dozens of small, opt-in modules on top of the default frames — class-coloured health, item levels, smart automation, tooltip data, chat cleanup, minimap tools, and more.

Every feature is **self-contained and toggleable**, so you can run the full suite or cherry-pick exactly what you want. The whole thing is built event-driven and tuned for performance, so it stays light on memory and CPU even across long sessions.

- **Enhance, don't replace** — your UI still looks and behaves like Blizzard's, just better.
- **Modular** — 60+ independent modules, each with its own settings and live-apply toggles.
- **Native settings** — a clean options panel built on Blizzard's own Settings API, plus Edit Mode movers for repositionable elements.
- **Performance-first** — local caches, throttled updates, and combat-safe deferrals throughout.

---

## Installation

**Via an addon manager (recommended)**
- [CurseForge](https://www.curseforge.com/wow/addons/nexenhance) — search for **NexEnhance** and install.

**Manual**
1. Download the latest release from the [Releases](https://github.com/Kkthnx-Wow/NexEnhance/releases) page.
2. Extract the `NexEnhance` folder into `World of Warcraft\_retail_\Interface\AddOns`.
3. Restart the game (or `/reload` if already in-game).

On first login you'll get a short **setup screen** offering a handful of recommended Blizzard CVars (auto-loot, locked action bars, class-coloured raid frames, etc.). Everything else is left untouched, and you can re-run it anytime with `/nex install`.

---

## Getting Started

| Command | Description |
| --- | --- |
| `/nex` or `/nexenhance` | Open the options panel |
| `/nex config` | Open the options panel |
| `/nex modules` | List every module and whether it's enabled |
| `/nex toggle <module>` | Toggle a module on/off |
| `/nex install` | Re-run the first-time setup screen |
| `/nex changelog` | Open the in-game changelog |
| `/nex credits` | Open the credits panel |
| `/nex profile` | Open the profile management window |
| `/nex reminder` | Preview the Buff Reminder icons (skinning/positioning) |
| `/nex afk` | Preview the AFK Camera screen |
| `/nexjunk add <item>` | Manage your custom Auto Vendor junk list |
| `/nexfilter` | Manage Chat Filter keywords |
| `/nexlogo` | Replay the login logo flyby |
| `/rl`, `/reloadui`, `//`, `/.` | Reload the interface |

---

## Features

NexEnhance groups its modules into the same themed categories you'll find in the options panel.

### General
- **UI Scale** — pixel-perfect (1 UI pixel = 1 screen pixel) auto-scaling, or a manual scale of your choice. Reload-safe and combat-aware.
- **Number Format** — choose how large numbers abbreviate everywhere: Standard (`1.2k`/`3.4m`), East Asian (`1.2w`/`3.4y`), or full numbers.
- **Camera Zoom** — raise the maximum camera zoom-out distance beyond the default.
- **Cast On Key Down** — fire action buttons on key press instead of release.

### Action Bars
- **Action Bars** — style Blizzard action buttons, abbreviate hotkeys, and toggle macro names, stack counts and keybind text (with adjustable font sizes).
- **Skin Extra Buttons** — give the Extra Action and Zone Ability buttons the standard action-bar frame, with an adjustable scale.
- **Cooldown Text** — formatted countdown numbers on cooldowns, with coloured/plain and decimal/integer styles, a configurable mm:ss threshold, a weeks tier, and optional scaling that hides text on tiny cooldowns.

### Unit Frames
- **Class-Coloured Health** — colour unit-frame health by class (players) or reaction (NPCs) across player, target, focus, boss, party and more, with an optional neutral target strip.
- **Frame Colour** — tint the default unit frames and HUD (player, pet, target, focus, boss, class resources, cast bars, totems, minimap) with a colour of your choice, including a custom border colour.

### Auras
- **Buff Reminder** — show a "Lack" icon when you're missing a buff you can provide. Resizable icons, a Blizzard-style border, and an Edit Mode mover (preview with `/nex reminder`).

### Inventory
- **Item Level** — item levels on equipped, bag, merchant, trade and loot items, with optional gem/socket/enchant info, missing-enchant warnings, BoE/BoA/WuE bind labels, and an adjustable font size.
- **Durability** — lowest equipped-item durability on the Character pane with a per-slot repair-cost tooltip.
- **Mail** — Collect-Gold, Take-All and quick-delete buttons on the mailbox.
- **Already Known** — tint already-known recipes, pets, toys and cosmetics green at vendors, the Auction House and Guild Bank.
- **Junk Icon** — always show the coin icon on Poor-quality bag items, not just at a merchant.
- **Unusable Items** — tint bag/bank icons red for gear your class can't use or that you're too low level for.

### Chat
- **Chat** — a deep set of chat tweaks: flat tabs, edit-box border/positioning/colouring, hide-when-inactive, side-button and scroll-bar hiding, Tab channel switching, quick scroll, sticky whispers, whisper sound, a font-size menu, repositionable Battle.net pop-up and Quick Join button, and **Keyword Auto-Invite**.
- **Chat Copy** — a button to copy the chat window's text.
- **Chat Channels** — tidy channel names, clickable/copyable URLs, abbreviated channel brackets and optional timestamps.

### Filters
- **Chat Filter** — hide spam by keyword or repeated near-identical messages, block strangers/repeat spammers, and append item level + sockets to item links in chat. Manage keywords with `/nexfilter`.

### Tooltip
- **Tooltip** — faction/role icons, hidden realm names and titles, Mythic+ score, quality-coloured border, and configurable health-bar position/height.
- **Tooltip IDs** — append spell, item, quest and other IDs.
- **Tooltip Icons** — show an icon next to the tooltip title.
- **Tooltip Item Level** — average item level on inspected player tooltips (optionally Shift-only).
- **Hover Tips** — tooltips when hovering item/spell links in chat.
- **Mount Source** — a mount's collection status and source on aura tooltips.
- **Vendor Location** — for special barter/curio items, show where to turn them in and Ctrl-Click to drop a map waypoint.

### Skins
Light, targeted restyling of select Blizzard frames — improved, not replaced.
- **Objective Tracker** — hide header backgrounds, tidy the minimise button, optional class-coloured bars.
- **Character Frames** — restyle and resize the Character and Inspect frames.
- **Missing Stats** — surface hidden character-sheet stats (attack power, weapon speed, spell power, regen, movement) and tidy the readouts.
- **Chat Bubbles** — a clean Blizzard-style border on chat bubbles.
- **Details!** — skin Details! Damage Meter windows with a minimalistic look and Blizzard-style border.
- **Quest Navigation** — an estimated arrival time under the super-tracked waypoint arrow.

### DataText
- **Stats** — a movable FPS/latency readout under the minimap, with a memory/addon tooltip, flip order, and class-coloured numbers.
- **Clock** — a minimap clock with a lockout/reset tooltip (daily/weekly resets, saved instances, world events and more).
- **Location** — zone and sub-zone text at the top of the minimap, optionally on mouseover.

### Maps
- **Minimap** — square shape, clean border, status pulse (combat/mail/invites), Easy Volume (Ctrl-scroll), a middle-click shortcut menu, and a button-collecting tray.
- **World Map** — player/cursor coordinates, a smaller windowed map, and fade-while-moving.
- **Map Reveal** — reveal unexplored areas by removing fog of war, with optional dimming of revealed tiles.
- **Wowhead Links** — copyable Wowhead links on the world map (tracked quest) and achievement frame.

### Automation
Hands-off quality-of-life.
- **Auto Vendor** — auto-sell junk and repair (with guild funds) at merchants, plus a custom junk list (`/nexjunk`).
- **Quick Quest** — auto accept/turn-in quests by frequency (regular/daily/weekly), protect costly turn-ins, with a configurable override key and per-NPC ignore.
- **Faster Loot** — instantly clear loot when auto-loot is active.
- **Faster Movie Skip** — instantly confirm the cinematic skip dialog.
- **Decline Duels** — auto-decline player and pet-battle duel requests.
- **Cancel Bad Buffs** — automatically remove cosmetic costume and holiday transforms (Hallow's End costumes, Mohawked!, Turkey Feathers and the like) while out of combat, with an optional announcement. Off by default.
- **Auto Accept Invites** — accept group invites from friends and/or guild.
- **Auto Goodbye** — send a friendly farewell after a dungeon or Mythic+ run.
- **Auto Resurrect** — accept resurrections out of combat, with an optional thank-you emote.
- **Auto Keystone** — slot your Mythic+ keystone when the Challenge Mode UI opens.
- **Auto Hide Tracker** — hide the Objective Tracker during bosses, arenas and (optionally) Mythic+.
- **Delves Automation** — auto-confirm the single-choice borrowed-power popup, with optional chat announcement.

### Announcements
- **Quest Notification** — announce accepted quests and completions to your group, with optional progress updates and a completion sound.
- **Rare Alert** — announce nearby rares and world events the moment their vignette appears, with an anti-burst sound throttle and optional clickable map links.

### Miscellaneous
- **AFK Camera** — an immersive cinematic AFK screen: rotating camera, your character (with class rune and faction crest) alongside a random collected battle pet, clock, logout countdown, rotating account stats and a whisper log. Preview with `/nex afk`.
- **Experience Bar** — a movable replacement for Blizzard's status tracking bar (XP, reputation, honor, Azerite) with fade options and Edit Mode sizing.
- **Animation** — a login logo flyby (`/nexlogo`) and an animated entering/leaving combat banner.
- **Alert Frames** — move achievement/loot/reward popups to the top of the screen, optionally hide the Talking Head.
- **Queue Timer** — a larger, colour-coded LFG/PvP ready countdown with a warning sound.
- **Trade Target Info** — show whether your trade partner is a stranger, friend or guild member.
- **Quick Item Delete** — a simple Yes/No prompt instead of typing DELETE for high-quality and quest items.
- **Drag Frames** — click-and-drag most Blizzard windows to move them.
- **Social Colours** — class-coloured names and difficulty-coloured levels in the Friends, Who and Guild panels.
- **Achievement Screenshot** — auto-screenshot when you earn a new achievement.
- **Profiles** — create, copy, switch and delete settings profiles, plus import/export any profile as a single copy-paste string. Available on the Profiles settings page or via `/nex profile`.
- **Reload UI** — `/rl`, `/reloadui`, `//` and `/.` reload commands.
- **Changelog & Credits** — in-game changelog (auto-shown after updates) and a credits panel.

### Always-On
- **BlizzFix** — a collection of quiet bug fixes for default-UI quirks (no settings; just works).

---

## Configuration

Open the panel with **`/nex`** (or through the Blizzard AddOns settings). Options are grouped into the same categories listed above. Most toggles apply **live**; a few that restyle protected frames note "reload to apply." Repositionable elements (Buff Reminder, Experience Bar, chat toasts) integrate with **Edit Mode**.

---

## Contributing

Contributions, bug reports and ideas are welcome! Open an [issue](https://github.com/Kkthnx-Wow/NexEnhance/issues) or a pull request. When filing a bug, including your client version and a `/reload`-able repro helps a ton.

---

## Credits

NexEnhance stands on the shoulders of incredible addon authors — borrowed with respect, adapted to fit the default UI, and shared back with gratitude. Full attributions live in-game under **`/nex credits`**, including:

- **Elv & the Tukui team** (ElvUI) — AFK module foundation
- **Mortalknight** (GW2 UI) — AFK model animation cycle
- **Siweia** (NDui) and **yleaf** — chat, automation, tooltip, inventory and item-level groundwork
- **p3lim** — QuickQuest, Dashi helpers, and **LibEditMode**
- **Peterodox** (Plumber), **Leatrix** (Leatrix Plus), **lightspark** (ls_Monobrow), **Lars Norberg**, **Shestak**, **Cloudy**, **emelio**, and **Alteredcross**

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
