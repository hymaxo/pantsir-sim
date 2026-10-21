# Pantsir SX Simulator

[Русский](README.md) | **English**

A prototype simulator of the crew workstation of a Pantsir air-defence missile and gun system, built with Godot 4. It models detection and tracking of air targets, switching between the commander's and the operator's screens, laying, guided missile launches and gun fire.

Current version: `1.1.0`.

> This is a game / research simulation. System parameters and behaviour are approximate and do not claim to reproduce the real system accurately.

## Download

Ready builds for Windows and Linux are on the [Releases](https://github.com/hymaxo/pantsir-sim/releases) page. Unpack the archive and run `PantsirSim.exe` (Windows) or `PantsirSim.sh` / `PantsirSim.x86_64` (Linux). The executable and the `.pck` file must stay in the same folder.

## Features

- main menu with complex selection (Pantsir-S1, Pantsir-SM; SM-SV is work in progress) and window settings;
- search radar (СОЦ) with a rotating beam, measurement errors, radial velocity, ground clutter and an R⁴ detection range driven by target RCS;
- S1: a single search radar beam (60 rpm) and an elevation sector scan — the radar picks the number of sectors from the upper boundary and the missile's maximum range; SM: two back-to-back beams (30 rpm), no sectors;
- СПЗ "Manual settings" window: speed limit, lower height and angle boundary, RCS threshold (saved between launches);
- tracking radar (МРЛС) with acquisition (3 of 5 detections) and automatic tracking (ДПЦ → АС);
- commander's screen with the radar picture and the target table;
- operator's screen with a thermal sight, engagement zone and guidance channels;
- 6DOF missile model with command guidance (П-РЛ → ЦУ), from War Thunder data: 95Ya6 on the S1 (20 km); on the SM the 95Ya6M (40 km, 1700 m/s, no fuze — detonated on the complex's command, forward-directed fragments) and the small TKB-1055 (7 km, four per container in place of one 95Ya6M);
- missile selector for the next launch — the button under «Запросить перезарядку»;
- guns with lead calculation and an automatic fire mode (АО / АВТ-П);
- reload request: choose the load per tube and gun (on the SM a tube takes a 95Ya6M or a 4× TKB-1055 container), 30 s with no firing;
- procedural 80×80 km terrain with forest that attenuates radar signals;
- targets: drone, terrain-following cruise missile, MLRS salvo;
- Linux and Windows export, automatic release builds with GitHub Actions.

## Requirements

- Godot Engine `4.7` — the version set in `project.godot`;
- Forward Plus renderer;
- to build executables — export templates for the same Godot version.

Compatibility with other Godot 4 versions has not been tested.

## Quick start

### From the editor

1. Open the Godot Project Manager.
2. Click **Import** and choose `project.godot` in the project root.
3. Wait for the resource import to finish.
4. Run the project with **F5** or **Run Project**.

The main scene is `res://Scenes/MainMenu.tscn`. The battle is `res://Scenes/main_system.tscn`; `Esc` returns from the battle to the menu.

### From the command line

If the Godot executable is on your `PATH`:

```bash
godot --editor --path .
```

Run the project without the editor:

```bash
godot --path .
```

## Controls and workflow

| Action | Control |
|---|---|
| Switch commander's / operator's screen | `C` |
| Fire the selected weapon | `Space` |
| Zoom out / increase displayed range | `-` |
| Zoom in / decrease displayed range | `+` or `=` |
| Select a track | Left click on a row of the commander's table |
| Scroll the track table | Mouse wheel over the table |
| Power, search radar or sector tracking | On-screen / panel buttons |
| Select missiles or guns | `ЗУР` / `ПШК` buttons on screen |
| Spawn an air target | `ЗАСПАВНИТЬ РАНДОМНУЮ ЦЕЛЬ` button |
| Spawn a ballistic salvo | `ЗАЛП MLRS HIMARS` button |

What `+` and `-` do depends on the active screen:

- on the commander's screen they change the radar range in 5 km steps between 5 and 50 km;
- on the operator's screen they change the manual optical zoom between `1x` and `60x`.

Basic workflow:

1. Switch on the main power.
2. Switch on the search radar.
3. Spawn a random target or a ballistic salvo.
4. Wait for a stable track to appear in the commander's table.
5. Click its row — sector tracking starts automatically.
6. Switch to the operator's screen with `C`.
7. Choose `ЗУР` or `ПШК` and fire with `Space`.

A missile can be launched only when the power is on, a track is selected and tracked, the target is inside the guidance sector, the two-second cooldown has passed and at least one of the four guidance channels is free.

## Architecture

```text
targets in the radar_targets group
        ↓
RadarScanner — visibility and detection range
        ↓
GlobalPantsirSystem.targets — current observations
        ↓
search / sector radar — track creation and ageing
        ↓
GlobalPantsirSystem.tracks
        ↓
commander's screen → target selection → turret and optics laying
        ↓
operator's screen → missile launch or gun fire
```

`GlobalPantsirSystem` is an autoload that holds all shared simulation state: power, radar states, targets and tracks, the selected target, drive positions, ammunition, cooldowns and guidance channels. Its state survives scene changes until the project tree is restarted.

Every `RadarScanner` packet carries the time of the actual measurement. A track is stored at that time, and the optics, launcher, indicators and missile channels all get the same prediction for the current physics tick from `GlobalPantsirSystem.get_predicted_track_state()`. This removes the hidden delay of one 50 ms radar packet and keeps all consumers on the same coordinates.

### Main files

| Path | Purpose |
|---|---|
| `project.godot` | Engine version, main scene, Input Map, window and autoloads |
| `Scenes/main_system.tscn` | Battle scene: virtual 3D world, workstation and test buttons |
| `Scripts/GlobalPantsirSystem.gd` | Core logic of radars, tracks, guidance, weapons and target spawning |
| `Scripts/RadarScanner.gd` | Collects targets from `radar_targets`, checks range and line of sight |
| `Scripts/c_screen.gd` | Commander's screen: radar, track table and target selection |
| `Scripts/o_screen.gd` | Operator's screen: optics, thermal view, weapons and guidance channels |
| `Scripts/MainSystem.gd` | Screen switching, zoom and launch sound |
| `Scripts/Drone_Lutiy.gd` | Drone behaviour |
| `Scripts/tomahawk.gd` | Cruise missile behaviour |
| `Scripts/BallisticTarget.gd` | Ballistic target for the salvo |
| `Scripts/PantsirMissile.gd` | 6DOF flight, autopilot, command guidance and fuze |
| `Scripts/MissileFlightConfig.gd` | Motor, aerodynamics, fin and limit parameters of the missile |
| `Docs/Missile6DOF.md` | 6DOF model, mapping to WT data and calibration assumptions |
| `Scripts/PantsirBullet.gd` | Shell ballistics and hit test |
| `Thermal.gdshader` | Thermal image post-processing |
| `export_presets.cfg` | Windows and Linux export presets |

### Directory layout

```text
.
├── Scenes/       # main and reusable scenes
├── Scripts/      # GDScript simulation and UI logic
├── meshes/       # imported 3D models (drone, cruise missile)
├── Sounds/       # sound effects
├── stations/     # workstation images
├── Tests/        # headless missile physics tests
├── .github/      # build and release workflow
├── project.godot
├── export_presets.cfg
└── Thermal.gdshader
```

`.import` and `.uid` files and the `.godot/` folder are created or used by Godot for resource import and identification. `.godot/` is excluded from Git.

## Key simulation parameters

All distances are in nominal metres.

| Parameter | Current value | Where to change |
|---|---:|---|
| Initial display range | 30 000 | `GlobalPantsirSystem.MAX_RANGE` |
| Search radar speed | 30 rpm, 2 beams (SM) / 60 rpm, 1 beam (S1) | `SCAN_SPEED_RPM`, `SOC_SINGLE_BEAM_SCAN_SPEED_RPM` |
| Search radar beam width | 6° | `BEAM_WIDTH_RAD` |
| Sector tracking limit | ±45° | `SECTOR_WIDTH_RAD` |
| Track lifetime without updates | 5 s (S1: at least 2.5 scan cycles) | `TRACK_DECAY_TIME` |
| Gun ammunition | 1200 | `ammo_guns` |
| Muzzle velocity | 960 | `GUN_MUZZLE_VELOCITY` |
| Interval between shots | 0.024 s | `GUN_RATE_OF_FIRE` |
| Missile load | 12, 3 on each of 4 arms | `missile_tubes_loaded` / `ammo_missiles` |
| Arm preparation before launch | 1 s | `MISSILE_ARM_RAISE_TIME` |
| Interval between launches | 2 s | `MISSILE_COOLDOWN_TIME` |
| Missile guidance channels | 4 | `guidance_channels` |
| Missile top speed | 1300 m/s (95Ya6) / 1700 m/s (95Ya6M) / 820 m/s (TKB-1055) | `MissileFlightConfig.maximum_speed_mps` |
| Missile maximum range | 20 000 m (95Ya6) / 40 000 m (95Ya6M) / 7000 m (TKB-1055) | `MissileFlightConfig.maximum_distance_m` |
| Missile lifetime | 30 s (95Ya6) / 35 s (95Ya6M) / 13.5 s (TKB-1055) | `MissileFlightConfig.maximum_flight_time_s` |
| Reload time | 30 s | `RELOAD_TIME_S` |

## Adding a new target type

A new target must:

1. Extend `Node3D`/`CharacterBody3D` and have `global_position` and `velocity`.
2. Get a unique id when it enters the tree:

   ```gdscript
   radar_id = GlobalPantsirSystem.get_new_uid()
   ```

3. Join the detectable targets group:

   ```gdscript
   add_to_group("radar_targets")
   ```

4. Provide the `radar_id` and `critical_hit` fields. The optional `radar_detection_range` field overrides the default 30 km detection range.
5. Implement `take_damage(is_critical: bool)` if it can be damaged.
6. Have its own `.tscn` scene and be wired to a spawner in `GlobalPantsirSystem.gd`.

`Drone_Lutiy.gd`, `tomahawk.gd` and `BallisticTarget.gd` can be used as templates.

## Building

The export presets are in `export_presets.cfg`.

Linux:

```bash
godot --headless --path . --export-release "Linux" build/linux/PantsirSim.x86_64
```

Windows:

```powershell
godot --headless --path . --export-release "Windows Desktop" build/windows/PantsirSim.exe
```

The `build/` folder is not stored in Git.

### Automatic builds and releases

On every push to `main` and every pull request, the `.github/workflows/build.yml` workflow installs Godot 4.7.2 with export templates, imports the project, runs `Tests/MissilePhysicsTest.tscn` and exports Windows and Linux builds. The builds are available as run artifacts.

A release is made by pushing a version tag:

```bash
git tag v1.1.0
git push origin v1.1.0
```

The workflow builds `PantsirSim-<version>-windows.zip` and `PantsirSim-<version>-linux.zip` and publishes them as a GitHub Release, with notes from `.github/release-notes/<tag>.md`. Before tagging, update `config/version` in `project.godot`, the versions in `export_presets.cfg`, and add the release notes file.

## Checking changes

The headless suite `Tests/MissilePhysicsTest.tscn` checks the 6DOF response, the speed and range profile, independence from render FPS, load factor limits, the fuze, guidance and measurement filtering. Run it with:

```powershell
godot --headless --path . Tests/MissilePhysicsTest.tscn
```

After changing the logic, also check by hand:

1. The project opens without import or GDScript parse errors.
2. Main power switches on both screens.
3. The search radar detects a random target.
4. The selected track is followed and visible in the optical channel.
5. Guns and missiles reduce their ammunition.
6. A hit target becomes damaged or is removed after the explosion.
7. The salvo creates six targets two seconds apart.
8. The Linux/Windows export runs outside the editor.

To check that the project loads after installing Godot:

```bash
godot --headless --path . --editor --quit
```

## Known limitations and technical debt

- physics runs at 200 ticks/s, which can load weaker machines noticeably;
- UI and simulation state are tightly coupled through the global autoload;
- most of the UI is drawn by hand in `_draw()`, so layout changes need coordinate edits in code;
- shell collisions are checked against every target, without a spatial index;
- the origin of some third-party models and images is not documented yet (complex photo sources are in `Assets/Complexes/CREDITS.md`).

## Ideas for further development

- split the global logic into radar, tracking, weapons and scenario subsystems;
- move balance values into Godot `Resource`s so they can be changed without editing code;
- replace hand-placed UI coordinates with `Container` nodes and adapt to resolution;
- add a separate test scene for targets and weapons;
- document the origin and licences of all external assets.

## AI policy

The project was originally written by hand. On top of that existing base, AI then did a huge amount of work to turn it into something playable.

You are welcome to suggest improvements or open pull requests made with the help of AI — but only if you clearly understand what you are adding and how, and you know the difference between vibe coding and using AI to write code.

## License

No license has been chosen — all rights are reserved by the project author. The source code is open to read, but it may not be used, copied, modified or distributed without the author's permission. Third-party images are distributed under their own licences (see `Assets/Complexes/CREDITS.md`).

## Disclaimer

This is a hobby project based solely on open-source information. It has no connection whatsoever to the Ministry of Defence of the Russian Federation or to the developer and manufacturers of the Pantsir system (KBP Instrument Design Bureau named after A. G. Shipunov, Ulyanovsk Mechanical Plant, the Tikhomirov Scientific Research Institute of Instrument Design and other enterprises and design bureaus), and it uses none of their internal or restricted materials. Names of systems and products are used for identification only.
