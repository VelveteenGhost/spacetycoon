# Roblox assets

Every asset uploaded for the port, all owned by Eli (user 1942187066). Open Cloud can't delete assets; archive
unused ones in the Creator Dashboard. A fixed file goes up as a new revision of its existing asset.

| Asset | ID | Source | Revision | Uploaded | In the place | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| VEH Pathfinder | 130623056517308 | `export/fbx/VEH.fbx` | 2 | 2026-11-08 | `Workspace.Port.VEH` | Revision 2 is the split re-export (33 parts, one material each), verified against the manifest. Revision 1 had the two-material bug |
| PAD Launch Mount | 138977096256584 | `export/fbx/PAD.fbx` | 1 | 2026-11-08 | `Workspace.Port.PAD` | Verified against the manifest |
| TWR Service Tower | 86272731500333 | `export/fbx/TWR.fbx` | 1 | 2026-11-08 | `Workspace.Port.TWR` | Verified against the manifest |
| SITE Kestrel Point | 129671137650864 | `export/fbx/SITE.fbx` (split) | 1 | 2026-11-08 | `Workspace.Port.SITE` and `ServerStorage.PortTemplates` | Verified against the manifest; rig joints stripped except the flag's |

The importer also created a mesh asset per MeshPart and an image asset per texture map; their IDs are on the
parts and SurfaceAppearances in the place.
