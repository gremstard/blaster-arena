# Blaster Arena

A first-person PvP arena shooter built in Godot 4.7 on top of Kenney's
[Starter Kit FPS](https://github.com/KenneyNL/Starter-Kit-FPS). Peer-to-peer:
one player hosts, everyone else pastes the host's IP. Includes a map editor.

## Playing

1. Run the app (`build/BlasterArena.app`) or open the project in Godot 4.7 and press Play.
2. Pick a name from the list or type one, choose a color. Both are remembered.
3. The host picks a map and clicks **Host game**. The lobby shows the host's LAN IP.
4. Friends type that IP into **Host IP** and click **Join game**. The map is sent to them automatically.
   Over the internet the host needs UDP port 7777 forwarded to their machine.
5. First to 15 kills, or the highest score when the 5-minute timer runs out, wins.
   The match restarts a few seconds later.

| Key | Action |
| --- | --- |
| W A S D | Move |
| Space | Jump (double jump) |
| Left mouse | Shoot |
| Right mouse | Toggle fire mode |
| E / middle click | Next weapon |
| 1 2 3 | Blaster / Repeater / Marksman |
| Tab | Scoreboard |
| Esc | Free the mouse (shows the Leave button) |

### Weapons and modes

| Weapon | Primary | Alternate (right click) |
| --- | --- | --- |
| Blaster | Scatter: 4 pellets, close range | Slug: one heavy shot |
| Repeater | Auto: fast stream | Burst: 3-round burst |
| Marksman | Snap: single strong shot | Scope: zoomed, highest damage |

### Pickups

Pads respawn 20 seconds after use. Health +50 (up to 100). Shield +50 (up to 150).
Speed and Double Damage last 12 seconds and show a glow on the player.
Kill streaks are announced at 3, 5 and 8 kills.

## Map editor

Click **Map editor** in the lobby.

- Left click places the selected piece where the cursor points, snapped to a 0.2 grid.
  Pieces stack on whatever surface you aim at.
- Scroll, `[` `]`, or keys 1-9 change the piece. R rotates 15°, Shift+R rotates 90°.
- X, Delete, or middle click removes the piece under the cursor.
- Right-drag looks around. WASD flies, Q/E go down/up, Shift is faster.
- Spawn points and pickup pads are pieces too. A map needs at least one spawn point.
- **Save map** writes JSON to the user data folder, and the map then appears in the
  lobby's map list on that machine. **Host game on this map** starts a match on it directly.
- Maps live in `user://maps/*.json`, which on macOS is
  `~/Library/Application Support/Godot/app_userdata/Blaster Arena/maps/`.

### Sharing maps

The map the host selects is used by everybody. Joining clients receive it over the
network, build it before spawning, and keep a copy named `<map> (from <host>)` in their
own map list so they can host it later. The host can switch maps mid-match: press Esc
and use the **Change map** dropdown in the top-left. Everyone rebuilds and respawns.

## How the networking works

- Godot's high-level multiplayer over ENet. The host is peer 1 and also plays.
- Each player owns their own movement. A `MultiplayerSynchronizer` on the
  player scene streams position, yaw, pitch, weapon and fire mode.
- The shooter raycasts locally and reports hits to the host. The host owns
  health, deaths, scores, pickups and respawns and broadcasts them.
- On join the host sends the map as JSON. The client builds it, then asks to be spawned.
- The lobby is an overlay inside the arena scene, so the `MultiplayerSpawner`
  and `Players` container already exist on every peer before anyone connects.

## Project layout

| Path | Purpose |
| --- | --- |
| `scenes/main.tscn` + `scripts/main.gd` | Arena root, lobby flow, map hand-off, spawner, respawns |
| `scripts/game.gd` | Autoload `Game`: host/join, registry, colors, scores, timer, settings |
| `scripts/level_builder.gd` | Builds levels from map data, saves and loads map files |
| `scripts/editor.gd` | In-game map editor |
| `scripts/lobby.gd` | Host/join menu |
| `scripts/hud.gd` | Crosshair, health and shield bars, effects, feed, scoreboard, banners |
| `objects/player.tscn` + `objects/player.gd` | Player controller, fire modes, remote body, damage and pickup RPCs |
| `objects/pickup.tscn` + `objects/pickup.gd` | Power-up pads |
| `weapons/*.tres` + `scripts/weapon.gd` | Weapon stats with primary and alternate modes |
| `maps/arena.json` | Built-in map |

## Building the app

Export presets for macOS and Windows are in `export_presets.cfg`. With the export
templates installed:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --export-release "macOS" build/BlasterArena.app
```

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --export-release "Windows Desktop" build/BlasterArena.exe
```

The macOS build is ad-hoc signed, so on another Mac you may need to right-click
and choose Open the first time.

## Testing on one machine

Launch two instances from the terminal. Arguments after `--` are read by the game.

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path . -- --host --name=Host
```

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path . -- --join=127.0.0.1 --name=Guest
```

Other flags: `--map=NAME` picks a saved map when hosting, `--editor` opens the editor,
`--screenshot=/path/out.png` saves the view after 3 s (`--screenshot-delay=N` changes that),
`--test-look` teleports next to the host and aims at them, `--test-hit` kills the host
every 4 s, `--test-pickup` teleports onto the first pickup, `--test-changemap=NAME` makes the host
switch map after 6 s. Add `--headless` to Godot's
own arguments for a windowless peer.

## Adding weapons

Duplicate a resource in `weapons/`, tweak it in the inspector, and add it to
the **Weapons** array on the `Player` node in `objects/player.tscn`.

## License

Code is MIT (Kenney's kit plus this project). Kenney's models, sprites and
sounds are CC0.
