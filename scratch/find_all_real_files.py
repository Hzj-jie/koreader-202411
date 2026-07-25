import os
import re

with open("scratch/luacheck_output.txt") as f:
    content = f.read()

blocks = re.split(r"\n(?=Checking )", content)
real_files_with_warnings = {}

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
            if rel_path not in real_files_with_warnings:
                real_files_with_warnings[rel_path] = (filepath, warnings)

print(f"Total Unique Real Files with Warnings: {len(real_files_with_warnings)}")
for rpath, (orig_path, warn_list) in sorted(real_files_with_warnings.items(), key=lambda x: len(x[1][1]), reverse=True):
    print(f"  {rpath}: {len(warn_list)} warnings")
