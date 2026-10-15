"""Lista los apoyos de un paso de clean.json con su posición respecto al otro
pie en el marco del cuerpo (para ajustar las reglas de los cuadros).

  python tool/anim3d/debug_steps.py <accion>
"""

import json
import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))


def segments(c):
    T, out, st = len(c), [], None
    for t in range(T):
        if c[t] and st is None:
            st = t
        if not c[t] and st is not None:
            out.append(list(range(st, t)))
            st = None
    if st is not None:
        if out and out[0][0] == 0:
            out[0] = list(range(st, T)) + out[0]
        else:
            out.append(list(range(st, T)))
    return out


def hang(a, b):
    return math.degrees(math.atan2(a[0] * b[1] - a[1] * b[0],
                                   a[0] * b[0] + a[1] * b[1]))


def rot(v, deg):
    a = math.radians(deg)
    return np.array([math.cos(a) * v[0] - math.sin(a) * v[1],
                     math.sin(a) * v[0] + math.cos(a) * v[1]])


def main():
    d = json.load(open(os.path.join(HERE, "clean.json")))[sys.argv[1]]
    J = np.array(d["joints"])
    P = len(J)
    lp, ls = J[:, 23, :2] - J[:, 24, :2], J[:, 11, :2] - J[:, 12, :2]
    bias = np.median([hang(ls[t], lp[t]) for t in range(P)])

    def fwd(t):
        lat = rot(lp[t], -bias) / np.linalg.norm(lp[t]) + \
            ls[t] / np.linalg.norm(ls[t])
        lat /= np.linalg.norm(lat)
        return np.array([lat[1], -lat[0]])

    mids = {s: (J[:, he, :2] + J[:, to, :2]) / 2
            for s, he, to in (("L", 29, 31), ("R", 30, 32))}
    cons = {s: np.array(d["contact_" + s], bool) for s in "LR"}
    last = {}
    for s in "LR":
        out = np.empty_like(mids[s])
        lv = mids[s][np.flatnonzero(cons[s])[-1]]
        for _ in range(2):
            for t in range(P):
                if cons[s][t]:
                    lv = mids[s][t]
                out[t] = lv
        last[s] = out
    for s, o in (("L", "R"), ("R", "L")):
        sg = segments(cons[s])
        for k, seg in enumerate(sg):
            pos = mids[s][seg].mean(0)
            prev = mids[s][sg[k - 1]].mean(0)
            other = last[o][seg[0]]
            f = fwd(seg[0])
            left = np.array([-f[1], f[0]])
            v = pos - other
            print(f"{s} t{seg[0]:>3} len{len(seg):>3} movido "
                  f"{np.linalg.norm(pos - prev):.2f} aleja "
                  f"{np.linalg.norm(v) - np.linalg.norm(prev - other):+.2f} "
                  f"lado {v @ left:+.2f} adelante {v @ f:+.2f} "
                  f"lado_centro {pos @ left:+.2f}")


if __name__ == "__main__":
    main()
