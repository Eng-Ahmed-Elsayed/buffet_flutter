"""Builds the launcher icons from the Digital Egypt mark.

The source is the logo exported from Figma (design/figma/logo.png): the mark
over the DIGITAL EGYPT FOR INVESTMENT wordmark, on a transparent ground. The
whole mark is about 5:1 and the wordmark is unreadable at 48px, so the icon
uses the *peaks*: the three mountains and their circuit trace, the distinctive
and least-wide part of the logo, in its own navy-to-violet gradient.

The logo is never recoloured (CLAUDE.md); only the ground behind it is chosen.
It is white, the logo's own ground, which is where its navy end reads best.
"""

from PIL import Image

MARK = 'design/figma/logo.png'

# The peaks and the baseline bar they stand on, cut square at both sides.
# The bar is taken whole: the diagonals end on it, and stopping above it
# truncated them and left a sliver of the bar as a hairline.
PEAK_BOX = (1330, 1460, 2900, 2070)

# The page's `surface` in lib/theme/brand_colors.dart. Mirrored in
# android/app/src/main/res/values/ic_launcher_background.xml.
GROUND = (255, 255, 255, 255)


def _peak():
    """The peaks, trimmed to their own ink.

    Trimming matters: the crop box is generous, so without this the glyph
    sits off centre with dead space around it.
    """
    peak = Image.open(MARK).convert('RGBA').crop(PEAK_BOX)
    bbox = peak.split()[3].getbbox()
    return peak.crop(bbox) if bbox else peak


def icon(size, fraction=0.70, transparent=False):
    """The peaks centred on the ground.

    `fraction` keeps the glyph inside the safe zone — Android masks launcher
    icons to a circle or squircle, so anything nearer the edge is clipped.
    """
    base = (Image.new('RGBA', (size, size), (0, 0, 0, 0))
            if transparent else Image.new('RGBA', (size, size), GROUND))
    peak = _peak()
    target_w = max(1, round(size * fraction))
    scale = target_w / peak.width
    m = peak.resize((target_w, max(1, round(peak.height * scale))),
                    Image.LANCZOS)
    base.alpha_composite(m, ((size - m.width) // 2, (size - m.height) // 2))
    return base


def foreground(size, fraction=0.54):
    """Adaptive-icon foreground: transparent, and smaller again because
    Android reserves the outer third of the layer for parallax and masking.

    0.54 puts the glyph's corners at 0.29 of the layer from its centre, just
    inside the 0.305 radius (66dp of 108dp) that every mask shape keeps."""
    return icon(size, fraction=fraction, transparent=True)


def monochrome(size, fraction=0.54):
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
