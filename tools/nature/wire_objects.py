"""Adds TerraBrush object types to scenes/misc/main.tscn by hand, the way the crystals were.

usage: python -I tools/nature/wire_objects.py <prefix> <id,id,...> [scene.tscn]

`nature_pipeline.py apply` refuses main.tscn, because its TerraBrush entries were wired by
hand (trees on Object_* masks, crystals on Nature_* masks). This appends instead: for each
id, an ext_resource for assets/nature/terrabrush/<id>.tres as `<prefix>_o<n>` and one for
its scatter mask scenes/misc/Main/Nature_<id>.res as `<prefix>_o<n>_mask`, then adds both to
the end of TerraBrush's `objects` list and the matching `objectsImage` list (TerraBrush pairs
them by index). An id already wired is left alone, so it can be run again.

A text edit rather than a re-save through Godot - close main.tscn in the editor first.
"""
import re
import sys


def wire(text, prefix, ids):
    nl = "\r\n" if "\r\n" in text else "\n"
    text = text.replace("\r\n", "\n")
    taken = set(re.findall(r'id="%s_o(\d+)"' % re.escape(prefix), text))
    index = max((int(n) for n in taken), default=-1) + 1
    ext, objects, images = [], [], []
    for asset_id in ids:
        resource = f"res://assets/nature/terrabrush/{asset_id}.tres"
        if f'path="{resource}"' in text:
            continue
        key = f"{prefix}_o{index}"
        index += 1
        ext.append(f'[ext_resource type="ObjectResource" path="{resource}" id="{key}"]\n'
                   f'[ext_resource type="Image" path="res://scenes/misc/Main/Nature_{asset_id}.res" id="{key}_mask"]\n')
        objects.append(f'ExtResource("{key}")')
        images.append(f'ExtResource("{key}_mask")')
    if not ext:
        return text.replace("\n", nl), 0
    last = list(re.finditer(r"^\[ext_resource [^\n]*\]\n", text, re.M))[-1]
    text = text[:last.end()] + "".join(ext) + text[last.end():]
    for field, entries in (("objects", objects), ("objectsImage", images)):
        pattern = re.compile(r"^(%s = Array\[\w+\]\(\[)([^\n]*)(\]\))$" % field, re.M)
        found = pattern.findall(text)
        if len(found) != 1:
            sys.exit(f"expected one `{field} = ...` line in the scene, found {len(found)}")
        text = pattern.sub(lambda m: m.group(1) + m.group(2) + ", " + ", ".join(entries) + m.group(3), text)
    return text.replace("\n", nl), len(ext)


def main():
    prefix, ids = sys.argv[1], [i for i in sys.argv[2].split(",") if i]
    scene = sys.argv[3] if len(sys.argv) > 3 else "scenes/misc/main.tscn"
    with open(scene, encoding="utf-8", newline="") as handle:
        text = handle.read()
    text, added = wire(text, prefix, ids)
    with open(scene, "w", encoding="utf-8", newline="") as handle:
        handle.write(text)
    print(f"{scene}: {added} object type(s) wired as {prefix}_o*")


if __name__ == "__main__":
    main()
