"""Extrae los 33 landmarks BlazePose de un video, replicando EXACTAMENTE el
muestreo que hace la app en Android (`MainActivity.processVideo`).

Por qué existe: la extracción en el teléfono tarda minutos por video. Para
calibrar hace falta iterar muchas veces, así que se replica el pipeline en PC
usando el MISMO fichero de modelo (`pose_landmarker_lite.task`) y los mismos
umbrales de confianza. La salida alimenta a `tool/calibrate.dart`, que corre el
`FeatureExtractor` y el `DtwComparator` de producción sin reimplementarlos.

Equivalencia con Android (MainActivity.kt:211):
  - intervalo de muestreo 33 ms, ts arranca en 0 y avanza mientras ts < duracion
  - OPTION_CLOSEST  -> se toma el fotograma más cercano a ese instante
  - RunningMode.VIDEO, numPoses=1, deteccion/presencia/tracking = 0.5
  - se descartan los instantes sin pose detectada
  - coordenadas normalizadas [0,1] + visibility, en orden BlazePose

Uso:
  python tool/extract_landmarks.py <salida.json> <video> [video ...]
"""

import json
import os
import sys

import cv2
import mediapipe as mp
from mediapipe.tasks import python as mp_python
from mediapipe.tasks.python import vision

INTERVAL_MS = 33  # idéntico a MainActivity.processVideo
MODEL = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "android", "app", "src", "main", "assets", "pose_landmarker_lite.task",
)


def make_landmarker():
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


def sample_indices(n_frames, fps):
    """Instantes que visitaría Android y el fotograma que le corresponde a cada
    uno. Devuelve [(ts_ms, frame_index)], con frame_index no decreciente."""
    duration_ms = n_frames * 1000.0 / fps
    out = []
    ts = 0
    while ts < duration_ms:
        idx = min(int(round(ts * fps / 1000.0)), n_frames - 1)
        out.append((ts, idx))
        ts += INTERVAL_MS
    return out


def extract(path, landmarker):
    cap = cv2.VideoCapture(path)
    if not cap.isOpened():
        raise RuntimeError("no se pudo abrir " + path)
    fps = cap.get(cv2.CAP_PROP_FPS)
    n_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    targets = sample_indices(n_frames, fps)

    frames = []
    cur = -1
    img = None
    dropped = 0
    for ts_ms, idx in targets:
        # Los índices no decrecen: se avanza en streaming en vez de hacer seek
        # (el seek por milisegundos en OpenCV no es fiable).
        while cur < idx:
            ok, bgr = cap.read()
            if not ok:
                break
            cur += 1
            img = bgr
        if img is None:
            continue
        rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
        res = landmarker.detect_for_video(
            mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb), ts_ms
        )
        if not res.pose_landmarks:
            dropped += 1
            continue
        flat = []
        for lm in res.pose_landmarks[0]:
            flat.extend([lm.x, lm.y, lm.z, lm.visibility])
        frames.append(flat)
    cap.release()
    return {
        "fps": fps,
        "sourceFrames": n_frames,
        "sampled": len(targets),
        "noPose": dropped,
        "frames": frames,
    }


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 1
    out_path, videos = sys.argv[1], sys.argv[2:]
    result = {}
    for v in videos:
        key = os.path.splitext(os.path.basename(v))[0]
        # Un landmarker NUEVO por video: en RunningMode.VIDEO los timestamps
        # deben crecer de forma monótona y cada video arranca en 0. Android
        # hace lo mismo (crea el PoseLandmarker dentro de processVideo).
        landmarker = make_landmarker()
        try:
            data = extract(v, landmarker)
        finally:
            landmarker.close()
        result[key] = data
        print(
            f"{key:<34} muestreados {data['sampled']:>4} "
            f"| con pose {len(data['frames']):>4} "
            f"| sin pose {data['noPose']:>3}",
            flush=True,
        )
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(result, f)
    print(f"\nescrito {out_path} ({os.path.getsize(out_path)/1e6:.1f} MB)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
