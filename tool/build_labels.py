"""Genera `tool/labels.json`: la nota humana de cada toma de BailesREVISADOS.

La nota es la del revisor en escala 1-10; aquí se guarda ya en porcentaje
(nota x 10) junto con la tolerancia que usa el banco (`tool/bench_real.dart`)
para dar una toma por buena.

De dónde sale cada nota:
  * Abdiel      del propio nombre del archivo: Abdiel_<Paso>_<nota>[_notas].
                "NADA" = no ejecutó el paso (SUPUESTO: nota muy baja).
  * Gabo        lista dada por el usuario el 2026-10-05, por paso. Cuando un
                paso tiene varias tomas suyas, la nota va a la que lleva "bien"
                en el nombre y, si hay empate o ninguna lo lleva, a la que mejor
                puntuó el motor en la corrida anterior (`previo`, abajo).
  * Avril       Avril_SItermina_bien (Suzy Q) y Avril_2porencima_bien
                (Cumbia Step): 8. Sus otras tomas quedan SIN ETIQUETA.
  * Resto       "los otros videos de Toto y primo y los sobrantes de gabo van
                de 3-5" -> 40 % con tolerancia 10 (banda 30-50).
                Excepción: en los pasos donde la nota de Gabo es menor que 3
                (Cumbia Step y Right Spot Turn, ambos 2), sus sobrantes quedan
                SIN ETIQUETA en vez de 3-5: no tendría sentido que superen a la
                mejor toma del mismo bailarín.
  * randoms     bailes ajenos al catálogo: 8 % con tolerancia 8.

Sin etiqueta (`"score": null`) significa que la toma se evalúa y se imprime
pero NO cuenta en la pérdida de la calibración.

Uso:
  python tool/build_labels.py          # regenera tool/labels.json
El archivo resultante se puede editar a mano: el banco lo lee tal cual.
"""

import json
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REVISADOS = os.path.join(ROOT, "BailonGObailes", "BailesREVISADOS")
OUT = os.path.join(ROOT, "tool", "labels.json")

# Nota del usuario (escala 1-10) por paso y bailarín. Varias notas en un paso
# = varias tomas de ese bailarín, de mejor a peor.
GABO = {
    "Basico": [5],
    "CubanBreak": [4, 3],
    "Cucaracha": [6, 4],
    "CumbiaStep": [2],
    "GiroPuntaTalon": [4],
    "Guapeo": [3],
    "KickFlick": [5],
    "RightSpotTurn": [2],
    "SuzyQ": [],  # el usuario no puntuó las de Gabo en Suzy Q
}
AVRIL = {
    "SuzyQ/Avril_SItermina_bien": 8,
    "CumbiaStep/Avril_2porencima_bien": 8,
}

# Nota que dio el motor en la corrida anterior (§7-sexies). Solo se usa para
# decidir a qué toma de Gabo le corresponde cada nota cuando hay varias.
PREVIO = {
    "CubanBreak/Gabo_2porencima_bien": 61,
    "CubanBreak/Gabo_bien": 51,
    "CubanBreak/Gabo_maso_sitermina": 32,
    "Cucaracha/Gabo_SalePocoDeLaToma": 57,
    "Cucaracha/Gabo_SalePoquitoDeLaToma": 36,
    "CumbiaStep/Gabo_seconfunde_termina": 50,
    "CumbiaStep/Gabo_2porencima_termina": 47,
    "GiroPuntaTalon/Gabo_muylargo_6demas_muyaladerecha": 51,
    "GiroPuntaTalon/Gabo_bien": 43,
    "GiroPuntaTalon/Gabo_muycorto_6pordebajo": 26,
    "KickFlick/Gabo_bien": 59,
    "KickFlick/Gabo_bien_largo": 54,
    "KickFlick/Gabo_largo_fondopersonas": 37,
    "RightSpotTurn/Gabo_bien": 50,
    "RightSpotTurn/Gabo_Noterminaestatico": 50,
    "RightSpotTurn/Gabo_AlfinlaSeEquivoca_seestaAdaptando": 44,
    "Guapeo/Gabo_bien": 42,
    "Basico/Gabo_7pordebajo": 33,
    "SuzyQ/Gabo_persona de fondo_termina": 63,
    "SuzyQ/Gabo_termina": 57,
    "SuzyQ/Gabo_notermina_9seg": 48,
}

TOL_NOTA = 7      # nota explícita del revisor: media nota arriba y abajo
TOL_BANDA = 10    # "3-5" -> 40 +- 10
BANDA = 40


def abdiel_score(fname):
    """Nota embebida en el nombre: Abdiel_<Paso>_<nota>_<lo que sea>."""
    parts = os.path.splitext(fname)[0].split("_")
    raw = parts[2] if len(parts) > 2 else ""
    if raw.upper().startswith("NADA"):
        return None
    m = re.match(r"(\d+)", raw)
    return int(m.group(1)) if m else None


def main():
    labels = {}
    for folder in sorted(os.listdir(REVISADOS)):
        d = os.path.join(REVISADOS, folder)
        if not os.path.isdir(d):
            continue
        files = sorted(f for f in os.listdir(d) if f.lower().endswith(".mp4"))
        if folder == "randoms":
            for f in files:
                labels[f"{folder}/{os.path.splitext(f)[0]}"] = {
                    "score": 8, "tol": 8, "src": "baile ajeno al catálogo"}
            continue

        gabo_pending = list(GABO.get(folder, []))
        # Orden de preferencia para repartir las notas de Gabo: primero las
        # tomas con "bien" en el nombre, y dentro de cada grupo, de mejor a
        # peor según lo que puntuó el motor antes.
        gabo_files = [f for f in files if f.lower().startswith("gabo")]
        gabo_files.sort(key=lambda f: (
            "bien" not in f.lower(),
            -PREVIO.get(f"{folder}/{os.path.splitext(f)[0]}", 0),
        ))
        gabo_scored = dict(zip(gabo_files, gabo_pending))
        # Si la mejor toma de Gabo no llega a 3, sus sobrantes no se etiquetan.
        gabo_low = bool(gabo_pending) and max(gabo_pending) < 3

        for f in files:
            key = f"{folder}/{os.path.splitext(f)[0]}"
            low = f.lower()
            if low.startswith(("abdiel", "adbiel")):
                n = abdiel_score(f)
                if n is None:
                    labels[key] = {"score": 10, "tol": 10,
                                   "src": "SUPUESTO: 'NADA' = no ejecutó el paso"}
                else:
                    labels[key] = {"score": n * 10, "tol": TOL_NOTA,
                                   "src": f"revisor {n}/10 (nombre del archivo)"}
            elif key in AVRIL:
                labels[key] = {"score": AVRIL[key] * 10, "tol": TOL_NOTA,
                               "src": f"revisor {AVRIL[key]}/10"}
            elif low.startswith("avril"):
                labels[key] = {"score": None, "tol": 0,
                               "src": "sin etiqueta: el revisor solo puntuó otra toma suya"}
            elif f in gabo_scored:
                n = gabo_scored[f]
                labels[key] = {"score": n * 10, "tol": TOL_NOTA,
                               "src": f"revisor {n}/10 (lista por paso)"}
            elif low.startswith("gabo") and gabo_low:
                labels[key] = {"score": None, "tol": 0,
                               "src": "sin etiqueta: su mejor toma del paso es < 3/10"}
            else:
                labels[key] = {"score": BANDA, "tol": TOL_BANDA,
                               "src": "banda 3-5/10 (Toto, Primo y sobrantes de Gabo)"}

    with open(OUT, "w", encoding="utf-8") as fh:
        json.dump(labels, fh, ensure_ascii=False, indent=1, sort_keys=True)

    con = sum(1 for v in labels.values() if v["score"] is not None)
    print(f"{OUT}: {len(labels)} tomas, {con} con etiqueta, "
          f"{len(labels) - con} sin etiqueta")
    for k in sorted(labels):
        v = labels[k]
        s = "  -" if v["score"] is None else f"{v['score']:3d}"
        print(f"  {k:<58} {s}  {v['src']}")


if __name__ == "__main__":
    main()
