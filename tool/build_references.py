"""Empaqueta la referencia de cada paso como asset: los landmarks de la toma
ideal, ya muestreados cada 33 ms, en `assets/references/<pasoId>.json`.

Por qué como asset y no solo en Firestore (`reference_data`):
  - Lo que hay en Firestore son FEATURES ya calculadas. Cualquier cambio en el
    extractor (cadera, corrección de aspecto...) las deja obsoletas en silencio
    y obliga a re-extraer los 9 videos en el teléfono (15-30 min).
  - Guardando LANDMARKS, la app calcula las features al cargar con el
    extractor vigente: nunca hay desajuste entre referencia y captura.
  - Funciona sin red desde la primera ejecución y carga en milisegundos.

Solo se guardan los 16 landmarks que usa `FeatureExtractor` (hombros, codos,
muñecas, caderas, rodillas, tobillos, talones y puntas), cuantizados:
x, y en diezmilésimas y visibilidad en centésimas. ~150 KB por paso.

Uso:
  python tool/extract_landmarks.py tool/landmarks.json assets/videos/*.mp4 ...
  python tool/build_references.py tool/landmarks.json
"""

import json
import os
import sys

STEPS = [
    "basico_adelante_atras", "basico_guapeo", "cucaracha", "suzy_q",
    "right_spot_turn", "cumbia_step", "cuban_break", "giro_punta_talon",
    "kick_flick",
]
INDICES = [11, 12, 13, 14, 15, 16, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32]
FORMAT_VERSION = 1


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    src = json.load(open(sys.argv[1], encoding="utf-8"))
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out_dir = os.path.join(root, "assets", "references")
    os.makedirs(out_dir, exist_ok=True)
    for step in STEPS:
        take = src.get(step)
        if take is None:
            print(f"!! falta {step} en {sys.argv[1]}")
            continue
        # Las tomas son 720x1280 (verificado con ffprobe); si el JSON trae la
        # geometría del video, manda esa.
        width = take.get("width", 720)
        height = take.get("height", 1280)
        frames = []
        for flat in take["frames"]:
            row = []
            for i in INDICES:
                row.append(round(flat[i * 4] * 10000))
                row.append(round(flat[i * 4 + 1] * 10000))
                row.append(round(flat[i * 4 + 3] * 100))
            frames.append(row)
        doc = {
            "format": FORMAT_VERSION,
            "pasoId": step,
            "aspect": height / width,
            "stepMs": 33,
            "indices": INDICES,
            "frames": frames,
        }
        path = os.path.join(out_dir, step + ".json")
        with open(path, "w", encoding="utf-8") as f:
            json.dump(doc, f, separators=(",", ":"))
        print(f"{step:<24} {len(frames):>4} fotogramas  "
              f"{os.path.getsize(path) / 1024:6.0f} KB")
    return 0


if __name__ == "__main__":
    sys.exit(main())
