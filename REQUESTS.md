# Requests for Eli

Newest first. Each item says what, why and by when. I keep working on anything that doesn't depend on you.
Items marked **BLOCKING** stop a whole phase.

## 2026-11-08

0. **BLOCKING the vehicle and SITE: split 13 meshes by material (in progress in Eli's Blender session).** The
   meshes are `VEH_Engine_SL_0`–`8`, `VEH_MVac`, `SITE_Car`, `SITE_FloodPole` and `SITE_Hangar`. The main piece
   keeps its name; the second becomes `<name>_Inner`, `SITE_Car_Paint`, `SITE_FloodPole_Lens` or
   `SITE_Hangar_Door`. Both pieces keep the original origin, each gets its own manifest entry, and attachments
   stay on the main piece. PAD.fbx and TWR.fbx don't change. Push the re-export to a branch and I'll pull it.
   Items 1 and 2 below are done; PAD and TWR are already in.

1. **BLOCKING the import: approve the upload folder.** In Studio, go to Assistant Settings, then MCP Permissions,
   and approve `/Users/eli/projects/roblox/roblox-space-tycoon/export`. Why: Open Cloud uploads only read files
   from approved folders. Needed before phase 1.
2. **BLOCKING the import: OK to create permanent assets on your account.** Each FBX upload becomes a Model asset
   owned by you (user 1942187066), along with the meshes and images inside it. Open Cloud can't delete assets;
   only the Creator Dashboard can archive them. Plan: VEH.fbx first, then the other three. Later, about 10
   effect textures. Only if the importer drops maps, up to 151 texture images. Needed before phase 1.
3. **Set Lighting.Technology to Future** in the Properties panel (select Lighting). Confirmed that MCP scripts
   can't write it. Needed before phase 5.
4. **Later: watch the static fire on your phone** at its default graphics level. The Studio emulator missed the
   mood study's speckle problem. Needed for phase 8.
