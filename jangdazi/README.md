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

## Assets in use

The `assets/` folder (kept out of git, copy it from the `shooter/assets` folder) provides:

- **City Map/City.fbx**: the playable city, about 400 m square with 100 m towers. The
  `city` map piece loads it with trimesh collision and centers it on the map origin.
  `tools/gen_city_map.gd` raycasts down through the model to find street-level points and
  writes `maps/city.json` with the zone, spawns and loot spots placed on streets. Rerun it
  after replacing the model:

  ```bash
  /Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script tools/gen_city_map.gd
  ```

- **ak-105**, **ak47fbx** and **classic-m4**: weapon models for the AK-105 (auto/burst),
  AK-47 (auto/semi) and the M4 Marksman (snap/scope). Textures are applied by material name from each `textures/`
  folder through `Weapon.build_model`, so a new gun only needs a `.tres` pointing at its
  FBX, a `model_scale`, and a `texture_dir`.

## Character models

Classes are defined in `scripts/game.gd` under `CLASSES`. Each entry names a model file,
a scale, a yaw, an optional texture folder with a material-name to file-prefix map, and mesh
names to hide (for example a gun baked into the character). If the model file is missing
the class falls back to a colored capsule, so the game always runs.

Currently wired:

| Operator | Source | Notes |
| --- | --- | --- |
| FSB Operator | `assets/fsb-operator/fsb.glb` | Converted from the Sketchfab `.blend` with `tools/blend2glb.py`; textures mapped from `textures/`; baked-in Krinkov hidden |
| Free Modular | `assets/FBX/SKM_Character.fbx` | The modular sample pack; shipped without textures, so it renders flat white |
| Insurgent 2 / 7 | `assets/characters/insurgent_2.glb`, `insurgent_7.glb` | Not yet available; capsules until the Fab packs are exported |

To convert a `.blend` (Blender is installed at `/Applications/Blender.app`):

```bash
/Applications/Blender.app/Contents/MacOS/Blender -b path/to/model.blend --python tools/blend2glb.py -- "$PWD/assets/<pack>/model.glb"
```

Put a `.gdignore` file in any folder holding the original `.blend` so Godot does not try to
import it. Textures that the blend referenced from the author's disk are not embedded; map
them by material name in the class entry instead.

For Unreal-only Fab packs: add them to a blank Unreal project, right-click the skeletal
mesh, **Asset Actions > Export** as FBX, and point the class entry at the file.

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
