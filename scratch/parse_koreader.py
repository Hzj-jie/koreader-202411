import re
from collections import defaultdict

with open("scratch/luacheck_output.txt") as f:
    content = f.read()

blocks = re.split(r"\n(?=Checking )", content)
koreader_warnings = defaultdict(int)

for block in blocks:
    lines = block.splitlines()
    if not lines:
        continue
    header = lines[0]
    if header.startswith("Checking koreader/"):
        filepath = header.split()[1]
        warnings = [l for l in lines[1:] if l.strip().startswith("koreader/")]
        if warnings:
            # Group by subfolder under koreader/
            parts = filepath.split("/")
            if len(parts) >= 3:
                subfolder = "/".join(parts[:3])
            else:
                subfolder = filepath
            koreader_warnings[subfolder] += len(warnings)

print(f"Found {len(koreader_warnings)} subfolders in koreader/ with warnings:")
for name, count in sorted(koreader_warnings.items(), key=lambda x: x[1], reverse=True):
    print(f"  {name}: {count} warnings")
