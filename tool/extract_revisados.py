"""Extrae landmarks de las tomas etiquetadas de BailonGObailes/BailesREVISADOS
(alumnos reales grabados con el teléfono) con el MISMO pipeline que
`extract_landmarks.py`. La clave de cada toma es `<Carpeta>/<archivo>` porque
hay nombres repetidos entre pasos (p.ej. Gabo_bien.mp4).

Uso:
  python tool/extract_revisados.py tool/landmarks_revisados.py
"""
import glob
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from extract_landmarks import extract, make_landmarker  # noqa: E402

ROOT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                    "BailonGObailes", "BailesREVISADOS")


def main():
    out_path = sys.argv[1] if len(sys.argv) > 1 else "tool/landmarks_revisados.json"
    result = {}
    if os.path.exists(out_path):
        result = json.load(open(out_path, encoding="utf-8"))
    videos = sorted(glob.glob(os.path.join(ROOT, "*", "*.mp4")))
    for v in videos:
        key = os.path.basename(os.path.dirname(v)) + "/" + os.path.splitext(os.path.basename(v))[0]
        if key in result:
            print(f"{key:<60} (ya extraído)", flush=True)
            continue
        lm = make_landmarker()
        try:
            data = extract(v, lm)
        finally:
            lm.close()
        result[key] = data
        print(f"{key:<60} muestreados {data['sampled']:>4} | con pose {len(data['frames']):>4} "
              f"| sin pose {data['noPose']:>3} | {data['width']}x{data['height']}", flush=True)
        with open(out_path, "w", encoding="utf-8") as f:
            json.dump(result, f)
    print(f"\nescrito {out_path} ({os.path.getsize(out_path)/1e6:.1f} MB)")


if __name__ == "__main__":
    main()
