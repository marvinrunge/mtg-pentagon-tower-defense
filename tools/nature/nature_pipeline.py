"""Builds the nature/foliage set end to end: Gemini concept art -> pick -> Meshy 3D ->
Godot import -> TerraBrush foliage/objects -> main.tscn.

Everything is driven by tools/nature/nature_assets.json. docs/NATURE_ASSETS.md explains
the plan; this file is only the machinery.

STAGES (run from the repo root, in this order - `run` chains them):

    python tools/nature/nature_pipeline.py prompts            # writes docs/NATURE_PROMPTS.md (free)
    python tools/nature/nature_pipeline.py concept --go       # Gemini: N concept images per asset
    python tools/nature/nature_pipeline.py pick               # auto-checks variants, suggests one, writes the review page
    python tools/nature/nature_pipeline.py approve <id>[:vN]  # YOU approve the reference image (default: the suggestion)
    python tools/nature/nature_pipeline.py reject <id>[:vN]   # throw variants away so `concept` makes new ones
    python tools/nature/nature_pipeline.py mesh --go          # Meshy image-to-3D, ONLY for approved reference images
    python tools/nature/nature_pipeline.py build              # Godot: key cards, import, build TerraBrush resources + scatter
    python tools/nature/nature_pipeline.py apply              # wire the result into scenes/misc/main.tscn
    python tools/nature/nature_pipeline.py status             # what exists, what is missing, what it will cost

    python tools/nature/nature_pipeline.py run --go --biome green   # all of the above for one biome

PAID STAGES NEED --go. Without it, `concept` and `mesh` print exactly what they would send
and spend nothing. `mesh` also stops at --max-credits (default 200) per invocation.

RESUMABLE ON PURPOSE, like tools/generate_sfx.py. A concept image or GLB that already
exists is never regenerated, and a Meshy task that was submitted but not downloaded is
resumed from its recorded task id instead of being paid for twice. Delete a file to buy a
fresh one of exactly that.

NOTHING GOES TO MESHY WITHOUT YOUR APPROVAL. `pick` only runs the quality gates and
*suggests* a variant; the review page assets/nature/_concepts/index.html shows every
variant with its gate result and the approve/reject command to copy. `approve` records
the file and its SHA-256, and `mesh` re-checks that hash before sending - an image that
was regenerated or edited after approval needs approving again. Card sheets (Gemini
only, no Meshy credits) still flow straight from the suggestion into `build`, but can be
approved the same way.

Keys come from the environment only, never from a file or the command line:

    $env:GEMINI_API_KEY = [Environment]::GetEnvironmentVariable('GeminiApiKey','User')
    $env:MESHY_API_KEY  = [Environment]::GetEnvironmentVariable('MeshyApiKey','User')
"""

import argparse
import base64
import hashlib
import io
import json
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request

try:
    from PIL import Image, ImageStat
except ImportError:  # Only `pick` and the reference-image compositing need it.
    Image = None

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
MANIFEST = os.path.join(ROOT, "tools", "nature", "nature_assets.json")
CONCEPT_ROOT = os.path.join(ROOT, "assets", "nature", "_concepts")
GENERATED_ROOT = os.path.join(ROOT, "assets", "generated")
LIBRARY_JSON = os.path.join(ROOT, "assets", "nature", "terrabrush", "library.json")
PROMPTS_DOC = os.path.join(ROOT, "docs", "NATURE_PROMPTS.md")
PROGRESS_DOC = os.path.join(ROOT, "docs", "NATURE_PROGRESS.md")
PROGRESS_LOG = os.path.join(ROOT, "tools", "nature", "progress_log.jsonl")
MAIN_SCENE = os.path.join(ROOT, "scenes", "misc", "main.tscn")
DEFAULT_GODOT = r"G:\Godot\Godot_v4.7-stable_win64_console.exe"


# --------------------------------------------------------------------------- manifest

def load_manifest():
    with open(MANIFEST, encoding="utf-8") as handle:
        return json.load(handle)


def select_assets(manifest, args):
    only = set(filter(None, (args.only or "").split(",")))
    chosen = []
    for asset in manifest["assets"]:
        if only and asset["id"] not in only:
            continue
        if args.biome and asset["biome"] != args.biome:
            continue
        if getattr(args, "route", None) and asset["route"] != args.route:
            continue
        chosen.append(asset)
    return chosen


def style_of(manifest, asset):
    """Mood, palette and optional style anchor: the asset's biome, or the shared colourless style
    for shapes generated once and tinted per biome in the engine."""
    if asset["biome"] == "shared":
        return manifest["shared_style"]
    return manifest["biomes"][asset["biome"]]


def generates_image(asset):
    """Tinted placements reuse a shared shape and existing sheets are done - neither
    gets a concept image of its own."""
    return asset["route"] in ("mesh", "card") and not asset.get("existing_sheet")


def tier_of(manifest, asset):
    """Tier defaults with the asset's own overrides on top."""
    merged = dict(manifest["tiers"].get(asset["tier"], {}))
    merged.update({k: v for k, v in asset.get("scatter", {}).items()})
    for key in ("collision",):
        if key in asset:
            merged[key] = asset[key]
    return merged


# --------------------------------------------------------------------------- prompts

def colour_name(rgb):
    return "#%02X%02X%02X" % tuple(rgb)


def reference_clause(manifest, asset):
    """Only when the asset's group has an `anchor` image - none do at the moment."""
    if not style_of(manifest, asset).get("anchor"):
        return ""
    if asset["biome"] == "shared":
        return ("Match the art style and rendering of the reference image, but ignore its colours "
                "completely and do not copy its subject. ")
    return "Match the art style, rendering and palette of the reference image, but do not copy its subject. "


def mesh_concept_prompt(manifest, asset):
    """The reference image Meshy builds the model from. Every clause exists for a reason:
    one object (Meshy reconstructs everything it sees), three-quarter view (Meshy infers
    the back from it best), full margin (a cropped edge becomes a flat cut in the mesh),
    flat background and no shadow (a shadow is reconstructed as a slab under the model),
    no glow halo (a halo is baked into the texture as a fog shell)."""
    biome = style_of(manifest, asset)
    width, height = asset["size_m"]
    background = colour_name(manifest["style"]["mesh_background"])
    return (
        f"Game asset concept render of a single isolated {asset['subject']} for a fantasy "
        f"tower defense game: {asset['details']}. "
        f"Setting: {biome['mood']}. Palette: {biome['palette']}. "
        "Style: semi-realistic fantasy game asset - believable natural materials and "
        "proportions, real surface detail (fractures, weathering, grain, subtle colour "
        "variation), colour slightly richer than life, and a clear silhouette that still reads "
        "from far away. Like a high-quality modern fantasy game asset render: not cartoon, not "
        "toon-shaded, not low-poly, not hand-painted, and not a photograph. "
        + reference_clause(manifest, asset) +
        f"About {width:g} metres wide and {height:g} metres tall. "
        "Framing: three-quarter view from slightly above, the whole object centred and fully "
        "inside the frame with a wide empty margin on every side, nothing cropped. "
        f"Background: plain flat uniform neutral mid-grey ({background}), no gradient, no "
        "vignette, no floor, no ground plane, no cast shadow, no contact shadow, no other "
        "objects, no scenery. Nothing around the object: no soil patch, no ground island, no "
        "base, no puddle or water, no grass tufts or pebbles at its foot, no mist, fog, smoke, "
        "steam, sparks, particles or drips - the object alone, cut off cleanly where it would "
        "meet the ground. Lighting: soft even neutral studio light, no coloured light, no "
        "dramatic rim light, no bloom, no glow halo outside the object. "
        "No text, no logo, no watermark, no border, no characters, no symbols from existing "
        "franchises."
    )


CARD_CONSTRAINTS = (
    "Style: semi-realistic natural plants with believable leaves, stems and petals, real colour "
    "variation and soft shading, like a high-quality foliage texture from a modern fantasy game - "
    "not flat vector art, not clip-art, not cartoon outlines. Plants only: no grid lines, no "
    "borders, no dividers, no frames, no labels, no letters, no numbers anywhere in the image. "
    "2x2 grid of four separate plants, evenly spaced with clear empty gaps between them, none "
    "touching or overlapping, none crossing the middle lines of the image, none cropped at the "
    "image edge. Pure flat white background, exactly #FFFFFF, no shadow, no gradient, no "
    "vignette, no ground, no soil, no pot. Orthographic front view at eye level, flat even "
    "lighting, no rim light, no dramatic highlights. Bold thick broad shapes - leaves, blades "
    "and petals clearly readable in silhouette, not hundreds of fine hairs. Crisp hard edges, "
    "sharp focus throughout, no motion blur, no depth of field, no soft glow or haze. Strongly "
    "saturated colour, no pale washed-out tips, no near-white values anywhere in the plant. All "
    "four plants at the same scale with their bases level along the bottom of their cell. Flat "
    "game asset texture sheet."
)


def card_sheet_prompt(manifest, asset):
    """Same rules as docs/GRASS_ATLAS_PROMPTS.md, for the same reason: the cards are keyed
    against white and drawn through an alpha scissor, so pale and hair-thin shapes fringe."""
    return (
        f"A 2x2 grid of four separate {asset['subject']} for a game texture sheet. "
        f"{asset['details']}.\n\n{CARD_CONSTRAINTS}"
    )


def prompt_for(manifest, asset):
    if asset["route"] == "mesh":
        return mesh_concept_prompt(manifest, asset)
    return card_sheet_prompt(manifest, asset)


def cmd_prompts(manifest, args):
    lines = [
        "# Nature Asset Prompts",
        "",
        "GENERATED by `python tools/nature/nature_pipeline.py prompts` from",
        "`tools/nature/nature_assets.json`. Edit the manifest, not this file.",
        "",
        "Plan and rationale: `docs/NATURE_ASSETS.md`. Paste any prompt into Gemini (Nano",
        "Banana Pro / Nano Banana 2) by hand, or let the `concept` stage send it.",
        "",
        "- **Mesh** prompts produce the reference image Meshy image-to-3D builds from. They are",
        "  text-only; if a group gets an `anchor` image in the manifest, attach it when",
        "  generating by hand.",
        "- **Card** prompts produce a 2x2 sheet on pure white that `tools/build_nature_cards.gd`",
        "  keys into alpha-cutout foliage textures.",
        "",
    ]
    sections = [("shared", {"name": "Shared crystal shapes (generated colourless, tinted per biome)",
                            "anchor": manifest["shared_style"].get("anchor")})] + list(manifest["biomes"].items())
    for biome_key, biome in sections:
        assets = [a for a in manifest["assets"] if a["biome"] == biome_key]
        lines += [f"## {biome_key.title()} - {biome['name']}", ""]
        if biome.get("anchor"):
            lines += [f"Style reference: `{biome['anchor']}`", ""]
        lines += [
                  "| Asset | Route | Tier | Size (m) | Tris |", "|---|---|---|---|---|"]
        for asset in assets:
            if asset["route"] == "tint":
                lines.append(f"| `{asset['id']}` | tint of `{asset['shape']}` | {asset['tier']} | - | - |")
                continue
            size = asset.get("size_m") or asset.get("card_size_m")
            lines.append(f"| `{asset['id']}` | {asset['route']} | {asset['tier']} | "
                         f"{size[0]:g} x {size[1]:g} | {asset.get('tris', '-')} |")
        lines.append("")
        for asset in assets:
            if asset["route"] == "tint":
                continue
            lines += [f"### `{asset['id']}`", ""]
            if asset.get("existing_sheet"):
                lines += [f"Already generated: `{asset['existing_sheet']}` - prompt in "
                          "`docs/GRASS_ATLAS_PROMPTS.md`.", ""]
                continue
            lines += ["```", prompt_for(manifest, asset), "```", ""]
    with open(PROMPTS_DOC, "w", encoding="utf-8", newline="\n") as handle:
        handle.write("\n".join(lines))
    print(f"Wrote {os.path.relpath(PROMPTS_DOC, ROOT)} ({len(manifest['assets'])} assets)")


# --------------------------------------------------------------------------- http

def http_json(method, url, headers, body=None, timeout=180):
    data = json.dumps(body).encode("utf-8") if body is not None else None
    request = urllib.request.Request(url, data=data, method=method, headers=headers)
    if data is not None:
        request.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        detail = error.read().decode("utf-8", "replace")[:800]
        raise RuntimeError(f"HTTP {error.code} from {url.split('?')[0]}: {detail}") from None


def download(url, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with urllib.request.urlopen(url, timeout=300) as response, open(path, "wb") as handle:
        shutil.copyfileobj(response, handle)


def require_key(name):
    value = os.environ.get(name, "").strip()
    if not value:
        sys.exit(f"{name} is not set. See the docstring at the top of this file.")
    return value


# --------------------------------------------------------------------------- gemini

def png_b64_on_background(path, rgb):
    """A style reference with transparency is flattened onto the same grey the prompt
    asks for, so the reference does not teach the model a different backdrop."""
    image = Image.open(path).convert("RGBA")
    flat = Image.new("RGBA", image.size, tuple(rgb) + (255,))
    flat.alpha_composite(image)
    buffer = io.BytesIO()
    flat.convert("RGB").save(buffer, "PNG")
    return base64.b64encode(buffer.getvalue()).decode("ascii")


def find_image_payload(node):
    """Walks a response for the first inline image. The interactions API and the legacy
    generateContent API nest it differently (and the interactions shape has moved during
    its preview), so this looks for the shape rather than a fixed path."""
    if isinstance(node, dict):
        if node.get("type") == "image" and isinstance(node.get("data"), str):
            return node["data"]
        for key in ("inlineData", "inline_data"):
            inline = node.get(key)
            if isinstance(inline, dict) and isinstance(inline.get("data"), str):
                return inline["data"]
        for value in node.values():
            found = find_image_payload(value)
            if found:
                return found
    elif isinstance(node, list):
        for value in node:
            found = find_image_payload(value)
            if found:
                return found
    return None


def gemini_generate(config, key, model, prompt, references):
    headers = {"x-goog-api-key": key}
    if config.get("api", "interactions") == "interactions":
        body = {
            "model": model,
            "input": [{"type": "text", "text": prompt}]
                     + [{"type": "image", "mime_type": "image/png", "data": ref} for ref in references],
            # The interactions API only returns JPEG (HTTP 400 on image/png, 2026-10-04);
            # it is re-saved as PNG on arrival, so nothing downstream sees a JPEG.
            "response_format": {"type": "image", "mime_type": "image/jpeg",
                                "aspect_ratio": "1:1", "image_size": config["image_size"]},
        }
        url = config["endpoint"]
    else:
        parts = [{"text": prompt}] + [{"inline_data": {"mime_type": "image/png", "data": ref}}
                                      for ref in references]
        body = {"contents": [{"parts": parts}],
                "generationConfig": {"responseModalities": ["IMAGE"],
                                     "imageConfig": {"aspectRatio": "1:1",
                                                     "imageSize": config["image_size"]}}}
        url = config["legacy_endpoint"].format(model=model)
    response = http_json("POST", url, headers, body, timeout=300)
    payload = find_image_payload(response)
    if not payload:
        raise RuntimeError("Gemini returned no image: "
                           + json.dumps(response)[:600])
    return base64.b64decode(payload)


def cmd_concept(manifest, args):
    config = manifest["providers"]["gemini"]
    assets = [a for a in select_assets(manifest, args) if generates_image(a)]
    variants = args.variants or config["variants"]
    jobs = []
    for asset in assets:
        folder = os.path.join(CONCEPT_ROOT, asset["id"])
        for index in range(1, variants + 1):
            path = os.path.join(folder, f"v{index}.png")
            if not os.path.exists(path):
                jobs.append((asset, path))
    print(f"{len(jobs)} concept image(s) missing across {len(assets)} asset(s).")
    if not jobs:
        return
    if not args.go:
        for asset, path in jobs[:3]:
            print(f"\n--- would generate {os.path.relpath(path, ROOT)}\n{prompt_for(manifest, asset)}")
        print("\nDry run. Add --go to send these to Gemini.")
        return

    key = require_key("GEMINI_API_KEY")
    background = manifest["style"]["mesh_background"]
    made, failed = [], []
    for number, (asset, path) in enumerate(jobs, 1):
        model = config["model_draft"] if args.draft else (
            config["model_mesh_concept"] if asset["route"] == "mesh" else config["model_card_sheet"])
        references = []
        anchor = style_of(manifest, asset).get("anchor")
        if asset["route"] == "mesh" and anchor:
            references.append(png_b64_on_background(os.path.join(ROOT, anchor), background))
        prompt = prompt_for(manifest, asset)
        print(f"[{number}/{len(jobs)}] {asset['id']} -> {os.path.basename(path)} ({model})")
        try:
            raw = gemini_generate(config, key, model, prompt, references)
        except (RuntimeError, OSError) as error:
            print(f"  FAILED: {error}")
            failed.append(f"{asset['id']}/{os.path.basename(path)}: {str(error)[:160]}")
            # Out of credit (402) or out of quota (429) fails every following request
            # the same way - stop instead of firing the rest of the queue at it.
            if str(error).startswith(("HTTP 402", "HTTP 429")):
                print("  Stopping: the Gemini account is out of credit or quota.")
                break
            continue
        os.makedirs(os.path.dirname(path), exist_ok=True)
        Image.open(io.BytesIO(raw)).convert("RGB").save(path, "PNG")
        with open(os.path.join(os.path.dirname(path), "prompt.txt"), "w", encoding="utf-8") as handle:
            handle.write(f"model: {model}\n\n{prompt}\n")
        made.append(f"{asset['id']}/{os.path.basename(path)}")
        time.sleep(config["delay_seconds"])
    ensure_gdignore()
    summary = f"{len(made)} image(s) generated with {'the draft model' if args.draft else 'Pro'}"
    if failed:
        summary += f", {len(failed)} failed: " + "; ".join(failed[:3])
    log_progress(manifest, "concept", summary)


def ensure_gdignore():
    """Concept art is source material, not a game texture - Godot must not import it."""
    os.makedirs(CONCEPT_ROOT, exist_ok=True)
    marker = os.path.join(CONCEPT_ROOT, ".gdignore")
    if not os.path.exists(marker):
        open(marker, "w").close()


# --------------------------------------------------------------------------- pick

def check_mesh_concept(path):
    """Rejects the failure modes that cost Meshy credits for nothing: a busy or gradient
    background, the object touching the frame (it gets a flat cut), and an object so small
    or so large that the reconstruction has nothing to work with or no context."""
    image = Image.open(path).convert("RGB")
    width, height = image.size
    patch = max(8, width // 32)
    corners = [image.crop(box) for box in (
        (0, 0, patch, patch), (width - patch, 0, width, patch),
        (0, height - patch, patch, height), (width - patch, height - patch, width, height))]
    stats = [ImageStat.Stat(c) for c in corners]
    if max(max(s.stddev) for s in stats) > 10:
        return False, "background corners are not flat", 0.0
    means = [s.mean for s in stats]
    spread = max(max(abs(a[i] - b[i]) for i in range(3)) for a in means for b in means)
    if spread > 14:
        return False, "background is a gradient (corners differ)", 0.0
    background = [sum(m[i] for m in means) / 4 for i in range(3)]

    small = image.resize((256, 256))
    pixels = small.load()
    rows, cols, filled = [0] * 256, [0] * 256, 0
    for y in range(256):
        for x in range(256):
            r, g, b = pixels[x, y]
            if max(abs(r - background[0]), abs(g - background[1]), abs(b - background[2])) > 28:
                rows[y] += 1
                cols[x] += 1
                filled += 1
    used_rows = [i for i, n in enumerate(rows) if n > 1]
    used_cols = [i for i, n in enumerate(cols) if n > 1]
    if not used_rows:
        return False, "no object found", 0.0
    margin = 4
    if used_rows[0] < margin or used_cols[0] < margin or used_rows[-1] > 255 - margin or used_cols[-1] > 255 - margin:
        return False, "object touches the frame edge", 0.0
    box = (used_cols[-1] - used_cols[0]) * (used_rows[-1] - used_rows[0]) / (256 * 256)
    if not 0.10 <= box <= 0.85:
        return False, f"object fills {box:.0%} of the frame", 0.0
    # Prefer the variant whose framing is closest to ~45% - big enough for detail,
    # small enough to leave Meshy's background removal a clean margin.
    return True, f"ok, fills {box:.0%}", 1.0 - abs(box - 0.45)


def check_card_sheet(path):
    """Mirrors tools/build_nature_cards.gd, which cuts a sheet into plants by SHAPE: what
    matters is a white background and plants that do not touch each other or the image
    edge. Crossing the middle lines is fine; drawn grid lines are removed by the builder
    and ignored here the same way."""
    image = Image.open(path).convert("RGB").resize((256, 256))
    pixels = image.load()

    def is_plant(rgb):
        high, low = max(rgb), min(rgb)
        return (1 - high / 255) > 0.12 or (high - low) / max(high, 1) > 0.18

    def is_grey_ink(rgb):
        high, low = max(rgb), min(rgb)
        return low < 240 and (high - low) / max(high, 1) < 0.12

    for x, y in ((2, 2), (253, 2), (2, 253), (253, 253)):
        if min(pixels[x, y]) < 240:
            return False, "background is not white", 0.0
    line_rows = {y for y in range(256) if sum(is_grey_ink(pixels[x, y]) for x in range(256)) > 204}
    line_cols = {x for x in range(256) if sum(is_grey_ink(pixels[x, y]) for y in range(256)) > 204}
    mask = [[is_plant(pixels[x, y]) and y not in line_rows and x not in line_cols for x in range(256)] for y in range(256)]
    for _ in range(2):  # join the leaves of one plant, as the builder does
        grown = [row[:] for row in mask]
        for y in range(256):
            for x in range(256):
                if not mask[y][x] and any(mask[y + dy][x + dx] for dy in (-1, 0, 1) for dx in (-1, 0, 1)
                                          if 0 <= y + dy < 256 and 0 <= x + dx < 256):
                    grown[y][x] = True
        mask = grown
    seen = [[False] * 256 for _ in range(256)]
    blobs, touching = 0, 0
    for sy in range(256):
        for sx in range(256):
            if not mask[sy][sx] or seen[sy][sx]:
                continue
            stack, size, edge = [(sx, sy)], 0, False
            seen[sy][sx] = True
            while stack:
                x, y = stack.pop()
                size += 1
                # The bottom edge is allowed: cards stand on their base, which is cut there anyway.
                edge = edge or x in (0, 255) or y == 0
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < 256 and 0 <= ny < 256 and mask[ny][nx] and not seen[ny][nx]:
                        seen[ny][nx] = True
                        stack.append((nx, ny))
            if size >= 256 * 256 * 0.006:
                blobs += 1
                touching += edge
    if touching:
        return False, "a plant is cut off at the top or side edge", 0.0
    if blobs < 2:
        return False, "plants touch each other (found %d separate plant)" % blobs, 0.0
    return True, f"ok, {blobs} plants", 1.0


def read_pick(asset_id):
    path = os.path.join(CONCEPT_ROOT, asset_id, "pick.json")
    if not os.path.exists(path):
        return {}
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def write_pick(asset_id, record):
    with open(os.path.join(CONCEPT_ROOT, asset_id, "pick.json"), "w", encoding="utf-8") as handle:
        json.dump(record, handle, indent=2)


def sha256_of(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        digest.update(handle.read())
    return digest.hexdigest()


def approved_image(asset_id):
    """The approved reference image, or None. None also when the file changed after it
    was approved - Meshy only ever sees exactly the pixels that were approved."""
    record = read_pick(asset_id).get("approved")
    if not record:
        return None
    path = os.path.join(CONCEPT_ROOT, asset_id, "pick.png")
    if not os.path.exists(path) or sha256_of(path) != record.get("sha256"):
        return None
    return path


def cmd_pick(manifest, args):
    rows = []
    for asset in select_assets(manifest, args):
        folder = os.path.join(CONCEPT_ROOT, asset["id"])
        if asset.get("existing_sheet") or not os.path.isdir(folder):
            continue
        record = read_pick(asset["id"])
        if record.get("approved"):
            rows.append((asset, f"approved {record['approved']['file']} - kept"))
            continue
        checker = check_mesh_concept if asset["route"] == "mesh" else check_card_sheet
        results = []
        for name in sorted(f for f in os.listdir(folder) if re.fullmatch(r"v\d+\.png", f)):
            ok, reason, score = checker(os.path.join(folder, name))
            results.append({"file": name, "ok": ok, "reason": reason, "score": round(score, 3)})
        passing = sorted((r for r in results if r["ok"]), key=lambda r: -r["score"])
        suggestion = passing[0]["file"] if passing else None
        write_pick(asset["id"], {"suggested": suggestion, "approved": None, "checks": results})
        if asset["route"] == "card" and suggestion:
            # Cards cost no Meshy credits, so the suggestion feeds `build` directly.
            shutil.copyfile(os.path.join(folder, suggestion), os.path.join(folder, "pick.png"))
        if suggestion:
            rows.append((asset, f"suggests {suggestion}" + (" - awaiting your approval" if asset["route"] == "mesh" else "")))
        else:
            rows.append((asset, "no variant passed the gates - `reject` it and run `concept --go` again"))
    for asset, verdict in rows:
        print(f"{asset['id']:<38} {verdict}")
    write_contact_sheet(manifest)
    print(f"\nReview page: {os.path.relpath(os.path.join(CONCEPT_ROOT, 'index.html'), ROOT)}")
    if rows:
        log_progress(manifest, "pick", "; ".join(f"{a['id']}: {v}" for a, v in rows))


def parse_targets(targets):
    """`id` or `id:v2` -> (id, "v2.png" or None)."""
    parsed = []
    for target in targets:
        asset_id, _, variant = target.partition(":")
        parsed.append((asset_id, f"{variant}.png" if variant else None))
    return parsed


def cmd_approve(manifest, args):
    known = {a["id"] for a in manifest["assets"]}
    if not args.targets:
        sys.exit("Name what to approve: approve <id>[:vN] [<id>[:vN] ...]")
    for asset_id, variant in parse_targets(args.targets):
        if asset_id not in known:
            print(f"{asset_id}: not in the manifest")
            continue
        record = read_pick(asset_id)
        chosen = variant or record.get("suggested")
        source = os.path.join(CONCEPT_ROOT, asset_id, chosen or "")
        if not chosen or not os.path.isfile(source):
            print(f"{asset_id}: nothing to approve ({chosen or 'no suggestion'}) - name a variant, e.g. {asset_id}:v1")
            continue
        target = os.path.join(CONCEPT_ROOT, asset_id, "pick.png")
        shutil.copyfile(source, target)
        record["approved"] = {"file": chosen, "sha256": sha256_of(target),
                              "at": time.strftime("%Y-%m-%d %H:%M")}
        write_pick(asset_id, record)
        print(f"{asset_id}: approved {chosen}")
        log_progress(manifest, "approve", f"{asset_id}: {chosen}", write=False)
    write_contact_sheet(manifest)
    write_progress(manifest)


def cmd_reject(manifest, args):
    if not args.targets:
        sys.exit("Name what to reject: reject <id> (all variants) or <id>:vN")
    for asset_id, variant in parse_targets(args.targets):
        folder = os.path.join(CONCEPT_ROOT, asset_id)
        if not os.path.isdir(folder):
            print(f"{asset_id}: no concepts")
            continue
        names = [variant] if variant else [f for f in os.listdir(folder) if re.fullmatch(r"v\d+\.png", f)]
        for name in names:
            if os.path.exists(os.path.join(folder, name)):
                os.remove(os.path.join(folder, name))
        for stale in ("pick.png", "pick.json"):
            if os.path.exists(os.path.join(folder, stale)):
                os.remove(os.path.join(folder, stale))
        print(f"{asset_id}: removed {', '.join(names) or 'nothing'} - `concept --go` will make replacements")
        log_progress(manifest, "reject", f"{asset_id}: {', '.join(names) or 'nothing'}", write=False)
    write_contact_sheet(manifest)
    write_progress(manifest)


def write_contact_sheet(manifest):
    """The review page: every variant, its gate result, and the command to approve it."""
    ensure_gdignore()
    sections = []
    for asset in manifest["assets"]:
        folder = os.path.join(CONCEPT_ROOT, asset["id"])
        if not os.path.isdir(folder):
            continue
        record = read_pick(asset["id"])
        approved = (record.get("approved") or {}).get("file") if approved_image(asset["id"]) else None
        checks = {c["file"]: c for c in record.get("checks", [])}
        figures = []
        for name in sorted(f for f in os.listdir(folder) if re.fullmatch(r"v\d+\.png", f)):
            state = "approved" if name == approved else "suggested" if name == record.get("suggested") else ""
            check = checks.get(name, {})
            verdict = check.get("reason", "not checked yet")
            variant = name[:-4]
            figures.append(
                f'<figure class="{state}"><img src="{asset["id"]}/{name}" loading="lazy">'
                f'<figcaption><b>{variant}</b> {"APPROVED" if state == "approved" else ""}'
                f'<br><span class="{"ok" if check.get("ok") else "bad"}">{verdict}</span>'
                f'<code>approve {asset["id"]}:{variant}</code></figcaption></figure>')
        status = "approved" if approved else "awaiting approval" if asset["route"] == "mesh" else "card"
        sections.append(
            f'<section><h2>{asset["id"]} <small>{asset["route"]} - {status}</small></h2>'
            f'<p class="prompt">{asset["subject"]}: {asset["details"]}</p>'
            f'<div class="row">{"".join(figures)}</div>'
            f'<code>reject {asset["id"]}</code></section>')
    html = ("<!doctype html><meta charset=utf-8><title>Nature reference images</title><style>"
            "body{font:14px system-ui;background:#1d1d1f;color:#eee;margin:16px;max-width:1400px}"
            ".row{display:flex;gap:10px;flex-wrap:wrap}figure{margin:0;border:3px solid #333;width:260px}"
            "figure.suggested{border-color:#d9b44a}figure.approved{border-color:#5fd068}"
            "img{width:100%;display:block}figcaption{padding:6px;font-size:12px}"
            ".ok{color:#8fd694}.bad{color:#f08a8a}code{display:block;margin-top:4px;color:#9cc4ff;"
            "user-select:all;font-size:11px}h2{font-size:15px;margin:22px 0 4px}small{color:#999;font-weight:400}"
            ".prompt{color:#aaa;margin:0 0 6px;font-size:12px}</style>"
            "<h1>Nature reference images</h1><p>Yellow = suggested by the quality gates, green = approved. "
            "Nothing is sent to Meshy until it is approved. Run from the repo root: "
            "<code>python tools/nature/nature_pipeline.py approve &lt;id&gt;:vN</code></p>"
            + "".join(sections))
    with open(os.path.join(CONCEPT_ROOT, "index.html"), "w", encoding="utf-8") as handle:
        handle.write(html)


# --------------------------------------------------------------------------- meshy

def meshy_request(manifest, asset, image_b64):
    config = manifest["providers"]["meshy"]
    model_type = asset.get("model_type", config["model_type"])
    body = {
        "image_url": "data:image/png;base64," + image_b64,
        # Smart Topology only runs on its own model (HTTP 400 "requires ai_model meshy-t1
        # or meshy-t2" otherwise, 2026-10-04); `ai_model` from the manifest applies to
        # the standard model type.
        "ai_model": "meshy-t2" if model_type == "smart-topology" else config["ai_model"],
        "model_type": model_type,
        "topology": "triangle",
        "target_polycount": asset["tris"],
        "should_texture": True,
        "enable_pbr": True,
        "texture_resolution": config["texture_resolution"],
        "remove_lighting": True,
        "origin_at": "bottom",
        "target_formats": ["glb"],
        "moderation": True,
    }
    if model_type == "standard":
        body["should_remesh"] = True
    else:
        # Smart Topology rejects remove_lighting (HTTP 400, 2026-10-04 - not in the docs)
        # and ignores topology; it is triangle-only anyway.
        del body["remove_lighting"]
        del body["topology"]
    if model_type != "standard" and asset["tris"] > 15000:
        raise ValueError(f"{asset['id']}: smart-topology caps target_polycount at 15000")
    return body


def cmd_mesh(manifest, args):
    config = manifest["providers"]["meshy"]
    todo = []
    for asset in select_assets(manifest, args):
        if asset["route"] != "mesh":
            continue
        glb = os.path.join(GENERATED_ROOT, asset["id"], asset["id"] + ".glb")
        if os.path.exists(glb):
            continue
        if approved_image(asset["id"]) is None:
            waiting = "approval was for a different file - approve again" if read_pick(asset["id"]).get("approved") else "awaiting your approval"
            print(f"{asset['id']:<38} {waiting}")
            continue
        todo.append(asset)
    cost = sum(config["estimated_credits"][a.get("model_type", config["model_type"])] for a in todo)
    print(f"{len(todo)} mesh(es) to generate, roughly {cost} Meshy credits.")
    if not todo:
        return
    if not args.go:
        sample = meshy_request(manifest, todo[0], "<approved pick.png as base64>")
        print(json.dumps(sample, indent=2))
        print("\nDry run. Add --go to submit (stops at --max-credits).")
        return

    key = require_key("MESHY_API_KEY")
    headers = {"Authorization": f"Bearer {key}"}
    spent = 0
    for asset in todo:
        estimate = config["estimated_credits"][asset.get("model_type", config["model_type"])]
        if spent + estimate > args.max_credits:
            print(f"Stopping: next asset would pass --max-credits {args.max_credits}.")
            break
        out_dir = os.path.join(GENERATED_ROOT, asset["id"])
        os.makedirs(out_dir, exist_ok=True)
        task_file = os.path.join(out_dir, asset["id"] + ".task.json")
        image_path = approved_image(asset["id"])
        if image_path is None:  # changed since the list above was made
            print(f"{asset['id']}: approval no longer matches the file, skipped")
            continue
        with open(image_path, "rb") as handle:
            image_b64 = base64.b64encode(handle.read()).decode("ascii")
        request = meshy_request(manifest, asset, image_b64)

        if os.path.exists(task_file):
            with open(task_file, encoding="utf-8") as handle:
                task_id = json.load(handle)["task_id"]
            print(f"{asset['id']}: resuming task {task_id}")
        else:
            try:
                task_id = http_json("POST", config["endpoint"], headers, request)["result"]
            except RuntimeError as error:
                # A rejected request creates no task and costs nothing; the rest go on.
                print(f"{asset['id']}: rejected - {error}")
                log_progress(manifest, "mesh", f"{asset['id']}: request rejected, no credits spent - {str(error)[:200]}")
                continue
            with open(task_file, "w", encoding="utf-8") as handle:
                json.dump({"task_id": task_id}, handle)
            print(f"{asset['id']}: submitted {task_id}")
            spent += estimate

        task = wait_meshy(config, headers, task_id)
        if task is None:
            continue
        glb = os.path.join(out_dir, asset["id"] + ".glb")
        download(task["model_urls"]["glb"], glb)
        if task.get("thumbnail_url"):
            download(task["thumbnail_url"], os.path.join(out_dir, asset["id"] + "_preview.png"))
        shutil.copyfile(os.path.join(CONCEPT_ROOT, asset["id"], "pick.png"),
                        os.path.join(out_dir, asset["id"] + "_concept.png"))
        provenance = {
            "generator": "Meshy Image to 3D API v1",
            "task_id": task_id,
            "status": task.get("status"),
            "consumed_credits": task.get("consumed_credits"),
            "request": {k: v for k, v in request.items() if k != "image_url"},
            "concept_image": f"{asset['id']}_concept.png",
            "concept_prompt": prompt_for(manifest, asset),
            "license_review_required": True,
        }
        with open(os.path.join(out_dir, asset["id"] + ".meshy.json"), "w", encoding="utf-8") as handle:
            json.dump(provenance, handle, indent=2)
        os.remove(task_file)
        print(f"{asset['id']}: saved {os.path.relpath(glb, ROOT)}")
        log_progress(manifest, "mesh", f"{asset['id']}: GLB saved, {task.get('consumed_credits')} credits")
    # The concept copy sits beside the glb for provenance; Godot must not import it.
    for asset in todo:
        concept = os.path.join(GENERATED_ROOT, asset["id"], asset["id"] + "_concept.png")
        if os.path.exists(concept) and not os.path.exists(concept + ".import"):
            with open(concept + ".import", "w", encoding="utf-8") as handle:
                handle.write('[remap]\n\nimporter="skip"\n')


def wait_meshy(config, headers, task_id):
    deadline = time.time() + config["timeout_seconds"]
    last = None
    while time.time() < deadline:
        task = http_json("GET", f"{config['endpoint']}/{task_id}", headers)
        state = (task.get("status"), task.get("progress"))
        if state != last:
            print(f"  {task_id}: {state[0]} {state[1]}%")
            last = state
        if task.get("status") == "SUCCEEDED":
            return task
        if task.get("status") in ("FAILED", "CANCELED"):
            print(f"  failed: {(task.get('task_error') or {}).get('message')}")
            return None
        time.sleep(config["poll_seconds"])
    print("  timed out - rerun `mesh` later to resume this task")
    return None


# --------------------------------------------------------------------------- godot

def godot_exe():
    return os.environ.get("GODOT_PATH") or DEFAULT_GODOT


def run_godot(*extra):
    command = [godot_exe(), "--headless", "--path", ROOT] + list(extra)
    print("> " + " ".join(command[1:]))
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace")
    for line in result.stdout.splitlines() + result.stderr.splitlines():
        if line.startswith(("[nature]", "ERROR", "SCRIPT ERROR", "WARNING: [nature]")):
            print("  " + line)
    if result.returncode != 0:
        sys.exit(f"Godot exited with {result.returncode}")


def cmd_build(manifest, args):
    passthrough = ["--"]
    if args.only:
        passthrough += ["--only", args.only]
    if args.biome:
        passthrough += ["--biome", args.biome]
    if args.no_scatter:
        passthrough += ["--no-scatter"]
    run_godot("--script", "res://tools/build_nature_cards.gd", *passthrough)
    # New PNGs and GLBs have to be imported before the next script can load() them.
    # --import starts the editor, and the Godot MCP plugin removes its runtime-probe
    # autoload from project.godot on editor shutdown - the same reason
    # tools/validate_godot.ps1 restores the file around its editor run.
    project_file = os.path.join(ROOT, "project.godot")
    with open(project_file, "rb") as handle:
        project_before = handle.read()
    try:
        run_godot("--import")
    finally:
        with open(project_file, "rb") as handle:
            if handle.read() != project_before:
                with open(project_file, "wb") as restore:
                    restore.write(project_before)
    run_godot("--script", "res://tools/build_nature_terrabrush.gd", *passthrough)


# --------------------------------------------------------------------------- apply

NATURE_ID = "nature_"


def cmd_apply(manifest, args):
    """Wires library.json into main.tscn as a text edit, because that keeps the diff to
    the lines that matter (re-saving the scene through Godot rewrites far more). Close the
    scene in the editor first, or the editor will save its stale copy over this.

    Owns the TerraBrush `foliages` / `objects` arrays and the zone's matching image arrays
    outright: TerraBrush pairs them by index, so any entry this did not write would be
    paired with the wrong image. If someone has painted their own foliage or objects by
    hand, this refuses rather than guess."""
    with open(LIBRARY_JSON, encoding="utf-8") as handle:
        library = json.load(handle)
    with open(MAIN_SCENE, encoding="utf-8") as handle:
        text = handle.read()

    # Anything in those arrays that a previous apply did not write is hand-made.
    for line in re.findall(r"^(?:foliages|objects|foliagesImage|objectsImage) = [^\n]*", text, re.M):
        foreign = [ref for ref in re.findall(r'(?:Ext|Sub)Resource\("([^"]+)"\)', line)
                   if not ref.startswith(NATURE_ID)]
        if foreign:
            sys.exit("main.tscn already has hand-made TerraBrush foliage/objects "
                     f"({', '.join(foreign)}) - merge by hand.")
    # Drop everything a previous apply wrote, so this is idempotent.
    text = re.sub(r'^\[ext_resource [^\n]*id="nature_[^"]*"\]\n', "", text, flags=re.M)
    text = re.sub(r"^(foliages|objects|foliagesImage|objectsImage) = [^\n]*\n", "", text, flags=re.M)

    ext_lines, foliage_refs, foliage_images, object_refs, object_images = [], [], [], [], []
    for kind, refs, images in (("foliages", foliage_refs, foliage_images), ("objects", object_refs, object_images)):
        resource_type = "FoliageResource" if kind == "foliages" else "ObjectResource"
        for index, entry in enumerate(library[kind]):
            rid = f"{NATURE_ID}{kind[0]}{index}"
            ext_lines.append(f'[ext_resource type="{resource_type}" path="{entry["resource"]}" id="{rid}"]')
            ext_lines.append(f'[ext_resource type="Image" path="{entry["mask"]}" id="{rid}_mask"]')
            refs.append(f'ExtResource("{rid}")')
            images.append(f'ExtResource("{rid}_mask")')

    last_ext = list(re.finditer(r'^\[ext_resource [^\n]*\]\n', text, re.M))[-1]
    text = text[:last_ext.end()] + "".join(line + "\n" for line in ext_lines) + text[last_ext.end():]

    node = re.search(r'^\[node name="TerraBrush" type="TerraBrush"[^\n]*\]\n', text, re.M)
    insert = ""
    if foliage_refs:
        insert += f"foliages = Array[FoliageResource]([{', '.join(foliage_refs)}])\n"
    if object_refs:
        insert += f"objects = Array[ObjectResource]([{', '.join(object_refs)}])\n"
    text = text[:node.end()] + insert + text[node.end():]

    zones_ref = re.search(r'^terrainZones = SubResource\("([^"]+)"\)', text, re.M).group(1)
    zones = re.search(r'^\[sub_resource type="ZonesResource" id="%s"\]\nzones = Array\[ZoneResource\]\(\[SubResource\("([^"]+)"\)' % re.escape(zones_ref), text, re.M)
    zone_header = re.search(r'^\[sub_resource type="ZoneResource" id="%s"\]\n' % re.escape(zones.group(1)), text, re.M)
    insert = ""
    if foliage_images:
        insert += f"foliagesImage = Array[Image]([{', '.join(foliage_images)}])\n"
    if object_images:
        insert += f"objectsImage = Array[Image]([{', '.join(object_images)}])\n"
    text = text[:zone_header.end()] + insert + text[zone_header.end():]

    with open(MAIN_SCENE, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(text)
    print(f"main.tscn: {len(foliage_refs)} foliage layer(s), {len(object_refs)} object type(s). "
          "Run ./tools/validate_godot.ps1 next.")


# --------------------------------------------------------------------------- progress

def log_progress(manifest, stage, summary, write=True):
    """Appends one line to the run log and (by default) rewrites docs/NATURE_PROGRESS.md."""
    entry = {"at": time.strftime("%Y-%m-%d %H:%M"), "stage": stage, "summary": summary}
    with open(PROGRESS_LOG, "a", encoding="utf-8") as handle:
        handle.write(json.dumps(entry) + "\n")
    if write:
        write_progress(manifest)


def asset_state(manifest, asset):
    """One word for where an asset is in the pipeline, plus a detail string."""
    if asset["route"] == "tint":
        shape = next(a for a in manifest["assets"] if a["id"] == asset["shape"])
        done = os.path.exists(os.path.join(GENERATED_ROOT, shape["id"], shape["id"] + ".glb"))
        return ("ready" if done else "waits on shape"), f"tint of {asset['shape']}"
    if asset.get("existing_sheet"):
        return "ready", "existing sheet"
    folder = os.path.join(CONCEPT_ROOT, asset["id"])
    variants = len([f for f in os.listdir(folder) if re.fullmatch(r"v\d+\.png", f)]) if os.path.isdir(folder) else 0
    if asset["route"] in ("mesh", "procedural") and os.path.exists(os.path.join(GENERATED_ROOT, asset["id"], asset["id"] + ".glb")):
        return "mesh done", ("built in Blender" if asset["route"] == "procedural" else f"{variants} concept(s)")
    if asset["route"] == "procedural":
        recipe = os.path.join(ROOT, "tools", "nature", "blender", "species", asset["id"] + ".json")
        return ("recipe ready" if os.path.exists(recipe) else "needs recipe"), "Blender (tools/nature/blender)"
    if approved_image(asset["id"]):
        return "approved", f"{read_pick(asset['id'])['approved']['file']} of {variants}"
    pick = read_pick(asset["id"])
    if pick.get("suggested"):
        return "to review", f"suggests {pick['suggested']} of {variants}"
    if variants:
        return "to review", f"{variants} concept(s), none passed the gates" if pick else f"{variants} concept(s), not checked"
    return "not started", ""


def write_progress(manifest):
    """docs/NATURE_PROGRESS.md: where every asset stands, plus the run log. Rewritten by
    every stage that changes something, so it is always current - read it, don't edit it."""
    states = [(asset, *asset_state(manifest, asset)) for asset in manifest["assets"]]
    counts = {}
    for _, state, _ in states:
        counts[state] = counts.get(state, 0) + 1
    order = ["mesh done", "ready", "approved", "to review", "recipe ready", "needs recipe", "waits on shape", "not started"]
    lines = ["# Nature Asset Progress", "",
             "GENERATED by `tools/nature/nature_pipeline.py` after every stage. Plan:",
             "`docs/NATURE_ASSETS.md`. Review page: `assets/nature/_concepts/index.html`.", "",
             "| State | Count |", "|---|---|"]
    lines += [f"| {state} | {counts[state]} |" for state in order if state in counts]
    groups = [("shared", "Shared crystal shapes")] + [(key, f"{key.title()} - {b['name']}") for key, b in manifest["biomes"].items()]
    for key, title in groups:
        rows = [row for row in states if row[0]["biome"] == key]
        if not rows:
            continue
        lines += ["", f"## {title}", "", "| Asset | Route | State | Detail |", "|---|---|---|---|"]
        lines += [f"| `{a['id']}` | {a['route']} | {state} | {detail} |" for a, state, detail in rows]
    lines += ["", "## Log", ""]
    if os.path.exists(PROGRESS_LOG):
        with open(PROGRESS_LOG, encoding="utf-8") as handle:
            entries = [json.loads(line) for line in handle if line.strip()]
        lines += [f"- {e['at']} **{e['stage']}** - {e['summary']}" for e in reversed(entries)]
    with open(PROGRESS_DOC, "w", encoding="utf-8", newline="\n") as handle:
        handle.write("\n".join(lines) + "\n")


# --------------------------------------------------------------------------- status

def cmd_status(manifest, args):
    config = manifest["providers"]["meshy"]
    credits = 0
    print(f"{'asset':<38} {'route':<5} {'concepts':<9} {'image':<10} {'glb':<4}")
    for asset in select_assets(manifest, args):
        if asset["route"] == "tint":
            continue
        folder = os.path.join(CONCEPT_ROOT, asset["id"])
        concepts = len([f for f in os.listdir(folder) if re.fullmatch(r"v\d+\.png", f)]) if os.path.isdir(folder) else 0
        if asset.get("existing_sheet"):
            pick = "existing"
        elif approved_image(asset["id"]):
            pick = "approved"
        elif read_pick(asset["id"]).get("suggested"):
            pick = "suggested"
        else:
            pick = "-"
        glb = "-"
        if asset["route"] == "mesh":
            glb = "yes" if os.path.exists(os.path.join(GENERATED_ROOT, asset["id"], asset["id"] + ".glb")) else "-"
            if glb == "-":
                credits += config["estimated_credits"][asset.get("model_type", config["model_type"])]
        print(f"{asset['id']:<38} {asset['route']:<5} {concepts if not asset.get('existing_sheet') else '-':<9} {pick:<10} {glb:<4}")
    print(f"\nMeshy credits still to spend (estimate): {credits}")
    write_progress(manifest)


# --------------------------------------------------------------------------- main

def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("stage", choices=["prompts", "concept", "pick", "approve", "reject", "mesh", "build", "apply", "status", "run"])
    parser.add_argument("targets", nargs="*", help="approve/reject: <id> or <id>:vN")
    parser.add_argument("--go", action="store_true", help="actually spend credits (concept, mesh, run)")
    parser.add_argument("--only", help="comma-separated asset ids")
    parser.add_argument("--biome", choices=["shared", "white", "blue", "black", "red", "green"])
    parser.add_argument("--route", choices=["mesh", "card", "tint", "procedural"])
    parser.add_argument("--variants", type=int, help="concept images per asset (default from manifest)")
    parser.add_argument("--draft", action="store_true", help="use the cheaper draft image model")
    parser.add_argument("--max-credits", type=int, default=200)
    parser.add_argument("--no-scatter", action="store_true", help="build resources but leave masks alone")
    args = parser.parse_args()

    os.chdir(ROOT)
    manifest = load_manifest()
    if args.stage == "run":
        cmd_prompts(manifest, args)
        cmd_concept(manifest, args)
        if not args.go:
            return
        cmd_pick(manifest, args)
        # Only what you approved before this run goes to Meshy; everything new waits
        # on the review page for the next run.
        cmd_mesh(manifest, args)
        cmd_build(manifest, args)
        cmd_apply(manifest, args)
        return
    {"prompts": cmd_prompts, "concept": cmd_concept, "pick": cmd_pick, "approve": cmd_approve,
     "reject": cmd_reject, "mesh": cmd_mesh,
     "build": cmd_build, "apply": cmd_apply, "status": cmd_status}[args.stage](manifest, args)


if __name__ == "__main__":
    main()
