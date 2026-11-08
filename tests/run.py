"""Execute the addon against mocked WoW APIs using Lua 5.1."""
from pathlib import Path

from lupa.lua51 import LuaRuntime

root = Path(__file__).resolve().parents[1]
lua = LuaRuntime(unpack_returned_tuples=True)
manifest = (root / "SmallerUI" / "SmallerUI.toc").read_text()
lua.globals().addon_sources = lua.table_from([
    (root / "SmallerUI" / line.strip()).read_text()
    for line in manifest.splitlines() if line.strip().endswith(".lua")
])
lua.execute((root / "tests" / "smaller_ui_test.lua").read_text())
