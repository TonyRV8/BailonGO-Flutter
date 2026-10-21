"""Renderiza una tira de fotogramas de una animación del GLB (para revisar).

blender -b -P tool/anim3d/preview.py -- <glb> <accion> <salida.png> [n] [vista]
vista: front | side | top | persp | close
"""

import math
import os
import sys
import tempfile

import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
glb, action_name, out = argv[0], argv[1], argv[2]
n = int(argv[3]) if len(argv) > 3 else 8
view = argv[4] if len(argv) > 4 else "persp"

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb)
scene = bpy.context.scene

arm = next(o for o in scene.objects if o.type == "ARMATURE")
act = bpy.data.actions[action_name]
# Se silencian las pistas NLA para que solo cuente la acción activa (y las de
# otros objetos con el mismo nombre de acción, p. ej. los cuadros del piso).
for ob in scene.objects:
    ad = ob.animation_data
    if not ad:
        continue
    for tr in ad.nla_tracks:
        tr.mute = tr.name != action_name and not any(
            s.action and s.action.name.startswith(action_name)
            for s in tr.strips)
        if tr.name == action_name:
            tr.mute = False
    # El importador deja activa la primera acción en todos los objetos y la
    # acción activa tapa las pistas NLA (se veía siempre el piso del básico).
    if ob != arm:
        ad.action = None
    if ob == arm:
        for tr in ad.nla_tracks:
            tr.mute = True
        ad.action = act
start, end = act.frame_range
scene.render.fps = 30

cam_data = bpy.data.cameras.new("cam")
cam = bpy.data.objects.new("cam", cam_data)
scene.collection.objects.link(cam)
scene.camera = cam
target = Vector((0, 0, 0.8))
if view == "front":
    cam.location = Vector((0, -6, 1.0))
elif view == "side":
    cam.location = Vector((6, 0, 1.0))
elif view == "top":
    cam.location = Vector((0, -0.01, 7))
    target = Vector((0, 0, 0))
elif view == "close":
    cam.location = Vector((1.3, -2.6, 1.9))
    target = Vector((0, 0, 0.55))
else:
    cam.location = Vector((3.2, -4.5, 2.6))
d = target - cam.location
cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
cam_data.lens = 40

scene.render.engine = "BLENDER_WORKBENCH"
scene.display.shading.light = "STUDIO"
scene.display.shading.color_type = "MATERIAL"
scene.render.resolution_x = 360
scene.render.resolution_y = 480
scene.render.film_transparent = False

tmp = tempfile.mkdtemp()
paths = []
for i in range(n):
    f = start + (end - start) * i / max(1, n - 1)
    scene.frame_set(int(round(f)))
    p = os.path.join(tmp, f"f{i:02d}.png")
    scene.render.filepath = p
    bpy.ops.render.render(write_still=True)
    paths.append(p)

# Une la tira en una sola imagen.
imgs = [bpy.data.images.load(p) for p in paths]
w, h = imgs[0].size
cols = min(n, 8)
rows = math.ceil(n / cols)
strip = bpy.data.images.new("strip", w * cols, h * rows)
px = [0.0] * (w * cols * h * rows * 4)
for k, im in enumerate(imgs):
    src = list(im.pixels)
    cx, cy = k % cols, rows - 1 - k // cols
    for y in range(h):
        row0 = ((cy * h + y) * w * cols + cx * w) * 4
        px[row0:row0 + w * 4] = src[y * w * 4:(y + 1) * w * 4]
strip.pixels = px
strip.filepath_raw = out
strip.file_format = "PNG"
strip.save()
print("OK", out, start, end)
