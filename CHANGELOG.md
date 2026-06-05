# NexEnhance — Changelog

> A lightweight, modular framework that **enhances** the default Blizzard UI — it improves what's already there instead of replacing it.

All notable changes to this project are documented here. This project follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

[1.2.0]: https://github.com/Kkthnx-Wow/NexEnhance/releases/tag/v1.2.0
[1.1.0]: https://github.com/Kkthnx-Wow/NexEnhance/releases/tag/v1.1.0
[1.0.0]: https://github.com/Kkthnx-Wow/NexEnhance/releases/tag/v1.0.0
