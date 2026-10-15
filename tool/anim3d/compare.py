"""Compara una animación del GLB con el video ideal, fotograma a fotograma.

  python tool/anim3d/compare.py <glb> <accion> <salida.png> [n] [front|feet]
                                [desde-hasta]   (fotogramas del bucle)

Arriba el video original, abajo el maniquí visto de frente en el mismo
instante (usa `source` de clean.json para saber qué tramo del video es el
bucle). Sirve para revisar a ojo si la animación copia bien el paso.
"""

import json
import os
import subprocess
import sys
import tempfile

import cv2
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
from build import BLENDER  # noqa: E402

RENDER = r'''
import bpy, sys, math
from mathutils import Vector
a = sys.argv[sys.argv.index("--") + 1:]
glb, action, out_dir, frames = a[0], a[1], a[2], [int(x) for x in a[3].split(",")]
P = int(a[4])
view = a[5]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb)
sc = bpy.context.scene
arm = next(o for o in sc.objects if o.type == "ARMATURE")
for ob in sc.objects:
    ad = ob.animation_data
    if not ad:
        continue
    for tr in ad.nla_tracks:
        tr.mute = tr.name != action
    if ob == arm:
        for tr in ad.nla_tracks:
            tr.mute = True
        ad.action = bpy.data.actions[action]
f0, f1 = bpy.data.actions[action].frame_range
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
sc.collection.objects.link(cam)
sc.camera = cam
if view == "feet":   # pies de cerca, 3/4 de perfil
    cam.location = Vector((1.6, -1.6, 0.45))
    target = Vector((0, 0, 0.12))
    cam.data.lens = 55
else:
    cam.location = Vector((0, -4.2, 1.15))
    target = Vector((0, 0, 0.55))
    cam.data.lens = 50
cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
sc.render.engine = "BLENDER_WORKBENCH"
sc.display.shading.light = "STUDIO"
sc.display.shading.color_type = "MATERIAL"
sc.render.resolution_x, sc.render.resolution_y = 240, 300
for i, t in enumerate(frames):
    f = f0 + (f1 - f0) * t / P
    sc.frame_set(int(f), subframe=f - int(f))
    sc.render.filepath = f"{out_dir}/r{i:02d}.png"
    bpy.ops.render.render(write_still=True)
'''


def main():
    glb, action, out = sys.argv[1], sys.argv[2], sys.argv[3]
    n = int(sys.argv[4]) if len(sys.argv) > 4 else 10
    view = sys.argv[5] if len(sys.argv) > 5 else "front"
    clean = json.load(open(os.path.join(HERE, "clean.json"), encoding="utf-8"))
    src = clean[action]["source"]
    P = clean[action]["frames"]
    a, b = 0, P
    if len(sys.argv) > 6:
        a, b = map(int, sys.argv[6].split("-"))
    ts = [a + round(i * (b - a) / n) for i in range(n)]
    tmp = tempfile.mkdtemp()
    script = os.path.join(tmp, "r.py")
    open(script, "w").write(RENDER)
    subprocess.run([BLENDER, "-b", "--factory-startup", "-P", script, "--",
                    os.path.abspath(glb), action, tmp,
                    ",".join(map(str, ts)), str(P), view],
                   capture_output=True, check=True)
    cap = cv2.VideoCapture(os.path.join(ROOT, "BailonGObailes", "Buenos",
                                        src["video"] + ".mp4"))
    vids = []
    for t in ts:
        vf = src["start"] + (t + src.get("shift", 0)) % P
        cap.set(cv2.CAP_PROP_POS_FRAMES, vf)
        ok, img = cap.read()
        img = cv2.resize(img, (240, 427))[60:360]
        cv2.putText(img, f"t{t} v{vf}", (4, 16), 0, 0.5, (0, 255, 255), 1)
        vids.append(img)
    rends = [cv2.imread(os.path.join(tmp, f"r{i:02d}.png")) for i in range(n)]
    sheet = np.vstack([np.hstack(vids), np.hstack(rends)])
    cv2.imwrite(out, sheet)
    print("OK", out)


if __name__ == "__main__":
    main()
