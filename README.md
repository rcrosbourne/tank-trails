# TankTrails

Room-level dungeon navigation and tank notes for WoW Forever. Spec: `docs/superpowers/specs/2026-10-12-tanktrails-design.md`.

## Build
- Toolchain (once): `python3 -m hererocks .lua -l 5.1 -r latest`, then `.lua/bin/luarocks install busted`.
- Tests: `.lua/bin/busted`.

## Install
`tools/install.sh "/Applications/World of Warcraft/_classic_beta_/Interface/AddOns"`, then run `docs/superpowers/notes/in-game-checklist.md`.

## Commands
`/tt help` lists the commands in game; see also spec §7.5.

## Layout
- `TankTrails/Model` pure logic, `TankTrails/Wow` game adapters, `TankTrails/UI` frames, `TankTrails/Core` wiring, `TankTrails/Data` shipped dungeons.
