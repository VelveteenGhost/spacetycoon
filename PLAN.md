# PLAN: Studio port of Sunrise on the Pad

Written Nov 8, 2026. This is the art test from the design doc: if the static fire and the first 20 seconds of
launch hold up in Roblox, on a phone, the art direction is validated.

Sources:

- [Port guide](https://claude.ai/artifact/DBE5H97Cdi4TPWL6Kase9V): scope, layout, lighting, effects, cameras, launch
  timeline and the done checks. This plan follows it and only notes where it departs.
- [Mood study](https://claude.ai/artifact/7MbRCfJcj6yx88JyhUML4X): the reference every shot is compared against.
- `export/`: the finished meshes, textures and `manifest.json`.

## Where things stand

- **The Blender work is done.** `export/` holds 245 meshes in four FBX files (VEH 23, PAD 11, TWR 5, SITE 206
  including 184 tree-belt tiles), 151 texture maps, and a manifest with every mesh's pivot, world box,
  attachments and placement rule. The largest mesh is 2,486 triangles.
- **The Studio place is the default template.** Space Tycoon (place 86616843655467) has a Baseplate, a
  SpawnLocation, default lighting and StreamingEnabled on.
- **Tooling works.** Studio MCP is connected, Open Cloud asset scopes are granted, and Rojo 7.7.1 is installed.
- **Departure from the guide:** its blockout step existed to prove camera framing before the long modelling work.
  Modelling is finished, so framing gets proven with the real meshes instead.

## Phases

Each phase ends on a check, and the next one starts only after it passes.

| # | Phase | Output | Check |
| --- | --- | --- | --- |
| 0 | Setup | Repo layout, place settings, generated manifest module | Place opens clean, no avatar, no errors |
| 1 | Import pilot: VEH | Vehicle templates, verified and repaired | 23 meshes, sizes within 1%, maps present, nozzle exits at 28.6 studs |
| 2 | Import PAD, TWR, SITE | All templates | Same checks, per mesh, against the manifest |
| 3 | Scene assembly | Whole site placed, ground and sea | Guide's scale checks; stills from all ten camera positions |
| 4 | Cameras, timeline, HUD | T−30 to T+25 plays on the pad set | Each camera matches its mood-study frame side by side |
| 5 | Lighting | Sunrise, morning and night; three skies; floods | Static-fire still beside the mood study |
| 6 | Effects | Flame, ground cloud, vents, ice, beacons, surf | Liftoff at full ground cloud holds frame rate on a phone |
| 7 | Altitude set | Max-Q through stage-2 ignition, T+25 to T+136 | Separation reads; MVac hidden until the stages part |
| 8 | Done checks | The guide's list | Eli's real-phone look and the side-by-side |

### 0. Setup

- Repo: `src/` mirrors the game tree and is the source of truth for code. I push it into Studio over MCP and keep
  a `default.project.json` for Rojo tooling. `tools/manifest_to_luau.py` turns `export/manifest.json` into
  `src/ReplicatedStorage/Port/Manifest.luau`, so pivots, attachments and placement rules come from one place.
- Place: StreamingEnabled off, so cameras 10 km out still see the whole site. CharacterAutoLoads off, since the
  shot is camera-only. Remove the Baseplate and SpawnLocation.
- Reference frames: render the mood study locally from its source and capture each of the ten cameras at fixed
  T-times, plus the static-fire still. They go in `previews/reference/`, which git ignores. They're the target
  for every check from phase 3 on.

**Progress, Nov 8:** StreamingEnabled and CharacterAutoLoads are off, the Baseplate and SpawnLocation are gone,
`ServerStorage.PortTemplates` exists for the repeated SITE props, and the manifest module is generated. Writing
`Lighting.Technology` from a script is confirmed blocked (Eli sets it). Reference frames are still to do.

### 1. Import pilot: VEH.fbx

The vehicle is in every shot and is the smallest file with the most moving parts, so it goes first.

1. Upload `export/fbx/VEH.fbx` through Open Cloud as a Model, then insert it into `ServerStorage.PortTemplates`.
2. Verify against the manifest: every name present, `size_studs` within 1%, a SurfaceAppearance with the right
   maps on each material, and the nozzle exits at 28.6 studs.
3. Repair what didn't survive: scale with `ScaleTo`, `PivotOffset` from `pivot_offset_studs`, attachments from
   `local_studs`, Anchored, collision off, CollisionFidelity Box, RenderFidelity Precise.
4. Rehearse the moving parts in Edit mode: grid fins, legs and fairing hinges turn about their hinge attachments,
   and stage 2 separates from the interstage.

If the pilot loses textures or names wholesale, Eli runs Studio's 3D Importer on the four files instead (the
README's steps, about 10 minutes). I then do the same verification and repair.

**Pilot result, Nov 8 (asset 130623056517308, inserted as `Workspace.VEH_Pilot`):**

- Kept: all 23 names, every single-material SurfaceAppearance with the right maps, and every pivot.
- Fixed in Studio: the model arrives at 1 stud per metre and yawed about 135°. `PivotTo` the origin with a 180°
  yaw plus `ScaleTo(1 / 0.28)` puts every part within 0.001 studs of the manifest's position, size and pivot.
  Nozzle exits sit at 28.57 studs and the fairing tip at 272.68. The 28 attachments, Precise and Box are in.
- Part frames come in turned 180° about Y from the table axes. So attachments and hinges are placed from the
  manifest's world positions, not from `local_studs`.
- **Broken: two-material meshes.** The importer doesn't split them. Each one becomes a single MeshPart with two
  SurfaceAppearances, the second empty, and a MeshPart renders only one. On the engines and MVac, the surviving
  map is the 256 px inner soot set, so the outer bells wear the wrong material. The same will hit `SITE_Car`,
  `SITE_FloodPole` and `SITE_Hangar` (13 meshes in all).
- Fix: split those 13 meshes in Blender into one object per material (`<name>` and `<name>_Inner`, `_Paint`,
  `_Lens`, `_Door`). Re-export VEH.fbx and SITE.fbx, then upload VEH as a new revision of the same asset, not a
  new one.

### 2. Import PAD, TWR, SITE

Same flow and checks, run by `tools/import_fix.py <GROUP> <path>`. SITE.fbx is 17.3 MB, under the 20 MB upload
cap, and waits for the split re-export.

**Progress, Nov 8:** PAD (138977096256584) and TWR (86272731500333) are uploaded and verified: every mesh is within
0.004 studs of the manifest, with one SurfaceAppearance each. VEH, PAD and TWR sit in `Workspace.Port` at their
table positions. Asset IDs are tracked in `ASSETS.md`.

### 3. Scene assembly

A re-runnable `SceneBuilder` clears and rebuilds `Workspace.Port` from the templates and the manifest. It runs at
edit time, so the set can be walked in Studio and the place saves the result. Every part is positioned from its
manifest world box and pivot, whatever the importer did.

- Modelled in place: vehicle, pad, mount, tower, spheres, tanks, hangar, range ops, water tower, the flag and its
  rig, and the 184 belt tiles.
- Placed by rule (from the manifest notes): masts ×3, flood poles ×4, cars ×34 with the fixed paint mix, fence
  posts ×145, power poles ×40, distant pads ×3, and 1,600 scrub and palmetto from the seeded rule.
- Beams: fence rails, power conductors, mast wires and guys, with the sags in the notes.
- Ground and sea: Terrain for the ground, beach, dune ridge and water. If Terrain costs too much memory on a phone
  at this size, the far ground switches to large flat parts.
- Check: fairing tip at 272.6 studs, tower roof at 314, tower mast at 371. Stills from all ten camera positions,
  with special attention to the far geometry (tree tiles reach 23,800 studs from the pad).

### 4. Cameras, timeline and HUD

The art test has no gameplay, so a client-side Director runs everything: the timeline, the ten cameras and the
HUD.

- Pull the vehicle's ascent profile, pitch program, camera aim rules and FOV ramps from the mood study's source.
- Timeline: the 13 events from T−30 to T+136. The pad set runs to about T+25, then a camera cut moves to the
  altitude set (phase 7).
- Motion on the pad: fuel arm −72° about its hinge from T−25 to T−19 (smoothstep), clamps +25° over 0.4 s at T−0,
  then the ascent.
- Cameras: the guide's ten, scriptable and smoothed, with a lead on the vehicle's velocity and shake delayed by
  the speed of sound. Narrower than 1°: move the camera closer along the same line of sight.
- HUD: a ScreenGui with the LIVE tag, camera name, telemetry, T-clock and lower third.

### 5. Lighting

Use the guide's table as the starting point: Future lighting, Atmosphere, clouds, bloom, colour grade, sun rays,
and the exposure dip at ignition. Then tune against the reference frames. Sunrise comes first as the hero look;
night with the floods comes last.

Roblox lights reach only 60 studs, so the floods are props: emissive lenses plus a glow sprite. The real light
comes from SpotLights within 15 m of the vehicle and a warm SurfaceLight under each pole.

### 6. Effects

- First, author the effect textures that aren't in `export/` yet: three top-lit billows, a flame glow, a plume
  streak, a four-shape ice-shard flipbook, a contrail Beam texture, a lamp glow and a foam strip. Upload them as
  Images.
- Then build in the guide's order: flame tongue, shock diamonds and halo; ground cloud; vents; ice shedding;
  beacons; surf.
- Check at the busiest moment, liftoff with the ground cloud at its fullest. Use the MicroProfiler for frame time
  and count triangles, lights and live particles.

### 7. Altitude set

A separate area where the vehicle stays near the origin while a backdrop moves past: an ocean-and-land plane with
haze, a horizon gradient and a curved limb.

- Covers Max-Q, MECO, separation, second-stage ignition with the MVac heat ramp, and the booster tumbling about its
  centre of mass.
- Contrail: particles for the first 6–8 s, then aging smoke Beams.
- Rebuild Cam 2 (tracker) here at 1° or wider. Cams 12 and 14 ride the vehicle.

### 8. Done checks

These are the guide's list: scale, motion, separation, all ten cameras side by side, MicroProfiler on a
mid-range laptop, and Eli looking at the flame and glows on a real phone.

## Risks to retire early

- **Import fidelity.** Answered by the VEH pilot: names, pivots and single-material maps survive. Scale and yaw
  are fixed by script, and two-material meshes must be split before upload (phase 1).
- **Far geometry.** Tree tiles sit up to 23,800 studs out and Cam 2 at about 40,000. Position jitter and
  distance culling show up in the phase 3 stills; the guide's altitude set already covers the flight.
- **Phone budget.** About 342,000 triangles as placed, 1,600 vegetation instances, then particles on top. Shared
  meshes keep the vegetation cheap, and phase 6 measures the worst case.
- **Lighting.Technology isn't scriptable over MCP.** Reading it fails with a capability error, so Eli sets Future by
  hand (see `REQUESTS.md`).
