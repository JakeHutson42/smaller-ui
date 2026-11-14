# Forever QoL

Finer UI scaling for **World of Warcraft: Forever**, with movable resource bars and a compact swing timer.

Built because WoW's default UI scale slider doesn't go low enough for my setup.

## Install

1. [Download Forever QoL 1.7.0](downloads/ForeverQoL-1.7.0.zip?raw=true).
2. Extract the `SmallerUI` folder into `_forever_/Interface/AddOns/` and enable it in game.
3. Open `/fqol` or click the minimap gear to adjust your settings.

The `SmallerUI` folder keeps existing settings. `/sui` still works, and `/fqol reset` restores the game's scale. Requires WoW Forever interface **16001**. No dependencies.

Enable **Swing timer** and choose a weapon lane, style, and theme. The timer starts with the first auto attack.

## Settings

Open **Forever QoL** with `/fqol` or the minimap gear. Use **Interface** for global and individual UI scaling. The **Personal bars**, **Party bars**, and **Pet bars** pages each have three tabs.

- **Display** controls health and power independently, with combat visibility and opacity.
- **Layout** controls sizes, spacing, and grouping. Personal bars can use horizontal bars or a curved HUD.
- **Appearance** controls themes, textures, colours, text, and motion.

Open **Move Mode** from the sidebar or run `/fqol move`. Select an element or click a preview, drag to position it, and use **- / +** to resize. **Group** links related bars or Blizzard frames. Hold **Shift** to bypass snapping. **Done & Settings** saves and returns to your settings tab. **Cancel** or **Escape** restores the previous layout.

*Illustrative UI previews, not in-game screenshots.*

![UI scale and individual element settings](docs/images/ui-scale-preview.png)

![Resource bar opacity settings and texture swatches](docs/images/combat-texture-settings-preview.png)

![Swing timer settings and line-and-dot preview](docs/images/swing-timer-settings-preview.png)
