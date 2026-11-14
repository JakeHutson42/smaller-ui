"""Build the installable addon archive from its manifest."""
from pathlib import Path
import re
import zipfile

root = Path(__file__).resolve().parents[1]
addon = root / "SmallerUI"
manifest = addon / "SmallerUI.toc"
text = manifest.read_text(encoding="utf-8")
version = re.search(r"^## Version: (.+)$", text, re.MULTILINE).group(1).strip()
files = [manifest, *(addon / line.strip() for line in text.splitlines()
                     if line.strip() and not line.lstrip().startswith("#"))]
files.extend((addon / "Media").glob("*.tga"))
destination = root / "downloads" / f"ForeverQoL-{version}.zip"
destination.parent.mkdir(exist_ok=True)
with zipfile.ZipFile(destination, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
    for file in sorted(files):
        entry = zipfile.ZipInfo("SmallerUI/" + file.relative_to(addon).as_posix(), date_time=(1980, 1, 1, 0, 0, 0))
        entry.compress_type = zipfile.ZIP_DEFLATED
        entry.create_system = 3
        entry.external_attr = 0o100644 << 16
        data = file.read_bytes() if file.suffix == ".tga" else file.read_text(encoding="utf-8").encode("utf-8")
        archive.writestr(entry, data)
print(destination.relative_to(root))
