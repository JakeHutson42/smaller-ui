"""Render clearly labelled illustrations from the actual Lua settings widgets."""
from pathlib import Path
import os

from lupa.lua51 import LuaRuntime
from PIL import Image, ImageChops, ImageDraw, ImageFont, ImageFilter

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
    box(draw, (x, y, x + width, y + height), "#1b2633" if enabled else "#171c21", "#7f6a49", 3)
    box(draw, (x + 2, y + 2, x + width - 2, y + height - 2), "#23303e" if enabled else "#1d242c", None, 2)
    face = font(12)
    label_width = draw.textlength(str(label), font=face) / SCALE
    text(draw, (x + (width - label_width) / 2, y + 3), label, 12, WHITE if enabled else MUTED)


def point(obj):
    points = obj._points
    if not points or not len(points):
        return None
    first = points[1]
    if first[1] == "TOPLEFT":
        if first[2] is None:
            return 0, 0
        if isinstance(first[2], (int, float)):
            return float(first[2]), -float(first[3] or 0)
    return None


def render(env, state, key, filename, content_offset=0, texture_menu=False):
    page = {"scaling": env.SmallerUIOptions,
            "resources": env.SmallerUIPersonalOptions, "party": env.SmallerUIPartyOptions,
            "pet": env.SmallerUIPetOptions, "swing": env.SmallerUISwingOptions}[key]
    extra_height = {"resources": 228, "party": 258, "pet": 210}.get(key, 0)
    page_id, content_id = page.uid, page.content.uid
    coordinates = {page_id: (0, 0), page.content.uid: (16, 90 - content_offset), page.scroll.uid: (16, 90)}

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

    canvas = Image.new("RGBA", (680 * SCALE, (552 + extra_height) * SCALE), "#171615")
    draw = ImageDraw.Draw(canvas)
    for _, obj in state.objects.items():
        if not belongs(obj) or not obj.IsVisible(obj):
            continue
        origin = position(obj)
        if origin is None:
            continue
        x, y = origin
        if content_offset and y < 90:
            ancestor = obj
            inside_content = False
            while ancestor is not None:
                if ancestor.uid == content_id:
                    inside_content = True
                    break
                ancestor = ancestor.parent
            if inside_content:
                continue
        width, height = float(obj.width or 0), float(obj.height or 0)
        if obj.kind == "Texture" and obj.color and height == 1:
            box(draw, (x, y, 628, y + 1), "#625238")
        elif obj.kind == "Texture" and obj.color and width and height:
            rgb = tuple(round(float(obj.color[index]) * 255) for index in (1, 2, 3))
            box(draw, (x, y, x + width, y + height), rgb, "#a89877", 1)
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
        elif obj.kind == "DropdownButton":
            box(draw, (x, y, x + width, y + height), "#211e19", "#75654b", 3)
            text(draw, (x + 8, y + 4), obj.text, 12)
            draw.polygon([(round(px * SCALE), round(py * SCALE)) for px, py in
                          ((x + width - 16, y + 11), (x + width - 8, y + 11), (x + width - 12, y + 16))], fill=GOLD)
        elif obj.kind == "EditBox":
            box(draw, (x, y, x + width, y + height), "#0b0a09", "#75654b", 3)
            text(draw, (x + 8, y + 3), obj.text, 13, MUTED if obj.enabled is False else WHITE)
        elif obj.kind == "Button" and obj.checked is not None:
            accent = GOLD if obj.checked and obj.enabled is not False else MUTED
            box(draw, (x + 2, y + 5, x + 38, y + 23), "#224738" if obj.checked else "#111820", accent, 3)
            thumb = x + (22 if obj.checked else 6)
            box(draw, (thumb, y + 8, thumb + 12, y + 20), accent, None, 2)
        elif obj.kind == "Button" and width and obj.stepper:
            box(draw, (x, y, x + width, y + height), "#27231c", "#75654b", 2)
            cx, cy = x + width / 2, y + height / 2
            direction = float(obj.stepDirection)
            draw.polygon([(round(px * SCALE), round(py * SCALE)) for px, py in
                          ((cx - 4, cy + direction * 2), (cx + 4, cy + direction * 2), (cx, cy - direction * 3))], fill=MUTED if obj.enabled is False else GOLD)
        elif obj.kind == "Button" and width:
            button(draw, x, y, width, height, obj.text, obj.enabled is not False)

    if key == "swing":
        preview = env.SmallerUISwingPreview
        x, y = position(preview)
        y += float(preview.height) / 2
        width, thickness = float(preview.width), float(preview.bar.height)
        fill = width * float(preview.bar.value)
        rgb = tuple(round(preview.bar.barColor[index] * 255) for index in (1, 2, 3))
        box(draw, (x, y - thickness / 2, x + width, y + thickness / 2), "#353b47")
        box(draw, (x, y - thickness / 2, x + fill, y + thickness / 2), rgb)
        if preview.bar.dot.IsShown(preview.bar.dot):
            radius = float(preview.bar.dot.width) / 2
            draw.ellipse(tuple(round(value * SCALE) for value in
                (x + fill - radius, y - radius, x + fill + radius, y + radius)), fill=rgb)

    if texture_menu:
        dropdown = env.SmallerUIPersonalBarTexture
        dropdown.GenerateMenu(dropdown)
        x, y = position(dropdown)
        y += float(dropdown.height) + 1
        box(draw, (x, y, x + 252, y + 8 + len(dropdown.menu) * 22), "#26231d", "#91805c", 4)
        rgb = tuple(round(value * 255) for value in state.addon.GetResourceColour(state.addon, "player", "health"))
        for index, row in dropdown.menu.items():
            swatch = dropdown.CreateTexture(dropdown)
            row.initialize(lua.table_from({"AttachTexture": lambda _: swatch}))
            texture = swatch.textureValue.rsplit("\\", 1)[-1]
            if texture.endswith(".tga"):
                with Image.open(ROOT / "SmallerUI" / "Media" / texture) as asset:
                    art = asset.convert("RGB")
            else:
                art = Image.new("RGB", (64, 32), "white")
            sample = ImageChops.multiply(art, Image.new("RGB", art.size, rgb)).resize((112 * SCALE, 12 * SCALE))
            row_y = y + 4 + (index - 1) * 22
            text(draw, (x + 9, row_y + 1), "●" if row.label == dropdown.text else "○", 11, GOLD)
            text(draw, (x + 29, row_y + 1), row.label, 12, WHITE)
            canvas.paste(sample, (round((x + 132) * SCALE), round((row_y + 3) * SCALE)))

    image = Image.new("RGBA", (WIDTH * SCALE, (HEIGHT + extra_height) * SCALE), "#101316")
    shadow = Image.new("RGBA", image.size)
    box(ImageDraw.Draw(shadow), (18, 48, 982, 778 + extra_height), "#000000", None, 12)
    image.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(12)))
    outer = ImageDraw.Draw(image)
    box(outer, (20, 44, 980, 770 + extra_height), "#101820", "#a18c65", 6)
    box(outer, (21, 45, 979, 110), "#172231")
    text(outer, (48, 63), state.addon.displayName, 22, GOLD, True)
    button(outer, 928, 64, 27, 25, "X")
    box(outer, (21, 111, 234, 730 + extra_height), "#131e28")
    for index, (category_key, label) in enumerate((("scaling", "Interface"),
            ("resources", "Personal bars"), ("party", "Party bars"),
            ("pet", "Pet bars"), ("swing", "Swing timer"))):
        y = 130 + index * 42
        box(outer, (37, y, 216, y + 34), "#332c21" if key == category_key else "#1b2633",
            GOLD if key == category_key else "#514837", 3)
        text(outer, (54, y + 7), label, 14, GOLD if key == category_key else WHITE)
    button(outer, 45, 665 + extra_height, 163, 30, "Move Mode")
    box(outer, (246, 122, 954, 702 + extra_height), "#171615", "#514837", 3)
    image.alpha_composite(canvas, (258 * SCALE, 126 * SCALE))
    text(outer, (287, 783 + extra_height), "Illustrative UI preview - not an in-game screenshot", 11, MUTED)
    image.convert("RGB").save(OUT / filename, optimize=True)
    print((OUT / filename).relative_to(ROOT))


def render_hud(state, filename, moving=False):
    """Illustrate the live unit-display widgets with synthetic fixture data."""
    image = Image.new("RGBA", (1200 * SCALE, 620 * SCALE), "#0d141b")
    draw = ImageDraw.Draw(image)
    addon = state.addon
    hud = addon.GetResourceDisplay(addon)
    cfg = addon.GetResourceSettings(addon)
    text(draw, (40, 28), "Move mode" if moving else "Personal bars", 23, GOLD, True)
    if not moving:
        text(draw, (40, 63), "Movable health and power bars, with optional party and pet displays.", 14, MUTED)

    def native_rect(frame):
        x, bottom, width, height = frame.GetRect(frame)
        scale = float(frame.GetEffectiveScale(frame))
        return float(x) * scale, 620 - (float(bottom) + float(height)) * scale, float(width) * scale, float(height) * scale

    def named(name):
        return next((obj for _, obj in state.objects.items() if obj._name == name), None)

    def unit(view, settings, x, y, scale, party=False):
        if state.geometry:
            x, y, _, _ = native_rect(view)
        left = float(view.barLeft) * scale
        if party and settings.portraits:
            size = float(view.portrait.GetWidth(view.portrait)) * scale
            box(draw, (x, y, x + size, y + size), "#22323e", "#42545f", 4)
            cx, cy = x + size / 2, y + size / 2
            draw.ellipse(tuple(int(v * SCALE) for v in (cx - size * .14, cy - size * .26, cx + size * .14, cy + size * .02)), fill="#7a929f")
            draw.ellipse(tuple(int(v * SCALE) for v in (cx - size * .25, cy + size * .05, cx + size * .25, cy + size * .42)), fill="#7a929f")
        if party and settings.names:
            text(draw, (x + left + 2, y), view.name.text, 12 * scale, WHITE)
        for kind in ("health", "power"):
            bar, dimensions = view[kind], settings[kind]
            if not bar.IsShown(bar):
                continue
            bx = x + left + float(dimensions.x) * scale
            by = y + float(view.nameHeight) * scale - float(dimensions.y) * scale
            if kind == "power":
                by += (float(settings.health.height) + float(settings.gap)) * scale
            width, height = float(dimensions.width) * scale, float(dimensions.height) * scale
            if state.geometry:
                bx, by, width, height = native_rect(bar)
            box(draw, (bx, by, bx + width, by + height), "#0a1117", "#283b45", 1)
            maximum = float(bar.fill.high)
            current, previous = float(bar.fill.value) / maximum, float(bar.trail.value) / maximum
            if previous > current:
                box(draw, (bx + 1, by + 1, bx + width * previous - 1, by + height - 1), "#26343d")
            rgb = tuple(int(float(bar.fill.barColor[index]) * 255) for index in (1, 2, 3))
            box(draw, (bx + 1, by + 1, bx + width * current - 1, by + height - 1), rgb)
            if kind == "health":
                end = current
                for prediction in ("direct", "hot"):
                    segment = bar.forecasts[prediction]
                    color = tuple(round(float(segment.barColor[index]) * 255) for index in (1, 2, 3))
                    amount = float(segment.value or 0) / maximum
                    if segment.IsShown(segment) and amount > 0 and end < 1:
                        next_end = min(1, end + amount)
                        box(draw, (bx + width * end, by + 1, bx + width * next_end - 1, by + height - 1), color)
                        end = next_end
                dot = bar.forecasts.dot
                if dot.IsShown(dot) and float(dot.value or 0) > 0:
                    start = max(0, current - float(dot.value) / maximum)
                    box(draw, (bx + width * start, by + 1, bx + width * current - 1, by + height - 1), "#aa6054")
            if bar.valueText.IsShown(bar.valueText):
                size = float(bar.valueText.fontSize or min(15, max(9, float(dimensions.height) * .5))) * scale
                value = str(bar.valueText.text)
                length = draw.textlength(value, font=font(size)) / SCALE
                alignment = str(bar.valueText.justifyH or "RIGHT")
                text_x = bx + 7 if alignment == "LEFT" else bx + (width - length) / 2 if alignment == "CENTER" else bx + width - length - 7
                text_colour = tuple(round(float(bar.valueText.textColor[index]) * 255) for index in (1, 2, 3))
                text(draw, (text_x, by + (height - size) / 2 - 2), value, size, text_colour)
                if bar.label.IsShown(bar.label):
                    text(draw, (bx + 7, by + (height - size) / 2 - 2), bar.label.text, size, text_colour)

    party_scale = float(cfg.party.scale)
    party_x = 600 + float(cfg.party.x) - float(hud.partyRoot.GetWidth(hud.partyRoot)) * party_scale / 2
    party_y = 310 - float(cfg.party.y) - float(hud.partyRoot.GetHeight(hud.partyRoot)) * party_scale / 2
    for _, view in hud.party.items():
        unit(view, cfg.party, party_x, party_y, party_scale, True)
        party_y += (float(view.GetHeight(view)) + float(cfg.party.spacing)) * party_scale
    player_scale = float(cfg.player.scale)
    player_x = 600 + float(cfg.player.x) - float(hud.player.GetWidth(hud.player)) * player_scale / 2
    player_y = 310 - float(cfg.player.y) - float(hud.player.GetHeight(hud.player)) * player_scale / 2
    if state.geometry:
        player_x, player_y, _, _ = native_rect(hud.player)
    unit(hud.player, cfg.player, player_x, player_y, player_scale)
    if not moving:
        text(draw, (player_x, player_y - 30), "YOUR BARS", 11, MUTED)
    seal = hud.player.seal
    if seal.IsShown(seal):
        size = float(cfg.seal.size) * player_scale
        sx = player_x + (float(cfg.player.health.width) + float(cfg.seal.x)) * player_scale
        stack_height = float(cfg.player.health.height)
        if hud.player.power.IsShown(hud.player.power):
            stack_height += float(cfg.player.gap) + float(cfg.player.power.height)
        sy = player_y + (stack_height / 2 - float(cfg.seal.y)) * player_scale - size / 2
        if state.geometry:
            sx, sy, _, _ = native_rect(seal)
        box(draw, (sx, sy, sx + size, sy + size), "#4a4638", "#bc9c5c", 3)
        # Symbolic icon: game artwork is supplied by WoW at runtime.
        text(draw, (sx + size * .36, sy + size * .12), "!" if seal.status == "missing" else "+", size * .6, GOLD, True)
        text(draw, (sx, sy - 24), "SEAL", 10, MUTED)
    if hud.pet.IsShown(hud.pet):
        pet_scale = float(cfg.pet.scale)
        pet_x = 600 + float(cfg.pet.x) - float(hud.pet.GetWidth(hud.pet)) * pet_scale / 2
        pet_y = 310 - float(cfg.pet.y) - float(hud.pet.GetHeight(hud.pet)) * pet_scale / 2
        unit(hud.pet, cfg.pet, pet_x, pet_y, pet_scale, True)
        if state.geometry:
            pet_x, pet_y, _, _ = native_rect(hud.pet)
        text(draw, (pet_x, pet_y - 26), "YOUR PET", 11, MUTED)
    if moving:
        for name in ("SmallerUIMoveVerticalGuide", "SmallerUIMoveHorizontalGuide"):
            guide = named(name)
            if guide is not None and guide.IsVisible(guide):
                x, y, width, height = native_rect(guide)
                box(draw, (x, y, x + max(1, width), y + max(1, height)), "#bc9c4c")
        selected = named("SmallerUIMoveSelection")
        if selected is not None and selected.IsVisible(selected):
            x, y, width, height = native_rect(selected)
            draw.rectangle(tuple(round(value * SCALE) for value in (x, y, x + width, y + height)), outline=GOLD, width=2 * SCALE)
            text(draw, (x, max(8, y - 20)), selected.label.text, 11, GOLD)
        toolbar = named("SmallerUIResourceEditor")
        x, y, width, height = native_rect(toolbar)
        box(draw, (x, y, x + width, y + height), "#171b1f", "#8e7d59", 6)
        text(draw, (x + 16, y + 12), "Move Mode", 16, GOLD)
        text(draw, (x + 162, y + 16), "Drag to move  /  Shift to bypass snap", 11)
        button(draw, x + 16, y + 42, 172, 26, named("SmallerUIMoveTarget").text)
        button(draw, x + 200, y + 42, 32, 26, "-")
        button(draw, x + 238, y + 42, 32, 26, "+")
        text(draw, (x + 325, y + 47), "Group", 12)
        for name, offset in (("SmallerUIResourceDemo", 16), ("SmallerUIResourceCancel", 312), ("SmallerUIResourceDone", 408)):
            control = named(name)
            button(draw, x + offset, y + 77, float(control.width), 26, control.text)
    text(draw, (360, 587), "Illustrative UI preview - not an in-game screenshot", 11, MUTED)
    image.convert("RGB").save(OUT / filename, optimize=True)
    print((OUT / filename).relative_to(ROOT))


lua = LuaRuntime(unpack_returned_tuples=True)
manifest = (ROOT / "SmallerUI" / "SmallerUI.toc").read_text()
lua.globals().addon_sources = lua.table_from([
    (ROOT / "SmallerUI" / line.strip()).read_text()
    for line in manifest.splitlines() if line.strip().endswith(".lua")
])
boot = lua.execute((ROOT / "tests" / "smaller_ui_test.lua").read_text())
preferences = lua.table_from({"scale": 0.4, "enabled": True,
                              "elements": lua.table_from({"chat": 1, "actionbars": 0.85})})
env, state, send_event, tick, _ = boot(preferences)
state.addon.ShowOptions(state.addon, "scaling")
render(env, state, "scaling", "ui-scale-preview.png")
state.addon.ShowOptions(state.addon, "resources")
render(env, state, "resources", "personal-resources-settings-preview.png")
render(env, state, "resources", "health-previews-settings-preview.png", content_offset=230)
env.SmallerUIPersonalcombatOpacity.SetValue(env.SmallerUIPersonalcombatOpacity, 90)
env.SmallerUIPersonaloutOfCombatOpacity.SetValue(env.SmallerUIPersonaloutOfCombatOpacity, 45)
page = env.SmallerUIPersonalOptions
page.SelectTab(page, "appearance")
render(env, state, "resources", "combat-texture-settings-preview.png", texture_menu=True)
env.SmallerUIPersonalcombatOpacity.SetValue(env.SmallerUIPersonalcombatOpacity, 100)
env.SmallerUIPersonaloutOfCombatOpacity.SetValue(env.SmallerUIPersonaloutOfCombatOpacity, 100)
state.Click(env.SmallerUIPersonalTextToggle)
state.Click(env.SmallerUIPersonalResourceColoursToggle)
render(env, state, "resources", "text-style-settings-preview.png", content_offset=360)
state.Click(env.SmallerUIPersonalTextToggle)
state.Click(env.SmallerUIPersonalResourceColoursToggle)
state.addon.ShowOptions(state.addon, "party")
render(env, state, "party", "party-display-settings-preview.png")
state.addon.ShowOptions(state.addon, "pet")
render(env, state, "pet", "pet-display-settings-preview.png")
state.addon.ShowOptions(state.addon, "swing")
render(env, state, "swing", "swing-timer-settings-preview.png")
state.addon.ShowOptions(state.addon, "resources")
cfg = state.addon.GetResourceSettings(state.addon)
cfg.enabled, cfg.partyEnabled, cfg.petEnabled = True, True, True
cfg.player.scale, cfg.player.x, cfg.player.y = 1.25, 210, -55
cfg.player.health.width, cfg.player.health.height = 300, 28
cfg.player.power.width, cfg.player.power.height = 300, 14
cfg.party.x, cfg.party.y, cfg.party.scale = -380, 25, 1.1
cfg.pet.x, cfg.pet.y, cfg.pet.scale = 210, -185, 1.1
state.units.pet = lua.table_from({"health": 2200, "maximum": 2500, "power": 65,
    "powerMax": 100, "token": "FOCUS", "name": "Your pet"})
state.units.player.health, state.units.player.maximum = 4500, 5000
state.units.player.incoming = 600
state["class"] = "PALADIN"
cfg.seal.lastSpellID = 20154
state.auras.player = lua.table_from({"HELPFUL": lua.table_from([
    lua.table_from({"spellId": 139, "sourceUnit": "player", "expirationTime": float(state.now) + 20, "auraInstanceID": 1})])})
for index, (name, health, token) in enumerate((("Party member 1", 4200, "MANA"),
        ("Party member 2", 3300, "ENERGY"), ("Party member 3", 4700, "RAGE"), ("Party member 4", 3900, "MANA")), 1):
    state.units["party" + str(index)] = lua.table_from({"health": health, "maximum": 5000, "power": 70,
        "powerMax": 100, "token": token, "name": name})
state.addon.ApplyResources(state.addon)
def periodic_tick():
    state.combatLog = lua.table_from([state.now, "SPELL_PERIODIC_HEAL", False, "player-guid", "Source", 0, 0,
        "player-guid", "Destination", 0, 0, 139, "Periodic heal", 2, 120])
    send_event("COMBAT_LOG_EVENT_UNFILTERED")
periodic_tick()
tick(2)
periodic_tick()
state.units.player.health = 2800
send_event("UNIT_HEALTH", "player")
render_hud(state, "resource-display-preview.png")

# Exercise the real editor and native-anchor mock for the movement illustration.
state.geometry = True
env.UIParent.SetSize(env.UIParent, 1200 / float(state.scale), 620 / float(state.scale))
state.addon.BeginResourceEdit(state.addon)
hud = state.addon.GetResourceDisplay(state.addon)
start_x, _, _, _ = hud.player.health.GetRect(hud.player.health)
pet_x, _, _, _ = hud.pet.health.GetRect(hud.pet.health)
start_x *= float(hud.player.health.GetEffectiveScale(hud.player.health))
pet_x *= float(hud.pet.health.GetEffectiveScale(hud.pet.health))
state.mouseDown = True
state.addon.BeginResourceDrag(state.addon, hud.player, "health")
state.cursorX = 100 + pet_x - 6 - start_x
tick(0.016)
render_hud(state, "move-mode-preview.png", moving=True)
state.mouseDown = False
state.addon.FinishResourceEdit(state.addon, False)
