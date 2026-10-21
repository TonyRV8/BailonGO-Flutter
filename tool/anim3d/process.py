"""Limpia los landmarks 3D de los videos ideales y produce trayectorias listas
para animar el maniquí (`tool/anim3d/clean.json`).

Problemas que corrige respecto a la animación original:
  - pies que "se teletransportan": MediaPipe a veces intercambia izquierda y
    derecha durante unos fotogramas; se detecta por continuidad y se deshace.
  - temblor: filtro de Hampel (picos) + paso bajo de fase cero.
  - pies que patinan / se cruzan: se detecta el apoyo de cada pie y, mientras
    está apoyado, su posición queda clavada en el piso. El desplazamiento de la
    cadera se reconstruye a partir de esos apoyos (mínimos cuadrados), así el
    cuerpo viaja sobre el pie que sostiene el peso como en la vida real.
  - bucle: se elige un ciclo del paso (8 tiempos) y se empalman los extremos
    para que la animación se repita sin salto.

Uso: python tool/anim3d/process.py world.json clean.json
Coordenadas de salida: las de Blender (Z arriba, el maniquí mira hacia -Y),
escaladas al tamaño del rig (cadera→tobillo = 0.84 m).
"""

import json
import sys

import numpy as np
from scipy import sparse
from scipy.signal import butter, filtfilt
from scipy.sparse.linalg import lsqr

# Índices BlazePose.
NOSE, EAR_L, EAR_R = 0, 7, 8
SH_L, SH_R, EL_L, EL_R, WR_L, WR_R = 11, 12, 13, 14, 15, 16
PK_L, PK_R, IX_L, IX_R, TH_L, TH_R = 17, 18, 19, 20, 21, 22
HIP_L, HIP_R, KN_L, KN_R, AN_L, AN_R = 23, 24, 25, 26, 27, 28
HE_L, HE_R, TO_L, TO_R = 29, 30, 31, 32
# Pares izquierda/derecha (para deshacer intercambios).
PAIRS = [(1, 4), (2, 5), (3, 6), (EAR_L, EAR_R), (9, 10), (SH_L, SH_R),
         (EL_L, EL_R), (WR_L, WR_R), (PK_L, PK_R), (IX_L, IX_R), (TH_L, TH_R),
         (HIP_L, HIP_R), (KN_L, KN_R), (AN_L, AN_R), (HE_L, HE_R),
         (TO_L, TO_R)]
LEG_PAIRS = [(KN_L, KN_R), (AN_L, AN_R), (HE_L, HE_R), (TO_L, TO_R)]
ARM_PAIRS = [(EL_L, EL_R), (WR_L, WR_R), (PK_L, PK_R), (IX_L, IX_R),
             (TH_L, TH_R)]

RIG_LEG = 0.84      # cadera→tobillo del rig (Thigh 0.42 + Shin 0.42)
RIG_ANKLE_H = 0.08  # altura del tobillo sobre el piso en el rig

# Nombre de la animación en el GLB y video del que sale.
STEPS = {
    "basico_3d": "basico_adelante_atras",
    "guapeo_3d": "basico_guapeo",
    "cucaracha_3d": "cucaracha",
    "suzyq_3d": "suzy_q",
    "vuelta_3d": "right_spot_turn",
    "cumbia_3d": "cumbia_step",
    "cuban_3d": "cuban_break",
    "toeheel_3d": "giro_punta_talon",
    "kickflick_3d": "kickflick",
}


# ---------------------------------------------------------------- utilidades
def fill_gaps(frames):
    """Lista con None → array (T, 33, k) interpolando los huecos."""
    idx = [i for i, f in enumerate(frames) if f is not None]
    arr = np.array([frames[i] for i in idx], dtype=float)
    t = np.arange(len(frames))
    out = np.empty((len(frames),) + arr.shape[1:])
    for j in range(arr.shape[1]):
        for k in range(arr.shape[2]):
            out[:, j, k] = np.interp(t, idx, arr[:, j, k])
    return out


def unswap(world, image):
    """Deshace intercambios izquierda/derecha por continuidad temporal.

    Para piernas y brazos por separado: si el fotograma t se parece más al
    anterior con los lados intercambiados, se intercambian."""
    w, im = world.copy(), image.copy()
    for pairs in (LEG_PAIRS, ARM_PAIRS):
        a = [p[0] for p in pairs]
        b = [p[1] for p in pairs]
        for t in range(1, len(w)):
            # Referencia: media de los 3 anteriores (ya corregidos).
            ref = w[max(0, t - 3):t, :, :3].mean(axis=0)
            keep = np.linalg.norm(w[t, a, :3] - ref[a], axis=1).sum() + \
                np.linalg.norm(w[t, b, :3] - ref[b], axis=1).sum()
            swap = np.linalg.norm(w[t, b, :3] - ref[a], axis=1).sum() + \
                np.linalg.norm(w[t, a, :3] - ref[b], axis=1).sum()
            if swap < 0.6 * keep:
                w[t, a + b] = w[t, b + a]
                im[t, a + b] = im[t, b + a]
    return w, im


def drop_flips(world, image, k=6, max_deg=90.0):
    """MediaPipe a veces "voltea" el cuerpo entero (confunde frente y espalda)
    durante 1-3 fotogramas. Se detecta por la orientación de cadera+hombros:
    si se aparta más de `max_deg` de la mediana de su vecindad, ese fotograma
    se descarta y se interpola con los buenos. Un giro real es gradual y no se
    marca."""
    lat = (world[:, SH_L, :3] - world[:, SH_R, :3]) + \
        (world[:, HIP_L, :3] - world[:, HIP_R, :3])
    yaw = np.unwrap(np.arctan2(lat[:, 2], lat[:, 0]))
    T = len(yaw)
    bad = np.zeros(T, bool)
    for t in range(T):
        win = yaw[max(0, t - k):t + k + 1]
        # Mediana circular aproximada: respecto al propio fotograma.
        d = np.angle(np.exp(1j * (win - yaw[t])))
        ref = yaw[t] + np.median(d)
        if abs(np.degrees(np.angle(np.exp(1j * (yaw[t] - ref))))) > max_deg:
            bad[t] = True
    good = np.flatnonzero(~bad)
    w, im = world.copy(), image.copy()
    for arr in (w, im):
        for j in range(arr.shape[1]):
            for c in range(arr.shape[2]):
                arr[bad, j, c] = np.interp(np.flatnonzero(bad), good,
                                           arr[good, j, c])
    return w, im, int(bad.sum())


def hampel(x, k=4, n_sigmas=3.0):
    """Sustituye picos aislados por la mediana local (por columna)."""
    x = x.copy()
    T = len(x)
    flat = x.reshape(T, -1)
    for c in range(flat.shape[1]):
        col = flat[:, c]
        for t in range(T):
            win = col[max(0, t - k):t + k + 1]
            med = np.median(win)
            mad = 1.4826 * np.median(np.abs(win - med)) + 1e-6
            if abs(col[t] - med) > n_sigmas * mad:
                col[t] = med
    return flat.reshape(x.shape)


def lowpass(x, fc, fps):
    b, a = butter(2, fc / (fps / 2))
    return filtfilt(b, a, x, axis=0, padtype="odd",
                    padlen=min(len(x) - 1, 30))


def to_blender(p):
    """MediaPipe world (x derecha imagen, y abajo, z hacia la cámara <0) →
    Blender (Z arriba, la cámara/espectador en -Y)."""
    return np.stack([p[..., 0], p[..., 2], -p[..., 1]], axis=-1)


def runs(mask):
    """[(ini, fin_exclusivo)] de los tramos True."""
    out, start = [], None
    for i, m in enumerate(mask):
        if m and start is None:
            start = i
        if not m and start is not None:
            out.append((start, i))
            start = None
    if start is not None:
        out.append((start, len(mask)))
    return out


# ------------------------------------------------------------------ apoyos
def detect_contacts(rel, img_speed, fps):
    """Apoyo de cada pie: lento en la imagen (velocidad absoluta, la cámara es
    fija) y no claramente más alto que el otro pie."""
    contacts = {}
    low = {s: np.minimum(rel[:, a, 2], np.minimum(rel[:, h, 2], rel[:, o, 2]))
           for s, (a, h, o) in {"L": (AN_L, HE_L, TO_L),
                                "R": (AN_R, HE_R, TO_R)}.items()}
    for s, other in (("L", "R"), ("R", "L")):
        speed = img_speed[s]
        lifted = low[s] > low[other] + 0.06
        # Histéresis: entra en apoyo por debajo de v_in, sale por encima de
        # v_out.
        v_in, v_out = 0.35, 0.6
        c = np.zeros(len(speed), bool)
        on = False
        for t in range(len(speed)):
            if on:
                on = speed[t] < v_out and not lifted[t]
            else:
                on = speed[t] < v_in and not lifted[t]
            c[t] = on
        # Huecos y apoyos muy cortos fuera.
        for a, b in runs(~c):
            if 0 < a and b < len(c) and b - a <= 2:
                c[a:b] = True
        for a, b in runs(c):
            if b - a < 4:
                c[a:b] = False
        contacts[s] = c
    # Nunca los dos pies en el aire mucho rato en salsa: si ninguno apoya,
    # apoya el más bajo (evita que la cadera flote sin referencia).
    none = ~contacts["L"] & ~contacts["R"]
    for a, b in runs(none):
        if b - a > 6:
            s = "L" if low["L"][a:b].mean() < low["R"][a:b].mean() else "R"
            contacts[s][a:b] = True
    return contacts


def solve_root(rel, contacts, img_root_x, fps):
    """Trayectoria horizontal de la cadera tal que los pies apoyados no se
    muevan. Mínimos cuadrados dispersos, por eje."""
    T = len(rel)
    segs = []
    for s, ank in (("L", AN_L), ("R", AN_R)):
        for a, b in runs(contacts[s]):
            segs.append((s, ank, a, b))
    n = T + len(segs)
    root = np.zeros((T, 2))
    for axis in (0, 1):
        rows, cols, vals, rhs = [], [], [], []
        r = 0
        for k, (s, ank, a, b) in enumerate(segs):
            for t in range(a, b):
                # root_t + rel_t - P_k = 0
                rows += [r, r]
                cols += [t, T + k]
                vals += [1.0, -1.0]
                rhs.append(-rel[t, ank, axis])
                r += 1
        w_acc = 3.0
        for t in range(1, T - 1):
            rows += [r, r, r]
            cols += [t - 1, t, t + 1]
            vals += [w_acc, -2 * w_acc, w_acc]
            rhs.append(0.0)
            r += 1
        # En X (de lado) la cámara fija dice dónde está la cadera: peso
        # fuerte, si no el maniquí no viajaba de lado (suzy Q, cumbia). En Y
        # (profundidad) la imagen no informa: solo se ancla a 0 muy débilmente.
        w_p = 1.0 if axis == 0 else 0.02
        prior = img_root_x if axis == 0 else np.zeros(T)
        for t in range(T):
            rows.append(r)
            cols.append(t)
            vals.append(w_p)
            rhs.append(w_p * prior[t])
            r += 1
        A = sparse.csr_matrix((vals, (rows, cols)), shape=(r, n))
        sol = lsqr(A, np.array(rhs), atol=1e-10, btol=1e-10,
                   iter_lim=20000)[0]
        root[:, axis] = sol[:T]
    return root


# -------------------------------------------------------------------- bucle
def pose_feature(g):
    """Pose comparable entre fotogramas: articulaciones relativas a la cadera
    (sin la traslación global)."""
    hip = (g[:, HIP_L] + g[:, HIP_R]) / 2
    sel = [SH_L, SH_R, EL_L, EL_R, WR_L, WR_R, KN_L, KN_R, AN_L, AN_R,
           TO_L, TO_R]
    return (g[:, sel] - hip[:, None]).reshape(len(g), -1)


def find_loop(g, fps, min_s, max_s):
    """Busca el ciclo [a, a+P) cuyos extremos más se parecen (pose y
    posición de la cadera). Devuelve (a, P)."""
    f = pose_feature(g)
    hip = (g[:, HIP_L] + g[:, HIP_R]) / 2
    T = len(f)
    best = (1e9, 0, 0)
    lo, hi = int(min_s * fps), int(max_s * fps)
    for P in range(lo, min(hi, T - 1) + 1):
        for a in range(0, T - P):
            b = a + P
            # Se comparan unos fotogramas alrededor de cada extremo, para que
            # también coincida la velocidad.
            ia = np.arange(a, min(a + 4, T))
            ib = np.arange(b, min(b + 4, T))
            m = min(len(ia), len(ib))
            d = np.linalg.norm(f[ia[:m]] - f[ib[:m]], axis=1).mean()
            d += 0.5 * np.linalg.norm(hip[a, :2] - hip[b, :2])
            if d < best[0]:
                best = (d, a, P)
    return best[1], best[2], best[0]


def make_seamless(g, contacts, a, P, blend):
    """Recorta [a, a+P) y reparte el desfase final→inicial a lo largo del ciclo
    (desplazamiento horizontal) y en los últimos `blend` fotogramas (pose)."""
    seg = g[a:a + P + 1].copy()
    hip = (seg[:, HIP_L] + seg[:, HIP_R]) / 2
    drift = hip[-1, :2] - hip[0, :2]
    ramp = np.linspace(0, 1, P + 1)[:, None]
    seg[:, :, :2] -= (ramp * drift)[:, None, :]
    # Pose: el último fotograma debe ser igual al primero.
    err = seg[-1] - seg[0]
    w = np.clip((np.arange(P + 1) - (P - blend)) / blend, 0, 1)
    w = w * w * (3 - 2 * w)
    seg -= w[:, None, None] * err[None]
    c = {s: contacts[s][a:a + P + 1].copy() for s in contacts}
    return seg[:P], {s: c[s][:P] for s in c}


# ------------------------------------------------------------- pies clavados
def lock_feet(g, contacts, ring=False):
    """Durante cada apoyo el pie (tobillo, talón y punta) se queda quieto en
    su posición media horizontal; en Z no baja del piso. Los extremos del
    apoyo se mezclan con suavidad para no dar tirones."""
    g = g.copy()
    T = len(g)
    if ring:
        # Trayectoria del pie en el aire más suave (el bucle es circular).
        r = 5
        k = np.exp(-0.5 * (np.arange(-r, r + 1) / 1.6) ** 2)
        k /= k.sum()
        feet = [AN_L, HE_L, TO_L, AN_R, HE_R, TO_R]
        ext_g = np.concatenate([g[-r:, feet], g[:, feet], g[:r, feet]])
        g[:, feet] = np.stack([np.tensordot(k, ext_g[i:i + 2 * r + 1], 1)
                               for i in range(T)])
    for s, pts in (("L", (AN_L, HE_L, TO_L)), ("R", (AN_R, HE_R, TO_R))):
        c = contacts[s]
        segs = runs(c)
        # En un bucle, un apoyo que cruza el final y el inicio es uno solo.
        if ring and len(segs) > 1 and segs[0][0] == 0 and segs[-1][1] == T:
            segs = [(segs[-1][0] - T, segs[0][1])] + segs[1:-1]
        for a, b in segs:
            idx = np.arange(a, b) % T
            for p in pts:
                target = g[idx, p, :2].mean(axis=0)
                ext = 4
                for k, t in enumerate(range(a - ext, b + ext)):
                    if not ring and (t < 0 or t >= T):
                        continue
                    tt = t % T
                    if a <= t < b:
                        w = 1.0
                    elif t < a:
                        w = (t - (a - ext)) / (ext + 1)
                    else:
                        w = ((b + ext) - t) / (ext + 1)
                    w = w * w * (3 - 2 * w)
                    g[tt, p, :2] = (1 - w) * g[tt, p, :2] + w * target
    return g


def keep_feet_apart(g, min_d=0.11):
    """Evita que un tobillo atraviese al otro: si en horizontal quedan a menos
    de `min_d`, se separan simétricamente (los cruces reales del baile, uno
    delante del otro, quedan a más distancia y no se tocan)."""
    g = g.copy()
    for t in range(len(g)):
        d = g[t, AN_L, :2] - g[t, AN_R, :2]
        n = np.linalg.norm(d)
        if n < min_d:
            dirv = d / n if n > 1e-6 else np.array([1.0, 0.0])
            push = (min_d - n) / 2 * dirv
            for p in (AN_L, HE_L, TO_L):
                g[t, p, :2] += push
            for p in (AN_R, HE_R, TO_R):
                g[t, p, :2] -= push
    return g


def feet_together_centre(g, contacts):
    """Punto medio de los pies cuando están juntos: los dos apoyados, a la
    misma altura en adelante/atrás y separados lo normal. Si el paso nunca
    junta los pies, el centro medio de la cadera."""
    mL = (g[:, HE_L, :2] + g[:, TO_L, :2]) / 2
    mR = (g[:, HE_R, :2] + g[:, TO_R, :2]) / 2
    d = mL - mR
    ok = contacts["L"] & contacts["R"] & (np.abs(d[:, 1]) < 0.08) &         (np.linalg.norm(d, axis=1) < 0.3)
    if ok.sum() >= 5:
        return np.median((mL[ok] + mR[ok]) / 2, axis=0)
    hip = (g[:, HIP_L, :2] + g[:, HIP_R, :2]) / 2
    return np.median(hip, axis=0)


# ------------------------------------------------------------------ proceso
def process(name, video, raw):
    fps = raw["fps"]
    world = fill_gaps(raw["world"])           # (T, 33, 4)
    image = fill_gaps(raw["image"])           # (T, 33, 3)
    world, image, flips = drop_flips(world, image)
    world, image = unswap(world, image)

    rel = to_blender(world[..., :3])
    rel = hampel(rel)
    # Paso bajo: cuerpo a 4.5 Hz (los pasos van a ~2.7 tiempos/s); la cara
    # (nariz, ojos, orejas) mucho más suave: de espaldas o de perfil MediaPipe
    # la estima mal y se veía la cabeza dando tirones.
    rel = lowpass(rel, 4.5, fps)
    rel[:, :11] = lowpass(rel[:, :11], 2.0, fps)
    # Hombros y brazos algo más suaves que las piernas: de espaldas o de perfil
    # (vuelta) MediaPipe los hace temblar.
    rel[:, 11:23] = lowpass(rel[:, 11:23], 3.0, fps)

    # Escala al rig.
    leg = np.median(np.concatenate([
        np.linalg.norm(rel[:, HIP_L] - rel[:, KN_L], axis=1) +
        np.linalg.norm(rel[:, KN_L] - rel[:, AN_L], axis=1),
        np.linalg.norm(rel[:, HIP_R] - rel[:, KN_R], axis=1) +
        np.linalg.norm(rel[:, KN_R] - rel[:, AN_R], axis=1)]))
    scale = RIG_LEG / leg
    rel *= scale

    # Imagen → metros: torso en píxeles vs torso en world.
    W, H = raw["width"], raw["height"]
    pix = image[..., :2] * np.array([W, H])
    pix = lowpass(hampel(pix), 6.0, fps)
    torso_px = np.linalg.norm(
        (pix[:, SH_L] + pix[:, SH_R]) / 2 - (pix[:, HIP_L] + pix[:, HIP_R]) / 2,
        axis=1)
    torso_m = np.linalg.norm(
        (rel[:, SH_L] + rel[:, SH_R]) / 2 - (rel[:, HIP_L] + rel[:, HIP_R]) / 2,
        axis=1)
    m_per_px = np.median(torso_m / torso_px)
    img_speed = {}
    for s, pts in (("L", (AN_L, HE_L, TO_L)), ("R", (AN_R, HE_R, TO_R))):
        v = np.linalg.norm(np.gradient(pix[:, list(pts)], axis=0), axis=2)
        img_speed[s] = v.mean(axis=1) * m_per_px * fps   # m/s
    hip_px = (pix[:, HIP_L] + pix[:, HIP_R]) / 2
    img_root_x = (hip_px[:, 0] - hip_px[:, 0].mean()) * m_per_px

    contacts = detect_contacts(rel, img_speed, fps)
    root_xy = solve_root(rel, contacts, img_root_x, fps)

    # Altura: el pie apoyado (el más bajo de los que apoyan) toca el piso.
    low = {s: np.minimum.reduce([rel[:, p, 2] for p in pts])
           for s, pts in (("L", (AN_L, HE_L, TO_L)),
                          ("R", (AN_R, HE_R, TO_R)))}
    zc = np.full(len(rel), np.nan)
    for t in range(len(rel)):
        cand = [low[s][t] for s in ("L", "R") if contacts[s][t]]
        if cand:
            zc[t] = -min(cand)
    ok = ~np.isnan(zc)
    root_z = np.interp(np.arange(len(rel)), np.flatnonzero(ok), zc[ok])
    root_z = lowpass(root_z, 3.0, fps)

    g = rel.copy()
    g[:, :, :2] += root_xy[:, None, :]
    g[:, :, 2] += root_z[:, None]

    # Ciclo de 8 tiempos: la duración del ciclo se busca entre 2.4 y 6 s
    # (los videos van a ritmo de práctica), el giro y la cumbia pueden ser
    # más largos.
    max_s = 8.5 if name in ("cumbia_3d",) else 6.5
    a, P, score = find_loop(g, fps, 2.4, max_s)
    loop, lc = make_seamless(g, contacts, a, P, blend=8)
    loop = lock_feet(loop, lc, ring=True)
    loop = keep_feet_apart(loop)
    # Ningún punto del pie por debajo del piso.
    for pts in ((AN_L, HE_L, TO_L), (AN_R, HE_R, TO_R)):
        m = loop[:, list(pts), 2].min(axis=1)
        under = np.minimum(m, 0.0)
        loop[:, :, 2] -= 0  # el cuerpo no se toca, solo el pie
        for p in pts:
            loop[:, p, 2] -= under
    # El origen de la guía es la posición "pies juntos" (de ahí
    # salen y ahí vuelven los pasos). No sirve la mediana de los apoyos: en
    # pasos que pasan mucho tiempo atrás (cumbia) el centro se corría y la base
    # quedaba "adelante", encendiendo siempre un cuadro.
    centre = np.array([*feet_together_centre(loop, lc), 0.0])
    loop -= centre

    # El "1" del conteo cae al inicio del bucle: se rota (es circular) para
    # que empiece en el apoyo de la pisada más adelantada.
    first = None
    for s, he, to in (("L", HE_L, TO_L), ("R", HE_R, TO_R)):
        mid = (loop[:, he, :2] + loop[:, to, :2]) / 2
        for a0, b0 in runs(lc[s]):
            p = mid[a0:b0].mean(axis=0)
            if p[1] < -0.10 and (first is None or p[1] < first[1]):
                first = (a0, p[1])
    shift = first[0] if first else 0
    loop = np.roll(loop, -shift, axis=0)
    lc = {s: np.roll(lc[s], -shift) for s in lc}

    # Tiempos musicales del ciclo: los videos van a ~165 bpm (una frase de 8
    # tiempos ≈ 2.9 s); los ciclos largos son frases dobles.
    beats = 8 * max(1, round(P / fps / 2.9))
    print(f"{name:<14} {video:<24} T={len(g):>4} ciclo {a:>4}+{P:<4}"
          f"({P / fps:.2f}s, {beats} tiempos) err {score:.3f} "
          f"escala {scale:.3f} "
          f"apoyo L {lc['L'].mean():.0%} R {lc['R'].mean():.0%} "
          f"volteos {flips}")
    return {"fps": fps, "frames": len(loop), "beats": beats,
            "joints": np.round(loop, 4).tolist(),
            "contact_L": lc["L"].astype(int).tolist(),
            "contact_R": lc["R"].astype(int).tolist(),
            "source": {"video": video, "start": int(a), "length": int(P),
                       "shift": int(shift)}}


def main():
    src, out = sys.argv[1], sys.argv[2]
    only = sys.argv[3:]
    with open(src, encoding="utf-8") as f:
        data = json.load(f)
    result = {}
    for name, video in STEPS.items():
        if only and name not in only:
            continue
        result[name] = process(name, video, data[video])
    with open(out, "w", encoding="utf-8") as f:
        json.dump(result, f)


if __name__ == "__main__":
    main()
