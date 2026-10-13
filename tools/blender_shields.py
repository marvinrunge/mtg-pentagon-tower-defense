"""Builds the two White shields in Blender: the paladin boss's and the White soldiers'.

Run inside Blender (Text editor, or exec() through the Blender MCP):

    exec(open(r"<repo>/tools/blender_shields.py").read()); build("soldier") / build("paladin")

Everything is made from code so a shape change is a number here, not a re-model. Each
shield is built from parts (face, rim, emblem, straps), every part with a procedural
material, then joined, UV-unwrapped and BAKED to one texture set, because procedural
nodes do not survive glTF. The sun on both is the White mana symbol.

Axes in Blender: front of the shield faces -Y, up is +Z. glTF export turns that into
front +Z, up +Y. The origin is the grip on the back, so the shield hangs off a hand
bone with an identity-ish transform.
"""
import math

import bmesh
import bpy
from mathutils import Vector

REPO = r"G:\Projekte\mtg-pentagon-tower-defense"

## Per shield. Sizes are metres at the scale the characters stand in Blender (soldier
## 1.8 m, paladin 2.4 m); the builders in Godot scale the glb anyway.
SHIELDS = {
    "soldier": {
        "out": REPO + r"\assets\weapons\human\human_shield.glb",
        "width": 0.58, "side": 0.30, "peak": 0.0,
        "bend": 0.55, "dome": 0.12, "thickness": 0.035,
        "rim_width": 0.03, "rim_depth": 0.05,
        "inner_band": None,
        "sun": {"core": 0.075, "rays": 8, "long": 0.17, "short": 0.11, "height": 0.022, "glow": False},
        "studs": 10,
        "face": "paint", "back": "wood", "rim": "brass", "emblem": "brass",
        "bake_size": 1024, "detail": (14, 10, 20), "rings": 8,
        "grip_z": 0.0,
    },
    "paladin": {
        "out": REPO + r"\assets\weapons\bosses\white_paladin\white_paladin_shield.glb",
        "width": 0.9, "side": 0.5, "peak": 0.13,
        "bend": 0.4, "dome": 0.08, "thickness": 0.05,
        "rim_width": 0.05, "rim_depth": 0.08,
        "inner_band": 0.82, "cross": True,
        "sun": {"core": 0.11, "rays": 12, "long": 0.32, "short": 0.2, "height": 0.035, "glow": True},
        "studs": 16,
        "face": "steel", "back": "steel_dark", "rim": "gold", "emblem": "gold",
        "bake_size": 2048, "detail": (22, 16, 30), "rings": 10,
        # Above the middle, so the tall shield hangs low from the fist like a tower shield.
        "grip_z": 0.22,
    },
}



## The back, at the soldier's size (scaled with width for the paladin): the grip is the
## origin, on the centre line at the shield's "grip_z" (metres above its middle).
GRIP_STANDOFF = 0.045
## The characters render fully non-metallic (metallic 0, roughness 1 - see the builders'
## materials). A fully metallic shield next to them reads near-black wherever there is
## little to reflect, which at night is everywhere, so the baked metalness is scaled down.
METAL_SCALE = 0.5

# --------------------------------------------------------------------------- shape

def outline(cfg):
    """Closed outline in the shield plane (x right, z up), counter-clockwise from the
    top centre. A heater shield: flat (or peaked) top, straight sides, two arcs of radius
    `width` that meet in the bottom point. The centre of the shield is z=0."""
    w = cfg["width"]
    half = w / 2.0
    side = cfg["side"]
    arc_drop = w * math.sin(math.radians(60))
    top = (side + arc_drop) / 2.0
    s = top - side  # where the sides turn into arcs
    pts = []
    n_top, n_side, n_arc = cfg["detail"]

    def top_z(x):
        # A gothic peak for the paladin: rises towards the middle, sharp at the centre.
        return top + cfg["peak"] * (1.0 - abs(x) / half) ** 1.6

    # top edge, from centre to the left corner
    for i in range(n_top):
        x = -half * i / n_top
        pts.append((x, top_z(x)))
    # left side down
    for i in range(n_side):
        pts.append((-half, top - side * i / n_side))
    # left arc to the bottom point: centre (half, s), radius w
    for i in range(n_arc):
        a = math.radians(180 + 60 * i / n_arc)
        pts.append((half + w * math.cos(a), s + w * math.sin(a)))
    # right arc from the bottom point up: centre (-half, s)
    for i in range(n_arc):
        a = math.radians(-60 + 60 * i / n_arc)
        pts.append((-half + w * math.cos(a), s + w * math.sin(a)))
    # right side up
    for i in range(n_side):
        pts.append((half, s + side * i / n_side))
    # top edge, right corner back to centre
    for i in range(n_top):
        x = half - half * i / n_top
        pts.append((x, top_z(x)))
    return pts


def outward_normals(pts):
    """2D outward normal per outline point, from the neighbours (the outline runs CCW
    seen from the front, i.e. from -Y, which in x/z is clockwise)."""
    out = []
    n = len(pts)
    for i in range(n):
        a = Vector(pts[i - 1]); b = Vector(pts[(i + 1) % n])
        t = (b - a).normalized()
        nrm = Vector((-t.y, t.x))
        out.append(nrm)
    # make sure they point away from the centre
    c = Vector((0.0, 0.0))
    if sum((Vector(p) - c).dot(nn) for p, nn in zip(pts, out)) < 0:
        out = [-v for v in out]
    return out


def surf(cfg, x, z):
    """Y of the FRONT surface at (x, z): bent round the vertical axis and slightly domed,
    the centre furthest forward (most -Y). 0 at the centre."""
    return cfg["bend"] * x * x + cfg["dome"] * z * z


# --------------------------------------------------------------------------- materials

def _principled(mat):
    return next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")


def _noise(nt, scale, detail=6.0, rough=0.6, coord="Object"):
    tc = nt.nodes.new("ShaderNodeTexCoord")
    nz = nt.nodes.new("ShaderNodeTexNoise")
    nz.inputs["Scale"].default_value = scale
    nz.inputs["Detail"].default_value = detail
    nz.inputs["Roughness"].default_value = rough
    nt.links.new(tc.outputs[coord], nz.inputs["Vector"])
    return nz


def _ramp(nt, src, stops):
    r = nt.nodes.new("ShaderNodeValToRGB")
    els = r.color_ramp.elements
    while len(els) > len(stops):
        els.remove(els[-1])
    while len(els) < len(stops):
        els.new(0.5)
    for el, (pos, col) in zip(els, stops):
        el.position = pos
        el.color = col if len(col) == 4 else (*col, 1.0)
    nt.links.new(src, r.inputs["Fac"])
    return r


def _bump(nt, bsdf, height_src, strength, distance=0.002):
    b = nt.nodes.new("ShaderNodeBump")
    b.inputs["Strength"].default_value = strength
    b.inputs["Distance"].default_value = distance
    nt.links.new(height_src, b.inputs["Height"])
    nt.links.new(b.outputs["Normal"], bsdf.inputs["Normal"])


def make_material(kind, key):
    # Per shield, so building one does not pull the materials out from under the other.
    name = "shield_%s_%s" % (key, kind)
    old = bpy.data.materials.get(name)
    if old:
        bpy.data.materials.remove(old)
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = _principled(mat)

    if kind == "paint":
        # Off-white enamel over steel, worn: chips show the metal, grime in the noise.
        grime = _noise(nt, 18.0, 8.0, 0.65)
        chips = _noise(nt, 55.0, 4.0, 0.7)
        col = _ramp(nt, grime.outputs["Fac"], [(0.3, (0.62, 0.6, 0.55)), (0.62, (0.86, 0.84, 0.79))])
        chip_mask = _ramp(nt, chips.outputs["Fac"], [(0.66, (0, 0, 0)), (0.7, (1, 1, 1))])
        mix = nt.nodes.new("ShaderNodeMix"); mix.data_type = "RGBA"
        nt.links.new(chip_mask.outputs["Color"], mix.inputs["Factor"])
        nt.links.new(col.outputs["Color"], mix.inputs[6])
        mix.inputs[7].default_value = (0.42, 0.41, 0.4, 1.0)
        nt.links.new(mix.outputs[2], bsdf.inputs["Base Color"])
        nt.links.new(chip_mask.outputs["Color"], bsdf.inputs["Metallic"])
        rough = _ramp(nt, grime.outputs["Fac"], [(0.3, (0.62, 0.62, 0.62)), (0.7, (0.42, 0.42, 0.42))])
        nt.links.new(rough.outputs["Color"], bsdf.inputs["Roughness"])
        _bump(nt, bsdf, chips.outputs["Fac"], 0.08)
    elif kind in ("brass", "gold"):
        base = (0.78, 0.58, 0.3) if kind == "brass" else (0.9, 0.68, 0.32)
        dark = (0.42, 0.3, 0.14) if kind == "brass" else (0.5, 0.36, 0.15)
        nz = _noise(nt, 22.0, 8.0, 0.6)
        col = _ramp(nt, nz.outputs["Fac"], [(0.32, dark), (0.6, base)])
        nt.links.new(col.outputs["Color"], bsdf.inputs["Base Color"])
        bsdf.inputs["Metallic"].default_value = 1.0
        rough = _ramp(nt, nz.outputs["Fac"], [(0.3, (0.55, 0.55, 0.55)), (0.7, (0.28, 0.28, 0.28))])
        nt.links.new(rough.outputs["Color"], bsdf.inputs["Roughness"])
        _bump(nt, bsdf, nz.outputs["Fac"], 0.06)
    elif kind in ("steel", "steel_dark"):
        # Warm grey plate like the paladin's armour, hammered.
        hi = (0.6, 0.58, 0.54) if kind == "steel" else (0.36, 0.34, 0.31)
        lo = (0.34, 0.32, 0.29) if kind == "steel" else (0.2, 0.19, 0.17)
        nz = _noise(nt, 10.0, 8.0, 0.62)
        ham = nt.nodes.new("ShaderNodeTexVoronoi")
        ham.inputs["Scale"].default_value = 60.0
        tc = nt.nodes.new("ShaderNodeTexCoord")
        nt.links.new(tc.outputs["Object"], ham.inputs["Vector"])
        col = _ramp(nt, nz.outputs["Fac"], [(0.3, lo), (0.65, hi)])
        nt.links.new(col.outputs["Color"], bsdf.inputs["Base Color"])
        bsdf.inputs["Metallic"].default_value = 1.0
        rough = _ramp(nt, nz.outputs["Fac"], [(0.3, (0.6, 0.6, 0.6)), (0.7, (0.36, 0.36, 0.36))])
        nt.links.new(rough.outputs["Color"], bsdf.inputs["Roughness"])
        _bump(nt, bsdf, ham.outputs["Distance"], 0.12)
    elif kind == "wood":
        wave = nt.nodes.new("ShaderNodeTexWave")
        wave.wave_type = "BANDS"; wave.bands_direction = "X"
        wave.inputs["Scale"].default_value = 14.0
        wave.inputs["Distortion"].default_value = 2.5
        wave.inputs["Detail"].default_value = 4.0
        wave.inputs["Detail Scale"].default_value = 2.0
        tc = nt.nodes.new("ShaderNodeTexCoord")
        nt.links.new(tc.outputs["Object"], wave.inputs["Vector"])
        col = _ramp(nt, wave.outputs["Fac"], [(0.15, (0.17, 0.1, 0.05)), (0.9, (0.3, 0.19, 0.1))])
        nt.links.new(col.outputs["Color"], bsdf.inputs["Base Color"])
        bsdf.inputs["Roughness"].default_value = 0.75
        _bump(nt, bsdf, wave.outputs["Fac"], 0.1)
    elif kind == "leather":
        nz = _noise(nt, 120.0, 6.0, 0.7)
        col = _ramp(nt, nz.outputs["Fac"], [(0.3, (0.12, 0.065, 0.03)), (0.7, (0.27, 0.15, 0.07))])
        nt.links.new(col.outputs["Color"], bsdf.inputs["Base Color"])
        bsdf.inputs["Roughness"].default_value = 0.68
        _bump(nt, bsdf, nz.outputs["Fac"], 0.15)
    elif kind == "glow":
        bsdf.inputs["Base Color"].default_value = (1.0, 0.85, 0.5, 1.0)
        bsdf.inputs["Emission Color"].default_value = (1.0, 0.78, 0.38, 1.0)
        bsdf.inputs["Emission Strength"].default_value = 2.5
        bsdf.inputs["Roughness"].default_value = 0.3
    return mat


# --------------------------------------------------------------------------- parts

def _new_obj(name, bm, mat, coll):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    coll.objects.link(ob)
    me.materials.append(mat)
    return ob


def build_face(cfg, pts, coll, mats):
    """Front plate + back plate + side wall, as rings from the centre to the outline so
    the edge flow follows the shape and the bend stays smooth."""
    rings = cfg["rings"]
    t = cfg["thickness"]
    bm = bmesh.new()
    n = len(pts)

    def ring_frac(r):
        # denser towards the edge, where the rim and the silhouette are
        return 1.0 - (1.0 - r / rings) ** 1.4

    def make_side(back):
        centre = bm.verts.new((0.0, (t if back else 0.0), 0.0))
        grid = []
        for r in range(1, rings + 1):
            f = ring_frac(r)
            row = []
            for (x, z) in pts:
                px, pz = x * f, z * f
                row.append(bm.verts.new((px, surf(cfg, px, pz) + (t if back else 0.0), pz)))
            grid.append(row)
        faces = []
        for i in range(n):
            j = (i + 1) % n
            faces.append(bm.faces.new((centre, grid[0][j], grid[0][i]) if not back else (centre, grid[0][i], grid[0][j])))
        for r in range(rings - 1):
            for i in range(n):
                j = (i + 1) % n
                q = (grid[r][i], grid[r][j], grid[r + 1][j], grid[r + 1][i])
                faces.append(bm.faces.new(q if not back else tuple(reversed(q))))
        return grid[-1], faces

    front_edge, front_faces = make_side(False)
    back_edge, back_faces = make_side(True)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((front_edge[i], back_edge[i], back_edge[j], front_edge[j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    for f in bm.faces:
        f.smooth = True
    # The back is a second material: wood or dark steel.
    for f in back_faces:
        f.material_index = 1
    ob = _new_obj("face", bm, mats[cfg["face"]], coll)
    ob.data.materials.append(mats[cfg["back"]])
    return ob


def build_band(cfg, pts, nrms, coll, mat, name, frac, width, depth, wrap):
    """A band following the outline: the rim (wrap=True: it folds round the edge onto the
    back) or an inner border on the face (wrap=False). Profile is a rounded box swept
    along the outline at `frac` of the way out."""
    t = cfg["thickness"]
    # profile in (outward, forward) - forward is -Y
    if wrap:
        prof = [(-width, -0.002), (-width * 0.7, depth * 0.35), (-width * 0.25, depth * 0.5),
                (0.006, depth * 0.45), (0.012, depth * 0.1), (0.012, -t - depth * 0.1),
                (0.006, -t - depth * 0.3), (-width * 0.5, -t - depth * 0.25), (-width * 0.8, -t - 0.002)]
    else:
        prof = [(-width / 2, -0.002), (-width * 0.38, depth * 0.8), (-width * 0.15, depth),
                (width * 0.15, depth), (width * 0.38, depth * 0.8), (width / 2, -0.002)]
    bm = bmesh.new()
    rows = []
    for (x, z), nn in zip(pts, nrms):
        px, pz = x * frac, z * frac
        row = []
        for (o, fwd) in prof:
            vx, vz = px + nn.x * o, pz + nn.y * o
            # follow the surface: y of the front at that point, minus forward
            row.append(bm.verts.new((vx, surf(cfg, vx, vz) - fwd, vz)))
        rows.append(row)
    n = len(rows); m = len(prof)
    closed = wrap
    for i in range(n):
        j = (i + 1) % n
        for k in range(m if closed else m - 1):
            l = (k + 1) % m
            bm.faces.new((rows[i][k], rows[j][k], rows[j][l], rows[i][l]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    for f in bm.faces:
        f.smooth = True
    return _new_obj(name, bm, mat, coll)


def _sun_outline(sun):
    """Star of alternating long/short rays: broad-based blades, five points each (base,
    flank, tip, flank, base) so build_sun can ridge them."""
    pts = []
    k = sun["rays"] * 2
    core = sun["core"] * 1.05
    for i in range(k):
        a = math.pi / 2 + 2 * math.pi * i / k
        r = sun["long"] if i % 2 == 0 else sun["short"]
        half_w = math.pi / k * (0.95 if i % 2 == 0 else 0.75)
        base_w = core * math.sin(half_w)
        d = Vector((math.cos(a), math.sin(a))); side = Vector((-d.y, d.x))
        mid_r = core + (r - core) * 0.4
        for p in (d * core * math.cos(half_w) - side * base_w,
                  d * mid_r - side * base_w * 0.9,
                  d * r,
                  d * mid_r + side * base_w * 0.9,
                  d * core * math.cos(half_w) + side * base_w):
            pts.append((p.x, p.y))
    return pts


def build_sun(cfg, coll, mats, cz):
    """The White mana sun: a star of rays with a ridge down each, a raised ring, and a
    domed core (glowing on the paladin)."""
    sun = cfg["sun"]
    h = sun["height"]
    objs = []

    # rays: flat-bottomed star, ridged - every outline point joined to the centre at
    # full height along the ray axis, half height at the flanks.
    bm = bmesh.new()
    star = _sun_outline(sun)
    centre_top = bm.verts.new((0, surf(cfg, 0, cz) - h * 0.7, cz))
    base = []; top = []
    for i, (x, z) in enumerate(star):
        k = i % 5
        lift = h * (0.3 if k in (0, 4) else 0.35 if k in (1, 3) else 0.15)
        base.append(bm.verts.new((x, surf(cfg, x, z + cz) + 0.002, z + cz)))
        top.append(bm.verts.new((x * 0.985, surf(cfg, x, z + cz) - lift, z + cz)))
    # ridge verts along each ray's axis
    n = len(star)
    for r in range(sun["rays"] * 2):
        idx = [r * 5 + q for q in range(5)]
        a = math.pi / 2 + 2 * math.pi * r / (sun["rays"] * 2)
        rr = sun["long"] if r % 2 == 0 else sun["short"]
        mid_r = sun["core"] * 1.05 + (rr - sun["core"] * 1.05) * 0.4
        mid = bm.verts.new((mid_r * math.cos(a), surf(cfg, mid_r * math.cos(a), mid_r * math.sin(a) + cz) - h, mid_r * math.sin(a) + cz))
        c0 = top[idx[0]]; c4 = top[idx[4]]
        bm.faces.new((centre_top, c0, top[idx[1]], mid))
        bm.faces.new((mid, top[idx[1]], top[idx[2]]))
        bm.faces.new((mid, top[idx[2]], top[idx[3]]))
        bm.faces.new((centre_top, mid, top[idx[3]], c4))
    for r in range(sun["rays"] * 2):
        a_last = top[r * 5 + 4]; b_first = top[((r + 1) * 5) % n]
        bm.faces.new((centre_top, a_last, b_first))
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((base[i], base[j], top[j], top[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    for f in bm.faces:
        f.smooth = False
    objs.append(_new_obj("sun_rays", bm, mats[cfg["emblem"]], coll))

    # ring round the core
    bm = bmesh.new()
    seg = 32
    rin, rout = sun["core"] * 0.82, sun["core"] * 1.12
    prof = [(rin, 0.2), (rin * 1.03, 1.0), (rout * 0.97, 1.0), (rout, 0.2)]
    rows = []
    for s in range(seg):
        a = 2 * math.pi * s / seg
        row = []
        for (r, hh) in prof:
            x, z = r * math.cos(a), r * math.sin(a) + cz
            row.append(bm.verts.new((x, surf(cfg, x, z) - h * (0.7 + 0.5 * hh), z)))
        rows.append(row)
    for s in range(seg):
        t2 = (s + 1) % seg
        for k in range(len(prof) - 1):
            bm.faces.new((rows[s][k], rows[t2][k], rows[t2][k + 1], rows[s][k + 1]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    for f in bm.faces:
        f.smooth = True
    objs.append(_new_obj("sun_ring", bm, mats[cfg["emblem"]], coll))

    # domed core
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=24, v_segments=8, radius=sun["core"] * 0.84)
    for v in bm.verts:
        v.co.y *= 0.35
    # only the front half shows; the back is inside the ring
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.y > 1e-4], context="VERTS")
    for v in bm.verts:
        x, z = v.co.x, v.co.z + cz
        v.co = Vector((x, surf(cfg, x, z) - h * 1.05 + v.co.y, z))
    for f in bm.faces:
        f.smooth = True
    objs.append(_new_obj("sun_core", bm, mats["glow" if sun["glow"] else cfg["emblem"]], coll))
    return objs


def build_studs(cfg, pts, nrms, coll, mat):
    """Rivet heads just inside the rim, evenly spaced along the outline."""
    bm = bmesh.new()
    n = len(pts)
    count = cfg["studs"]
    # between the rim and the inner band, where there is one
    inset = cfg["rim_width"] * (1.25 if cfg["inner_band"] else 1.6)
    r = cfg["rim_width"] * 0.28
    for s in range(count):
        i = int(n * s / count)
        (x, z), nn = pts[i], nrms[i]
        cx, cz = x - nn.x * inset, z - nn.y * inset
        res = bmesh.ops.create_uvsphere(bm, u_segments=8, v_segments=4, radius=r)
        back = [v for v in res["verts"] if v.co.y > 1e-4]
        front = [v for v in res["verts"] if v.co.y <= 1e-4]
        bmesh.ops.delete(bm, geom=back, context="VERTS")
        for v in front:
            v.co.y *= 0.55
            px, pz = cx + v.co.x, cz + v.co.z
            v.co = Vector((px, surf(cfg, px, pz) - cfg["rim_depth"] * 0.15 + v.co.y, pz))
    for f in bm.faces:
        f.smooth = True
    return _new_obj("studs", bm, mat, coll)


def build_straps(cfg, coll, mat_leather, mat_metal):
    """Back: a centre grip - one upright leather-wrapped bar at the origin, held in the
    fist with the forearm pointing at the shield, which is how tools/fit_shields.gd hangs
    it off the hand (the shield then faces wherever the arm points, i.e. forward in the
    sword-and-shield walk)."""
    t = cfg["thickness"]
    s = cfg["width"] / 0.58
    objs = []
    bm = bmesh.new()

    def strap(x, length, width, standoff):
        segs = 12
        rows = []
        for i in range(segs + 1):
            z = cfg["grip_z"] - length / 2 + length * i / segs
            # arcs away from the back so the hand / forearm fits under it
            lift = standoff * math.sin(math.pi * i / segs) ** 0.6
            y0 = surf(cfg, x, z) + t + lift
            rows.append([bm.verts.new((x - width * 0.5, y0, z)), bm.verts.new((x + width * 0.5, y0, z)),
                         bm.verts.new((x + width * 0.5, y0 + 0.008 * s, z)), bm.verts.new((x - width * 0.5, y0 + 0.008 * s, z))])
        for i in range(segs):
            for k in range(4):
                l = (k + 1) % 4
                bm.faces.new((rows[i][k], rows[i + 1][k], rows[i + 1][l], rows[i][l]))
        bm.faces.new(tuple(rows[0])); bm.faces.new(tuple(reversed(rows[-1])))

    strap(0.0, 0.2 * s, 0.035 * s, GRIP_STANDOFF * s)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    objs.append(_new_obj("straps", bm, mat_leather, coll))

    # brackets where the straps meet the back
    bm = bmesh.new()
    for (x, half) in [(0.0, 0.1 * s)]:
        for z in (cfg["grip_z"] - half, cfg["grip_z"] + half):
            res = bmesh.ops.create_cube(bm, size=1.0)
            for v in res["verts"]:
                v.co = Vector((x + v.co.x * 0.065 * s, surf(cfg, x, z) + t + 0.006 + v.co.y * 0.012, z + v.co.z * 0.035 * s))
    objs.append(_new_obj("brackets", bm, mat_metal, coll))
    return objs


def build_cross(cfg, coll, mat, cz):
    """Paladin only: a raised gold cross from the sun out to the inner band, the plate
    split in four like the panels on the paladin's armour."""
    sun = cfg["sun"]
    frac = cfg["inner_band"]
    w = cfg["width"]
    arc_drop = w * math.sin(math.radians(60))
    top = (cfg["side"] + arc_drop) / 2.0
    width = cfg["rim_width"] * 0.6
    depth = cfg["rim_depth"] * 0.2
    start = sun["long"] * 1.02
    arms = [  # (direction, length from the sun's centre to the inner band)
        (Vector((0, 1)), (top + cfg["peak"]) * frac - cz),
        (Vector((0, -1)), top * frac + cz),
        (Vector((1, 0)), w / 2 * frac),
        (Vector((-1, 0)), w / 2 * frac),
    ]
    prof = [(-width / 2, -0.002), (-width * 0.35, depth * 0.85), (0.0, depth), (width * 0.35, depth * 0.85), (width / 2, -0.002)]
    bm = bmesh.new()
    for d, length in arms:
        side = Vector((-d.y, d.x))
        segs = 16
        rows = []
        for i in range(segs + 1):
            c = d * (start + (length - start) * i / segs)
            row = []
            for (o, fwd) in prof:
                x, z = c.x + side.x * o, c.y + side.y * o + cz
                row.append(bm.verts.new((x, surf(cfg, x, z) - fwd, z)))
            rows.append(row)
        for i in range(segs):
            for k in range(len(prof) - 1):
                bm.faces.new((rows[i][k], rows[i + 1][k], rows[i + 1][k + 1], rows[i][k + 1]))
        bm.faces.new(tuple(rows[0]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    for f in bm.faces:
        f.smooth = True
    return _new_obj("cross", bm, mat, coll)


def bevel(ob, width, segs=2):
    m = ob.modifiers.new("bevel", "BEVEL")
    m.width = width
    m.segments = segs
    m.limit_method = "ANGLE"
    m.angle_limit = math.radians(35)
    m.harden_normals = False


# --------------------------------------------------------------------------- build

def build(key):
    cfg = SHIELDS[key]
    cname = "shield_" + key
    coll = bpy.data.collections.get(cname)
    if coll:
        for o in list(coll.objects):
            bpy.data.objects.remove(o, do_unlink=True)
    else:
        coll = bpy.data.collections.new(cname)
        bpy.context.scene.collection.children.link(coll)

    kinds = {cfg["face"], cfg["back"], cfg["rim"], cfg["emblem"], "leather", "glow"}
    mats = {k: make_material(k, key) for k in kinds}

    pts = outline(cfg)
    nrms = outward_normals(pts)
    parts = [build_face(cfg, pts, coll, mats)]
    parts.append(build_band(cfg, pts, nrms, coll, mats[cfg["rim"]], "rim", 1.0, cfg["rim_width"], cfg["rim_depth"] * 0.5, True))
    if cfg["inner_band"]:
        parts.append(build_band(cfg, pts, nrms, coll, mats[cfg["rim"]], "inner_band", cfg["inner_band"], cfg["rim_width"] * 0.45, cfg["rim_depth"] * 0.22, False))
    parts.append(build_studs(cfg, pts, nrms, coll, mats[cfg["rim"]]))
    cz = 0.06 * cfg["width"]
    parts += build_sun(cfg, coll, mats, cz)
    if cfg.get("cross"):
        parts.append(build_cross(cfg, coll, mats[cfg["emblem"]], cz))
    parts += build_straps(cfg, coll, mats["leather"], mats[cfg["rim"]])
    return parts


# --------------------------------------------------------------------------- bake + export

def _grip(cfg):
    """Centre of the hand grip on the back - the shield's origin."""
    s = cfg["width"] / 0.58
    return Vector((0.0, surf(cfg, 0.0, cfg["grip_z"]) + cfg["thickness"] + GRIP_STANDOFF * s * 0.6, cfg["grip_z"]))


def _channel_source(mat, socket_name):
    bsdf = _principled(mat)
    sock = bsdf.inputs[socket_name]
    return (sock.links[0].from_socket if sock.links else None), sock.default_value


def _bake_emit(obj, mats, img, socket_name):
    """Bakes one Principled input of every material to `img` by routing it through an
    Emission shader for the duration of the bake."""
    restore = []
    for mat in mats:
        nt = mat.node_tree
        out = next(n for n in nt.nodes if n.type == "OUTPUT_MATERIAL" and n.is_active_output)
        old = out.inputs["Surface"].links[0].from_socket
        em = nt.nodes.new("ShaderNodeEmission")
        src, val = _channel_source(mat, socket_name)
        if src is not None:
            nt.links.new(src, em.inputs["Color"])
        else:
            em.inputs["Color"].default_value = tuple(val) if hasattr(val, "__len__") else (val, val, val, 1.0)
        nt.links.new(em.outputs["Emission"], out.inputs["Surface"])
        restore.append((nt, out, old, em))
    try:
        bpy.ops.object.bake(type="EMIT", margin=8)
    finally:
        for nt, out, old, em in restore:
            nt.links.new(old, out.inputs["Surface"])
            nt.nodes.remove(em)


def bake_and_export(key, export=True):
    import numpy as np

    cfg = SHIELDS[key]
    coll = bpy.data.collections["shield_" + key]
    size = cfg["bake_size"]
    name = "%s_shield" % ("human" if key == "soldier" else "white_paladin")

    old = bpy.data.objects.get(name)
    if old:
        bpy.data.objects.remove(old, do_unlink=True)
    for stale in (bpy.data.meshes.get(name), bpy.data.materials.get(name + "_glow")):
        if stale:
            (bpy.data.meshes if isinstance(stale, bpy.types.Mesh) else bpy.data.materials).remove(stale)

    # 1. join copies of the parts
    bpy.ops.object.select_all(action="DESELECT")
    copies = []
    for o in list(coll.objects):
        if o.type != "MESH" or o.name.startswith(name):
            continue
        c = o.copy(); c.data = o.data.copy()
        coll.objects.link(c)
        c.location = (0, 0, 0)
        copies.append(c)
    for c in copies:
        c.select_set(True)
    bpy.context.view_layer.objects.active = copies[0]
    bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    obj.name = name
    obj.data.name = name
    # origin on the grip
    g = _grip(cfg)
    obj.data.transform(__import__("mathutils").Matrix.Translation(-g))
    # triangles: the glTF exporter cannot make tangents for the n-gon caps
    bm = bmesh.new(); bm.from_mesh(obj.data)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    bm.to_mesh(obj.data); bm.free()

    # 2. UVs
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.004, scale_to_bounds=True)
    bpy.ops.uv.pack_islands(margin=0.004, rotate=True)
    bpy.ops.object.mode_set(mode="OBJECT")

    # 3. bake targets
    def new_img(suffix, non_color):
        n = "%s_%s" % (name, suffix)
        if n in bpy.data.images:
            bpy.data.images.remove(bpy.data.images[n])
        im = bpy.data.images.new(n, size, size, alpha=False, float_buffer=False)
        if non_color:
            im.colorspace_settings.name = "Non-Color"
        return im

    img_col = new_img("base_color", False)
    img_rough = new_img("rough", True)
    img_metal = new_img("metal", True)
    img_nrm = new_img("normal", True)

    glow = [m for m in obj.data.materials if m and m.name.endswith("_glow")]
    baked_mats = [m for m in obj.data.materials if m and m not in glow]

    scene = bpy.context.scene
    prev_engine = scene.render.engine
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 4
    scene.render.bake.use_selected_to_active = False
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj

    def target(img):
        for m in baked_mats + glow:
            nt = m.node_tree
            tn = nt.nodes.get("_bake_target") or nt.nodes.new("ShaderNodeTexImage")
            tn.name = "_bake_target"
            tn.image = img
            nt.nodes.active = tn

    try:
        target(img_col); _bake_emit(obj, baked_mats + glow, img_col, "Base Color")
        target(img_rough); _bake_emit(obj, baked_mats + glow, img_rough, "Roughness")
        target(img_metal); _bake_emit(obj, baked_mats + glow, img_metal, "Metallic")
        target(img_nrm)
        bpy.ops.object.bake(type="NORMAL", normal_space="TANGENT", margin=8)
    finally:
        for m in baked_mats + glow:
            tn = m.node_tree.nodes.get("_bake_target")
            if tn:
                m.node_tree.nodes.remove(tn)
        scene.render.engine = prev_engine

    # 4. pack roughness (G) and metallic (B) the glTF way
    px = size * size * 4
    r = np.empty(px, dtype=np.float32); img_rough.pixels.foreach_get(r)
    mt = np.empty(px, dtype=np.float32); img_metal.pixels.foreach_get(mt)
    orm = np.ones(px, dtype=np.float32)
    orm[1::4] = r[0::4]
    orm[2::4] = mt[0::4] * METAL_SCALE
    img_orm = new_img("metallic_roughness", True)
    img_orm.pixels.foreach_set(orm)
    bpy.data.images.remove(img_rough); bpy.data.images.remove(img_metal)
    for im in (img_col, img_orm, img_nrm):
        im.pack()

    # 5. one textured material (+ the glow, which stays a flat emissive)
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    for n in list(nt.nodes):
        if n.type != "OUTPUT_MATERIAL":
            nt.nodes.remove(n)
    out = next(n for n in nt.nodes if n.type == "OUTPUT_MATERIAL")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bsdf.outputs[0], out.inputs["Surface"])
    t_col = nt.nodes.new("ShaderNodeTexImage"); t_col.image = img_col
    t_orm = nt.nodes.new("ShaderNodeTexImage"); t_orm.image = img_orm
    t_nrm = nt.nodes.new("ShaderNodeTexImage"); t_nrm.image = img_nrm
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nt.links.new(t_col.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(t_orm.outputs["Color"], sep.inputs["Color"])
    nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
    nt.links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])
    nt.links.new(t_nrm.outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])

    glow_idx = {i for i, m in enumerate(obj.data.materials) if m in glow}
    glowing = [p.material_index in glow_idx for p in obj.data.polygons]
    obj.data.materials.clear()  # resets the indices, hence the list above
    obj.data.materials.append(mat)
    if glow:
        gm = glow[0].copy()
        gm.name = name + "_glow"
        obj.data.materials.append(gm)
    for p, g in zip(obj.data.polygons, glowing):
        p.material_index = 1 if g else 0

    print(name, "tris", sum(len(p.vertices) - 2 for p in obj.data.polygons))

    if export:
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.export_scene.gltf(filepath=cfg["out"], export_format="GLB", use_selection=True,
                                  export_yup=True, export_apply=True, export_tangents=True,
                                  export_image_format="AUTO", export_animations=False,
                                  export_skins=False, export_morph=False)
        print("wrote", cfg["out"])
    return obj
