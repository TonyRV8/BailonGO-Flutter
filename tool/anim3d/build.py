"""Pipeline completo de la animación 3D de los pasos ideales.

  python tool/anim3d/build.py [--extract]

1. (--extract o si falta world.json) landmarks 3D de BailonGObailes/Buenos con
   el modelo heavy → tool/anim3d/world.json
2. limpieza, apoyos de los pies y bucle → tool/anim3d/clean.json
3. Blender headless: retarget + piso de 4 cuadros →
   assets/models/DanceGrid1.glb (maniquí) y assets/models/<Nombre>.glb por
   cada personaje de Mixamo en tool/anim3d/personajes/<Nombre>.fbx

Blender se busca en $BLENDER_EXE, en "D:/Program Files" o en "C:/Program Files".
"""

import glob
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
# Blender: $BLENDER_EXE, la instalación del equipo (D:) o la estándar en C:.
BLENDER_CANDIDATES = [
    r"D:\Program Files\Blender Foundation\Blender 5.2\blender.exe",
    r"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe",
]


def find_blender():
    if os.environ.get("BLENDER_EXE"):
        return os.environ["BLENDER_EXE"]
    for c in BLENDER_CANDIDATES:
        if os.path.exists(c):
            return c
    return "blender"  # en el PATH


BLENDER = find_blender()


def run(cmd):
    print("$", " ".join(cmd), flush=True)
    subprocess.run(cmd, cwd=ROOT, check=True)


def main():
    world = os.path.join(HERE, "world.json")
    clean = os.path.join(HERE, "clean.json")
    if "--extract" in sys.argv or not os.path.exists(world):
        videos = sorted(glob.glob(os.path.join(ROOT, "BailonGObailes",
                                               "Buenos", "*.mp4")))
        run([sys.executable, os.path.join(HERE, "extract_world.py"), world,
             *videos])
    run([sys.executable, os.path.join(HERE, "process.py"), world, clean])
    base = os.path.join(HERE, "base_DanceGrid1.glb")
    models = os.path.join(ROOT, "assets", "models")
    # Maniquí (escena base) y un GLB por personaje de Mixamo en personajes/.
    jobs = [(os.path.join(models, "DanceGrid1.glb"), "")]
    for fbx in sorted(glob.glob(os.path.join(HERE, "personajes", "*.fbx"))):
        name = os.path.splitext(os.path.basename(fbx))[0]
        jobs.append((os.path.join(models, name + ".glb"), fbx))
    for out, fbx in jobs:
        run([BLENDER, "-b", "--factory-startup", "--python-exit-code", "1",
             "-P", os.path.join(HERE, "build_glb.py"), "--",
             base, clean, out, "2", fbx])


if __name__ == "__main__":
    main()
