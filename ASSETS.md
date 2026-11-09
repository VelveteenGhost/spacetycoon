# Roblox assets

Every asset uploaded for the port, all owned by Eli (user 1942187066). Open Cloud can't delete assets; archive
unused ones in the Creator Dashboard. A fixed file goes up as a new revision of its existing asset.

| Asset | ID | Source | Revision | Uploaded | In the place | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| VEH Pathfinder | 130623056517308 | `export/fbx/VEH.fbx` | 2 | 2026-11-08 | `Workspace.Port.VEH` | Revision 2 is the split re-export (33 parts, one material each), verified against the manifest. Revision 1 had the two-material bug |
| PAD Launch Mount | 138977096256584 | `export/fbx/PAD.fbx` | 1 | 2026-11-08 | `Workspace.Port.PAD` | Verified against the manifest |
| TWR Service Tower | 86272731500333 | `export/fbx/TWR.fbx` | 1 | 2026-11-08 | `Workspace.Port.TWR` | Verified against the manifest |
| SITE Kestrel Point | 129671137650864 | `export/fbx/SITE.fbx` (split) | 1 | 2026-11-08 | `Workspace.Port.SITE` and `ServerStorage.PortTemplates` | Verified against the manifest; rig joints stripped except the flag's |
| FX glow | 87877243907028 | `art/effects/glow.png` | 1 | 2026-11-09 | `Look`/`Effects` (by ID) | Flame halo, lamp and beacon glows |
| FX billow A | 92443369380936 | `art/effects/billow_a.png` | 1 | 2026-11-09 | `Look`/`Effects` (by ID) | Lit exhaust billow |
| FX billow B | 84261181024933 | `art/effects/billow_b.png` | 1 | 2026-11-09 | `Look`/`Effects` (by ID) | Lit exhaust billow |
| FX billow C | 99218850171999 | `art/effects/billow_c.png` | 1 | 2026-11-09 | `Look`/`Effects` (by ID) | Lit exhaust billow |
| FX billow soft | 129350902832508 | `art/effects/billow_soft.png` | 1 | 2026-11-09 | `Look`/`Effects` (by ID) | Ground-cloud billow |
| FX puff | 102549625842700 | `art/effects/puff.png` | 1 | 2026-11-09 | `Look`/`Effects` (by ID) | Vent steam |
| FX flame | 125011676503064 | `art/effects/flame.png` | 1 | 2026-11-09 | `Look`/`Effects` (by ID) | Flame tongue; white-hot end at the top, so emitters use Rotation 180 |
| FX plume streak | 119359214952709 | `art/effects/plume_streak.png` | 1 | 2026-11-09 | `Look`/`Effects` (by ID) | Plume beam, hot at the left (U = 0) |
| FX contrail | 101788017573609 | `art/effects/contrail.png` | 1 | 2026-11-09 | `Look`/`Effects` (by ID) | Contrail beam, tiles along U |
| FX ice shards | 77986681991291 | `art/effects/ice_shards.png` | 1 | 2026-11-09 | `Look`/`Effects` (by ID) | Ice-shedding flipbook, 2x2 |
| FX foam | 131903125071793 | `art/effects/foam.png` | 1 | 2026-11-09 | `Look`/`Effects` (by ID) | Surf foam strip, crests along U |
| SKY sunrise clear (6 faces) | Ft 74452865708429, Bk 76395395920883, Lf 125463061980066, Rt 104748221518327, Up 128230331054611, Dn 71567945509173 | `art/sky/sunrise_clear/roblox/` | 1 | 2026-11-09 | `Look.SKIES` | "v2" in the names; faces from `tools/sky_faces.py` |
| SKY sunrise marine (6) | Ft 75295199837881, Bk 83969054959625, Lf 119212809721070, Rt 108088757614601, Up 140671860122825, Dn 122569486126598 | `art/sky/sunrise_marine/roblox/` | 1 | 2026-11-09 | `Look.SKIES` | |
| SKY morning clear (6) | Ft 94348730903564, Bk 100311366876654, Lf 88815821364390, Rt 76544168503481, Up 93938769047047, Dn 120208560375831 | `art/sky/morning_clear/roblox/` | 1 | 2026-11-09 | `Look.SKIES` | "v2" in the names |
| SKY morning marine (6) | Ft 99914108142373, Bk 138431261291023, Lf 119214462142794, Rt 95558103401701, Up 120542799668619, Dn 119126671791747 | `art/sky/morning_marine/roblox/` | 1 | 2026-11-09 | `Look.SKIES` | |
| SKY blue clear (6) | Ft 75412030884892, Bk 102513676718498, Lf 97168747930666, Rt 117543217177987, Up 120942709483749, Dn 91984109479355 | `art/sky/blue_clear/roblox/` | 1 | 2026-11-09 | `Look.SKIES` | "v4" in the names |
| SKY blue marine (6) | Ft 139294421549517, Bk 135094528664117, Lf 95171566630310, Rt 136177695619367, Up 138485525349648, Dn 109081657162555 | `art/sky/blue_marine/roblox/` | 1 | 2026-11-09 | `Look.SKIES` | "v2" in the names |
| SKY space | 140544353846875 | `art/sky/space/black.png` | 1 | 2026-11-09 | `Look.SKIES.space` | Near-black, all six faces, for cameras above 30 km |
| SKY debug (6) | Ft 121822676620631, Bk 90217123698292, Lf 114205032131790, Rt 115261494877789, Up 131034227023496, Dn 109041593503491 | `art/sky/debug/` | 1 | 2026-11-09 | none | Grey labelled faces for checking how Roblox orients a skybox |

Superseded sky uploads from the Nov 9 tuning passes, safe to archive: every "SKY ..." image without a matching row
above (sunrise clear v1, blue clear v1-v3, blue marine v1, morning clear v1).

The importer also created a mesh asset per MeshPart and an image asset per texture map; their IDs are on the
parts and SurfaceAppearances in the place.
