import os
import re

with open("scratch/luacheck_output.txt") as f:
    content = f.read()

blocks = re.split(r"\n(?=Checking )", content)
real_files = {}

for block in blocks:
    lines = block.splitlines()
    if not lines:
        continue
    header = lines[0]
    if header.startswith("Checking "):
        filepath = header.split()[1]
        try:
            real_path = os.path.realpath(filepath)
            rel_path = os.path.relpath(real_path, os.getcwd())
        except Exception:
            rel_path = filepath
        
        warnings = [l for l in lines[1:] if " (W" in l]
        if warnings:
            if rel_path not in real_files:
                real_files[rel_path] = (filepath, warnings)

for rpath, (orig_path, warn_list) in sorted(real_files.items()):
    print(f"=== {rpath} ({len(warn_list)}) ===")
    for w in warn_list:
        # Strip front/front/... prefixes to see exact line numbers
        match = re.search(r"(\S+\.lua:\d+:\d+: \(W\d+\) .*)$", w.strip())
        if match:
            print("  ", match.group(1))
        else:
            print("  ", w.strip())
