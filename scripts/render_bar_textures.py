"""Generate the tintable bar surfaces and trim used by the class themes."""
from math import cos, exp, hypot, pi
from pathlib import Path
from struct import pack


MEDIA = Path(__file__).resolve().parents[1] / "SmallerUI" / "Media"


def channel(value):
    return round(255 * max(0, min(1, value)))


def write_texture(name, width, height, sample):
    # Uncompressed BGRA with an upper-left origin and eight alpha bits.
    header = pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, width, height, 32, 0x28)
    pixels = bytearray()
    for y in range(height):
        for x in range(width):
            gray, alpha = sample((x + 0.5) / width, (y + 0.5) / height)
            shade = channel(gray)
            pixels.extend((shade, shade, shade, channel(alpha)))
    (MEDIA / f"{name}.tga").write_bytes(header + pixels)


def satin(x, y):
    highlight = 0.13 * exp(-((y - 0.18) / 0.32) ** 2)
    return 0.88 - 0.24 * y + highlight + 0.025 * cos((x - 0.42) * 2 * pi)


def etched(x, y):
    # Recessed chevrons with a highlight on the lower edge of each cut.
    distance = (x * 12 + abs(y - 0.5) * 0.46) % 1
    cut = 0.15 * exp(-((distance - 0.5) / 0.11) ** 2)
    lip = 0.08 * exp(-((distance - 0.67) / 0.09) ** 2)
    return satin(x, y) + lip - cut


def woven(x, y):
    along = cos((x * 16 + y * 0.72) * 2 * pi)
    across = cos((x * 16 - y * 0.72) * 2 * pi)
    return satin(x, y) + 0.08 * (along + across) / 2 - 0.075 * along * across


def jewel(x, y):
    distance = abs(x - 0.5) + abs(y - 0.5)
    coverage = (0.48 - distance) * 16
    if distance > 0.34:
        return 0.24 + 0.3 * (1 - y), coverage
    facet = 0.97 if y < x and x + y < 1 else 0.83 if y < 0.5 else 0.61
    return facet, coverage


def arc(x, y, outline=False):
    # Round-ended stroke. The left curve bows out by 25 units at its midpoint.
    end = min(0.974, max(0.026, y))
    centre = 0.22 + 0.60 * (2 * end - 1) ** 2
    radius = 4.2 + 1.7 * (1 - abs(2 * end - 1))
    distance = hypot((x - centre) * 42, (y - end) * 216)
    fill = max(0, min(1, (radius - distance) * 3 + 0.5))
    outer = max(0, min(1, (radius + 1 - distance) * 3 + 0.5))
    return 1, outer - fill if outline else fill


if __name__ == "__main__":
    for name, surface in (("Satin", satin), ("Etched", etched), ("Woven", woven)):
        write_texture(name, 128, 32, lambda x, y: (surface(x, y), 1))
    write_texture("TrimJewel", 16, 16, jewel)
    write_texture("ArcFill", 128, 512, arc)
    write_texture("ArcOutline", 128, 512, lambda x, y: arc(x, y, outline=True))
