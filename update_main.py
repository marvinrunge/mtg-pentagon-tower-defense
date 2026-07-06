import re

def update_main_tscn():
    with open('scenes/main.tscn', 'r', encoding='utf-8') as f:
        content = f.read()

    # 1. BasePentagon radius
    content = re.sub(
        r'(\[node name="BasePentagon" type="CSGCylinder3D"[^]]*\]\n(?:[^\[]*\n)*?radius = )([\d\.]+)',
        g_radius,
        content
    )

    # 2. Lane Geometry Z offset
    content = re.sub(
        r'(\[node name="Geometry" type="CSGPolygon3D"[^]]*\]\n(?:[^\[]*\n)*?transform = Transform3D\([^,]+, [^,]+, [^,]+, [^,]+, [^,]+, [^,]+, [^,]+, [^,]+, [^,]+, [^,]+, [^,]+, )([\-\d\.]+)(\))',
        g_geom_trans,
        content
    )

    # 3. Lane Polygon (scale X by 2)
    content = re.sub(
        r'(\[node name="Geometry" type="CSGPolygon3D"[^]]*\]\n(?:[^\[]*\n)*?polygon = PackedVector2Array\()([^\)]+)(\))',
        g_poly,
        content
    )

    # 4. ManaSource Z offset
    content = re.sub(
        r'(\[node name="ManaSource" type="Area3D"[^]]*\]\n(?:[^\[]*\n)*?transform = Transform3D\([^,]+, [^,]+, [^,]+, [^,]+, [^,]+, [^,]+, [^,]+, [^,]+, [^,]+, [^,]+, [^,]+, )([\-\d\.]+)(\))',
        g_mana,
        content
    )

    # 5. EnemySpawner Z offset
    content = re.sub(
        r'(\[node name="EnemySpawner" type="Marker3D"[^]]*\]\n(?:[^\[]*\n)*?transform = Transform3D\([^,]+, [^,]+, [^,]+, [^,]+, [^,]+, [^,]+, [^,]+, [^,]+, [^,]+, [^,]+, [^,]+, )([\-\d\.]+)(\))',
        g_spawner,
        content
    )

    with open('scenes/main.tscn', 'w', encoding='utf-8') as f:
        f.write(content)


def g_radius(m):
    return m.group(1) + '50.0'

def g_geom_trans(m):
    return m.group(1) + '-40.4508' + m.group(3)

def g_poly(m):
    coords = [float(x.strip()) for x in m.group(2).split(',')]
    # double the X values (every even index)
    for i in range(0, len(coords), 2):
        coords[i] *= 2.0
    return m.group(1) + ', '.join(f"{x:g}" for x in coords) + m.group(3)

def g_mana(m):
    return m.group(1) + '-112.4508' + m.group(3)

def g_spawner(m):
    return m.group(1) + '-184.4505' + m.group(3)

if __name__ == '__main__':
    update_main_tscn()
