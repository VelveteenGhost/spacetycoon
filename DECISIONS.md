# Decisions

Newest first. One line of reason each.

## 2026-11-08

- **Far cameras get a scaled proxy of the launch complex rather than new camera positions.** Roblox stops
  drawing the complex beyond 2,000–6,000 studs at the quality levels phones use, and scripts can't change that.
  A copy scaled about the camera keeps the mood study's framing and foregrounds exactly; moving cameras in would
  change both.
- **Land is 770 flat parts, while the dune, beach and sea are Terrain.** Flat Terrain at 24 × 20 km would be
  heavy for a phone, and parts match the mood study's flat ground plane. The coast needs Terrain's water and
  sub-voxel dune crest.
- **The Director runs on the client and takes test commands as attributes (Sequence, Camera, SeekT, Paused,
  Motion).** It's a single-viewer cinematic, and the attributes let a playtest jump to any frame for the
  numeric checks against the reference.
- **The launch loops at T+34 until phase 7 builds the altitude set.** Past about T+30 the vehicle leaves the pad
  set's true-scale range, and the director's later cuts belong to the altitude set.
- **Keep the reference tooling and `frames.json` in `tools/reference/`; the PNGs stay in the ignored
  `previews/`.** The 64 PNGs come to over 100 MB, while the camera states are 27 KB and are what the checks use.
- **Push code into Studio over MCP with a length and Adler-32 checksum check.** The Assistant's HTTP allowlist
  blocks a localhost sync, and the checksum proves Studio runs exactly what's in git.
- **Strip the importer's rig from SITE, but keep the flag's RootPart, bones, Motor6D and AnimationController in
  their own `Flag` model.** 208 joints on static props are clutter and would tie moved copies back to the root.
  The flag still needs its skeleton for the wave.
- **Keep origin-modelled props as templates in `ServerStorage.PortTemplates`, one model per prop or pair, pivot
  at the origin.** They were sitting on the pad, and SceneBuilder copies them out by the manifest's placement
  rules.
- **Upload SITE myself after the split, rather than wait for a second agent.** The Blender agent handled VEH's
  revision; SITE had no asset yet, and the checks live here.
- **Split the 13 two-material meshes into one object per material before upload, rather than patch them in
  Studio.** A MeshPart renders only one SurfaceAppearance, and the effects need those surfaces separate anyway:
  bell glow, nozzle heat ramp, paint tints, lit lenses.
- **Re-upload a fixed FBX as a new revision of its existing asset, not as a new asset.** Assets are permanent, and
  one asset per group keeps the account clean.
- **Place attachments and hinges from the manifest's world positions, not `local_studs`.** Imported part frames
  are turned 180° about Y from the table axes, so local offsets would land mirrored.
- **Keep `tools/manifest_to_luau.py` as the single path from the manifest into Studio code.** The pilot's checks
  needed the same pivots, boxes and attachments that SceneBuilder will.
- **Skip the port guide's blockout and prove camera framing with the real meshes.** The blockout protected the
  modelling time, and the modelling is already done.
- **Import through Open Cloud uploads over MCP, piloted on VEH.fbx, instead of the 3D Importer by hand.** I can
  run and verify it end to end. If the pilot loses textures or names, Eli runs the 3D Importer instead.
- **Position every part from `manifest.json`, not from where the importer drops it.** The manifest has every
  mesh's world box and pivot, so placement is exact and can be re-run.
- **Build the scene at edit time with a re-runnable SceneBuilder; animate at play time on the client.** Eli can
  walk the finished set in Studio, and the builder in git can rebuild it if the place is lost.
- **`src/` is the source of truth for code, pushed into Studio over MCP.** No Rojo plugin session for Eli to start
  each time; the Rojo project file stays for tooling.
- **StreamingEnabled off and no avatars in the art test.** The cameras 10 km out must see the whole site, and the
  shot is camera-only.
- **Build the art test in the Space Tycoon root place for now.** There's no gameplay yet to clash with it; it
  moves to its own place when the cold-open prototype starts.
