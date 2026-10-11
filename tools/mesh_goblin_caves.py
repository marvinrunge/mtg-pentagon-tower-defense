"""Meshes the goblin cave kit from its Gemini reference images (docs/GOBLIN_CAVES.md).

usage: python tools/mesh_goblin_caves.py [--go] [id ...]

Reads assets/generated/goblin-<id>/goblin-<id>_concept.jpg and sends it to Meshy
image-to-3D on Smart Topology (meshy-t2), the same request the nature set uses
(meshy_request in tools/nature/nature_pipeline.py). Writes goblin-<id>.glb, a preview and
the provenance .meshy.json beside the concept.

PAID: without --go it only prints the requests. Resumable like the nature pipeline: a
submitted task is recorded in goblin-<id>.task.json and picked up again instead of being
paid for twice, and an asset whose .glb exists is skipped.

    $env:MESHY_API_KEY = [Environment]::GetEnvironmentVariable('Meshy API Key','User')
"""
import base64
import json
import os
import sys
import threading

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "nature"))
import nature_pipeline as pipeline  # noqa: E402

## Target triangles. Roughly half of the "Tris" column in docs/GOBLIN_CAVES.md: the
## pieces repeat a lot across the Red wedge, so polygons are saved wherever the
## silhouette survives it. Smart Topology spends them on the shape, not on noise.
TRIS = {
    "sand-cliff-facade-wide": 3500,
    "basalt-cliff-facade-wide": 3500,
    "sand-cliff-facade-tall": 3000,
    "basalt-cliff-facade-tall": 3000,
    "sand-cave-mouth": 2000,
    "basalt-cave-mouth": 2000,
    "sand-rock-pillar-dwelling": 5000,
    "basalt-rock-pillar-dwelling": 5000,
    "sand-carved-stairs": 800,
    "basalt-carved-stairs": 800,
    "walkway-straight": 1000,
    "platform-corner": 900,
    "ladder-long": 400,
    "doorframe": 600,
    "hide-awning": 500,
    "rope-bridge": 1500,
    "ember-brazier": 400,
    "hanging-lantern": 300,
    "pulley-crane": 1000,
    "junk-pile": 800,
    "forge-chimney": 500,
    "spiked-barricade": 700,
    "war-banner": 400,
}


def mesh(manifest, asset_id, go, key):
    name = f"goblin-{asset_id}"
    folder = os.path.join(ROOT, "assets", "generated", name)
    stem = os.path.join(folder, name)
    concept = stem + "_concept.jpg"
    if os.path.exists(stem + ".glb"):
        print(f"{asset_id}: glb exists, skipped")
        return
    if not os.path.exists(concept):
        print(f"{asset_id}: no reference image yet")
        return
    asset = {"id": name, "tris": TRIS[asset_id], "model_type": "smart-topology"}
    with open(concept, "rb") as handle:
        image_b64 = base64.b64encode(handle.read()).decode("ascii")
    request = pipeline.meshy_request(manifest, asset, image_b64)
    request["image_url"] = "data:image/jpeg;base64," + image_b64
    if not go:
        print(asset_id, json.dumps({k: v for k, v in request.items() if k != "image_url"}))
        return
    config = manifest["providers"]["meshy"]
    headers = {"Authorization": f"Bearer {key}"}
    task_file = stem + ".task.json"
    if os.path.exists(task_file):
        with open(task_file, encoding="utf-8") as handle:
            task_id = json.load(handle)["task_id"]
        print(f"{asset_id}: resuming {task_id}")
    else:
        try:
            task_id = pipeline.http_json("POST", config["endpoint"], headers, request)["result"]
        except RuntimeError as error:
            # A rejected request creates no task and costs nothing; the rest go on.
            print(f"{asset_id}: rejected - {error}")
            return
        with open(task_file, "w", encoding="utf-8") as handle:
            json.dump({"task_id": task_id}, handle)
        print(f"{asset_id}: submitted {task_id}")
    task = pipeline.wait_meshy(config, headers, task_id)
    if task is None:
        return
    pipeline.download(task["model_urls"]["glb"], stem + ".glb")
    if task.get("thumbnail_url"):
        pipeline.download(task["thumbnail_url"], stem + "_preview.png")
    with open(stem + ".meshy.json", "w", encoding="utf-8") as handle:
        json.dump({
            "generator": "Meshy Image to 3D API v1",
            "task_id": task_id,
            "status": task.get("status"),
            "consumed_credits": task.get("consumed_credits"),
            "request": {k: v for k, v in request.items() if k != "image_url"},
            "concept_image": f"{name}_concept.jpg",
            "concept_prompt": f"docs/GOBLIN_CAVES.md, {name} (Gemini 3 Pro Image)",
            "license_review_required": True,
        }, handle, indent=2)
    os.remove(task_file)
    print(f"{asset_id}: saved {os.path.relpath(stem + '.glb', ROOT)}, {task.get('consumed_credits')} credits")


def main():
    go = "--go" in sys.argv
    ids = [a for a in sys.argv[1:] if a in TRIS] or list(TRIS)
    manifest = pipeline.load_manifest()
    # Asked for here, not in the threads: require_key exits, and a thread swallows that.
    key = pipeline.require_key("MESHY_API_KEY") if go else ""
    # They run side by side: each one is mostly waiting on Meshy.
    threads = [threading.Thread(target=mesh, args=(manifest, a, go, key)) for a in ids]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join()


if __name__ == "__main__":
    main()
