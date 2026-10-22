"""Genera `tool/labels.json`: la nota humana de cada toma de BailesREVISADOS.

La nota es la del revisor en escala 1-10; aquí se guarda ya en porcentaje
(nota x 10) junto con la tolerancia que usa el banco (`tool/bench_real.dart`)
para dar una toma por buena.

De dónde sale cada nota:
  * Nombre      cuando el archivo trae la nota en el nombre se usa esa, que
                es la fuente más directa. Dos formatos:
                  Abdiel_<Paso>_<nota>[_<notas>]       (tanda de Abdiel)
                  Avril<n>_<Paso>[_<desfase>]_calif<nota>[_arg<motivo>]
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

# Medio punto de cortesía a las tomas de Avril (2026-10-13, decisión del
# usuario). Son las mejores ejecuciones que se pudieron grabar y, al no haber
# material de 9 o 10, hacen de techo del corpus: si se las deja en su nota
# nominal, el ajuste no tiene ningún motivo para dejar alcanzable el
# sobresaliente. Es un ajuste DECLARADO de la escala, no una nota del revisor,
# y por eso queda escrito en el campo `src` de cada entrada.
AVRIL_BONO = 5

# Diez puntos de cortesía a TODAS las tomas de alumno (2026-10-21, decisión
# del usuario tras probar la app). Probando los pasos en el teléfono, las
# notas salían más duras que el juicio de quien baila: una ejecución decente
# se sentía 15 puntos por debajo de lo que merecía. Como el ajuste solo sabe
# de las etiquetas, subirlas es la forma declarada de mover la escala entera
# sin tocar el algoritmo. Se suma DESPUÉS del bono de Avril y queda escrito en
# el campo `src`. No aplica a los bailes ajenos ni a la tanda de 10 de la
# profesora, que son los dos extremos que sostienen la escala.
ALUMNO_BONO = 10

TOL_BANDA = 10    # "3-5" -> 40 +- 10
BANDA = 40

# La tanda de 10 de la profesora: `Profa_<Paso>_calif10.mp4`, movida a las
# carpetas de cada paso el 2026-10-21. Tolerancia más estrecha porque es el
# ancla del extremo alto.
TOL_PROFA = 5


def name_score(fname):
    """Nota embebida en el nombre del archivo.

    Devuelve (nota, encontrada). `encontrada` distingue "no trae nota" de
    "trae NADA", que significa que no ejecutó el paso.

    El marcador `calif<n>` vale para cualquier toma. La nota en la tercera
    posición del nombre SÓLO se lee en la tanda de Abdiel, que es la que usa
    ese formato: en los demás, ese hueco describe la toma y suele empezar por
    un número de segundos ("notermina_9seg", "muycorto_6pordebajo"), que no es
    una calificación.
    """
    base = os.path.splitext(fname)[0]
    m = re.search(r"calif(\d+)", base, re.I)
    if m:
        return int(m.group(1)), True
    if not base.lower().startswith(("abdiel", "adbiel")):
        return None, False
    parts = base.split("_")
    raw = parts[2] if len(parts) > 2 else ""
    if raw.upper().startswith("NADA"):
        return None, True
    m = re.match(r"(\d+)", raw)
    return (int(m.group(1)), True) if m else (None, False)


def name_reason(fname):
    """Motivo de la nota, cuando el nombre lo trae tras `arg`."""
    m = re.search(r"_arg(.+)$", os.path.splitext(fname)[0], re.I)
    return m.group(1) if m else None


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
            n, found = name_score(f)
            if found:
                if n is None:
                    labels[key] = {"score": 10, "tol": 10,
                                   "src": "SUPUESTO: 'NADA' = no ejecutó el "
                                          "paso (sin bono de escala)"}
                else:
                    src = f"revisor {n}/10 (nombre del archivo)"
                    reason = name_reason(f)
                    if reason:
                        src += f" — {reason}"
                    score = n * 10
                    if low.startswith("profa"):
                        labels[key] = {
                            "score": score, "tol": TOL_PROFA,
                            "src": f"{src} — tanda de 10 de la profesora "
                                   f"(ancla del extremo alto)"}
                        continue
                    if low.startswith("avril"):
                        score += AVRIL_BONO
                        src += f" +{AVRIL_BONO} de cortesía (techo del corpus)"
                    score += ALUMNO_BONO
                    src += f" +{ALUMNO_BONO} de escala (2026-10-21)"
                    labels[key] = {"score": min(score, 100), "tol": TOL_NOTA,
                                   "src": src}
            elif key in AVRIL:
                labels[key] = {
                    "score": min(AVRIL[key] * 10 + AVRIL_BONO + ALUMNO_BONO, 100),
                    "tol": TOL_NOTA,
                    "src": f"revisor {AVRIL[key]}/10 "
                           f"+{AVRIL_BONO} de cortesía (techo del corpus) "
                           f"+{ALUMNO_BONO} de escala (2026-10-21)",
                }
            elif low.startswith("avril"):
                labels[key] = {"score": None, "tol": 0,
                               "src": "sin etiqueta: el revisor solo puntuó otra toma suya"}
            elif f in gabo_scored:
                n = gabo_scored[f]
                labels[key] = {
                    "score": min(n * 10 + ALUMNO_BONO, 100), "tol": TOL_NOTA,
                    "src": f"revisor {n}/10 (lista por paso) "
                           f"+{ALUMNO_BONO} de escala (2026-10-21)"}
            elif low.startswith("gabo") and gabo_low:
                labels[key] = {"score": None, "tol": 0,
                               "src": "sin etiqueta: su mejor toma del paso es < 3/10"}
            else:
                labels[key] = {
                    "score": BANDA + ALUMNO_BONO, "tol": TOL_BANDA,
                    "src": "banda 3-5/10 (Toto, Primo y sobrantes de Gabo) "
                           f"+{ALUMNO_BONO} de escala (2026-10-21)"}

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
