import re
from collections import defaultdict

with open("scratch/luacheck_output.txt") as f:
    content = f.read()

blocks = re.split(r"\n(?=Checking )", content)
by_dir = defaultdict(int)
total_warnings = 0

for block in blocks:
    lines = block.splitlines()
    if not lines:
        continue
    header = lines[0]
    if header.startswith("Checking "):
        filepath = header.split()[1]
        warnings = [l for l in lines[1:] if l.strip().startswith(filepath) or l.strip().startswith("linux/spec/") or l.strip().startswith("koreader/")]
        count = len(warnings)
        if count > 0:
            # Get top level directory under koreader or linux
            parts = filepath.split("/")
            if len(parts) >= 3:
                top_dir = "/".join(parts[:3])
            else:
                top_dir = filepath
            by_dir[top_dir] += count
            total_warnings += count

print(f"Total Warnings parsed: {total_warnings}")
print("Warnings by Top-Level Folder:")
for d, cnt in sorted(by_dir.items(), key=lambda x: x[1], reverse=True):
    print(f"  {d}: {cnt} warnings")
