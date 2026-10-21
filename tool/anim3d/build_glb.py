"""Reconstruye `assets/models/DanceGrid1.glb` dentro de Blender.

  blender -b -P tool/anim3d/build_glb.py -- <base.glb> <clean.json> <salida.glb>
                                            [niveles_subdivision=2]

- Parte de la escena base (maniquí, pista, luces) y borra las animaciones y el
  dance grid viejos. El maniquí se suelda, se sombrea suave y se subdivide
  (venía facetado).
- Por cada paso de `clean.json` (salida de process.py) crea una acción del
  armature con una clave por fotograma:
    * columna/cuello/brazos: se orienta cada hueso hacia la dirección que
      marcan los landmarks, controlando también el giro sobre su eje;
    * cadera: sin el sesgo fijo cadera/hombros de MediaPipe y con el cuban
      motion amplificado (vaivén hacia la pierna de apoyo + inclinación);
    * cabeza: limitada respecto al pecho (de espaldas MediaPipe inventa la
      cara);
    * piernas: IK analítica de dos huesos hacia el tobillo limpio (clavado
      mientras apoya). La rodilla apunta siempre al frente de la pelvis (con
      el giro limitado de la real) y el pie va plano salvo punta/talón claros:
      el talón y la punta de MediaPipe vistos de frente no son fiables.
- Dibuja por paso una grilla simétrica (`salsa_dance_grid`): una cruz de 5
  cuadros que crece (con sus espejos) solo donde un apoyo no cae en ningún
  cuadro, centrada donde los pies pasan más tiempo dentro de los cuadros (ver
  dance_grid.py). Cada apoyo enciende su cuadro con el color del pie. Las animaciones van en la misma
  animación glTF que el maniquí (pistas NLA con el mismo nombre).
"""

import json
import math
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Matrix, Quaternion, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
from dance_grid import (CELL, STEP_GRIDS, STEP_MIRRORS, STEP_OVERRIDES,
                        STEP_SOLID_CELLS, plan_guide, step_contacts)
from foot_pitch import FOOT_LENGTH, STEP_HEIGHT_PITCH, tap_pitch

argv = sys.argv[sys.argv.index("--") + 1:]
BASE, CLEAN, OUT = argv[0], argv[1], argv[2]

# Índices BlazePose (ver process.py).
NOSE, EAR_L, EAR_R = 0, 7, 8
SH_L, SH_R, EL_L, EL_R, WR_L, WR_R = 11, 12, 13, 14, 15, 16
PK_L, PK_R, IX_L, IX_R = 17, 18, 19, 20
HIP_L, HIP_R, KN_L, KN_R, AN_L, AN_R = 23, 24, 25, 26, 27, 28
HE_L, HE_R, TO_L, TO_R = 29, 30, 31, 32

# Las casillas se ajustan a los apoyos de cada paso, en la escala del personaje.
GRID_Z = 0.006
# Emisión de los rellenos (magenta = pie izquierdo, amarillo = derecho). Por
# debajo de 1: el tone mapping de <model-viewer> desatura (lava a blanco) los
# emisivos cercanos a 1.
FOOT_RGB = {"L": (0.62, 0.07, 0.40), "R": (0.75, 0.45, 0.0)}
# Niveles de subdivisión del maniquí (0 = solo sombreado suave).
SUBDIV = int(argv[3]) if len(argv) > 3 else 2
MANNEQUIN_RGB = (0.80, 0.74, 0.66, 1.0)
# Personaje opcional (FBX con esqueleto de Mixamo). Sin él se anima el maniquí
# de la escena base.
CHARACTER = argv[4] if len(argv) > 4 and argv[4] else None
# Lado máximo de las texturas del personaje (2048 → 1024 baja mucho el GLB y
# en un teléfono no se nota).
TEXTURE_MAX = 1024

# Huesos "semánticos" que mueve este script → huesos reales de cada esqueleto.
# Los huesos reales que no aparecen (pelo, falda, dedos, giros de brazo…)
# siguen a su padre tal cual están en reposo.
SEMANTIC = ("Hips", "Spine", "Chest", "Neck", "Head",
            "Shoulder.L", "UpperArm.L", "LowerArm.L", "Hand.L",
            "Shoulder.R", "UpperArm.R", "LowerArm.R", "Hand.R",
            "Thigh.L", "Shin.L", "Foot.L", "Thigh.R", "Shin.R", "Foot.R")
MIXAMO = {
    "Hips": "Hips", "Spine": "Spine", "Chest": "Spine2", "Neck": "Neck",
    "Head": "Head",
    "Shoulder.L": "LeftShoulder", "UpperArm.L": "LeftArm",
    "LowerArm.L": "LeftForeArm", "Hand.L": "LeftHand",
    "Shoulder.R": "RightShoulder", "UpperArm.R": "RightArm",
    "LowerArm.R": "RightForeArm", "Hand.R": "RightHand",
    "Thigh.L": "LeftUpLeg", "Shin.L": "LeftLeg", "Foot.L": "LeftFoot",
    "Thigh.R": "RightUpLeg", "Shin.R": "RightLeg", "Foot.R": "RightFoot",
}
# Columna: cada hueso real toma esta fracción del giro entre cadera y pecho.
SPINE_FRACS = {"maniqui": {"Spine": 0.5},
               "mixamo": {"Spine": 0.33, "Spine1": 0.67}}
# El maniquí del que salen los datos (process.py): cadera→tobillo.
DATA_LEG = 0.84


# ------------------------------------------------------------------ escena
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=BASE)
scene = bpy.context.scene
scene.render.fps = 30
arm = next(o for o in scene.objects if o.type == "ARMATURE")

# Fuera las animaciones viejas y el grid viejo.
for ob in list(scene.objects):
    if ob.animation_data:
        for tr in list(ob.animation_data.nla_tracks):
            ob.animation_data.nla_tracks.remove(tr)
        ob.animation_data.action = None
for act in list(bpy.data.actions):
    bpy.data.actions.remove(act)
for pb in arm.pose.bones:
    pb.custom_shape = None
for name in ("salsa_dance_grid", "Icosphere"):
    ob = bpy.data.objects.get(name)
    if ob:
        bpy.data.objects.remove(ob, do_unlink=True)
for ob in list(scene.objects):
    if ob.name.startswith("pisada_"):
        bpy.data.objects.remove(ob, do_unlink=True)


def load_character(path):
    """Cambia el maniquí de la escena base por un personaje de Mixamo (FBX).
    Devuelve su armature, ya en metros, Z arriba y mirando a -Y como el
    maniquí (se aplican la rotación y la escala que trae el FBX)."""
    for ob in [arm] + list(arm.children_recursive):
        bpy.data.objects.remove(ob, do_unlink=True)
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    rig = next(o for o in new if o.type == "ARMATURE")
    objs = [rig] + [o for o in new if o.parent == rig]
    with bpy.context.temp_override(selected_editable_objects=objs,
                                   selected_objects=objs, active_object=rig,
                                   object=rig):
        bpy.ops.object.transform_apply(location=False, rotation=True,
                                       scale=True)
    # Fuera la animación de muestra de Mixamo.
    if rig.animation_data:
        rig.animation_data.action = None
    for act in list(bpy.data.actions):
        bpy.data.actions.remove(act)
    for pb in rig.pose.bones:
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = (1, 0, 0, 0)
        pb.location = (0, 0, 0)
    # Texturas más livianas para el teléfono.
    for im in bpy.data.images:
        w, h = im.size
        if max(w, h) > TEXTURE_MAX:
            f = TEXTURE_MAX / max(w, h)
            im.scale(int(w * f), int(h * f))
    rig.name = "Personaje"
    print(f"PERSONAJE {path}: {len(rig.data.bones)} huesos, "
          f"{sum(len(o.data.vertices) for o in objs if o.type == 'MESH')} "
          "vértices")
    return rig


if CHARACTER:
    arm = load_character(CHARACTER)
    RIG = "mixamo"
    _hips = next(b.name for b in arm.data.bones if b.name.endswith("Hips"))
    _prefix = _hips[:-len("Hips")]           # "mixamorig:" o variantes
    BONE = {sem: _prefix + MIXAMO[sem] for sem in SEMANTIC}
    SPINE_EXTRA = {_prefix + n: f for n, f in SPINE_FRACS["mixamo"].items()}
    MANI = None
else:
    RIG = "maniqui"
    BONE = {sem: sem for sem in SEMANTIC}
    SPINE_EXTRA = dict(SPINE_FRACS["maniqui"])
    MANI = next(o for o in scene.objects
                if o.type == "MESH" and o.parent == arm)


def smooth_mannequin(level):
    """El maniquí viene facetado (caras planas y vértices duplicados): se
    sueldan los vértices, se sombrea suave y se subdivide. Los pesos del
    esqueleto se interpolan solos al aplicar la subdivisión."""
    import bmesh
    mani = MANI
    bm = bmesh.new()
    bm.from_mesh(mani.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0005)
    bm.to_mesh(mani.data)
    bm.free()
    for poly in mani.data.polygons:
        poly.use_smooth = True
    if level > 0:
        mod = mani.modifiers.new("Suavizado", "SUBSURF")
        mod.levels = mod.render_levels = level
        with bpy.context.temp_override(object=mani, active_object=mani):
            bpy.ops.object.modifier_move_to_index(modifier=mod.name, index=0)
            bpy.ops.object.modifier_apply(modifier=mod.name)
    # Material mate, tono maniquí de madera clara en vez de gris plástico.
    mat = mani.material_slots[0].material
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = MANNEQUIN_RGB
        bsdf.inputs["Roughness"].default_value = 0.55
    print(f"MANIQUI {len(mani.data.vertices)} vértices, "
          f"{len(mani.data.polygons)} caras")


if MANI is not None:
    smooth_mannequin(SUBDIV)


def make_shoes():
    """Tenis para el maniquí. Su pie era un tubo doblado sin talón: no se
    distinguía talón de punta. Cada tenis es una malla rígida (parte de
    arriba clara, suela oscura) colgada del hueso Foot: talón ~6 cm detrás del
    tobillo, punta redondeada adelante (-Y), suela en z = 0 en reposo."""
    import bmesh
    upper = bpy.data.materials.new("mat_tenis")
    upper.use_nodes = True
    b = upper.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (0.93, 0.93, 0.95, 1.0)
    b.inputs["Roughness"].default_value = 0.6
    sole = bpy.data.materials.new("mat_tenis_suela")
    sole.use_nodes = True
    b = sole.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (0.08, 0.08, 0.09, 1.0)
    b.inputs["Roughness"].default_value = 0.8
    shoes = {}
    for s in ("L", "R"):
        cx = REST_HEAD0[f"Foot.{s}"][0]
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=3,
                                  use_grid_fill=True)
        for v in bm.verts:
            x, y, z = v.co
            u = 0.5 - y                      # 0 talón … 1 punta
            width = 0.078 + 0.024 * math.sin(math.pi * min(u * 1.25, 1.0))
            height = 0.105 if u < 0.35 else 0.105 - (u - 0.35) / 0.65 * 0.06
            h = z + 0.5                      # 0 suela … 1 empeine
            taper = 1.0 - 0.28 * h * h       # más angosto arriba
            v.co = Vector((cx + x * width * taper, 0.065 - u * 0.27,
                           h * height))
        me = bpy.data.meshes.new(f"mesh_tenis_{s}")
        bm.to_mesh(me)
        bm.free()
        me.materials.append(upper)
        me.materials.append(sole)
        for poly in me.polygons:
            poly.use_smooth = True
            if poly.center.z < 0.02:
                poly.material_index = 1
        ob = bpy.data.objects.new(f"tenis_{s}", me)
        scene.collection.objects.link(ob)
        mod = ob.modifiers.new("Suavizado", "SUBSURF")
        mod.levels = mod.render_levels = 2
        with bpy.context.temp_override(object=ob, active_object=ob):
            bpy.ops.object.modifier_apply(modifier=mod.name)
        # La subdivisión redondea y sube la base: se vuelve a apoyar en z=0.
        zmin = min(v.co.z for v in me.vertices)
        for v in me.vertices:
            v.co.z -= zmin
        # Colgado del hueso del pie conservando su lugar en reposo.
        bone = arm.data.bones[f"Foot.{s}"]
        ob.parent = arm
        ob.parent_type = "BONE"
        ob.parent_bone = bone.name
        tail = arm.matrix_world @ bone.tail_local
        rest = arm.matrix_world @ bone.matrix_local
        rest.translation = tail
        ob.matrix_parent_inverse = rest.inverted()
        shoes[s] = ob
    return shoes


REST_HEAD0 = {b.name: np.array(b.head_local) for b in arm.data.bones}
SHOES = make_shoes() if MANI is not None else None

bones = arm.data.bones
REST = {b.name: b.matrix_local.copy() for b in bones}
REST_ROT = {n: np.array(m.to_3x3()) for n, m in REST.items()}
REST_HEAD = {n: np.array(m.translation) for n, m in REST.items()}
PARENT = {b.name: b.parent.name if b.parent else None for b in bones}
ORDER = [b.name for b in bones]  # Blender los da de padre a hijo
# Los cálculos usan nombres semánticos ("Thigh.L"…): alias a los reales.
for _sem, _real in BONE.items():
    REST_ROT[_sem] = REST_ROT[_real]
    REST_HEAD[_sem] = REST_HEAD[_real]
REAL_TO_SEM = {real: sem for sem, real in BONE.items()}
# Largos de cabeza a cabeza (en Mixamo la cola de un hueso no siempre toca la
# cabeza del siguiente).
L_THIGH = float(np.linalg.norm(REST_HEAD["Shin.L"] - REST_HEAD["Thigh.L"]))
L_SHIN = float(np.linalg.norm(REST_HEAD["Foot.L"] - REST_HEAD["Shin.L"]))
# Los landmarks vienen escalados al maniquí: se llevan al tamaño del rig.
SCALE = (L_THIGH + L_SHIN) / DATA_LEG
print(f"RIG {RIG}: pierna {L_THIGH + L_SHIN:.3f} m, escala {SCALE:.3f}")


# ----------------------------------------------------------------- matemática
def unit(v):
    n = np.linalg.norm(v)
    return v / n if n > 1e-9 else v


def frame_from(y, s):
    """Base ortonormal [x, y, z] con y como eje principal y `s` (proyectado)
    fijando el giro: devuelve columnas (y, s⟂, y×s⟂)."""
    y = unit(y)
    s = unit(s - np.dot(s, y) * y)
    return np.stack([y, s, np.cross(y, s)], axis=1)


def align(name, y_target, s_target, y_rest=None, s_rest=None):
    """Rotación (armature) del hueso `name` para que su eje Y (o `y_rest`)
    apunte a `y_target` y la referencia `s_rest` quede hacia `s_target`."""
    R = REST_ROT[name]
    if y_rest is None:
        y_rest = R[:, 1]
    F_rest = frame_from(np.asarray(y_rest, float), np.asarray(s_rest, float))
    F_t = frame_from(y_target, s_target)
    return F_t @ F_rest.T @ R


def child_rest_rot(parent_pose_rot, parent, child):
    """Rotación del hijo si no se le aplica pose propia (sigue al padre)."""
    return parent_pose_rot @ REST_ROT[parent].T @ REST_ROT[child]


def two_bone_ik(hip, ankle, pole):
    """Rodilla tal que |hip-rodilla| = L_THIGH y |rodilla-tobillo| = L_SHIN,
    en el plano que contiene `pole`. El tobillo se acerca si no se alcanza."""
    d = ankle - hip
    dist = np.linalg.norm(d)
    max_r = (L_THIGH + L_SHIN) * 0.995
    if dist > max_r:
        ankle = hip + d / dist * max_r
        d = ankle - hip
        dist = max_r
    dn = d / dist
    a = (L_THIGH ** 2 - L_SHIN ** 2 + dist ** 2) / (2 * dist)
    h = math.sqrt(max(L_THIGH ** 2 - a * a, 0.0))
    p = pole - np.dot(pole, dn) * dn
    p = unit(p)
    return hip + dn * a + p * h, ankle


def mat4(rot, loc):
    m = Matrix([list(rot[0]) + [loc[0]], list(rot[1]) + [loc[1]],
                list(rot[2]) + [loc[2]], [0, 0, 0, 1]])
    return m


FWD = np.array([0.0, -1.0, 0.0])
UP = np.array([0.0, 0.0, 1.0])
LAT = np.array([1.0, 0.0, 0.0])

# Límites "anatómicos" (grados). MediaPipe estima mal la profundidad de la
# cara, rodillas y pies (sobre todo de espaldas o de perfil); en vez de copiar
# esos errores se limita cada articulación a un rango creíble.
KNEE_TURNOUT = 40     # rodilla: cuánto puede apuntar fuera del frente de la pelvis
FOOT_VS_KNEE = 20     # pie: cuánto puede girar respecto a su rodilla
FOOT_PITCH_DEAD = 8   # inclinación del pie que se ignora (ruido/sesgo)
FOOT_PITCH_UP = 35    # talón apoyado, punta arriba
FOOT_PITCH_DOWN = 40  # punta apoyada / pie estirado en el aire
HEAD_MAX = 35         # cabeza respecto al pecho
HIP_GAIN = 1.6        # amplifica el movimiento de cadera respecto al pecho
HIP_MAX = 30
HIP_SWAY_GAIN = 1.8   # vaivén lateral de la cadera hacia la pierna de apoyo
HIP_ROLL_PER_M = 150  # grados de inclinación de pelvis por metro de vaivén
HIP_ROLL_MAX = 9
SWING_LIFT_GAIN = 1.5  # altura del pie en el aire
UPPER_SMOOTH = 2.2     # suavizado final de tronco y brazos (fotogramas)


def rotz(v, deg):
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    return np.array([c * v[0] - s * v[1], s * v[0] + c * v[1], v[2]])


def hangle(a, b):
    """Ángulo con signo (grados) de b respecto de a en el plano horizontal."""
    return math.degrees(math.atan2(a[0] * b[1] - a[1] * b[0],
                                   a[0] * b[0] + a[1] * b[1]))


def horiz(v):
    return unit(np.array([v[0], v[1], 0.0]))


def circ_smooth(x, sigma):
    """Suavizado gaussiano circular (el bucle se repite), por columnas."""
    x = np.asarray(x, float)
    r = int(math.ceil(3 * sigma))
    k = np.exp(-0.5 * (np.arange(-r, r + 1) / sigma) ** 2)
    k /= k.sum()
    n = len(x)
    ext = np.concatenate([x[n - r:], x, x[:r]], axis=0)
    out = np.empty_like(x)
    for i in range(n):
        out[i] = np.tensordot(k, ext[i:i + 2 * r + 1], axes=(0, 0))
    return out


def clamp_rel(parent_rot, child_rot, max_deg, gain=1.0):
    """Rotación del hijo relativa al padre, multiplicada por `gain` y con el
    ángulo total limitado a `max_deg`."""
    rel = Matrix((parent_rot.T @ child_rot).tolist()).to_quaternion()
    axis, ang = rel.to_axis_angle()
    if ang > math.pi:
        ang -= 2 * math.pi
    ang = max(-math.radians(max_deg), min(ang * gain, math.radians(max_deg)))
    q = Quaternion(axis, ang)
    return parent_rot @ np.array(q.to_matrix())


def slerp_rot(r0, r1, f):
    q0 = Matrix(r0.tolist()).to_quaternion()
    q1 = Matrix(r1.tolist()).to_quaternion()
    return np.array(q0.slerp(q1, f).to_matrix())


class StepCtx:
    """Datos de un paso que no salen de un solo fotograma: sesgos de
    MediaPipe, orientación de rodillas y pies ya filtrada en el tiempo y
    cuánto bajar la cadera."""

    def __init__(self, J_all, data, by_height=False):
        self.N = len(J_all)
        lat_p = J_all[:, HIP_L] - J_all[:, HIP_R]
        lat_s = J_all[:, SH_L] - J_all[:, SH_R]
        # Sesgo fijo de giro entre cadera y hombros (la bailarina los lleva
        # alineados; MediaPipe los da ~25° torcidos y el torso se veía
        # retorcido).
        d = [hangle(lat_s[t], lat_p[t]) for t in range(self.N)]
        self.hip_bias = float(np.median(d))
        self.knee_yaw = {}
        self.foot_rot = {}
        self.contact = {}
        self.foot_pitch = {}
        for s, hp, kn, an, he, to in (("L", HIP_L, KN_L, AN_L, HE_L, TO_L),
                                      ("R", HIP_R, KN_R, AN_R, HE_R, TO_R)):
            c = np.array(data[f"contact_{s}"] + data[f"contact_{s}"][:1],
                         bool)[:self.N]
            self.contact[s] = c
            k_yaw = np.zeros(self.N)
            f_yaw = np.zeros(self.N)
            pitch = np.zeros(self.N)
            for t in range(self.N):
                J = J_all[t]
                fwd_p = self.pelvis_fwd(J)
                dn = unit(J[an] - J[hp])
                k = J[kn] - J[hp]
                kp = k - np.dot(k, dn) * dn
                if np.linalg.norm(kp[:2]) > 0.03:
                    k_yaw[t] = float(np.clip(hangle(fwd_p, horiz(kp)),
                                             -KNEE_TURNOUT, KNEE_TURNOUT))
                ft = J[to] - J[he]
                pole = rotz(fwd_p, k_yaw[t])
                if np.linalg.norm(ft[:2]) > 0.03:
                    f_yaw[t] = float(np.clip(hangle(pole, horiz(ft)),
                                             -FOOT_VS_KNEE, FOOT_VS_KNEE))
                pitch[t] = math.degrees(math.atan2(
                    ft[2], np.linalg.norm(ft[:2]) + 1e-6))
            # Inclinación: el talón/punta de MediaPipe vistos de frente tienen
            # un sesgo enorme (el pie "apunta" 20-50° abajo aunque esté plano:
            # parecía caminar de puntas). Solo cuenta la desviación clara
            # respecto a su valor típico en apoyo (punta-talón de verdad).
            if by_height:
                # Punta-talón: la inclinación sale de las alturas de talón y
                # punta (fiables), no del largo horizontal del pie (aplastado),
                # y se exagera para que el toque se note.
                rel = circ_smooth(tap_pitch(J_all[:, he, 2], J_all[:, to, 2],
                                            FOOT_LENGTH * SCALE), 2.5)
            else:
                base = np.median(pitch[c]) if c.any() else np.median(pitch)
                rel = circ_smooth(pitch - base, 2.5)
                mag = np.maximum(np.abs(rel) - FOOT_PITCH_DEAD, 0.0)
                rel = np.clip(np.sign(rel) * mag, -FOOT_PITCH_DOWN, FOOT_PITCH_UP)
            self.foot_pitch[s] = rel
            self.knee_yaw[s] = circ_smooth(k_yaw, 2.0)
            f_yaw = circ_smooth(f_yaw, 2.0)
            self.foot_rot[s] = []
            for t in range(self.N):
                fwd_p = self.pelvis_fwd(J_all[t])
                yaw_dir = rotz(fwd_p, self.knee_yaw[s][t] + f_yaw[t])
                pr = math.radians(rel[t])
                fwd = math.cos(pr) * yaw_dir + math.sin(pr) * UP
                up = np.cross(np.cross(fwd, UP), fwd)
                self.foot_rot[s].append(align(f"Foot.{s}", fwd, up,
                                              y_rest=FWD, s_rest=UP))
        self.drop = np.zeros(self.N)
        # Vaivén de cadera: cuánto está la cadera hacia un lado respecto al
        # punto medio de los tobillos (centrado: MediaPipe trae un sesgo fijo).
        sway = np.zeros(self.N)
        for t in range(self.N):
            J = J_all[t]
            left = -np.cross(self.pelvis_fwd(J), UP)
            hip = (J[HIP_L] + J[HIP_R]) / 2
            feet = (J[AN_L] + J[AN_R]) / 2
            sway[t] = np.dot((hip - feet)[:2], left[:2])
        self.sway = circ_smooth(sway - np.median(sway), 2.0)

    def pelvis_fwd(self, J):
        lat = unit(rotz(J[HIP_L] - J[HIP_R], -self.hip_bias)) + \
            unit(J[SH_L] - J[SH_R])
        return horiz(np.cross(horiz(lat), UP))


def pose_frame(J, ctx, t):
    """Rotaciones (armature space) de todos los huesos para el fotograma t
    (landmarks J (33, 3)), la ubicación de la cadera y cuánto habría que
    bajarla para que las piernas alcancen."""
    rot = {}
    hipC = (J[HIP_L] + J[HIP_R]) / 2
    shC = (J[SH_L] + J[SH_R]) / 2
    lat_p = rotz(J[HIP_L] - J[HIP_R], -ctx.hip_bias)
    lat_s = J[SH_L] - J[SH_R]
    up_t = shC - hipC

    rot["Chest"] = align("Chest", up_t, lat_s, y_rest=UP, s_rest=LAT)
    hips_raw = align("Hips", up_t, lat_p, y_rest=UP, s_rest=LAT)
    # Movimiento de cadera (cuban motion) más visible: la cadera respecto al
    # pecho se amplifica.
    rot["Hips"] = clamp_rel(rot["Chest"], hips_raw, HIP_MAX, HIP_GAIN)
    # Cuban motion: la cadera del lado que sostiene el peso sube (gira sobre
    # el eje adelante del cuerpo; positivo = sube el lado izquierdo).
    fwd_p = ctx.pelvis_fwd(J)
    roll = float(np.clip(HIP_ROLL_PER_M * ctx.sway[t], -HIP_ROLL_MAX,
                         HIP_ROLL_MAX))
    R_roll = np.array(Matrix.Rotation(math.radians(roll), 3,
                                      Vector(fwd_p.tolist())))
    rot["Hips"] = R_roll @ rot["Hips"]
    rot["Spine"] = slerp_rot(rot["Hips"], rot["Chest"], 0.5)
    earC = (J[EAR_L] + J[EAR_R]) / 2
    lat_h = J[EAR_L] - J[EAR_R]
    fwd_h = J[NOSE] - earC
    up_h = np.cross(unit(fwd_h), unit(lat_h))
    head = align("Head", up_h, lat_h, y_rest=UP, s_rest=LAT)
    # La cabeza no puede girar más de HEAD_MAX respecto al pecho (de espaldas
    # MediaPipe inventa la cara y la cabeza daba vueltas raras).
    rot["Head"] = clamp_rel(rot["Chest"], head, HEAD_MAX)
    rot["Neck"] = slerp_rot(rot["Chest"], rot["Head"], 0.45)

    # Brazos. La clavícula sigue al pecho.
    chest_fwd = np.cross(unit(up_t), unit(lat_s))
    chest_fwd = -chest_fwd if np.dot(chest_fwd, FWD) < 0 else chest_fwd
    for s, sh, el, wr, ix, pk in (("L", SH_L, EL_L, WR_L, IX_L, PK_L),
                                  ("R", SH_R, EL_R, WR_R, IX_R, PK_R)):
        rot[f"Shoulder.{s}"] = child_rest_rot(rot["Chest"], "Chest",
                                              f"Shoulder.{s}")
        upper = J[el] - J[sh]
        fore = J[wr] - J[el]
        u, f = unit(upper), unit(fore)
        bend = np.linalg.norm(np.cross(u, f))   # 0 recto, 1 a 90°
        sec_u = f - np.dot(f, u) * u
        w = min(1.0, bend / 0.35)
        sec_u = w * unit(sec_u) + (1 - w) * chest_fwd
        rot[f"UpperArm.{s}"] = align(f"UpperArm.{s}", upper, sec_u,
                                     s_rest=FWD)
        sec_f = -u - np.dot(-u, f) * f
        sec_f = w * unit(sec_f) + (1 - w) * unit(sec_u)
        rot[f"LowerArm.{s}"] = align(f"LowerArm.{s}", fore, sec_f,
                                     s_rest=FWD)
        hand = (J[ix] + J[pk]) / 2 - J[wr]
        # La mano se dobla poco: se mezcla con la dirección del antebrazo.
        rot[f"Hand.{s}"] = align(f"Hand.{s}", 0.4 * unit(hand) + 0.6 * f,
                                 sec_f, s_rest=FWD)

    # Ubicación de la cabeza del hueso Hips: centro de cadera + el desfase del
    # rig (Hips está 3 cm sobre la línea de las articulaciones de la cadera).
    rig_hipC = (REST_HEAD["Thigh.L"] + REST_HEAD["Thigh.R"]) / 2
    T_h = rot["Hips"] @ REST_ROT["Hips"].T
    hips_loc = hipC + T_h @ (REST_HEAD["Hips"] - rig_hipC)
    # Y la cadera se va más hacia la pierna de apoyo.
    left = -np.cross(fwd_p, UP)
    hips_loc = hips_loc + left * (HIP_SWAY_GAIN - 1.0) * ctx.sway[t]

    # Si alguna pierna no alcanza su tobillo (el rig y la bailarina no miden
    # igual), se baja la cadera lo justo en vez de despegar el pie del piso.
    # La primera pasada lo mide; la segunda usa el valor suavizado.
    max_r = (L_THIGH + L_SHIN) * 0.985
    drop = 0.0
    for s, an in (("L", AN_L), ("R", AN_R)):
        hr = hips_loc + T_h @ (REST_HEAD[f"Thigh.{s}"] - REST_HEAD["Hips"])
        d = J[an] - hr
        dxy2 = d[0] ** 2 + d[1] ** 2
        if np.linalg.norm(d) > max_r and dxy2 < max_r ** 2:
            drop = max(drop, -d[2] - math.sqrt(max_r ** 2 - dxy2))
    hips_loc = hips_loc - np.array([0.0, 0.0, max(drop, ctx.drop[t])])

    # Piernas: IK hacia el tobillo limpio. La rodilla apunta al frente de la
    # pelvis con el giro (limitado) de la rodilla real: nunca hacia atrás.
    fwd_p = ctx.pelvis_fwd(J)
    for s, an in (("L", AN_L), ("R", AN_R)):
        hip_rig = hips_loc + T_h @ (REST_HEAD[f"Thigh.{s}"] - REST_HEAD["Hips"])
        pole = rotz(fwd_p, ctx.knee_yaw[s][t])
        knee, ankle = two_bone_ik(hip_rig, J[an], pole)
        rot[f"Thigh.{s}"] = align(f"Thigh.{s}", knee - hip_rig, pole,
                                  s_rest=FWD)
        rot[f"Shin.{s}"] = align(f"Shin.{s}", ankle - knee, pole,
                                 s_rest=FWD)
        rot[f"Foot.{s}"] = ctx.foot_rot[s][t]
    return rot, hips_loc, drop


def real_rotations(rot):
    """Rotaciones semánticas → rotación (armature) de cada hueso real. Los
    de la columna intermedia reparten el giro cadera→pecho; los que no se
    animan siguen a su padre como en reposo."""
    out = {}
    for name in ORDER:
        sem = REAL_TO_SEM.get(name)
        if name in SPINE_EXTRA:
            out[name] = slerp_rot(rot["Hips"], rot["Chest"], SPINE_EXTRA[name])
        elif sem is not None:
            out[name] = rot[sem]
        else:
            p = PARENT[name]
            out[name] = child_rest_rot(out[p], p, name) if p else \
                REST_ROT[name]
    return out


def to_basis(rot, hips_loc):
    """Rotaciones armature → (location, quaternion) locales de cada hueso
    real. La raíz del esqueleto (la cadera) además lleva la ubicación."""
    rot = real_rotations(rot)
    out = {}
    for name in ORDER:
        p = PARENT[name]
        R_rest = REST_ROT[name]
        if p is None:
            q = Matrix((R_rest.T @ rot[name]).tolist()).to_quaternion()
            loc = R_rest.T @ (hips_loc - REST_HEAD[name])
        else:
            local = R_rest.T @ REST_ROT[p] @ rot[p].T @ rot[name]
            q = Matrix(local.tolist()).to_quaternion()
            loc = np.zeros(3)
        out[name] = (loc, q)
    return out


# ------------------------------------------------------------------ claves
def set_keys(action, path_values):
    """Escribe fcurves directamente (rápido). path_values:
    {(data_path, index): [valores por fotograma]}; fotogramas desde 0."""
    slot = action.slots[0]
    layer = action.layers[0] if action.layers else action.layers.new("Layer")
    strip = layer.strips[0] if layer.strips else layer.strips.new(
        type="KEYFRAME")
    bag = strip.channelbag(slot, ensure=True)
    for (path, idx), vals in path_values.items():
        # Sin group_name: es opcional en Blender 5 y no existe en Blender 4.5.
        fc = bag.fcurves.new(path, index=idx)
        n = len(vals)
        fc.keyframe_points.add(n)
        co = np.empty(2 * n)
        co[0::2] = np.arange(n)
        co[1::2] = vals
        fc.keyframe_points.foreach_set("co", co)
        fc.keyframe_points.foreach_set("interpolation", [1] * n)  # LINEAR
        fc.update()


def new_action(name, ob):
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    if ob.animation_data is None:
        ob.animation_data_create()
    ob.animation_data.action = act   # crea/asigna el slot
    if not act.slots:
        act.slots.new(id_type="OBJECT", name=ob.name)
        ob.animation_data.action_slot = act.slots[0]
    return act


def push_nla(ob, act, track_name):
    ad = ob.animation_data
    tr = ad.nla_tracks.new()
    tr.name = track_name
    st = tr.strips.new(track_name, 0, act)
    st.action_frame_start, st.action_frame_end = act.frame_range
    ad.action = None


def foot_vertices():
    """Vértices de cada pie relativos a la cabeza del hueso Foot, en reposo:
    los tenis del maniquí o, en un personaje, los vértices pesados al pie y a
    los dedos. Sirven para saber cuánto baja el pie según cómo esté girado
    (la suela es lo que toca el piso)."""
    out = {}
    for s in ("L", "R"):
        if SHOES is not None:
            pts = [list(v.co) for v in SHOES[s].data.vertices]
        else:
            foot = BONE[f"Foot.{s}"]
            kids = {b.name for b in arm.data.bones[foot].children_recursive}
            names = {foot} | kids
            pts = []
            for ob in arm.children:
                if ob.type != "MESH":
                    continue
                idx = {g.index for g in ob.vertex_groups if g.name in names}
                for v in ob.data.vertices:
                    if sum(e.weight for e in v.groups if e.group in idx) > 0.5:
                        pts.append(list(ob.matrix_world @ v.co))
        out[s] = np.array(pts) - REST_HEAD[f"Foot.{s}"]
    return out


FOOT_VERTS = None


def ground_ankles(J_all, ctx):
    """Ajusta la altura de los tobillos con la geometría real del pie: en
    apoyo, el punto más bajo del pie toca el piso (z = 0); en el aire, nunca
    queda por debajo. El ajuste se suaviza para no dar saltos al pisar."""
    P = len(J_all) - 1
    for s, an, he, to in (("L", AN_L, HE_L, TO_L), ("R", AN_R, HE_R, TO_R)):
        c = ctx.contact[s]
        floor_h = np.empty(P + 1)   # altura del tobillo con el pie tocando
        for t in range(P + 1):
            R = ctx.foot_rot[s][t] @ REST_ROT[f"Foot.{s}"].T
            floor_h[t] = -(FOOT_VERTS[s] @ R.T)[:, 2].min()
        z = J_all[:, an, 2]
        want = np.where(c, floor_h, np.maximum(z, floor_h))
        delta = want - z
        # Suavizado circular corto del ajuste y se reimpone el piso.
        k = np.array([1, 2, 3, 2, 1], float)
        k /= k.sum()
        ext = np.concatenate([delta[-3:-1], delta, delta[1:3]])
        delta = np.convolve(ext, k, mode="same")[2:-2]
        newz = np.maximum(z + delta, floor_h - 0.003)
        newz[c] = floor_h[c]
        # MediaPipe aplana la altura del pie: en el aire se veía "barriendo"
        # el piso. Se exagera la elevación (en los apoyos es 0, no cambia).
        newz = floor_h + np.maximum(newz - floor_h, 0.0) * SWING_LIFT_GAIN
        shift = newz - z
        for p in (an, he, to):
            J_all[:, p, 2] += shift
    return J_all


# Huesos cuya rotación se suaviza al final. Ni las piernas ni la cadera (su
# padre): el IK ya dejó el pie clavado y suavizarlas lo haría vibrar/patinar.
SMOOTH_BONES = ("Spine", "Chest", "Neck", "Head", "Shoulder.L",
                "Shoulder.R", "UpperArm.L", "UpperArm.R", "LowerArm.L",
                "LowerArm.R", "Hand.L", "Hand.R")


def bake_step(name, data):
    J_all = np.array(data["joints"]) * SCALE   # (P, 33, 3), tamaño del rig
    P = len(J_all)
    # Fotograma P = fotograma 0: el bucle cierra sin salto.
    J_all = np.concatenate([J_all, J_all[:1]], axis=0)
    ctx = StepCtx(J_all, data, by_height=name in STEP_HEIGHT_PITCH)
    # Apoyos agregados a mano: solo bajan el pie al piso y encienden la
    # casilla; la inclinación del pie ya se calculó con los apoyos grabados.
    extra = step_contacts(name, {s: list(ctx.contact[s][:P]) for s in ("L", "R")})
    ctx.contact = {s: np.array(extra[s] + extra[s][:1], bool) for s in ("L", "R")}
    J_all = ground_ankles(J_all, ctx)
    # Pasada 1: cuánto hay que bajar la cadera en cada fotograma; se suaviza
    # (sin quedar por debajo de lo necesario) para que no dé tirones.
    raw = np.array([pose_frame(J_all[t], ctx, t)[2] for t in range(P)])
    wide = np.array([raw[np.arange(t - 4, t + 5) % P].max() for t in range(P)])
    sm = circ_smooth(wide, 2.0)
    ctx.drop = np.append(sm, sm[0])
    basis = []
    for t in range(P + 1):
        rot, hips_loc, _ = pose_frame(J_all[t], ctx, t)
        basis.append(to_basis(rot, hips_loc))
    # Cuaterniones continuos (sin saltos de signo); tronco y brazos además se
    # suavizan.
    quats = {}
    smooth = {BONE[s] for s in SMOOTH_BONES} | \
        (set(SPINE_EXTRA) - {BONE["Hips"]})
    for n in ORDER:
        q = np.array([list(basis[t][n][1]) for t in range(P)])
        for t in range(1, P):
            if np.dot(q[t], q[t - 1]) < 0:
                q[t] = -q[t]
        if n in smooth and np.dot(q[0], q[P - 1]) > 0:
            q = circ_smooth(q, UPPER_SMOOTH)
            q /= np.linalg.norm(q, axis=1, keepdims=True)
        q0 = q[0] if np.dot(q[0], q[P - 1]) >= 0 else -q[0]
        quats[n] = np.concatenate([q, q0[None]], axis=0)
    vals = {}
    for n in ORDER:
        for i in range(4):
            vals[(f'pose.bones["{n}"].rotation_quaternion', i)] = \
                quats[n][:, i].tolist()
    hips = BONE["Hips"]
    for i in range(3):
        vals[(f'pose.bones["{hips}"].location', i)] = \
            [float(basis[t][hips][0][i]) for t in range(P + 1)]
    act = new_action(name, arm)
    set_keys(act, vals)
    push_nla(arm, act, name)
    print(f"  {name}: sesgo cadera/hombros {ctx.hip_bias:.1f}°")
    # La casilla se decide en las mismas coordenadas del piso y del personaje,
    # no en la escala original de los datos (Claire tiene un rig más pequeño).
    return J_all, P, ctx


# --------------------------------------------------------------- dance grid
def make_material(name, rgb, strength, alpha, base=None):
    """Material emisivo. `base` (color difuso) oscuro = el color lo pone la
    emisión y no se lava con la luz de entorno de <model-viewer>."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*(base or rgb), 1.0)
    bsdf.inputs["Emission Color"].default_value = (*rgb, 1.0)
    bsdf.inputs["Emission Strength"].default_value = strength
    bsdf.inputs["Roughness"].default_value = 0.6
    bsdf.inputs["Alpha"].default_value = alpha
    if alpha < 1.0:
        m.surface_render_method = "BLENDED"
    return m


def build_grid(count, cell_size):
    """Casillas reutilizables: cada clip coloca y muestra solo las que necesita."""
    border = cell_size * 0.04
    verts, faces, mats = [], [], []

    def quad(x0, y0, x1, y1, z, mat):
        i = len(verts)
        verts.extend([(x0, y0, z), (x1, y0, z), (x1, y1, z), (x0, y1, z)])
        faces.append((i, i + 1, i + 2, i + 3))
        mats.append(mat)

    h = cell_size / 2
    x0, x1, y0, y1 = -h, h, -h, h
    quad(x0 + border, y0 + border, x1 - border, y1 - border, GRID_Z, 1)
    quad(x0, y0, x1, y0 + border, GRID_Z + 0.001, 0)
    quad(x0, y1 - border, x1, y1, GRID_Z + 0.001, 0)
    quad(x0, y0 + border, x0 + border, y1 - border, GRID_Z + 0.001, 0)
    quad(x1 - border, y0 + border, x1, y1 - border, GRID_Z + 0.001, 0)
    me = bpy.data.meshes.new("mesh_salsa_grid")
    me.from_pydata(verts, [], faces)
    me.polygons.foreach_set("material_index", mats)
    me.materials.append(make_material("mat_salsa_grid", (0.0, 0.65, 0.7),
                                      0.4, 1.0, base=(0.0, 0.04, 0.04)))
    me.materials.append(make_material("mat_salsa_grid_relleno",
                                      (0.01, 0.04, 0.05), 0.15, 1.0))
    grid = bpy.data.objects.new("salsa_dance_grid", None)
    scene.collection.objects.link(grid)

    # Rellenos que se encienden al pisar, uno por pie y cuadro (magenta = pie
    # izquierdo, amarillo = derecho; los mismos colores que la leyenda del
    # visor). Escala ~0 = apagado.
    lit = {"L": make_material("mat_pisada_izq", FOOT_RGB["L"], 1.0, 1.0,
                                base=(0.02, 0.02, 0.02)),
           "R": make_material("mat_pisada_der", FOOT_RGB["R"], 1.0, 1.0,
                                base=(0.02, 0.02, 0.02))}
    cells, pads = {}, {}
    for index in range(count):
        cell = bpy.data.objects.new(f"casilla_{index}", me)
        cell.parent = grid
        cell.scale = (0.001, 0.001, 0.001)
        scene.collection.objects.link(cell)
        cells[index] = cell
        for k, (foot, tag) in enumerate((("L", "izq"), ("R", "der"))):
            s = h - border
            pme = bpy.data.meshes.new(f"mesh_pisada_{index}_{tag}")
            pme.from_pydata([(-s, -s, 0), (s, -s, 0), (s, s, 0), (-s, s, 0)],
                            [], [(0, 1, 2, 3)])
            pme.materials.append(lit[foot])
            ob = bpy.data.objects.new(f"pisada_{index}_pie_{tag}", pme)
            ob.location = (0, 0, GRID_Z + 0.002 + 0.001 * k)
            ob.scale = (0.001, 0.001, 0.001)
            ob.parent = cell
            scene.collection.objects.link(ob)
            pads[(index, foot)] = ob
    return grid, cells, pads


def bake_guide(name, guide, P, cells, pads):
    """El plano no se mueve dentro del clip; las luces siguen los apoyos."""
    # Algunos pasos usan casillas más grandes: se escala la casilla y sus
    # pisadas (hijas de ella) la heredan, con medidas locales sin escalar.
    size = guide.cell_size / (CELL * SCALE)
    local_cell = CELL * SCALE
    for index, ob in cells.items():
        used = index < len(guide.centers)
        xy = guide.centers[index] if used else (0, 0)
        act = new_action(f"{name}__{ob.name}", ob)
        vals = {("location", 0): [float(xy[0])] * (P + 1),
                ("location", 1): [float(xy[1])] * (P + 1),
                ("location", 2): [0.0] * (P + 1)}
        vals.update({("scale", axis): [size if used else 0.001] * (P + 1)
                     for axis in range(3)})
        set_keys(act, vals)
        push_nla(ob, act, name)
    usage = {}
    for key, ob in pads.items():
        index, foot = key
        v = (guide.assignments[foot] == index).astype(float)
        sm = v.copy()
        for k in (1, 2):
            sm = np.maximum(sm, np.roll(v, k) * (1 - k / 3))
        sc = np.maximum(0.001, np.append(sm, sm[0]))
        act = new_action(f"{name}__{ob.name}", ob)
        shared = name not in STEP_SOLID_CELLS and all(
            np.any(assigned == index) for assigned in guide.assignments.values())
        # Solo las casillas compartidas dividen sus colores; las otras se
        # iluminan completas. Se reinicia también la posición al cambiar de clip.
        half = (local_cell / 2 - local_cell * 0.04) / 2
        dx = half * (1 if foot == "L" else -1) if shared else 0.0
        vals = {("scale", 0): (sc * (0.48 if shared else 1.0)).tolist(),
                ("scale", 1): sc.tolist(), ("scale", 2): sc.tolist(),
                ("location", 0): [dx] * (P + 1),
                ("location", 1): [0.0] * (P + 1),
                ("location", 2): [GRID_Z + 0.002 + (0.001 if foot == "R" else 0)] * (P + 1)}
        set_keys(act, vals)
        push_nla(ob, act, name)
        if v.any():
            usage[f"{index}/{foot}"] = float(v.mean())
    return usage


# ------------------------------------------------------------------- main
with open(CLEAN, encoding="utf-8") as f:
    clean = json.load(f)
FOOT_VERTS = foot_vertices()
steps = {}
for name, data in clean.items():
    J_all, P, ctx = bake_step(name, data)
    guide = plan_guide(J_all, P, ctx.contact, scale=SCALE,
                       overrides=STEP_OVERRIDES.get(name, ()),
                       mirror=STEP_MIRRORS.get(name),
                       **STEP_GRIDS.get(name, {}))
    steps[name] = (P, guide)
grid, cells, pads = build_grid(max(len(guide.centers) for _, guide in steps.values()),
                              CELL * SCALE)
for name, (P, guide) in steps.items():
    usage = bake_guide(name, guide, P, cells, pads)
    print(f"PASO {name}: {len(guide.centers)} casillas, {P} fotogramas "
          + " ".join(f"{k}={v:.0%}" for k, v in usage.items()))

scene.frame_start = 0
# El exportador toma la pose "por defecto" de cada nodo del estado actual de
# la escena (con las pistas NLA activas): sin esto un relleno encendido en el
# fotograma 0 del básico quedaba con escala 1 por defecto y, en los pasos que
# no lo animan, se veía siempre prendido. Se silencian las pistas, se dejan
# los rellenos apagados y además se exportan sus canales aunque sean
# constantes.
for ob in scene.objects:
    if ob.animation_data:
        for tr in ob.animation_data.nla_tracks:
            tr.mute = True
for ob in list(cells.values()) + list(pads.values()):
    ob.scale = (0.001, 0.001, 0.001)
scene.frame_set(0)
bpy.ops.export_scene.gltf(
    filepath=OUT,
    export_format="GLB",
    export_animation_mode="NLA_TRACKS",
    export_force_sampling=True,
    export_optimize_animation_size=True,
    export_optimize_animation_keep_anim_object=True,
    # Huesos que solo siguen a su padre (pelo, falda, dedos…) no llevan
    # canales: el GLB del personaje queda mucho más liviano.
    export_optimize_animation_keep_anim_armature=False,
    export_def_bones=False,
    export_cameras=False,
    export_lights=False,
    export_apply=False,
)
print("EXPORTADO", OUT)
