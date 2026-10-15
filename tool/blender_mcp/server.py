"""Servidor MCP (stdio, sin dependencias) para manejar Blender en modo headless.

Herramientas:
  - blender_run_python: ejecuta código Python dentro de Blender (opcionalmente
    abriendo antes un .glb/.blend) y devuelve la salida.
  - blender_render_preview: renderiza una tira de fotogramas de una animación
    del GLB (usa tool/anim3d/preview.py) y devuelve la ruta del PNG.
  - blender_build_dance_glb: regenera assets/models/DanceGrid1.glb desde los
    landmarks (tool/anim3d/build_glb.py).

Blender se busca en $BLENDER_EXE, en "D:/Program Files" o en "C:/Program Files".
Registro: ver `.mcp.json` en la raíz del repo.
"""

import json
import os
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(
    __file__))))
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


def blender_exe():
    return find_blender()


def run_blender(args, timeout=900):
    proc = subprocess.run(
        [blender_exe(), "-b", "--factory-startup", *args],
        cwd=ROOT, capture_output=True, text=True, encoding="utf-8",
        errors="replace", timeout=timeout)
    out = proc.stdout + proc.stderr
    # Se recorta el ruido de arranque de Blender.
    lines = [l for l in out.splitlines()
             if not l.startswith(("Blender ", "Read prefs", "Color management"))]
    return proc.returncode, "\n".join(lines[-400:])


def tool_run_python(args):
    code = args["code"]
    pre = ""
    if args.get("open"):
        path = os.path.abspath(os.path.join(ROOT, args["open"]))
        if path.lower().endswith(".blend"):
            pre = f"import bpy\nbpy.ops.wm.open_mainfile(filepath={path!r})\n"
        else:
            pre = ("import bpy\nbpy.ops.wm.read_factory_settings(use_empty=True)"
                   f"\nbpy.ops.import_scene.gltf(filepath={path!r})\n")
    with tempfile.NamedTemporaryFile("w", suffix=".py", delete=False,
                                     encoding="utf-8") as f:
        f.write(pre + code)
        script = f.name
    try:
        rc, out = run_blender(["--python-exit-code", "1", "-P", script])
    finally:
        os.unlink(script)
    return f"exit {rc}\n{out}"


def tool_render_preview(args):
    out = args.get("output") or os.path.join(
        tempfile.gettempdir(), f"preview_{args['action']}.png")
    rc, log = run_blender([
        "-P", os.path.join(ROOT, "tool", "anim3d", "preview.py"), "--",
        args.get("glb", "assets/models/DanceGrid1.glb"), args["action"], out,
        str(args.get("frames", 8)), args.get("view", "persp")])
    return f"exit {rc}\nPNG: {out}\n{log[-2000:]}"


def tool_build(args):
    cmd = [sys.executable, os.path.join(ROOT, "tool", "anim3d", "build.py")]
    proc = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True,
                          encoding="utf-8", errors="replace", timeout=1800)
    return f"exit {proc.returncode}\n{(proc.stdout + proc.stderr)[-6000:]}"


TOOLS = {
    "blender_run_python": (tool_run_python, {
        "description": "Ejecuta código Python (bpy) en Blender headless. "
                       "'open' carga antes un .glb o .blend del repo.",
        "inputSchema": {"type": "object", "properties": {
            "code": {"type": "string"},
            "open": {"type": "string",
                     "description": "Ruta relativa al repo (.glb/.blend)"}},
            "required": ["code"]}}),
    "blender_render_preview": (tool_render_preview, {
        "description": "Renderiza una tira PNG de fotogramas de una animación "
                       "del GLB (vista front/side/top/persp).",
        "inputSchema": {"type": "object", "properties": {
            "action": {"type": "string"},
            "glb": {"type": "string"},
            "output": {"type": "string"},
            "frames": {"type": "integer"},
            "view": {"type": "string",
                     "enum": ["front", "side", "top", "persp"]}},
            "required": ["action"]}}),
    "blender_build_dance_glb": (tool_build, {
        "description": "Regenera assets/models/DanceGrid1.glb (animaciones "
                       "limpias + cuadros del piso) desde los landmarks.",
        "inputSchema": {"type": "object", "properties": {}}}),
}


def reply(msg_id, result=None, error=None):
    msg = {"jsonrpc": "2.0", "id": msg_id}
    if error:
        msg["error"] = error
    else:
        msg["result"] = result
    sys.stdout.write(json.dumps(msg) + "\n")
    sys.stdout.flush()


def main():
    for line in sys.stdin:
        if not line.strip():
            continue
        req = json.loads(line)
        method, msg_id = req.get("method"), req.get("id")
        if msg_id is None:  # notificación
            continue
        if method == "initialize":
            reply(msg_id, {
                "protocolVersion": req["params"].get("protocolVersion",
                                                     "2024-11-05"),
                "capabilities": {"tools": {}},
                "serverInfo": {"name": "blender", "version": "1.0"}})
        elif method == "tools/list":
            reply(msg_id, {"tools": [dict(name=n, **meta)
                                     for n, (_, meta) in TOOLS.items()]})
        elif method == "tools/call":
            name = req["params"]["name"]
            try:
                text = TOOLS[name][0](req["params"].get("arguments") or {})
                reply(msg_id, {"content": [{"type": "text", "text": text}]})
            except Exception as e:  # noqa: BLE001
                reply(msg_id, {"content": [{"type": "text",
                                            "text": f"error: {e}"}],
                               "isError": True})
        elif method == "ping":
            reply(msg_id, {})
        else:
            reply(msg_id, error={"code": -32601, "message": "method not found"})


if __name__ == "__main__":
    main()
