"""Render clearly labelled illustrations from the actual Lua settings widgets."""
from pathlib import Path
import os

from lupa.lua51 import LuaRuntime
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "docs" / "images"
OUT.mkdir(parents=True, exist_ok=True)
SCALE = 2
WIDTH, HEIGHT = 1000, 810
GOLD, WHITE, MUTED = "#ddbd79", "#e9e3d7", "#a29c91"
FONT_DIR = Path(os.environ.get("WINDIR", "C:/Windows")) / "Fonts"


def font(size, title=False):
    candidate = FONT_DIR / ("georgia.ttf" if title else "segoeui.ttf")
    if candidate.exists():
        return ImageFont.truetype(str(candidate), round(size * SCALE))
    return ImageFont.truetype("DejaVuSans.ttf", round(size * SCALE))


def box(draw, rect, fill, outline=None, radius=0):
    draw.rounded_rectangle(tuple(round(v * SCALE) for v in rect), radius=radius * SCALE,
                           fill=fill, outline=outline, width=SCALE)


def text(draw, xy, value, size=14, color=WHITE, title=False, width=None):
    face = font(size, title)
    lines = []
    for paragraph in str(value).splitlines():
        if not width:
            lines.append(paragraph)
            continue
        line = ""
        for word in paragraph.split():
            trial = (line + " " + word).strip()
            if line and draw.textlength(trial, font=face) > width * SCALE:
                lines.append(line)
                line = word
            else:
                line = trial
        lines.append(line)
    for index, line in enumerate(lines):
        draw.text((xy[0] * SCALE, (xy[1] + index * (size + 3)) * SCALE), line, font=face, fill=color)


def button(draw, x, y, width, height, label, enabled=True):
    box(draw, (x, y, x + width, y + height), "#4a2625" if enabled else "#272422", "#8a6b48", 3)
    box(draw, (x + 2, y + 2, x + width - 2, y + height - 2), "#632f2c" if enabled else "#302c29", None, 2)
    face = font(12)
    label_width = draw.textlength(str(label), font=face) / SCALE
    text(draw, (x + (width - label_width) / 2, y + 3), label, 12, WHITE if enabled else MUTED)


def point(obj):
    points = obj._points
    if not points or not len(points):
        return None
    first = points[1]
    if first[1] == "TOPLEFT" and isinstance(first[2], (int, float)):
        return float(first[2]), -float(first[3] or 0)
    return None


def render(env, state, key, filename):
    page = env.SmallerUIOptions if key == "scaling" else env.SmallerUIReadyPage
    page_id, content_id = page.uid, page.content.uid
    coordinates = {page_id: (0, 0), page.content.uid: (16, 90), page.scroll.uid: (16, 90)}

    def belongs(obj):
        current = obj
        while current is not None:
            if current.uid == page_id:
                return True
            current = current.parent
        return False

    def position(obj):
        if obj.uid in coordinates:
            return coordinates[obj.uid]
        offset = point(obj)
        if offset is None or obj.parent is None:
            return None
        origin = position(obj.parent)
        if origin is None:
            return None
        result = origin[0] + offset[0], origin[1] + offset[1]
        coordinates[obj.uid] = result
        return result

    canvas = Image.new("RGBA", (680 * SCALE, 552 * SCALE), "#171615")
    draw = ImageDraw.Draw(canvas)
    for _, obj in state.objects.items():
        if not belongs(obj) or not obj.IsVisible(obj):
            continue
        origin = position(obj)
        if origin is None:
            continue
        x, y = origin
        width, height = float(obj.width or 0), float(obj.height or 0)
        if obj.kind == "Texture" and obj.color and height == 1:
            box(draw, (x, y, 628, y + 1), "#625238")
        elif obj.kind == "FontString" and obj.text:
            style = str(obj.font or "GameFontHighlight")
            color = MUTED if "Disable" in style else GOLD if "Normal" in style else WHITE
            size = 17 if "Large" in style else 11 if "Small" in style else 13
            text(draw, (x, y), obj.text, size, color, "Large" in style, width or None)
        elif obj.kind == "Slider":
            title = obj.Text.text if obj.Text else ""
            text(draw, (x, y - 23), title, 13, GOLD)
            box(draw, (x, y + 5, x + width, y + 11), "#080808", "#625238", 2)
            ratio = (float(obj.value or obj.low) - float(obj.low)) / (float(obj.high) - float(obj.low))
            thumb = x + ratio * width
            box(draw, (thumb - 5, y - 2, thumb + 5, y + 18), "#d2b47b", "#f5dfa3", 2)
            text(draw, (x, y + 23), obj.Low.text, 11, MUTED)
            text(draw, (x + width - 24, y + 23), obj.High.text, 11, MUTED)
        elif obj.kind == "EditBox":
            box(draw, (x, y, x + width, y + height), "#0b0a09", "#75654b", 3)
            text(draw, (x + 8, y + 3), obj.text, 13)
        elif obj.kind == "CheckButton":
            box(draw, (x + 3, y + 3, x + 22, y + 22), "#0d0c0a", "#8a7551", 2)
            if obj.checked:
                draw.line([(int(v[0] * SCALE), int(v[1] * SCALE)) for v in
                           ((x + 7, y + 12), (x + 11, y + 17), (x + 20, y + 7))], fill=GOLD, width=3 * SCALE)
            if obj.Text and obj.Text.text:
                text(draw, (x + 31, y + 4), obj.Text.text, 13)
        elif obj.kind == "Button" and width:
            button(draw, x, y, width, height, obj.text, obj.enabled is not False)

    image = Image.new("RGBA", (WIDTH * SCALE, HEIGHT * SCALE), "#101316")
    shadow = Image.new("RGBA", image.size)
    box(ImageDraw.Draw(shadow), (18, 48, 982, 778), "#000000", None, 12)
    image.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(12)))
    outer = ImageDraw.Draw(image)
    box(outer, (20, 44, 980, 770), "#25211d", "#a18c65", 9)
    box(outer, (26, 50, 974, 764), "#181716", "#564b39", 6)
    box(outer, (30, 54, 970, 96), "#302922", "#68583f", 4)
    text(outer, (451, 62), "Settings", 20, GOLD, True)
    button(outer, 938, 61, 25, 24, "X")
    text(outer, (52, 112), "Game", 14, MUTED)
    text(outer, (132, 112), "AddOns", 14, GOLD)
    box(outer, (128, 137, 199, 139), GOLD)
    box(outer, (42, 154, 248, 706), "#121110", "#514837", 3)
    box(outer, (54, 170, 236, 198), "#0b0b0a", "#574c37", 3)
    text(outer, (64, 176), "Search", 12, "#807b71")
    if key == "scaling":
        box(outer, (50, 214, 240, 246), "#4b3d27", None, 2)
    else:
        box(outer, (50, 250, 240, 282), "#4b3d27", None, 2)
    text(outer, (61, 221), "v  Smaller UI", 14, GOLD)
    text(outer, (82, 258), "Cooldown flashes", 12, GOLD if key == "cooldowns" else WHITE)
    box(outer, (264, 150, 958, 710), "#171615", "#514837", 3)
    image.alpha_composite(canvas, (274 * SCALE, 154 * SCALE))
    box(outer, (937, 174, 942, 686), "#34302a", None, 2)
    thumb_end = 588 if key == "scaling" else 686
    box(outer, (936, 175, 943, thumb_end), "#9d8966", None, 2)
    button(outer, 837, 725, 112, 25, "Close")
    text(outer, (287, 783), "Illustrative UI preview - not an in-game screenshot", 11, MUTED)
    image.convert("RGB").save(OUT / filename, optimize=True)
    print((OUT / filename).relative_to(ROOT))


lua = LuaRuntime(unpack_returned_tuples=True)
manifest = (ROOT / "SmallerUI" / "SmallerUI.toc").read_text()
lua.globals().addon_sources = lua.table_from([
    (ROOT / "SmallerUI" / line.strip()).read_text()
    for line in manifest.splitlines() if line.strip().endswith(".lua")
])
boot = lua.execute((ROOT / "tests" / "smaller_ui_test.lua").read_text())
preferences = lua.table_from({"scale": 0.4, "enabled": True, "readyFlash": True,
                              "elements": lua.table_from({"chat": 1, "actionbars": 0.85})})
character = lua.table_from({"readySlots": lua.table_from({"ActionButton1": True, "MultiBarBottomLeftButton2": True})})
env, state, *_ = boot(preferences, character)
state.addon.ShowOptions(state.addon, "scaling")
render(env, state, "scaling", "ui-scale-preview.png")
state.addon.ShowOptions(state.addon, "cooldowns")
render(env, state, "cooldowns", "cooldown-flashes-preview.png")
