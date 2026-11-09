# Decisions

Newest first. One line of reason each.

## 2026-11-09

- **Bake the mood study's sky into a Roblox skybox per look (sunrise, morning, blue hour × clear, marine), and
  divide out Roblox's own sky tint.** Roblox's sky can't make the reference's teal-grey dawn. It also multiplies any
  skybox by a tint that follows the sun (neutral above about +12°, olive and 4× darker at +3°, 40× darker and
  nearly blue-free below the horizon) and by the scene exposure, so `tools/sky_faces.py` scales each texel by
  K / (tint(elevation) × 2^exposure). Broken weather uses the clear sky under Roblox's clouds.
- **At blue hour Roblox's sun waits at the morning angle with Brightness 0, the Atmosphere comes out, and plain
  distance fog stands in.** Below the horizon the sky tint is past what a texture can undo, and from the parked
  angle Atmosphere would scatter daylight into the sky and haze. The far shots lose some haze at night, where
  it matters least.
- **Treat ColorShift_Top as a shift, not a multiplier: (1, 0.3, 0.1) at sunrise, easing to (0.45, 0.35, 0.25) by
  +18°.** Under Realistic lighting it shifts Roblox's olive low sun; this pair matches the mood study's peach on
  the mount shot.
- **Floods: three cones per pole from 16–18 m plus an apron pool, tuned at quality level 15.** A Roblox light has
  little left near its 120-stud reach, so cones from the poles' real 48 m lit nothing. Light response differs by
  quality level, so the tuning names its level.
- **The far-camera copy carries the lights too, at a 5-stud minimum range and 6× brightness.** Lights scaled to a
  couple of studs draw nothing, and the floods are what the far shots see at night.
- **Fly the altitude set on the true trajectory through the far-camera copy, not on a separate backdrop set.** The
  copy already shows any distance at any scale, so the tracker and the onboard cameras just keep using it; the copy's
  ground widens with the camera's height.
- **Simulate the contrail, the separation gas and the far cameras' ground cloud in Lua (`Puffs`), drawn as
  billboards.** Roblox particles live in one space, so they can't follow the copy's scale and recentring, and real
  ones are hidden by the copy's ground and fogged by real distance. True-space puffs also stay continuous across cuts.
  The near cameras keep the particle cloud, which looked better up close.
- **Long lenses dolly in, widening the lens, when the vehicle would span under 2° unzoomed.** Roblox culls small parts
  by size and distance whatever the lens, so the tracker showed empty sky at quality level 1; framing at the
  vehicle's depth is unchanged, only the background's perspective shifts.
- **Above 30 km: a black skybox, glowing ground in the copy, and fill from OutdoorAmbient.** The mood study drops its
  sky there; under Realistic lighting a black sky lights nothing, so the ground glows in its hazed colours.
- **Glows are BillboardGuis on Terrain attachments, placed each frame in real or copy space.** One set serves
  every camera without copying billboards into the proxy.

## 2026-11-08

- **The far-camera copy includes the ground (flat bands with a hole around the camera) and everything that stands
  in the shot.** Ground tiles get culled too at low quality. A plane scaled about the camera lines up with the
  real ground at the hole's edge, but it hides real objects just below eye level, so the press flag is copied
  as well.
- **Each frame the copy follows the live camera, scale fixed per shot and rescaled past 20% drift.** It handles
  the moving drone and handheld drift alike, and rewriting about 2,100 sizes only on a cut keeps frames cheap.
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
