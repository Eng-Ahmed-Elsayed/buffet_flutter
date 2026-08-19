"""Builds the launcher icons from the Digital Egypt mark.

The full mark is 5.11:1 — far too wide to read at 48px, and its navy end
disappears against a navy ground. So the icon uses the *peak*: the mountain
plus its circuit trace, the distinctive and near-square part of the logo,
carrying the same navy-to-violet gradient the palette is sampled from.

The logo is never recoloured (CLAUDE.md); only the ground behind it is chosen,
and it is taken from the existing brand tokens.
"""

from PIL import Image

MARK = 'assets/images/logo-defi-mark.png'

# The peak, located by where the top ink row rises above the horizontal rules.
PEAK_BOX = (100, 0, 252, 63)

# Sampled from lib/theme/brand_colors.dart — not new colours.
BRAND_DARK = (11, 30, 75)    # 0xFF0B1E4B
BRAND = (18, 58, 122)        # 0xFF123A7A


def _peak():
    """The peak, trimmed to its own ink.

    Trimming matters: the crop box keeps the mark's full height, so without
    this the glyph sits low in the frame with dead space beneath it.
    """
    peak = Image.open(MARK).convert('RGBA').crop(PEAK_BOX)
    bbox = peak.split()[3].getbbox()
    return peak.crop(bbox) if bbox else peak


def _ground(size):
    """Diagonal brand gradient. Dark enough that the mark's navy end still
    separates from it, which a flat brand fill did not."""
    g = Image.new('RGBA', (size, size))
    px = g.load()
    last = max(1, size - 1)
    for y in range(size):
        for x in range(size):
            t = (x + y) / (2 * last)
            px[x, y] = (
                round(BRAND_DARK[0] + (BRAND[0] - BRAND_DARK[0]) * t),
                round(BRAND_DARK[1] + (BRAND[1] - BRAND_DARK[1]) * t),
                round(BRAND_DARK[2] + (BRAND[2] - BRAND_DARK[2]) * t),
                255,
            )
    return g


def icon(size, fraction=0.62, transparent=False):
    """The peak centred on the ground.

    `fraction` keeps the glyph inside the safe zone — Android masks launcher
    icons to a circle or squircle, so anything nearer the edge is clipped.
    """
    base = (Image.new('RGBA', (size, size), (0, 0, 0, 0))
            if transparent else _ground(size))
    peak = _peak()
    target_w = max(1, round(size * fraction))
    scale = target_w / peak.width
    m = peak.resize((target_w, max(1, round(peak.height * scale))),
                    Image.LANCZOS)
    base.alpha_composite(m, ((size - m.width) // 2, (size - m.height) // 2))
    return base


def foreground(size, fraction=0.42):
    """Adaptive-icon foreground: transparent, and smaller again because
    Android reserves the outer third of the layer for parallax and masking."""
    return icon(size, fraction=fraction, transparent=True)


def monochrome(size, fraction=0.42):
    """Android 13 themed-icon layer.

    The system tints this layer with the user's wallpaper palette, so it must
    be a flat silhouette: a gradient here is recoloured unpredictably. The
    alpha channel is kept and the colour flattened to white.
    """
    layer = foreground(size, fraction=fraction)
    alpha = layer.split()[3]
    out = Image.new('RGBA', layer.size, (255, 255, 255, 0))
    out.putalpha(alpha)
    white = Image.new('RGBA', layer.size, (255, 255, 255, 255))
    white.putalpha(alpha)
    return white


def main():
    """Regenerates every launcher icon from the mark.

    Run from the repo root with Pillow available:

        python tool/generate_launcher_icons.py

    Deliberately a script rather than a `flutter_launcher_icons` dependency —
    §10 settled the stack, and this needs no package at build time.
    """
    import json

    densities = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96,
                 'xxhdpi': 144, 'xxxhdpi': 192}

    for dpi, size in densities.items():
        d = f'android/app/src/main/res/mipmap-{dpi}'
        icon(size).save(f'{d}/ic_launcher.png')
        # Adaptive layers are 108dp where the legacy icon is 48dp.
        adaptive = round(size * 108 / 48)
        foreground(adaptive).save(f'{d}/ic_launcher_foreground.png')
        monochrome(adaptive).save(f'{d}/ic_launcher_monochrome.png')

    p = 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
    with open(f'{p}/Contents.json', encoding='utf-8') as f:
        meta = json.load(f)
    for entry in meta['images']:
        filename = entry.get('filename')
        if not filename:
            continue
        width = float(entry['size'].split('x')[0])
        scale = int(entry['scale'].rstrip('x'))
        # Flattened to RGB: the App Store icon must carry no alpha channel.
        icon(round(width * scale)).convert('RGB').save(f'{p}/{filename}')

    print('launcher icons regenerated')


if __name__ == '__main__':
    main()
