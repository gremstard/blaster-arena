# JangDazi

A city siege game in Godot 4.7: battle royale drop-ins and looting, Rainbow Six style
zone control, peer-to-peer over a pasted IP. Forked from Blaster Arena (the folder above)
and Kenney's CC0 Starter Kit FPS.

## The game

- **Two sides.** Defenders (FSB Operator, Free Modular) drop into the central plaza.
  Attackers (Insurgent 2, Insurgent 7) drop in at the city edge.
- **Round flow.** *Setup* (40 s): both sides loot. *Siege* (4 min): attackers must capture
  the control zone in the plaza, or eliminate every defender. Defenders win by wiping the
  attackers or holding out until the timer. No respawns inside a round.
- **The ring.** During the siege a red ring closes from the city edge to the plaza. Anyone
  outside takes damage every second.
- **Winning changes sides.** If the attackers win they take the city and defend it next
  round. Defenders who win stay defenders. First side to 3 round wins takes the match.
- **Loot economy.** Everyone starts with a pistol. Center loot starts scarce (2 crates)
  and grows by 2 each round. Outer loot starts rich (28) and shrinks by 4 each round.
  Crates hold the Repeater, Blaster, Marksman, overshield, health, and power-ups.
- **Friendly fire is off.** Teammates' name tags show through walls.

| Key | Action |
| --- | --- |
| W A S D | Move (steer while dropping) |
| Space | Jump (double jump) |
| Left mouse | Shoot |
| Right mouse | Toggle fire mode |
| E / 1-4 | Switch between owned weapons |
| Tab | Scoreboard |
| Esc | Menu (host: Start match, Change map, Leave) |

## Playing

1. Run the game. Pick a name and an operator. The operator sets your preferred side;
   the host balances teams when the match starts.
2. Host clicks **Host game** and shares the LAN IP shown. Friends paste it and **Join game**.
   Over the internet, forward UDP port 7777 to the host.
3. Everyone warms up in the plaza. The host presses Esc and clicks **START MATCH**.
4. Players who join mid-round spectate until the next round.

## Character models from Fab

The character packs are Unreal-format, so Fab only offers "Add to library". To use them:

1. Install Unreal Engine from the Epic Games Launcher and create a blank project.
2. In the launcher's Fab library, add each pack to that project.
3. In Unreal's Content Browser, right-click the skeletal mesh (and its animations if you
   want them), choose **Asset Actions > Export**, and save as FBX. Include textures.
4. Copy the FBX files into `assets/characters/` with these names:

| Operator | File |
| --- | --- |
| FSB Operator | `fsb_operator.glb` (or convert the FBX to glTF in Blender) |
| Free Modular | `free_modular.glb` |
| Insurgent 2 | `insurgent_2.glb` |
| Insurgent 7 | `insurgent_7.glb` |

The paths are in `scripts/game.gd` under `CLASSES`. If you keep FBX, change the extension
there. The game checks whether the file exists and falls back to a colored capsule if not,
so nothing else changes. Animations are not yet driven; that is the next step once the
models are in.

## Map editor

Same editor as Blaster Arena with city pieces: buildings (small, mid, tall, wide), 2 m
blocks for stairs, 20 m ground slabs, Kenney platforms and walls, plus markers for the
control zone, defender and attacker spawns, and center and outer loot spots. A map needs
one zone, at least one spawn of each side, and some loot spots. Saved maps live in
`user://maps` and the host's map is sent to everyone on join.

## Project layout

| Path | Purpose |
| --- | --- |
| `scripts/game.gd` | Autoload: connection, classes, teams, phases, ring and capture state |
| `scripts/main.gd` | Round manager: phases, drops, loot spawning, capture, ring damage, side swaps |
| `scripts/level_builder.gd` | Builds city maps from JSON; box buildings, zone, spawn and loot markers |
| `objects/player.gd` | Controller, inventory, drop-in, team rules, damage RPCs |
| `objects/loot.gd` | Loot crates |
| `maps/city.json` | Built-in generated city |

## Testing on one machine

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path . -- --host --name=Host --class="FSB Operator" --fast --autostart=5
```

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path . -- --join=127.0.0.1 --name=Guest --class="Insurgent 2"
```

`--fast` shortens phases (6 s setup, 30 s siege). Other flags: `--autostart=N` starts the
match after N seconds, `--test-zone` puts you in the zone when the siege starts,
`--test-hit` kills the host every 4 s, `--screenshot=PATH`, `--screenshot-delay=N`,
`--editor`, `--map=NAME`. Add `--headless` before `--` for a windowless peer.

## Building

Export presets for macOS and Windows are included:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --export-release "macOS" build/JangDazi.app
```

## License

Code MIT. Kenney assets CC0. Fab character packs keep their own licenses and are not in this repo.
