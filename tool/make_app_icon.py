"""Genera los íconos de la app (Android, iOS y web) desde una sola imagen.

Uso: python tool/make_app_icon.py [assets/icon/bailongo_icon.png]

La imagen es cuadrada (1024x1024) y a sangre completa, con fondo liso.
Android 8+ recorta el ícono adaptable con su propia forma (círculo, gota...)
y sólo deja ver el 66 % central, así que ahí el dibujo se reduce y el resto
se rellena con el color del fondo para que no se corten la figura ni el aro.
"""

import json
import os
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    ROOT, 'assets', 'icon', 'bailongo_icon.png')

# Escala del dibujo dentro del ícono adaptable de Android y del maskable web.
ADAPTIVE_SCALE = 0.66


def save(img, path, size):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.resize((size, size), Image.LANCZOS).save(path, optimize=True)


def padded(img, scale):
    """El dibujo reducido a [scale] sobre un lienzo del color del fondo."""
    w = img.width
    bg = img.getpixel((0, 0))
    canvas = Image.new('RGB', (w, w), bg)
    inner = img.resize((round(w * scale),) * 2, Image.LANCZOS)
    off = (w - inner.width) // 2
    canvas.paste(inner, (off, off))
    return canvas


def main():
    img = Image.open(SRC).convert('RGB')  # iOS rechaza íconos con alfa
    assert img.width == img.height, 'la imagen debe ser cuadrada'
    bg = '#%02X%02X%02X' % img.getpixel((0, 0))

    # Android: ícono clásico por densidad + ícono adaptable (API 26+).
    res = os.path.join(ROOT, 'android', 'app', 'src', 'main', 'res')
    legacy = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144,
              'xxxhdpi': 192}
    fg = padded(img, ADAPTIVE_SCALE)
    for dpi, size in legacy.items():
        save(img, os.path.join(res, f'mipmap-{dpi}', 'ic_launcher.png'), size)
        # El primer plano adaptable mide 108 dp (48 dp * 2.25).
        save(fg, os.path.join(res, f'mipmap-{dpi}',
                              'ic_launcher_foreground.png'), size * 9 // 4)
    anydpi = os.path.join(res, 'mipmap-anydpi-v26')
    os.makedirs(anydpi, exist_ok=True)
    with open(os.path.join(anydpi, 'ic_launcher.xml'), 'w',
              encoding='utf-8', newline='\n') as f:
        f.write('<?xml version="1.0" encoding="utf-8"?>\n'
                '<adaptive-icon xmlns:android='
                '"http://schemas.android.com/apk/res/android">\n'
                '    <background android:drawable="@color/ic_launcher_background"/>\n'
                '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
                '</adaptive-icon>\n')
    with open(os.path.join(res, 'values', 'ic_launcher_background.xml'), 'w',
              encoding='utf-8', newline='\n') as f:
        f.write('<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
                f'    <color name="ic_launcher_background">{bg}</color>\n'
                '</resources>\n')

    # iOS: todos los tamaños que pide el AppIcon.appiconset.
    icons = os.path.join(ROOT, 'ios', 'Runner', 'Assets.xcassets',
                         'AppIcon.appiconset')
    with open(os.path.join(icons, 'Contents.json'), encoding='utf-8') as f:
        spec = json.load(f)
    for entry in spec['images']:
        pts = float(entry['size'].split('x')[0])
        px = round(pts * int(entry['scale'][0]))
        save(img, os.path.join(icons, entry['filename']), px)

    # Web (PWA).
    web = os.path.join(ROOT, 'web')
    for size in (192, 512):
        save(img, os.path.join(web, 'icons', f'Icon-{size}.png'), size)
        save(padded(img, 0.8), os.path.join(
            web, 'icons', f'Icon-maskable-{size}.png'), size)
    save(img, os.path.join(web, 'favicon.png'), 32)
    print('íconos generados desde', SRC)


if __name__ == '__main__':
    main()
