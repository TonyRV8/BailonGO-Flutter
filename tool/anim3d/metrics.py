"""Mide la calidad de las animaciones de un GLB (pies) y vuelca trayectorias.

  blender -b -P tool/anim3d/metrics.py -- <glb> <salida.json>

Por animación, muestreando a 30 fps:
  - salto_max: mayor desplazamiento de un tobillo entre fotogramas (m). Un
    "teletransporte" se ve como un pico aquí.
  - acel_p95: percentil 95 de la aceleración del tobillo (tirones).
  - patina: velocidad horizontal mediana (m/s) del tobillo en el 40 % de
    fotogramas en que está más bajo (cuando debería estar apoyado).
  - cruces: fotogramas en que los tobillos quedan a < 8 cm en horizontal.
  - bajo_piso: vértice más bajo de la malla del maniquí (m, negativo =
    atraviesa el piso).
"""

import json
import sys

import bpy
import numpy as np

argv = sys.argv[sys.argv.index("--") + 1:]
glb, out = argv[0], argv[1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb)
scene = bpy.context.scene
arm = next(o for o in scene.objects if o.type == "ARMATURE")
ad = arm.animation_data
names = sorted({tr.name for tr in ad.nla_tracks})
for tr in ad.nla_tracks:
    tr.mute = True
fps_imp = scene.render.fps / scene.render.fps_base
# Hueso del pie: maniquí ("Foot.L") o Mixamo ("mixamorig:LeftFoot").
FOOT = {s: next(b.name for b in arm.data.bones
                if b.name == f"Foot.{s}" or
                b.name.endswith(("LeftFoot" if s == "L" else "RightFoot")))
        for s in ("L", "R")}

res = {}
for name in names:
    act = bpy.data.actions[name]
    ad.action = act
    f0, f1 = act.frame_range
    dur = (f1 - f0) / fps_imp
    n = int(round(dur * 30))
    tr = {"L": [], "R": []}
    lowest = 1e9
    mani = max((o for o in arm.children if o.type == "MESH"),
               key=lambda o: len(o.data.vertices))
    for i in range(n + 1):
        scene.frame_set(int(f0), subframe=0.0)
        f = f0 + i * (f1 - f0) / n
        scene.frame_set(int(f), subframe=f - int(f))
        for s in ("L", "R"):
            pb = arm.pose.bones[FOOT[s]]
            tr[s].append(list(arm.matrix_world @ pb.head))
        if i % 3 == 0:
            dg = bpy.context.evaluated_depsgraph_get()
            ev = mani.evaluated_get(dg)
            co = np.empty(len(ev.data.vertices) * 3)
            ev.data.vertices.foreach_get("co", co)
            mw = np.array(ev.matrix_world)
            z = co.reshape(-1, 3) @ mw[2, :3] + mw[2, 3]
            lowest = min(lowest, float(z.min()))
    A = {s: np.array(tr[s]) for s in tr}
    m = {}
    jumps = [np.linalg.norm(np.diff(A[s], axis=0), axis=1) for s in "LR"]
    m["salto_max"] = float(max(j.max() for j in jumps))
    acc = [np.linalg.norm(np.diff(A[s], 2, axis=0), axis=1) * 900 for s in "LR"]
    m["acel_p95"] = float(np.percentile(np.concatenate(acc), 95))
    slide = []
    for s in "LR":
        z = A[s][:-1, 2]
        low = z <= np.percentile(z, 40)
        v = np.linalg.norm(np.diff(A[s][:, :2], axis=0), axis=1) * 30
        slide.append(v[low])
    m["patina"] = float(np.median(np.concatenate(slide)))
    dxy = np.linalg.norm(A["L"][:, :2] - A["R"][:, :2], axis=1)
    m["cruces"] = int((dxy < 0.08).sum())
    m["bajo_piso"] = lowest
    m["dur"] = round(dur, 2)
    res[name] = {"m": m, "tray": {s: tr[s] for s in tr}}
    print(f"MET {name:<14} " + " ".join(
        f"{k}={v:.3f}" if isinstance(v, float) else f"{k}={v}"
        for k, v in m.items()))
with open(out, "w") as f:
    json.dump(res, f)
