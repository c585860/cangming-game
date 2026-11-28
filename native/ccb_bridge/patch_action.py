#!/usr/bin/env python3
"""Expose the active CCB adjacent-target prompt without modifying the upstream checkout."""

import sys
from pathlib import Path

source, output = map(Path, sys.argv[1:])
text = source.read_text(encoding="utf-8")
anchor = '#include "action.h"\n'
prompt = "    const std::optional<tripoint_bub_ms> chosen = choose_adjacent( pos, message, allow_vertical );"
if text.count(anchor) != 1 or text.count(prompt) != 1:
    raise RuntimeError(f"Cannot locate adjacent-target prompt in {source}")

text = text.replace(anchor, anchor + '#include "bridge_adjacent_targets.hpp"\n')
text = text.replace(prompt, "    const ccb_bridge::AdjacentTargetScope bridge_targets( valid );\n" + prompt)
if not output.exists() or output.read_text(encoding="utf-8") != text:
    output.write_text(text, encoding="utf-8")
