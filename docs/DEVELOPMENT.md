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
