"""Landmark detection + quadruped armature for the Meshy beasts.

Mesh conventions (after normalisation): head toward -Y, feet on z=0, centred on x.
Everything here works in the mesh object's local space; the armature is created at the
same location so local == armature space.
"""
import bpy
from mathutils import Vector


def verts(o):
    return [v.co.copy() for v in o.data.vertices]


def kmeans1d(vals, k=2, it=30):
    vals = sorted(vals)
    cs = [vals[int((i + 0.5) * len(vals) / k)] for i in range(k)]
    for _ in range(it):
        g = [[] for _ in cs]
        for v in vals:
            g[min(range(k), key=lambda i: abs(v - cs[i]))].append(v)
        cs = [sum(x) / len(x) if x else cs[i] for i, x in enumerate(g)]
    return sorted(cs)


def centroid(ps):
    s = Vector()
    for p in ps:
        s += p
    return s / max(len(ps), 1)


def find_feet(V, H, low=0.07):
    lowv = [p for p in V if p.z < low * H]
    ys = kmeans1d([p.y for p in lowv], 2)
    split = (ys[0] + ys[1]) / 2
    feet = {}
    for side, sx in (('L', 1), ('R', -1)):
        for end, sel in (('front', lambda p: p.y < split), ('hind', lambda p: p.y >= split)):
            ps = [p for p in lowv if (p.x * sx > 0) and sel(p)]
            c = centroid(ps)
            toe = min(ps, key=lambda p: p.y)
            feet[(end, side)] = {'c': Vector((c.x, c.y, 0.0)), 'toe_y': toe.y, 'pts': ps}
    return feet, split


def trace_leg(V, foot, H, top_frac, R=None, dz=None):
    """Walk up a leg from its foot, following slice centroids that stay on this side."""
    R = R or 0.09 * H
    dz = dz or 0.03 * H
    c = foot['c'].copy()
    sx = 1 if c.x > 0 else -1
    pts = [Vector((c.x, c.y, 0.0))]
    z = 0.0
    while z < top_frac * H:
        sl = [p for p in V if z <= p.z < z + dz and (Vector((p.x, p.y)) - Vector((c.x, c.y))).length < R and p.x * sx > 0]
        if not sl:
            break
        n = centroid(sl)
        c = Vector((n.x, n.y, z + dz / 2))
        pts.append(c.copy())
        z += dz
    return pts


def point_at_z(pts, z):
    for a, b in zip(pts, pts[1:]):
        if a.z <= z <= b.z:
            t = (z - a.z) / max(b.z - a.z, 1e-6)
            return a.lerp(b, t)
    return pts[-1].copy()


def spine_center(V, y, H, dy, zmin, xlim=None):
    sl = [p for p in V if abs(p.y - y) < dy and p.z > zmin and (xlim is None or abs(p.x) < xlim)]
    if not sl:
        return None
    zs = [p.z for p in sl]
    return Vector((0.0, y, (min(zs) + max(zs)) / 2))


def chain(points, n):
    """Resample a polyline into n+1 points evenly by arc length."""
    segs = [(a, b, (b - a).length) for a, b in zip(points, points[1:])]
    total = sum(s[2] for s in segs)
    out = []
    for i in range(n + 1):
        d = total * i / n
        for a, b, l in segs:
            if d <= l or (a, b, l) == segs[-1]:
                out.append(a.lerp(b, min(d / max(l, 1e-9), 1.0)))
                break
            d -= l
    return out


def analyse(o, cfg):
    V = verts(o)
    H = max(p.z for p in V)
    ymin = min(p.y for p in V)
    ymax = max(p.y for p in V)
    feet, split = find_feet(V, H, cfg.get('foot_low', 0.07))
    legs = {}
    for key, f in feet.items():
        end = key[0]
        pts = trace_leg(V, f, H, cfg[end + '_trace'])
        legs[key] = pts
    y_front = (feet[('front', 'L')]['c'].y + feet[('front', 'R')]['c'].y) / 2
    y_hind = (feet[('hind', 'L')]['c'].y + feet[('hind', 'R')]['c'].y) / 2
    return dict(V=V, H=H, ymin=ymin, ymax=ymax, feet=feet, legs=legs, y_front=y_front, y_hind=y_hind)


def centerline(V, y0, y1, n, H, dy, zmin, xlim=None):
    pts = []
    for i in range(n + 1):
        y = y0 + (y1 - y0) * i / n
        c = spine_center(V, y, H, dy, zmin, xlim)
        if c:
            pts.append(c)
    return pts


def build(o, cfg):
    A = analyse(o, cfg)
    V, H = A['V'], A['H']
    dy = 0.03 * (A['ymax'] - A['ymin'])
    belly = cfg.get('belly', 0.35) * H
    yh, yf = A['y_hind'] + cfg.get('hip_dy', 0.0), A['y_front'] + cfg.get('chest_dy', 0.0)
    # spine centre points, lowered a touch toward the back third
    sp = centerline(V, yh, yf, 6, H, dy, belly)
    sp = [p + Vector((0, 0, cfg.get('spine_dz', 0.0) * H)) for p in sp]
    spine = chain(sp, 3)
    # neck + head toward the snout
    head_front = A['ymin'] + cfg.get('snout_in', 0.02) * (A['ymax'] - A['ymin'])
    neck_end_y = yf + cfg.get('neck_frac', 0.45) * (head_front - yf)
    nk = centerline(V, yf, neck_end_y, 4, H, dy, cfg.get('neck_zmin', 0.3) * H)
    neck = [spine[-1], nk[-1] + Vector((0, 0, cfg.get('neck_dz', 0.0) * H))]
    hc = centerline(V, neck_end_y, head_front, 4, H, dy, cfg.get('head_zmin', 0.3) * H)
    head = [neck[1], hc[-1] + Vector((0, 0, cfg.get('head_dz', 0.0) * H))]
    # tail
    tail_start = spine[0]
    tp = centerline(V, yh, A['ymax'] - 0.01, 14, H, dy, cfg.get('tail_zmin', 0.15) * H, cfg.get('tail_xlim', 0.06) * H)
    tail = chain([tail_start] + tp[1:], cfg.get('tail_bones', 5))

    arm_data = bpy.data.armatures.new(o.name + '_Rig')
    arm = bpy.data.objects.new(o.name + '_Rig', arm_data)
    bpy.context.scene.collection.objects.link(arm)
    arm.location = o.location
    arm_data.display_type = 'STICK'
    arm.show_in_front = True
    bpy.ops.object.select_all(action='DESELECT')
    bpy.context.view_layer.objects.active = arm
    arm.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    eb = arm_data.edit_bones

    def bone(name, h, t, parent=None, connect=False, deform=True):
        b = eb.new(name)
        b.head, b.tail = h, t
        b.roll = 0.0
        if parent:
            b.parent = eb[parent]
            b.use_connect = connect
        b.use_deform = deform
        return b

    bone('root', Vector((0, 0, 0)), Vector((0, -0.3 * H, 0)), deform=False)
    # hips points backward (from spine[0] toward tail) so it carries tail+hind legs
    bone('hips', spine[0], spine[0] + (spine[0] - spine[1]).normalized() * 0.15 * H, 'root')
    prev = 'hips'
    for i in range(3):
        nm = ['spine', 'spine1', 'chest'][i]
        bone(nm, spine[i], spine[i + 1], prev if i else 'hips', connect=False)
        prev = nm
    bone('neck', neck[0], neck[1], 'chest', True)
    bone('head', head[0], head[1], 'neck', True)
    # jaw: hinge partway along the head, low
    hv = head[1] - head[0]
    hinge = head[0] + hv * cfg.get('jaw_hinge', 0.35) + Vector((0, 0, -cfg.get('jaw_drop', 0.06) * H))
    jaw_tip = head[1] + Vector((0, 0, -cfg.get('jaw_tip_drop', 0.09) * H))
    bone('jaw', hinge, jaw_tip, 'head')
    prev = 'hips'
    for i in range(len(tail) - 1):
        nm = 'tail%d' % i
        bone(nm, tail[i], tail[i + 1], prev, connect=(i > 0))
        prev = nm

    for (end, side), pts in A['legs'].items():
        f = A['feet'][(end, side)]
        hip_z = cfg[end + '_joint_z'] * H
        top = pts[-1]
        joint = Vector((top.x * cfg.get('joint_x_in', 0.8), top.y + cfg.get(end + '_joint_dy', 0.0) * H, hip_z))
        knee = point_at_z(pts, cfg[end + '_knee_z'] * H)
        knee += Vector((0, cfg.get(end + '_knee_dy', 0.0) * H, 0))
        ankle = point_at_z(pts, cfg[end + '_ankle_z'] * H)
        ankle += Vector((0, cfg.get(end + '_ankle_dy', 0.0) * H, 0))
        toe = Vector((f['c'].x, f['toe_y'] * 0.25 + f['c'].y * 0.75, 0.02 * H))
        toe.y = min(toe.y, ankle.y - 0.04 * H)
        pre = ('front' if end == 'front' else 'hind') + '_'
        par = 'chest' if end == 'front' else 'hips'
        bone(pre + 'upper.' + side, joint, knee, par)
        bone(pre + 'lower.' + side, knee, ankle, pre + 'upper.' + side, True)
        bone(pre + 'foot.' + side, ankle, toe, pre + 'lower.' + side, True)
        # IK controller (non-deforming) parented to root, at the ankle
        bone('IK_' + end + '.' + side, ankle, ankle + Vector((0, 0.12 * H, 0)), 'root', deform=False)
        # pole: elbows point back on front legs, knees forward on hind legs (by default)
        mid = (joint + ankle) / 2
        pole_dir = cfg.get(end + '_pole', 1.0 if end == 'front' else -1.0)
        pole = mid + Vector((0, pole_dir * 0.6 * H, 0))
        bone('POLE_' + end + '.' + side, pole, pole + Vector((0, 0, 0.05 * H)), 'root', deform=False)
    bpy.ops.object.mode_set(mode='OBJECT')
    return arm, A


def add_ik(arm, use_pole=True):
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode='POSE')
    pb = arm.pose.bones
    for end in ('front', 'hind'):
        for side in ('L', 'R'):
            lo = pb[end + '_lower.' + side]
            for c in list(lo.constraints):
                lo.constraints.remove(c)
            c = lo.constraints.new('IK')
            c.target = arm
            c.subtarget = 'IK_' + end + '.' + side
            c.chain_count = 2
            if use_pole:
                c.pole_target = arm
                c.pole_subtarget = 'POLE_' + end + '.' + side
                c.pole_angle = 0.0
    bpy.ops.object.mode_set(mode='OBJECT')
    # Feet keep their rest orientation in armature space (stay flat on the ground while the
    # leg swings); foot roll is keyed on the foot's own local rotation.
    for end in ('front', 'hind'):
        for side in ('L', 'R'):
            arm.data.bones[end + '_foot.' + side].use_inherit_rotation = False


def fill_unweighted(o):
    """Give vertices bone heat missed (separate claw/tooth islands) their nearest weighted neighbour's weights."""
    from mathutils import kdtree
    me = o.data
    weighted = [v for v in me.vertices if any(g.weight > 0.01 for g in v.groups)]
    kd = kdtree.KDTree(len(weighted))
    for i, v in enumerate(weighted):
        kd.insert(v.co, i)
    kd.balance()
    n = 0
    for v in me.vertices:
        if any(g.weight > 0.01 for g in v.groups):
            continue
        _, i, _ = kd.find(v.co)
        src = weighted[i]
        for g in src.groups:
            o.vertex_groups[g.group].add([v.index], g.weight, 'REPLACE')
        n += 1
    return n


def set_jaw_weights(o, arm, cut_fn):
    """Jaw gets the verts below the mouth line inside the head; cut_fn(co) -> True for lower jaw."""
    vg_j = o.vertex_groups['jaw']
    vg_h = o.vertex_groups['head']
    for v in o.data.vertices:
        gs = {o.vertex_groups[g.group].name: g.weight for g in v.groups}
        hj = gs.get('head', 0) + gs.get('jaw', 0)
        if hj <= 0:
            continue
        if cut_fn(v.co):
            vg_j.add([v.index], hj, 'REPLACE'); vg_h.remove([v.index])
        else:
            vg_h.add([v.index], hj, 'REPLACE'); vg_j.remove([v.index])


def fit_poles(arm):
    """Pick each leg's pole angle so the IK reproduces the rest pose."""
    import math
    def dev(leg):
        d = 0
        for b in ('upper', 'lower'):
            n = '%s_%s.%s' % (leg[0], b, leg[1])
            pb = arm.pose.bones[n]
            d += (pb.tail - arm.data.bones[n].tail_local).length + (pb.head - arm.data.bones[n].head_local).length
        return d
    res = {}
    for leg in [('front', 'L'), ('front', 'R'), ('hind', 'L'), ('hind', 'R')]:
        c = arm.pose.bones['%s_lower.%s' % leg].constraints[0]
        best = None
        for a in range(-180, 180, 5):
            c.pole_angle = math.radians(a)
            bpy.context.view_layer.update()
            d = dev(leg)
            if best is None or d < best[0]:
                best = (d, a)
        c.pole_angle = math.radians(best[1])
        res[leg] = best
    bpy.context.view_layer.update()
    return res


def smooth_weights(o, skip=('head', 'jaw'), factor=0.5, repeat=2):
    """Laplacian smoothing of deform weights over mesh edges, then normalise per vertex.
    Groups in `skip` keep their exact values (the jaw split is a hard edge on purpose)."""
    me = o.data
    nbr = [[] for _ in me.vertices]
    for e in me.edges:
        a, b = e.vertices
        nbr[a].append(b); nbr[b].append(a)
    names = [g.name for g in o.vertex_groups]
    W = {n: [0.0] * len(me.vertices) for n in names}
    for v in me.vertices:
        for g in v.groups:
            W[names[g.group]][v.index] = g.weight
    for n in names:
        if n in skip:
            continue
        w = W[n]
        for _ in range(repeat):
            w = [(1 - factor) * w[i] + factor * (sum(w[j] for j in nbr[i]) / len(nbr[i])) if nbr[i] else w[i]
                 for i in range(len(w))]
        W[n] = w
    for i in range(len(me.vertices)):
        fixed = sum(W[n][i] for n in skip if n in W)
        free = [n for n in names if n not in skip]
        tot = sum(W[n][i] for n in free)
        if tot > 0:
            s = max(1.0 - fixed, 0.0) / tot
            for n in free:
                W[n][i] *= s
    for n in names:
        vg = o.vertex_groups[n]
        w = W[n]
        for i, x in enumerate(w):
            if x > 0.001:
                vg.add([i], x, 'REPLACE')
            else:
                vg.remove([i])


def split_jaw(o, mouth_z, hinge_y, mouth_z_front=None, front_y=None):
    """Hard head/jaw split along the mouth line (optionally sloped from hinge_y to front_y).
    Small islands (teeth) go wholly to whichever side their top sits on."""
    import bmesh
    me = o.data
    bm = bmesh.new(); bm.from_mesh(me); bm.verts.ensure_lookup_table()
    seen = {}; isl = []
    for v in bm.verts:
        if v.index in seen:
            continue
        st = [v]; cur = []; seen[v.index] = len(isl)
        while st:
            a = st.pop(); cur.append(a.index)
            for e in a.link_edges:
                b = e.other_vert(a)
                if b.index not in seen:
                    seen[b.index] = len(isl); st.append(b)
        isl.append(cur)
    bm.free()
    main = max(range(len(isl)), key=lambda i: len(isl[i]))

    def line_z(y):
        if mouth_z_front is None:
            return mouth_z
        t = max(0.0, min(1.0, (y - hinge_y) / (front_y - hinge_y)))
        return mouth_z + (mouth_z_front - mouth_z) * t

    def is_jaw(vi):
        i = seen[vi]; co = me.vertices[vi].co
        if i == main:
            return co.y < hinge_y and co.z < line_z(co.y)
        top = max(isl[i], key=lambda j: me.vertices[j].co.z)
        c = me.vertices[top].co
        return c.y < hinge_y and c.z < line_z(c.y)
    vj = o.vertex_groups['jaw']; vh = o.vertex_groups['head']
    nj = 0
    for v in me.vertices:
        gs = {o.vertex_groups[g.group].name: g.weight for g in v.groups}
        hj = gs.get('head', 0) + gs.get('jaw', 0)
        if hj <= 0:
            continue
        if is_jaw(v.index):
            vj.add([v.index], hj, 'REPLACE'); vh.remove([v.index]); nj += 1
        else:
            vh.add([v.index], hj, 'REPLACE'); vj.remove([v.index])
    return nj


def skin(o, arm):
    bpy.ops.object.select_all(action='DESELECT')
    o.select_set(True); arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.parent_set(type='ARMATURE_AUTO')
    return fill_unweighted(o)


def split_jaw_geodesic(o, mouth_z, hinge_y, mouth_z_front=None, front_y=None, seed_frac=0.3, blend_rings=1, margin=0.03, jaw_front_y=None):
    """Head/jaw split by growing labels along the surface from the skull top (head) and the
    chin underside (jaw). A tooth ends up on the jaw it is rooted in, however far its tip
    hangs past the mouth line. Disconnected islands fall back to where their top sits."""
    import heapq
    me = o.data
    names = [g.name for g in o.vertex_groups]
    gi_h, gi_j = o.vertex_groups['head'].index, o.vertex_groups['jaw'].index

    def line_z(y):
        if mouth_z_front is None:
            return mouth_z
        t = max(0.0, min(1.0, (y - hinge_y) / (front_y - hinge_y)))
        return mouth_z + (mouth_z_front - mouth_z) * t

    hj = {}
    for v in me.vertices:
        s = sum(g.weight for g in v.groups if g.group in (gi_h, gi_j))
        if s > 0:
            hj[v.index] = s
    R = set(hj)
    nbr = {i: [] for i in R}
    for e in me.edges:
        a, b = e.vertices
        if a in R and b in R:
            l = (me.vertices[a].co - me.vertices[b].co).length
            nbr[a].append((b, l)); nbr[b].append((a, l))
    # islands: seeds and slice extents come from the main surface only - a loose tooth's
    # tip is the lowest point of its slice and must not pose as chin
    import bmesh
    bm = bmesh.new(); bm.from_mesh(me); bm.verts.ensure_lookup_table()
    island_of = {}
    islands = []
    for v in bm.verts:
        if v.index in island_of:
            continue
        st = [v]; cur = []; island_of[v.index] = len(islands)
        while st:
            a = st.pop(); cur.append(a.index)
            for e in a.link_edges:
                b = e.other_vert(a)
                if b.index not in island_of:
                    island_of[b.index] = len(islands); st.append(b)
        islands.append(cur)
    bm.free()
    main = max(range(len(islands)), key=lambda k: len(islands[k]))
    # per-slice top/bottom of the head region (in front of the hinge)
    step = 0.02
    top, bot = {}, {}
    for i in R:
        if island_of[i] != main:
            continue
        c = me.vertices[i].co
        k = round(c.y / step)
        top[k] = max(top.get(k, -1e9), c.z)
        bot[k] = min(bot.get(k, 1e9), c.z)
    label = {}
    dist = {}
    pq = []
    for i in R:
        c = me.vertices[i].co
        if not nbr[i] or island_of[i] != main:
            continue
        k = round(c.y / step)
        lz = line_z(c.y)
        if c.y >= hinge_y:
            lab = 'head' if c.z >= lz else None
        elif c.z >= max(top[k] - seed_frac * (top[k] - lz), lz + margin):
            lab = 'head'
        elif c.z <= min(bot[k] + seed_frac * (lz - bot[k]), lz - margin):
            # the snout tip overhangs the lower jaw: its underside is NOT chin
            lab = 'jaw'
        else:
            lab = None
        if lab:
            label[i] = lab; dist[i] = 0.0
            heapq.heappush(pq, (0.0, i, lab))
    while pq:
        d, i, lab = heapq.heappop(pq)
        if d > dist.get(i, 1e9) or label.get(i) != lab:
            continue
        for j, l in nbr[i]:
            nd = d + l
            if nd < dist.get(j, 1e9):
                dist[j] = nd; label[j] = lab
                heapq.heappush(pq, (nd, j, lab))
    # the main surface clearly above the mouth line is skull, whatever path the growth took
    # (palate reached through the throat)
    for i in R:
        c = me.vertices[i].co
        if island_of[i] == main and c.y < hinge_y and c.z > line_z(c.y) + margin:
            label[i] = 'head'
    # unreached (separate tooth islands, or behind-hinge verts below the line): island-top rule
    for i in R:
        if i in label:
            continue
        isl = islands[island_of[i]]
        reached = [label[j] for j in isl if j in label]
        if reached:
            lab = max(set(reached), key=reached.count)
        else:
            t = max(isl, key=lambda j: me.vertices[j].co.z)
            c = me.vertices[t].co
            lab = 'jaw' if (c.y < hinge_y and c.z < line_z(c.y)) else 'head'
        for j in isl:
            if j in R and j not in label:
                label[j] = lab
    f = {i: (1.0 if label[i] == 'jaw' else 0.0) for i in R}
    # soften only along the label boundary (mouth corners / throat), never across teeth tips
    for _ in range(blend_rings):
        edge = [i for i in R if any(f[j] != f[i] for j, _ in nbr[i])]
        nf = dict(f)
        for i in edge:
            ns = [f[j] for j, _ in nbr[i]]
            nf[i] = 0.5 * f[i] + 0.5 * sum(ns) / len(ns)
        f = nf
    vj = o.vertex_groups['jaw']; vh = o.vertex_groups['head']
    nj = 0
    for i, s in hj.items():
        wj = s * f[i]; wh = s - wj
        if wj > 0.001:
            vj.add([i], wj, 'REPLACE')
        else:
            vj.remove([i])
        if wh > 0.001:
            vh.add([i], wh, 'REPLACE')
        else:
            vh.remove([i])
        nj += f[i] > 0.5
    return nj
