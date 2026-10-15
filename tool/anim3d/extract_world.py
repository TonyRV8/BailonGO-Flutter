"""Extrae landmarks 3D (world) + 2D (imagen) de los videos ideales para animar
el maniquí del visor 3D.

A diferencia de `tool/extract_landmarks.py` (que replica el muestreo de la app
con el modelo lite), aquí se busca calidad: modelo HEAVY, TODOS los fotogramas
y las coordenadas `pose_world_landmarks` (metros, origen en la cadera), que son
las que dan profundidad real a la animación.

Uso:
  python tool/anim3d/extract_world.py <salida.json> <video> [video ...]
"""

import json
import os
import sys

import cv2
import mediapipe as mp
from mediapipe.tasks import python as mp_python
from mediapipe.tasks.python import vision

MODEL = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                     "pose_landmarker_heavy.task")
MODEL_URL = ("https://storage.googleapis.com/mediapipe-models/pose_landmarker/"
             "pose_landmarker_heavy/float16/latest/pose_landmarker_heavy.task")


def make_landmarker():
    if not os.path.exists(MODEL):  # 30 MB, no va en el repo
        import urllib.request
        print("descargando", MODEL_URL, flush=True)
        urllib.request.urlretrieve(MODEL_URL, MODEL)
    return vision.PoseLandmarker.create_from_options(
        vision.PoseLandmarkerOptions(
            base_options=mp_python.BaseOptions(model_asset_path=MODEL),
            running_mode=vision.RunningMode.VIDEO,
            num_poses=1,
            min_pose_detection_confidence=0.5,
            min_pose_presence_confidence=0.5,
            min_tracking_confidence=0.5,
        )
    )


def extract(path):
    cap = cv2.VideoCapture(path)
    fps = cap.get(cv2.CAP_PROP_FPS)
    w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    lm = make_landmarker()
    world, image = [], []
    i = 0
    while True:
        ok, bgr = cap.read()
        if not ok:
            break
        ts = int(round(i * 1000.0 / fps))
        res = lm.detect_for_video(
            mp.Image(image_format=mp.ImageFormat.SRGB,
                     data=cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)), ts)
        if res.pose_world_landmarks:
            world.append([[round(p.x, 5), round(p.y, 5), round(p.z, 5),
                           round(p.visibility, 3)]
                          for p in res.pose_world_landmarks[0]])
            image.append([[round(p.x, 5), round(p.y, 5), round(p.z, 5)]
                          for p in res.pose_landmarks[0]])
        else:  # se conserva el hueco para no romper el tiempo
            world.append(None)
            image.append(None)
        i += 1
    cap.release()
    lm.close()
    return {"fps": fps, "width": w, "height": h, "world": world,
            "image": image}


def main():
    out, videos = sys.argv[1], sys.argv[2:]
    result = {}
    for v in videos:
        key = os.path.splitext(os.path.basename(v))[0]
        d = extract(v)
        miss = sum(1 for f in d["world"] if f is None)
        print(f"{key:<26} frames {len(d['world']):>4} sin pose {miss}",
              flush=True)
        result[key] = d
    with open(out, "w", encoding="utf-8") as f:
        json.dump(result, f)


if __name__ == "__main__":
    sys.exit(main())
