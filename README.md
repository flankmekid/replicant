# Replicant

The scripts of Replicant, a souls-like PvP game on Roblox, written in Luau and synced
with [Rojo](https://rojo.space).

- **Combat:** 14 weapons in five families, with branch and hybrid weapons. Each has
  M1 combos, an M2 guard break, an E, and a throw, plus block, parry, a guard bar,
  and a burst. The server owns every hit.
- **Movement:** dash charges, slides, wall runs, wall climbs, ledge grabs, and fall
  damage with a roll.
- **Progression:** races with racial skills, weapon levels and class quests, skill
  points and stats, a spellbook, armor with transmog, and titles.
- **World:** spires to rest at and travel between, quests, mobs and bosses, and a
  downed state with carry and execute.
- **Saves:** ProfileStore, with session locking.

## What is in this repository

This repository holds the code only. The place file holds the rest, and it is not
included: the map, the UIs in StarterGui, the weapons and equipment in ServerStorage,
the NPCs, and the asset folders (`ReplicatedStorage/assets`, `music`, `effects`, and
the others listed under `ignoreTrees` in `default.project.json`). The scripts look
these up by name, so a fork needs its own place with the same instance names. A fork
also needs its own footstep script: the one in the game is not included, because it
has no license.

## Getting started

1. Install [Rokit](https://github.com/rojo-rbx/rokit), then run `rokit install` in
   this folder. It installs the pinned versions of Rojo, StyLua, and selene.
2. Build a place file with `rojo build -o build.rbxl`, or open your place in Studio
   and run `rojo serve` with the Rojo plugin.

## Before you publish a fork

- Put your own developer accounts in
  `src/ServerScriptService/modules/DevConfig.luau`.
- Pick your own data store name in `src/ServerScriptService/modules/dataManager.luau`.
- Replace the asset IDs. Animations and some audio only play in experiences owned by
  the account that uploaded them.

## Project layout

```text
src/
  ReplicatedStorage/        Shared modules, client combat handlers, configs, remotes
  ServerScriptService/      Server scripts: combat, data, quests, spires, AI
  StarterCharacterScripts/  Movement, lock-on, fall damage, per-character scripts
  StarterPlayerScripts/     Input, HUD, and menus
docs/
  combat-design.md          Why the combat timings are what they are
  systems-design.md         Why the other systems work the way they do
```

## Development

```sh
stylua src            # format
stylua --check src    # check formatting
selene src            # lint
```

Read `CONVENTIONS.md` before you change code. It covers naming, comments, and logs.

## License

The code written for Replicant is under the MIT license, in `LICENSE`. The bundled
third-party libraries keep their own licenses, listed in `THIRD_PARTY.md`.
