"""Print the Luau that repairs and checks one imported FBX group in Studio.

Run it, then paste the output into an execute_luau call (Edit datamodel):

    python3 tools/import_fix.py PAD Workspace.PAD_Import

What the Luau does, from what the VEH pilot showed about Open Cloud FBX imports:
- The model's pivot is the FBX scene origin, but the model arrives yawed and at 1 stud per metre. Part frames
  are the table axes turned 180 degrees about Y, so the pivot goes to the origin with that yaw, then ScaleTo.
- Anchored, no collision or queries, CollisionFidelity Box; RenderFidelity Precise where the README says.
- Attachments come from the manifest's world positions (not local_studs, which assume unrotated part frames).
- Every MeshPart is compared with the manifest: box centre, world size and pivot, to 0.05 studs.
- The PackageLink is removed, so local repairs don't trip package auto-update.
"""

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PRECISE_GROUPS = {"VEH", "TWR"}


def vec(v):
    return "{" + ",".join(f"{x:.3f}" for x in v) + "}"


def main():
    group, path = sys.argv[1], sys.argv[2]
    meshes = json.loads((ROOT / "export" / "manifest.json").read_text())["meshes"]
    rows = []
    for name, m in sorted(meshes.items()):
        if m["group"] != group:
            continue
        centre = [(a + b) / 2 for a, b in zip(m["bbox_min_studs"], m["bbox_max_studs"])]
        atts = ",".join(
            f'{{"{a["name"]}",{vec(a["world_studs"])}}}' for a in m.get("attachments") or []
        )
        precise = "true" if group in PRECISE_GROUPS or name.startswith("VEG_Belt_") else "false"
        rows.append(
            f"{name}={{c={vec(centre)},s={vec(m['size_studs'])},p={vec(m['pivot_studs'])},"
            f"precise={precise},a={{{atts}}}}}"
        )
    print(f"local PATH = \"{path}\"")
    print("local E = {" + ",".join(rows) + "}")
    print((ROOT / "tools" / "import_fix.luau").read_text())


if __name__ == "__main__":
    main()
