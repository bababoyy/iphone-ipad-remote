#!/usr/bin/env python3
from pathlib import Path
root = Path(__file__).resolve().parent.parent
page = (root / "controller/index.html").read_bytes()
rows = ["  \"" + "".join(f"\\x{x:02x}" for x in page[i:i+24]) + "\"" for i in range(0, len(page), 24)]
(root / "receiver/ControllerPage.generated.h").write_text(
    "#pragma once\nstatic const char kControllerHTML[] =\n"
    + "\n".join(rows) + ";\n"
    + f"static const unsigned long kControllerHTMLLength = {len(page)}UL;\n"
)
print("Embedded", len(page), "HTML bytes")
