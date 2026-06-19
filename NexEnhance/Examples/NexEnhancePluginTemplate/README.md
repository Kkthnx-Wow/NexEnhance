# NexEnhance plugin template

This folder is **not** loaded by NexEnhance automatically. Copy it to your WoW
`Interface/AddOns/` directory under a new name (for example `MyNexPlugin`) and
enable that addon in the character limiter list.

## Requirements

- NexEnhance must be installed and enabled.
- Your addon's `.toc` must include `## Dependencies: NexEnhance`.
- Call `NexEnhance:RegisterPlugin({ ... })` once NexEnhance has loaded.

## Where settings appear

- **Esc → Options → NexEnhance → Plugin Manager** — overview cards with enable toggles.
- **Esc → Options → NexEnhance → Plugins** — per-plugin settings (when the plugin
  implements `RegisterOptions`).

## API version

Check `NexEnhance.API_VERSION` before registering if you ship a plugin that must
target a specific NexEnhance release.

## Slash commands

- `/nex plugins` — list installed plugins and their state.
- `/nex toggle ExamplePlugin` — toggle by internal `name` (not display title).

See `Core/Plugins.lua` in the main addon for the full `RegisterPlugin` contract.
