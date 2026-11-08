# Requests for Eli

Newest first. Each item says what, why and by when. I keep working on anything that doesn't depend on you.
Items marked **BLOCKING** stop a whole phase.

## 2026-11-08

0. **BLOCKING phases 1–2: split 13 meshes by material.** The VEH pilot showed that two-material meshes import as
   a single MeshPart that shows only one material (details in `PLAN.md`, phase 1). Blender isn't on this Mac,
   and the export pipeline (`/blender/`) isn't in the repo. Either run the split where the pipeline lives, or OK
   me to install Blender with Homebrew and do it here.
   Items 1 and 2 below are done (the VEH upload went through on Nov 8).

1. **BLOCKING the import: approve the upload folder.** In Studio, go to Assistant Settings, then MCP Permissions,
   and approve `/Users/eli/projects/roblox/roblox-space-tycoon/export`. Why: Open Cloud uploads only read files
   from approved folders. Needed before phase 1.
2. **BLOCKING the import: OK to create permanent assets on your account.** Each FBX upload becomes a Model asset
   owned by you (user 1942187066), along with the meshes and images inside it. Open Cloud can't delete assets;
   only the Creator Dashboard can archive them. Plan: VEH.fbx first, then the other three. Later, about 10
   effect textures. Only if the importer drops maps, up to 151 texture images. Needed before phase 1.
3. **Set Lighting.Technology to Future** in the Properties panel (select Lighting). MCP scripts can't read this
   property, so they almost certainly can't set it. Needed before phase 5.
4. **Later: watch the static fire on your phone** at its default graphics level. The Studio emulator missed the
   mood study's speckle problem. Needed for phase 8.
