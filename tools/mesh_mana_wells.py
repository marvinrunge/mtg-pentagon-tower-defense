"""Meshes the five mana wells from their concept images (docs/MANA_WELL_PROMPTS.md).

usage: python tools/mesh_mana_wells.py [--go] [colour ...]

Reads assets/structures/mana-well-<colour>/mana-well-<colour>_concept.png and sends it to
Meshy image-to-3D on Smart Topology (meshy-t2), the same request the nature set uses
(meshy_request in tools/nature/nature_pipeline.py). Writes mana-well-<colour>.glb, a
preview and the provenance .meshy.json beside the concept, replacing the old text-to-3D
well - the .glb.import, and with it the uid scenes/mana_wells/*.tscn point at, is kept.

PAID: without --go it only prints the request. Resumable like the nature pipeline: a task
that was submitted is recorded in mana-well-<colour>.task.json and picked up again
instead of being paid for twice.

    $env:MESHY_API_KEY = [Environment]::GetEnvironmentVariable('Meshy API Key','User')
"""
import base64
import glob
import json
import os
import sys
import threading

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "nature"))
import nature_pipeline as pipeline  # noqa: E402

COLOURS = ["white", "blue", "black", "red", "green"]
## A hero prop the players walk right up to, five on the map: more than the 3,000-4,000 the
## prompt doc first named, so basalt columns, roots and leaves keep their shape.
TRIS = 8000


def mesh(manifest, colour, go, key):
    folder = os.path.join(ROOT, "assets", "structures", f"mana-well-{colour}")
    stem = os.path.join(folder, f"mana-well-{colour}")
    asset = {"id": f"mana-well-{colour}", "tris": TRIS, "model_type": "smart-topology"}
    with open(stem + "_concept.png", "rb") as handle:
        image_b64 = base64.b64encode(handle.read()).decode("ascii")
    request = pipeline.meshy_request(manifest, asset, image_b64)
    if not go:
        print(colour, json.dumps({k: v for k, v in request.items() if k != "image_url"}))
        return
    config = manifest["providers"]["meshy"]
    headers = {"Authorization": f"Bearer {key}"}
    task_file = stem + ".task.json"
    if os.path.exists(task_file):
        with open(task_file, encoding="utf-8") as handle:
            task_id = json.load(handle)["task_id"]
        print(f"{colour}: resuming {task_id}")
    else:
        task_id = pipeline.http_json("POST", config["endpoint"], headers, request)["result"]
        with open(task_file, "w", encoding="utf-8") as handle:
            json.dump({"task_id": task_id}, handle)
        print(f"{colour}: submitted {task_id}")
    task = pipeline.wait_meshy(config, headers, task_id)
    if task is None:
        return
    # The old well's textures were extracted from its glb on import; the new glb brings
    # its own, so the old ones go rather than lingering under the same names.
    for old in glob.glob(stem + "_Image_*"):
        os.remove(old)
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
            "concept_image": f"mana-well-{colour}_concept.png",
            "concept_prompt": "docs/MANA_WELL_PROMPTS.md, revision 2",
            "license_review_required": True,
        }, handle, indent=2)
    os.remove(task_file)
    print(f"{colour}: saved {os.path.relpath(stem + '.glb', ROOT)}, {task.get('consumed_credits')} credits")


def main():
    go = "--go" in sys.argv
    colours = [a for a in sys.argv[1:] if a in COLOURS] or COLOURS
    manifest = pipeline.load_manifest()
    # Asked for here, not in the threads: require_key exits, and a thread swallows that.
    key = pipeline.require_key("MESHY_API_KEY") if go else ""
    # The five run side by side: each one is mostly waiting on Meshy.
    threads = [threading.Thread(target=mesh, args=(manifest, c, go, key)) for c in colours]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join()


if __name__ == "__main__":
    main()
