# Sunrise on the Pad: meshes

Finished meshes for the Roblox port of mood study 02, built to the
[port guide](https://claude.ai/artifact/DBE5H97Cdi4TPWL6Kase9V). Coordinates are the guide's table
coordinates: origin at the pad centre on the ground, +X east toward the ocean, Y up.

| Path | What |
| --- | --- |
| `fbx/VEH.fbx` | `VEH_S1_Body`, `VEH_Engine_SL_0`–`8` with `VEH_Engine_SL_0_Inner`–`8_Inner`, `VEH_S1_Interstage`, `VEH_GridFin_0`–`3`, `VEH_Leg_0`–`3`, `VEH_S2_Body`, `VEH_MVac` with `VEH_MVac_Inner`, `VEH_Fairing_A`/`B` |
| `fbx/PAD.fbx` | `PAD_Mount`, `PAD_Apron`, `PAD_Apron_Centre`, `PAD_Apron_Asphalt`, `PAD_Clamp_0`–`3`, `PAD_Deflector`, `PAD_Trench`, `PAD_Lines` |
| `fbx/TWR.fbx` | `TWR_Lattice_A`/`B`/`C`, `TWR_CrewArm`, `TWR_FuelArm` |
| `fbx/SITE.fbx` | `SITE_` masts, flood pole with `SITE_FloodPole_Lens`, water tower, spheres, tanks, hangar with `SITE_Hangar_Door`, range ops, car with `SITE_Car_Paint`, fence post, power pole, distant pad, flag with `SITE_Flag_Rig`; `VEG_Scrub_A`–`C`, `VEG_Palmetto_A`/`B`, `VEG_TreeClump_A`–`C`, `VEG_Belt_0`–`183` |
| `textures/` | `<Material>_<Color/Normal/Roughness/Metalness>.png` for SurfaceAppearance, at most 1024 px. Color is sRGB; Normal (OpenGL, +Y), Roughness and Metalness are linear |
| `manifest.json` | Per mesh: triangles and budget, pivot, size, `pivot_offset_studs`, materials and maps, attachments, placement notes |

The FBX files are in metres, Y-up, with identity transforms and the textures embedded. Every mesh is under the
guide's triangle budget. The whole site as placed is about 342,000 triangles: 227,000 in the 1,600 scrub
and palmetto instances, 75,000 in the tree belts, 11,000 in the vehicle.

## Import

1. 3D Importer, file unit metres (1 m = 3.571 studs). Check: the nozzle exits sit at 28.6 studs.
2. If a MeshPart's pivot lands at its bounding-box centre, set `PivotOffset` to `pivot_offset_studs`.
3. If the importer doesn't create `SurfaceAppearance` from the embedded maps, add one per material from
   `textures/`.
4. Add the attachments from the manifest (`local_studs` is relative to the pivot).
5. CanCollide, CanTouch and CanQuery off; CollisionFidelity Box. RenderFidelity Precise on the vehicle,
   the tower and the tree belts.

## Placement

Meshes with a world pivot in the manifest are modelled in place. Repeated props are modelled once at the
origin, and their `notes` give the placement rule: `SITE_Mast` ×3, `SITE_FloodPole` ×4, `SITE_Car` ×34,
`SITE_FencePost` ×145, `SITE_PowerPole` ×40, `SITE_DistantPad` ×3, and 1,600 `VEG_Scrub` /
`VEG_Palmetto` instances (the rule is in `VEG_Scrub_A`'s notes). The mood study's 3,600 trees are already in
the `VEG_Belt` tiles; `VEG_TreeClump_A`–`C` are for trees placed by hand near the cameras.

Every object carries one material, because Roblox gives each MeshPart only one. Five meshes therefore ship
as two parts that share the original origin: `VEH_Engine_SL_<k>` and `VEH_Engine_SL_<k>_Inner` (the inner
bell, for the firing glow), `VEH_MVac` and `VEH_MVac_Inner`, `SITE_Car` and `SITE_Car_Paint`,
`SITE_FloodPole` and `SITE_FloodPole_Lens`, `SITE_Hangar` and `SITE_Hangar_Door`. Give both parts of a pair
the same CFrame, or keep them in one Model; gimbals, hinges and placement rules are unchanged. In the
manifest, `parts` and `part_of` link each pair, attachments stay on the main part, and `triangles_with_parts`
is the count the budget applies to.

## Studio checks

- `SITE_Flag`: DoubleSided on. `SITE_Flag_Rig` (Root, Fly0–Fly5) imports with it; drive the Fly bones with a
  travelling sine wave while Cam 6 is live.
- `VEH_Fairing_A` and `_B`: DoubleSided on when they open, since their insides show.
- Tint `SITE_Car_Paint` with `SurfaceAppearance.Color`; the six paints and the per-car mix are in
  `SITE_Car`'s notes.
- `SITE_FloodPole_Lens` is drawn lit. By day set its `SurfaceAppearance.Color` to #3b3e43; restore white at
  night.
- Fence rails, power conductors and mast wires are Beams between the manifest attachments. Widths and sags
  are in the notes.
- `VEG_Belt_0`–`183` are split so that no MeshPart exceeds 2,048 studs on any axis. They share one texture
  set.
