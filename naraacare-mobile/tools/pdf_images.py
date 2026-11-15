"""List (and save) raster images embedded in PDFs: python -I pdf_images.py <out_dir> <pdf>..."""
import re
import sys
import zlib
from pathlib import Path

from PIL import Image

out = Path(sys.argv[1])
out.mkdir(parents=True, exist_ok=True)
OBJ = re.compile(rb"(\d+) 0 obj\s*<<(.*?)>>\s*stream\r?\n", re.S)


def num(d, key):
    m = re.search(rb"/" + key + rb"\s+(\d+)", d)
    return int(m.group(1)) if m else None


for pdf in sys.argv[2:]:
    data = Path(pdf).read_bytes()
    stem = Path(pdf).stem.replace(" ", "_")
    for m in OBJ.finditer(data):
        d = m.group(2)
        if b"/Image" not in d:
            continue
        length = None if re.search(rb"/Length\s+\d+\s+0\s+R", d) else num(d, b"Length")
        start = m.end()
        raw = data[start : start + length] if length else data[start : data.index(b"endstream", start)]
        w, h = num(d, b"Width"), num(d, b"Height")
        bpc = num(d, b"BitsPerComponent") or 8
        name = f"{stem}_obj{m.group(1).decode()}_{w}x{h}"
        smask = b"/SMask" in d
        cs = b"Gray" if b"DeviceGray" in d else b"RGB"
        print(pdf, name, "DCT" if b"DCTDecode" in d else "Flate", cs.decode(), "smask" if smask else "")
        try:
            if b"DCTDecode" in d:
                (out / f"{name}.jpg").write_bytes(raw)
            elif b"FlateDecode" in d and bpc == 8 and b"DecodeParms" not in d:
                pix = zlib.decompress(raw)
                mode = "L" if cs == b"Gray" else "RGB"
                Image.frombytes(mode, (w, h), pix).save(out / f"{name}.png")
        except Exception as exc:  # report and continue
            print("  could not decode:", type(exc).__name__, exc)
