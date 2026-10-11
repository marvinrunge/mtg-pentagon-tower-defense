"""Writes the crystals round the mana wells and the hub into scenes/misc/main.tscn as nodes.

usage: python -I tools/bake_placed_crystals.py <placed_crystals.json>

The JSON comes from tools/tests/bake_placed_crystals.tscn, which runs the placement in
scripts/well_crystals.gd on the real terrain. Every crystal becomes an instance of its
nature scene under PlacedCrystals/Wells or PlacedCrystals/Hub, every light an OmniLight3D,
each at the transform it was given - from then on they are ordinary nodes, to be moved or
deleted in the editor like anything else, and the game no longer places them itself.

A text edit rather than a re-save through Godot, which would rewrite far more of the scene
than this touches. Idempotent: everything a previous run wrote (the PlacedCrystals branch
and its `placed_` ext_resources) is removed first. Close main.tscn in the editor first, or
the editor will save its stale copy over this.
"""
import json
import re
import sys

MAIN = "scenes/misc/main.tscn"


def main() -> None:
    with open(sys.argv[1], encoding="utf-8") as handle:
        entries = json.load(handle)
    with open(MAIN, encoding="utf-8", newline="") as handle:
        text = handle.read()
    nl = "\r\n" if "\r\n" in text else "\n"
    text = text.replace("\r\n", "\n")

    # Drop what a previous run wrote: its ext_resources, and every node of the branch.
    text = re.sub(r'^\[ext_resource [^\n]*id="placed_[^"]*"\]\n', "", text, flags=re.M)
    blocks = re.split(r"(?=^\[node )", text, flags=re.M)
    kept = [b for b in blocks
            if not re.match(r'\[node name="PlacedCrystals"', b)
            and not re.match(r'\[node [^\n]*parent="PlacedCrystals', b)]
    text = "".join(kept)

    scenes = sorted({e["scene"] for e in entries if "scene" in e})
    ids = {path: f"placed_{index}" for index, path in enumerate(scenes)}
    ext = "".join(f'[ext_resource type="PackedScene" path="{path}" id="{ids[path]}"]\n' for path in scenes)
    last = list(re.finditer(r"^\[ext_resource [^\n]*\]\n", text, re.M))[-1]
    text = text[:last.end()] + ext + text[last.end():]

    nodes = ['[node name="PlacedCrystals" type="Node3D" parent="."]\n\n',
             '[node name="Wells" type="Node3D" parent="PlacedCrystals"]\n\n',
             '[node name="Hub" type="Node3D" parent="PlacedCrystals"]\n\n']
    used = set()
    for entry in entries:
        if "scene" in entry:
            # "res://.../nature-red-ruby-crystals.tscn" -> "RedRubyCrystals"
            stem = entry["scene"].rsplit("/", 1)[-1].removesuffix(".tscn").removeprefix("nature-")
            name = "".join(part.capitalize() for part in stem.split("-"))
        else:
            name = entry["name"].lstrip("@").replace("@", "_")
        base, n = name, 2
        while (entry["group"], name) in used:
            name, n = f"{base}_{n}", n + 1
        used.add((entry["group"], name))
        parent = f'PlacedCrystals/{entry["group"]}'
        if "scene" in entry:
            nodes.append(f'[node name="{name}" parent="{parent}" instance=ExtResource("{ids[entry["scene"]]}")]\n'
                         f'transform = {entry["transform"]}\n\n')
        else:
            light = entry["light"]
            nodes.append(f'[node name="{name}" type="OmniLight3D" parent="{parent}"]\n'
                         f'transform = {entry["transform"]}\n'
                         f'light_color = {light["light_color"]}\n'
                         f'light_energy = {light["light_energy"]}\n'
                         f'omni_range = {light["omni_range"]}\n'
                         f'distance_fade_enabled = true\n'
                         f'distance_fade_begin = {light["distance_fade_begin"]}\n'
                         f'distance_fade_length = {light["distance_fade_length"]}\n\n')
    # Nodes go before any [connection] / [editable] sections, which close a scene file.
    tail = re.search(r"^\[(connection|editable) ", text, re.M)
    head, rest = (text[:tail.start()], text[tail.start():]) if tail else (text, "")
    head = head.rstrip("\n") + "\n\n" + "".join(nodes)
    text = head + rest if rest else head.rstrip("\n") + "\n"

    with open(MAIN, "w", encoding="utf-8", newline="") as handle:
        handle.write(text.replace("\n", nl))
    print(f"main.tscn: {len(entries)} crystal(s) and light(s) under PlacedCrystals, {len(scenes)} scene(s)")


if __name__ == "__main__":
    main()
