"""Procedural trees for the nature set: one recipe per species -> GLB + preview render.

Run headless with Blender 5.2 (no MCP needed - this is the reproducible production path;
Blender MCP is for tuning a recipe interactively):

    "G:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b -P tools/nature/blender/build_trees.py -- [--only id,id] [--no-render]

Inputs:
  tools/nature/blender/species/<id>.json   the recipe (shape, bark, leaf set)
  assets/nature/_concepts/textures/<bark>  bark swatch (seamless)
  assets/nature/leaves/<set>_NN.png        keyed leaf tiles from tools/build_nature_cards.gd

Outputs (the same folder Meshy assets use, so tools/build_nature_terrabrush.gd takes them
as they are):
  assets/generated/<id>/<id>.glb
  assets/nature/_concepts/<id>/blender_preview.png

Why Python/bmesh rather than Geometry Nodes: every number lives in the recipe JSON, the
same seed always gives the same tree, and the script diffs cleanly. A Geometry Nodes
setup would hide the same parameters inside a .blend.

What the mesh carries for the game:
  - bark tubes, cylindrically UV-mapped so the swatch tiles every `bark_tile_m` metres
  - leaf cards (alpha-cut quads) UV'd into one atlas of the species' leaf tiles, with
    normals bent outward from the canopy centre, so the crown lights as one volume
    instead of flickering card by card
  - a colour attribute "Col": R is the wind weight, 0 at the trunk base to 1 at the
    leaf tips, for the sway shader (docs/NATURE_ASSETS.md 3b)
"""

import json
import math
import os
import random
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
SPECIES_DIR = os.path.join(ROOT, "tools", "nature", "blender", "species")
TEXTURE_DIR = os.path.join(ROOT, "assets", "nature", "_concepts", "textures")
LEAF_DIR = os.path.join(ROOT, "assets", "nature", "leaves")
GENERATED_DIR = os.path.join(ROOT, "assets", "generated")
CONCEPT_DIR = os.path.join(ROOT, "assets", "nature", "_concepts")

GOLDEN_ANGLE = math.radians(137.5)
# Leaf cards cut where the tile alpha drops below this - the same threshold the foliage
# cards and tools/alpha_key.gd use.
ALPHA_CUTOFF = 0.3


# --------------------------------------------------------------------------- helpers

def perpendicular(v):
    other = Vector((0, 0, 1)) if abs(v.z) < 0.9 else Vector((1, 0, 0))
    return v.cross(other).normalized()


def rotate(v, axis, degrees):
    return (Matrix.Rotation(math.radians(degrees), 3, axis) @ v).normalized()


def lerp(a, b, t):
    return a + (b - a) * t


def point_on(points, t):
    """Point and direction at fraction t of a polyline's length."""
    lengths = [(points[i + 1] - points[i]).length for i in range(len(points) - 1)]
    target = sum(lengths) * t
    for i, seg in enumerate(lengths):
        if target <= seg or i == len(lengths) - 1:
            f = 0.0 if seg == 0 else min(target / seg, 1.0)
            direction = (points[i + 1] - points[i]).normalized()
            return points[i].lerp(points[i + 1], f), direction, (i + f) / len(lengths)
        target -= seg
    return points[-1], (points[-1] - points[-2]).normalized(), 1.0


def rgb_to_hsv(rgb):
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    mx, mn = rgb.max(-1), rgb.min(-1)
    delta = mx - mn
    h = np.zeros_like(mx)
    safe = np.where(delta > 1e-6, delta, 1.0)
    h = np.where(mx == r, ((g - b) / safe) % 6, h)
    h = np.where(mx == g, (b - r) / safe + 2, h)
    h = np.where(mx == b, (r - g) / safe + 4, h)
    h = np.where(delta > 1e-6, h / 6.0, 0.0)
    s = np.where(mx > 1e-6, delta / np.where(mx > 1e-6, mx, 1.0), 0.0)
    return np.stack([h, s, mx], -1)


def hsv_to_rgb(hsv):
    h, s, v = hsv[..., 0], hsv[..., 1], hsv[..., 2]
    i = np.floor(h * 6).astype(int) % 6
    f = h * 6 - np.floor(h * 6)
    p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
    choices = [np.stack(c, -1) for c in ((v, t, p), (q, v, p), (p, v, t), (p, q, v), (t, p, v), (v, p, q))]
    out = np.zeros_like(hsv)
    for k in range(6):
        out = np.where((i == k)[..., None], choices[k], out)
    return out


# --------------------------------------------------------------------------- textures

def leaf_sets(recipe):
    """Every leaf set a recipe uses, with its colour adjustment: the main `leaves` set
    (recoloured by leaf_hue_shift / leaf_saturation / leaf_value) plus the set of each
    `extra_cards` entry (its own hue_shift / saturation / value, default unchanged)."""
    sets = {recipe["leaves"]: (recipe.get("leaf_hue_shift", 0), recipe.get("leaf_saturation", 1.0), recipe.get("leaf_value", 1.0))}
    for extra in recipe.get("extra_cards", []):
        sets.setdefault(extra["set"], (extra.get("hue_shift", 0), extra.get("saturation", 1.0), extra.get("value", 1.0)))
    return sets


def leaf_atlas(recipe, name):
    """All keyed tiles of every leaf set the species uses, packed into one square atlas,
    each set recoloured on its own (the broad oak borrows the golden sun-oak leaves and
    shifts them green; the cypress moss keeps its colour)."""
    sets = leaf_sets(recipe)
    entries = []
    for leaf_set in sets:
        tiles = sorted(f for f in os.listdir(LEAF_DIR) if f.startswith(leaf_set + "_") and f.endswith(".png"))
        if not tiles:
            raise SystemExit(f"no leaf tiles for {leaf_set} in {LEAF_DIR} - run tools/build_nature_cards.gd")
        entries += [(leaf_set, f) for f in tiles]
    grid = math.ceil(math.sqrt(len(entries)))
    size = 512
    atlas = np.zeros((grid * size, grid * size, 4), dtype=np.float32)
    rects = {leaf_set: [] for leaf_set in sets}
    for index, (leaf_set, file) in enumerate(entries):
        image = bpy.data.images.load(os.path.join(LEAF_DIR, file))
        if tuple(image.size) != (size, size):
            image.scale(size, size)
        pixels = np.empty(size * size * 4, dtype=np.float32)
        image.pixels.foreach_get(pixels)
        pixels = pixels.reshape(size, size, 4)
        bpy.data.images.remove(image)
        shift, saturation, value = sets[leaf_set]
        if shift or saturation != 1.0 or value != 1.0:
            hsv = rgb_to_hsv(pixels[..., :3])
            hsv[..., 0] = (hsv[..., 0] + shift / 360.0) % 1.0
            hsv[..., 1] = np.clip(hsv[..., 1] * saturation, 0, 1)
            hsv[..., 2] = np.clip(hsv[..., 2] * value, 0, 1)
            pixels[..., :3] = hsv_to_rgb(hsv)
        cx, cy = index % grid, index // grid
        atlas[cy * size:(cy + 1) * size, cx * size:(cx + 1) * size] = pixels
        rects[leaf_set].append((cx / grid, cy / grid, (cx + 1) / grid, (cy + 1) / grid))

    image = bpy.data.images.new(f"{name}_leaves", grid * size, grid * size, alpha=True)
    image.pixels.foreach_set(atlas.ravel())
    image.file_format = "PNG"
    image.pack()
    return image, rects


def bark_image(recipe, name):
    image = bpy.data.images.load(os.path.join(TEXTURE_DIR, recipe["bark"]))
    if image.size[0] > 1024:
        image.scale(1024, 1024)  # keeps the GLB small; bark is seen at a distance
    image.name = f"{name}_bark"
    image.pack()
    return image


def make_materials(name, bark, leaves):
    bark_mat = bpy.data.materials.new(f"{name}_bark")
    bark_mat.use_nodes = True
    nodes, links = bark_mat.node_tree.nodes, bark_mat.node_tree.links
    bsdf = nodes["Principled BSDF"]
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = bark
    links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.9

    leaf_mat = bpy.data.materials.new(f"{name}_leaves")
    leaf_mat.use_nodes = True
    leaf_mat.use_backface_culling = False
    nodes, links = leaf_mat.node_tree.nodes, leaf_mat.node_tree.links
    bsdf = nodes["Principled BSDF"]
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = leaves
    links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    # alpha -> (alpha < cutoff) -> 1 - x : the node pattern Blender's glTF exporter
    # recognises as alphaMode MASK with this cutoff, so Godot imports an alpha scissor.
    less = nodes.new("ShaderNodeMath")
    less.operation = "LESS_THAN"
    less.inputs[1].default_value = ALPHA_CUTOFF
    invert = nodes.new("ShaderNodeMath")
    invert.operation = "SUBTRACT"
    invert.inputs[0].default_value = 1.0
    links.new(tex.outputs["Alpha"], less.inputs[0])
    links.new(less.outputs[0], invert.inputs[1])
    links.new(invert.outputs[0], bsdf.inputs["Alpha"])
    bsdf.inputs["Roughness"].default_value = 0.75
    return bark_mat, leaf_mat


# --------------------------------------------------------------------------- mesh

class TreeMesh:
    def __init__(self, recipe, rng, leaf_rects):
        self.recipe = recipe
        self.rng = rng
        self.leaf_rects = leaf_rects
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.new("UVMap")
        self.col = self.bm.loops.layers.float_color.new("Col")
        self.card_normals = {}   # face -> normal for each of its loops
        self.card_centres = []

    def tube(self, points, radii, ring, wind_from, wind_to):
        tile = self.recipe["bark_tile_m"]
        count = len(points)
        tangents = []
        for i in range(count):
            a = points[max(i - 1, 0)]
            b = points[min(i + 1, count - 1)]
            tangents.append((b - a).normalized())
        normal = perpendicular(tangents[0])
        rings = []
        travelled = 0.0
        vs = []
        for i in range(count):
            if i > 0:
                # parallel transport: rotate the frame by the bend between segments
                rotation = tangents[i - 1].rotation_difference(tangents[i])
                normal = (rotation @ normal).normalized()
                travelled += (points[i] - points[i - 1]).length
            binormal = tangents[i].cross(normal)
            verts = []
            for j in range(ring):
                angle = 2 * math.pi * j / ring
                offset = normal * math.cos(angle) + binormal * math.sin(angle)
                verts.append(self.bm.verts.new(points[i] + offset * radii[i]))
            rings.append(verts)
            vs.append(travelled / tile)
        circumference_scale = max(1, round(2 * math.pi * radii[0] / tile * 2)) / 2.0
        for i in range(count - 1):
            w0 = lerp(wind_from, wind_to, i / (count - 1))
            w1 = lerp(wind_from, wind_to, (i + 1) / (count - 1))
            for j in range(ring):
                k = (j + 1) % ring
                face = self.bm.faces.new((rings[i][j], rings[i][k], rings[i + 1][k], rings[i + 1][j]))
                face.material_index = 0
                face.smooth = True
                u0 = j / ring * circumference_scale
                u1 = (j + 1) / ring * circumference_scale
                for loop, (u, v, w) in zip(face.loops, ((u0, vs[i], w0), (u1, vs[i], w0), (u1, vs[i + 1], w1), (u0, vs[i + 1], w1))):
                    loop[self.uv].uv = (u, v)
                    loop[self.col] = (w, 0.0, 0.0, 1.0)

    def card(self, base, up, facing, width, height, wind=1.0, leaf_set=None):
        up = up.normalized()
        right = up.cross(facing).normalized()
        if right.length < 1e-4:
            right = perpendicular(up)
        corners = [base - right * width / 2, base + right * width / 2,
                   base + right * width / 2 + up * height, base - right * width / 2 + up * height]
        verts = [self.bm.verts.new(c) for c in corners]
        face = self.bm.faces.new(verts)
        face.material_index = 1
        u0, v0, u1, v1 = self.rng.choice(self.leaf_rects[leaf_set or self.recipe["leaves"]])
        for loop, uv in zip(face.loops, ((u0, v0), (u1, v0), (u1, v1), (u0, v1))):
            loop[self.uv].uv = uv
            loop[self.col] = (wind, 0.0, 0.0, 1.0)
        self.card_centres.append((face, base + up * height * 0.5))

    def finish(self, name, materials, normal_bend, canopy_centre):
        mesh = bpy.data.meshes.new(name)
        self.bm.normal_update()
        # Bend each card's normals outward from the canopy centre - the standard trick
        # that makes a cloud of alpha cards shade like one leafy volume.
        self.bm.faces.index_update()
        normals_by_face = {}
        for face, centre in self.card_centres:
            outward = centre - canopy_centre
            outward.z += 0.35 * outward.length  # a little sky bias
            outward = outward.normalized() if outward.length > 1e-4 else Vector((0, 0, 1))
            normals_by_face[face.index] = face.normal.lerp(outward, normal_bend).normalized()
        self.bm.to_mesh(mesh)
        self.bm.free()
        for material in materials:
            mesh.materials.append(material)
        loop_normals = [(0.0, 0.0, 0.0)] * len(mesh.loops)
        for poly in mesh.polygons:
            normal = normals_by_face.get(poly.index)
            if normal is not None:
                for li in poly.loop_indices:
                    loop_normals[li] = tuple(normal)
        mesh.normals_split_custom_set(loop_normals)
        obj = bpy.data.objects.new(name, mesh)
        bpy.context.scene.collection.objects.link(obj)
        return obj


# --------------------------------------------------------------------------- growth

def wobble_path(start, direction, length, segments, gnarl, up_bias, rng, droop=0.0, bias=None):
    """A branch as a polyline: random wobble of `gnarl` degrees per segment, pulled up by
    up_bias, down by droop, and sideways by `bias` (the windswept pine's prevailing wind)."""
    bias = bias or Vector((0, 0, 0))
    points = [start.copy()]
    d = direction.normalized()
    step = length / segments
    for i in range(segments):
        axis = perpendicular(d)
        axis = rotate(axis, d, rng.uniform(0, 360))
        d = rotate(d, axis, rng.gauss(0, gnarl))
        d = (d + Vector((0, 0, up_bias - droop)) + bias).normalized()
        points.append(points[-1] + d * step)
    return points


def place_card(tree, spec, base, direction, rng, leaf_set=None, wind=1.0):
    """One leaf card (two when spec["layers"] is 2) at `base`, oriented by
    spec["orientation"]:
      outward  along the branch, tilted at random - the default crown
      up       pointing at the sky - rosettes (dragonblood)
      flat     lying roughly horizontal along the branch - pine pads
      hanging  hanging straight down from the point - willow strands, moss"""
    size = rng.uniform(*spec["size"])
    width = size * spec.get("aspect", 1.0)
    mode = spec.get("orientation", "outward")
    tilt = spec.get("tilt", 30)
    if mode == "up":
        up = rotate(Vector((0, 0, 1)), perpendicular(Vector((0, 0, 1))), rng.uniform(-tilt, tilt))
        up = rotate(up, Vector((0, 0, 1)), rng.uniform(0, 360))
        facing = rotate(perpendicular(up), up, rng.uniform(0, 360))
    elif mode == "flat":
        up = Vector((direction.x, direction.y, 0))
        up = up.normalized() if up.length > 1e-3 else Vector((1, 0, 0))
        up = rotate(up, Vector((0, 0, 1)), rng.gauss(0, 25))
        facing = rotate(Vector((0, 0, 1)), up, rng.gauss(0, tilt))
        base = base - up * size * 0.3
    elif mode == "hanging":
        up = Vector((0, 0, 1))
        facing = rotate(Vector((1, 0, 0)), up, rng.uniform(0, 360))
        base = base - Vector((0, 0, size * spec.get("hang", 0.95)))
    else:
        up = direction + Vector((0, 0, 0.25))
        up = rotate(up.normalized(), perpendicular(up), rng.uniform(-tilt, tilt))
        facing = rotate(perpendicular(up), up, rng.uniform(0, 360))
    spread = spec.get("spread", 0.0)
    if spread:
        base = base + Vector((rng.gauss(0, spread * 0.3), rng.gauss(0, spread * 0.3), rng.gauss(0, spread * 0.2)))
    for layer in range(spec.get("layers", 1)):
        turn = layer * 90.0 if mode != "flat" else (layer - 0.5) * spec.get("cross_angle", 40)
        tree.card(base, up, rotate(facing, up, turn), width, size, wind=wind, leaf_set=leaf_set)


def grow_roots(tree, recipe, trunk_pts, rng):
    """Arching stilt roots from the lower trunk down to the ground (mangrove)."""
    roots = recipe.get("roots")
    if not roots:
        return
    for k in range(roots["count"]):
        angle = 2 * math.pi * k / roots["count"] + rng.gauss(0, 0.25)
        outward = Vector((math.cos(angle), math.sin(angle), 0))
        start, _, _ = point_on(trunk_pts, rng.uniform(*roots["height"]))
        end = outward * roots["spread"] * rng.uniform(0.75, 1.15) + Vector((0, 0, -0.15))
        control = start.lerp(end, 0.5) + outward * roots["spread"] * 0.35 + Vector((0, 0, roots["arch"]))
        points = []
        for i in range(roots["segments"] + 1):
            t = i / roots["segments"]
            points.append(start * (1 - t) ** 2 + control * 2 * t * (1 - t) + end * t * t)
        r = roots["radius"] * rng.uniform(0.8, 1.2)
        tree.tube(points, [lerp(r, r * 0.6, i / roots["segments"]) for i in range(len(points))], 5, 0.0, 0.0)


def grow_knees(tree, recipe, rng):
    """Cypress knees: knobbly stumps poking out of the ground round the trunk."""
    knees = recipe.get("knees")
    if not knees:
        return
    for k in range(knees["count"]):
        angle = rng.uniform(0, 2 * math.pi)
        distance = rng.uniform(*knees["distance"])
        base = Vector((math.cos(angle) * distance, math.sin(angle) * distance, -0.1))
        height = rng.uniform(*knees["height"])
        tip = base + Vector((rng.gauss(0, 0.08), rng.gauss(0, 0.08), height))
        mid = base.lerp(tip, 0.55) + Vector((rng.gauss(0, 0.04), rng.gauss(0, 0.04), 0))
        r = knees["radius"] * rng.uniform(0.7, 1.3)
        tree.tube([base, mid, tip], [r, r * 0.7, r * 0.2], 5, 0.0, 0.0)


def grow_deciduous(tree, recipe, rng):
    trunk = recipe["trunk"]
    levels = recipe["levels"]
    rings = recipe["ring_vertices"]
    cards = recipe["leaf_cards"]
    bias = Vector(recipe.get("bias", (0, 0, 0)))
    if bias.length:
        lean_axis = Vector((0, 0, 1)).cross(bias).normalized()   # lean with the wind
    else:
        lean_axis = rotate(Vector((1, 0, 0)), Vector((0, 0, 1)), rng.uniform(0, 360))
    trunk_dir = rotate(Vector((0, 0, 1)), lean_axis, trunk["lean"])
    start = Vector((0, 0, trunk.get("start_z", 0.0)))
    trunk_pts = wobble_path(start, trunk_dir, trunk["length"], trunk["segments"], trunk["gnarl"], 0.05, rng,
                            bias=bias * trunk.get("bias_weight", 0.5))
    grow_roots(tree, recipe, trunk_pts, rng)
    grow_knees(tree, recipe, rng)
    trunk_radii = [lerp(trunk["radius"], trunk["radius"] * trunk["taper"], i / (len(trunk_pts) - 1)) for i in range(len(trunk_pts))]
    trunk_radii[0] *= trunk.get("flare", 1.0)
    tips = []

    def branch(points, radii, depth, wind_from, wind_to):
        tree.tube(points, radii, rings[min(depth, len(rings) - 1)], wind_from, wind_to)
        length = sum((points[i + 1] - points[i]).length for i in range(len(points) - 1))
        # Crossed pairs (layers: 2): a lone card seen edge-on is a hard streak; two at
        # right angles always show one face.
        for spec in [dict(cards, set=recipe["leaves"])] + recipe.get("extra_cards", []):
            if depth != spec["on_level"]:
                continue
            for k in range(spec["per_branch"]):
                t = spec["from"] + (1 - spec["from"]) * (k + rng.random()) / spec["per_branch"]
                base, direction, _ = point_on(points, t)
                place_card(tree, spec, base, direction, rng, leaf_set=spec["set"])
        if depth == cards["on_level"]:
            tips.append(points[-1])
        if depth >= len(levels):
            return
        spec = levels[depth]
        # "exact" for forks that must stay forks (dragonblood); otherwise a little variety.
        count = spec["count"] if spec.get("exact") else max(1, spec["count"] + rng.choice((-1, 0, 0, 1)))
        azimuth0 = rng.uniform(0, 2 * math.pi)
        for k in range(count):
            t = spec["start"] + (1 - spec["start"]) * (k + rng.uniform(0.2, 0.8)) / count
            base, direction, f = point_on(points, t)
            radius_here = lerp(radii[0], radii[-1], f)
            side = rotate(perpendicular(direction), direction, math.degrees(azimuth0 + GOLDEN_ANGLE * k))
            child_dir = rotate(direction, direction.cross(side), spec["angle"] + rng.gauss(0, spec["angle_spread"]))
            child_len = length * spec["length"] * rng.uniform(1 - spec["length_spread"], 1 + spec["length_spread"]) * (1 - 0.3 * t)
            child_pts = wobble_path(base, child_dir, child_len, spec["segments"], spec["gnarl"], spec["up"], rng,
                                    droop=spec.get("droop", 0.0), bias=bias * spec.get("bias_weight", 1.0))
            r0 = max(radius_here * spec["radius"], 0.015)
            child_radii = [lerp(r0, r0 * 0.25, i / (len(child_pts) - 1)) for i in range(len(child_pts))]
            span = (wind_to - wind_from)
            branch(child_pts, child_radii, depth + 1, wind_from + span * t, min(1.0, wind_to + 0.25))

    branch(trunk_pts, trunk_radii, 0, 0.0, 0.2)
    centre = sum(tips, Vector()) / max(len(tips), 1)
    return centre


def grow_conifer(tree, recipe, rng):
    trunk = recipe["trunk"]
    whorls = recipe["whorls"]
    rings = recipe["ring_vertices"]
    cards = recipe["leaf_cards"]
    height = trunk["length"]
    trunk_pts = wobble_path(Vector((0, 0, 0)), Vector((0, 0, 1)), height, trunk["segments"], trunk["gnarl"], 0.0, rng)
    trunk_radii = [lerp(trunk["radius"], trunk["radius"] * trunk["taper"], i / (len(trunk_pts) - 1)) for i in range(len(trunk_pts))]
    trunk_radii[0] *= trunk.get("flare", 1.0)
    tree.tube(trunk_pts, trunk_radii, rings[0], 0.0, 0.35)

    h = whorls["from"] * height
    whorl_index = 0
    while h < whorls["to"] * height:
        frac = (whorls["to"] * height - h) / ((whorls["to"] - whorls["from"]) * height)
        max_len = whorls["min_length"] + (whorls["max_length"] - whorls["min_length"]) * (frac ** whorls["shape_power"])
        base, _, _ = point_on(trunk_pts, h / height)
        count = whorls["per_whorl"] + rng.choice((-1, 0, 0, 1))
        offset = whorl_index * 0.5 + rng.random()
        for k in range(count):
            azimuth = 2 * math.pi * (k + offset) / count + rng.gauss(0, 0.15)
            horizontal = Vector((math.cos(azimuth), math.sin(azimuth), 0))
            tilt = whorls["angle"] - 90 + rng.gauss(0, whorls["angle_spread"])
            direction = rotate(horizontal, horizontal.cross(Vector((0, 0, 1))), tilt)
            length = max_len * rng.uniform(0.85, 1.1)
            points = wobble_path(base, direction, length, whorls["segments"], 6, 0.0, rng, droop=math.radians(whorls["droop"]) / whorls["segments"])
            r0 = whorls["radius"] * (0.5 + 0.5 * frac)
            radii = [lerp(r0, r0 * 0.3, i / (len(points) - 1)) for i in range(len(points))]
            wind_base = 0.3 + 0.4 * (h / height)
            tree.tube(points, radii, rings[1], wind_base, min(1.0, wind_base + 0.4))
            steps = max(1, int(length / cards["spacing"]))
            for s in range(steps):
                t = (s + 0.5) / steps
                p, d, _ = point_on(points, t * 0.92)
                # flat spray along the branch, roughly horizontal, tilted a little
                facing = rotate(Vector((0, 0, 1)), d, rng.gauss(0, cards["tilt"]))
                facing = (facing - d * facing.dot(d)).normalized()
                size = rng.uniform(*cards["size"]) * (0.6 + 0.4 * (1 - t * 0.5))
                start = p - d * size * 0.35
                layers = cards.get("layers", 1)
                for layer in range(layers):
                    roll = (layer - (layers - 1) / 2) * cards.get("cross_angle", 0)
                    tree.card(start, d, rotate(facing, d, roll), size, size, wind=min(1.0, wind_base + 0.5 * t))
        h += whorls["spacing"] * rng.uniform(0.85, 1.15)
        whorl_index += 1

    top = trunk_pts[-1]
    for k in range(cards.get("top_tuft", 0)):
        axis = Vector((math.cos(k * 2.4), math.sin(k * 2.4), 0))
        d = rotate(Vector((0, 0, 1)), axis, 18)
        tree.card(top - Vector((0, 0, 0.9)), d, axis, 0.75, 1.1)
    return Vector((0, 0, height * 0.45))


# --------------------------------------------------------------------------- export

def export_glb(obj, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    options = dict(filepath=path, export_format="GLB", use_selection=True, export_apply=True,
                   export_vertex_color="ACTIVE", export_yup=True)
    for _ in range(3):
        try:
            bpy.ops.export_scene.gltf(**options)
            return
        except TypeError as error:
            bad = str(error).split('"')[1] if '"' in str(error) else None
            if not bad or bad not in options:
                raise
            options.pop(bad)


def render_preview(obj, path, height):
    scene = bpy.context.scene
    for engine in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE", "BLENDER_WORKBENCH"):
        try:
            scene.render.engine = engine
            break
        except TypeError:
            continue
    scene.render.resolution_x = scene.render.resolution_y = 768
    scene.render.film_transparent = False
    world = bpy.data.worlds.new("preview") if not scene.world else scene.world
    scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.42, 0.5, 0.6, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.8
    sun_data = bpy.data.lights.new("sun", "SUN")
    sun_data.energy = 3.5
    sun = bpy.data.objects.new("sun", sun_data)
    sun.rotation_euler = (math.radians(50), 0, math.radians(35))
    scene.collection.objects.link(sun)
    ground = bpy.data.meshes.new("ground")
    gbm = bmesh.new()
    bmesh.ops.create_grid(gbm, x_segments=1, y_segments=1, size=height * 2)
    gbm.to_mesh(ground)
    gbm.free()
    ground_obj = bpy.data.objects.new("ground", ground)
    gmat = bpy.data.materials.new("ground")
    gmat.use_nodes = True
    gmat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.18, 0.16, 0.12, 1)
    ground.materials.append(gmat)
    scene.collection.objects.link(ground_obj)
    cam_data = bpy.data.cameras.new("cam")
    cam_data.lens = 50
    cam = bpy.data.objects.new("cam", cam_data)
    scene.collection.objects.link(cam)
    target = Vector((0, 0, height * 0.5))
    cam.location = target + Vector((1.0, -1.25, 0.18)).normalized() * height * 2.3
    cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    scene.render.filepath = path
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.render.render(write_still=True)


# --------------------------------------------------------------------------- main

def build(species_id, render):
    with open(os.path.join(SPECIES_DIR, species_id + ".json"), encoding="utf-8") as handle:
        recipe = json.load(handle)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    rng = random.Random(recipe["seed"])
    atlas, rects = leaf_atlas(recipe, species_id)
    bark = bark_image(recipe, species_id)
    materials = make_materials(species_id, bark, atlas)
    tree = TreeMesh(recipe, rng, rects)
    grow = grow_conifer if recipe["form"] == "conifer" else grow_deciduous
    centre = grow(tree, recipe, rng)
    obj = tree.finish(species_id, materials, recipe["leaf_cards"].get("outward_normals", 0.7), centre)
    tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    dims = obj.dimensions
    glb = os.path.join(GENERATED_DIR, species_id, species_id + ".glb")
    export_glb(obj, glb)
    print(f"[trees] {species_id}: {tris} tris, {dims.x:.1f} x {dims.y:.1f} x {dims.z:.1f} m -> {os.path.relpath(glb, ROOT)}")
    if render:
        preview = os.path.join(CONCEPT_DIR, species_id, "blender_preview.png")
        render_preview(obj, preview, dims.z)
        print(f"[trees] preview {os.path.relpath(preview, ROOT)}")


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    only = None
    render = "--no-render" not in argv
    if "--only" in argv:
        only = argv[argv.index("--only") + 1].split(",")
    species = sorted(f[:-5] for f in os.listdir(SPECIES_DIR) if f.endswith(".json"))
    for species_id in species:
        if only and species_id not in only:
            continue
        build(species_id, render)


main()
