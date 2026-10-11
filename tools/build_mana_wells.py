"""Writes scenes/mana_wells/mana_well_<colour>.tscn from the fit of the new well models.

usage: python -I tools/build_mana_wells.py <wells_fit.json>

The JSON comes from tools/tests/fit_mana_wells.tscn. Each well scene gets:

    Model        the Meshy model (tools/mesh_mana_wells.py), scaled and centred by the fit
    ManaSurface  the basin's magical surface: the mesh the fit cut to the basin, at the
                 level it holds, with assets/shaders/mana_pool.gdshader in the well's colour
    Motes        a few sparks of the colour rising off the surface

and the well's Visual node in scenes/misc/main.tscn is moved so the model's base sits on
the terrain under it. The scene files keep their uids, so main.tscn's references stay.
The light at each well stays where it is: WellGlow_<colour> under PlacedCrystals/Wells.

A text edit of main.tscn rather than a re-save through Godot - see
tools/bake_placed_crystals.py. Close main.tscn in the editor first.
"""
import json
import re
import sys

MAIN = "scenes/misc/main.tscn"
## How far the base goes into the ground, so a mound's edge never floats over a dip.
SINK = 0.15

## Per colour: the root name and uid the scene already has, its lane in main.tscn, and the
## surface's shader parameters. Colours lean on the crystals' (tools/nature/nature_assets.json).
WELLS = {
    "white": {
        "root": "ManaWellWhite", "uid": "uid://bujxuwn5eicwh", "lane": "Lane_White",
        # Golden light-water.
        "pool": {"deep_color": (0.9, 0.7, 0.32), "bright_color": (1.0, 0.94, 0.72),
                 "pattern_scale": 3.5, "flow_speed": 0.05, "swirl_speed": 0.05,
                 "vein_sharpness": 6.0, "vein_strength": 0.9, "liquid_roughness": 0.05,
                 "day_glow": 0.55},
    },
    "blue": {
        "root": "ManaWellBlue", "uid": "uid://ckixg7hxy7mnh", "lane": "Lane_Blue",
        # Glowing sea-water.
        "pool": {"deep_color": (0.02, 0.1, 0.28), "bright_color": (0.2, 0.68, 1.0),
                 "pattern_scale": 3.5, "flow_speed": 0.06, "swirl_speed": 0.07,
                 "vein_sharpness": 5.0, "vein_strength": 1.1, "liquid_roughness": 0.04},
    },
    "black": {
        "root": "ManaWellBlack", "uid": "uid://ovg6bup0stwp", "lane": "Lane_Black",
        # Violet ooze: slow, oily, thin bright veins.
        "pool": {"deep_color": (0.06, 0.01, 0.1), "bright_color": (0.66, 0.3, 1.0),
                 "pattern_scale": 3.0, "flow_speed": 0.025, "swirl_speed": 0.025,
                 "vein_sharpness": 9.0, "vein_strength": 1.3, "liquid_roughness": 0.22,
                 "ripple_strength": 0.15, "day_glow": 0.25},
    },
    "red": {
        "root": "ManaWellRed", "uid": "uid://dm18yoqik3i42", "lane": "Lane_Red",
        # Lava: crusted plates, glowing cracks - and it glows by day too.
        "pool": {"deep_color": (0.55, 0.06, 0.0), "bright_color": (1.0, 0.48, 0.1),
                 "pattern_scale": 4.5, "flow_speed": 0.03, "swirl_speed": 0.015,
                 "vein_sharpness": 4.0, "vein_strength": 1.6, "crust": 0.6,
                 "crust_color": (0.07, 0.035, 0.025), "day_glow": 0.9, "night_glow": 2.0},
    },
    "green": {
        "root": "ManaWellGreen", "uid": "uid://bpcfm7k0vv3bv", "lane": "Lane_Green",
        # Luminous sap.
        "pool": {"deep_color": (0.08, 0.26, 0.03), "bright_color": (0.55, 1.0, 0.3),
                 "pattern_scale": 3.5, "flow_speed": 0.035, "swirl_speed": 0.04,
                 "vein_sharpness": 6.0, "vein_strength": 1.0, "liquid_roughness": 0.12},
    },
}


def value(v):
    if isinstance(v, tuple):
        return "Color(%s, %s, %s, 1)" % v
    return repr(float(v))


def well_scene(colour, fit):
    well = WELLS[colour]
    pool = "\n".join(f"shader_parameter/{k} = {value(v)}" for k, v in well["pool"].items())
    bright = well["pool"]["bright_color"]
    radius = max(fit["surface_radius"] * 0.75, 0.2)
    level = fit["level"]
    return f'''[gd_scene format=3 uid="{well["uid"]}"]

[ext_resource type="PackedScene" path="res://assets/structures/mana-well-{colour}/mana-well-{colour}.glb" id="1_model"]
[ext_resource type="Shader" path="res://assets/shaders/mana_pool.gdshader" id="2_pool"]
[ext_resource type="ArrayMesh" path="{fit["surface_mesh"]}" id="3_surface"]

[sub_resource type="ShaderMaterial" id="ShaderMaterial_pool"]
render_priority = 0
shader = ExtResource("2_pool")
{pool}

[sub_resource type="Gradient" id="Gradient_mote"]
offsets = PackedFloat32Array(0, 1)
colors = PackedColorArray(1, 1, 1, 1, 1, 1, 1, 0)

[sub_resource type="GradientTexture2D" id="GradientTexture2D_mote"]
gradient = SubResource("Gradient_mote")
width = 32
height = 32
fill = 1
fill_from = Vector2(0.5, 0.5)
fill_to = Vector2(1, 0.5)

[sub_resource type="StandardMaterial3D" id="StandardMaterial3D_mote"]
transparency = 1
shading_mode = 0
vertex_color_use_as_albedo = true
albedo_texture = SubResource("GradientTexture2D_mote")
billboard_mode = 3
billboard_keep_scale = true
particles_anim_h_frames = 1
particles_anim_v_frames = 1
particles_anim_loop = false

[sub_resource type="QuadMesh" id="QuadMesh_mote"]
material = SubResource("StandardMaterial3D_mote")
size = Vector2(0.08, 0.08)

[sub_resource type="Gradient" id="Gradient_fade"]
offsets = PackedFloat32Array(0, 0.2, 0.7, 1)
colors = PackedColorArray(1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 0.8, 1, 1, 1, 0)

[sub_resource type="GradientTexture1D" id="GradientTexture1D_fade"]
gradient = SubResource("Gradient_fade")

[sub_resource type="ParticleProcessMaterial" id="ParticleProcessMaterial_motes"]
emission_shape = 6
emission_ring_axis = Vector3(0, 1, 0)
emission_ring_height = 0.0
emission_ring_radius = {radius:.3f}
emission_ring_inner_radius = 0.0
direction = Vector3(0, 1, 0)
spread = 12.0
initial_velocity_min = 0.25
initial_velocity_max = 0.55
gravity = Vector3(0, 0.04, 0)
scale_min = 0.6
scale_max = 1.3
color = Color({bright[0]}, {bright[1]}, {bright[2]}, 1)
color_ramp = SubResource("GradientTexture1D_fade")
turbulence_enabled = true
turbulence_noise_strength = 0.3
turbulence_noise_scale = 2.0

[node name="{well["root"]}" type="Node3D"]

[node name="Model" parent="." instance=ExtResource("1_model")]
transform = {fit["model_transform"]}

[node name="ManaSurface" type="MeshInstance3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, {level:.4f}, 0)
cast_shadow = 0
mesh = ExtResource("3_surface")
surface_material_override/0 = SubResource("ShaderMaterial_pool")

[node name="Motes" type="GPUParticles3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, {level + 0.03:.4f}, 0)
cast_shadow = 0
visibility_range_end = 70.0
amount = 14
lifetime = 3.5
preprocess = 3.5
visibility_aabb = AABB(-2, -0.5, -2, 4, 4.5, 4)
process_material = SubResource("ParticleProcessMaterial_motes")
draw_pass_1 = SubResource("QuadMesh_mote")
'''


def main():
    with open(sys.argv[1], encoding="utf-8") as handle:
        fits = json.load(handle)
    for colour, fit in fits.items():
        with open(f"scenes/mana_wells/mana_well_{colour}.tscn", "w", encoding="utf-8", newline="\n") as handle:
            handle.write(well_scene(colour, fit))

    with open(MAIN, encoding="utf-8", newline="") as handle:
        text = handle.read()
    for colour, fit in fits.items():
        lane = WELLS[colour]["lane"]
        y = fit["ground_offset"] - SINK
        pattern = re.compile(r'(\[node name="Visual" parent="NavigationRegion3D/Lanes/%s/ManaSource"[^\]]*\]\r?\ntransform = Transform3D\()([^)]*)\)' % lane)
        match = pattern.search(text)
        if match is None:
            sys.exit(f"main.tscn: no Visual node under {lane}/ManaSource")
        parts = [p.strip() for p in match.group(2).split(",")]
        parts[10] = repr(round(y, 4))
        text = text[:match.start(2)] + ", ".join(parts) + text[match.end(2):]
        print(f"{colour}: Visual y {y:+.3f}, surface at {fit['level']:.2f} m")
    with open(MAIN, "w", encoding="utf-8", newline="") as handle:
        handle.write(text)


if __name__ == "__main__":
    main()
