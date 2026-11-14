# Development

The addon targets WoW Forever interface `16001` and has no runtime dependencies.

```sh
python -m pip install -r tests/requirements.txt
python tests/run.py
python scripts/package.py
```

Tests execute Lua 5.1 against mocked WoW APIs. In-game rendering, protected-frame
behaviour and compatibility with other addons still require client testing.

Generate the labelled documentation previews with `python scripts/render_previews.py`
after installing Pillow and the test requirements. They are illustrations of the
actual settings layout, not in-game screenshots.

## Bar textures

Run `python scripts/render_bar_textures.py` to rebuild Satin, Etched, Woven, the jewelled trim, and the curved HUD mask and outline.
Glacier Glass, Runefang, and Rivetsteel were made with the built-in ImageGen tool and converted to 256 × 64 tintable TGA files in `SmallerUI/Media/`.

The three ImageGen requests used this shared prompt with one of the directions below.

> Use case: ui-mockup. Generate a single original grayscale texture for the live fill of a slim horizontal fantasy MMORPG health or mana bar, inspired by the range of bar finishes in IceHUD. Production texture art, orthographic and flat-on, as if a material sample. Fill the whole landscape canvas edge-to-edge with a single uninterrupted texture; artwork runs off the left and right edges, and occupies the full height. The entire height of the image will be compressed into a 7–20 pixel high horizontal fill and tinted by the player's chosen colour. Favor clean bright silver and soft gray midtones, restrained contrast and a bold readable motif. Brighter top and darker bottom give a subtle bevel. Keep the material equally readable all the way along its length, including when filled to 20%. No bar outline or separate frame, no background, no surrounding margin, no different panels, no perspective, no typography, no icon, no colored light, no compositing or presentation.

- **Glacier Glass**. A continuous luminous frosted-glass surface with gently curved bands of refraction running horizontally along the full strip, like a refined glow-arc HUD translated into a straight bar. Top silver glint, velvety middle, softly shaded lower bevel. Avoid crystalline shards or complex noise.
- **Runefang**. A spectral runic surface with a subtle repeating row of roughly 12 broad angular fang-chevron incisions, like inlaid rune metal. Shapes have thick clean contours, a soft rim catching light, and no literal lettering. Keep the center of each segment bright and opaque.
- **Rivetsteel**. A dark-fantasy forged-steel surface with roughly 12 evenly spaced bold rivets and fine diagonal seams across the width, like a precise mechanical tank HUD. Broad flat brushed-silver faces with consistent brightness. Rivets should be discernible at 10 pixels high, with minimal grain.
