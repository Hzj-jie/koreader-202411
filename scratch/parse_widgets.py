import re

with open("scratch/luacheck_output.txt") as f:
    content = f.read()

blocks = re.split(r"\n(?=Checking )", content)
widget_warnings = {}

for block in blocks:
    lines = block.splitlines()
    if not lines:
        continue
    header = lines[0]
    if "koreader/frontend/ui/widget/" in header:
        fname = header.split()[1].replace("koreader/frontend/ui/widget/", "")
        warnings = [l for l in lines[1:] if l.strip().startswith("koreader/frontend/ui/widget/")]
        if warnings:
            widget_warnings[fname] = len(warnings)

print(f"Found {len(widget_warnings)} widget files with warnings:")
for name, count in sorted(widget_warnings.items(), key=lambda x: x[1], reverse=True):
    print(f"  koreader/frontend/ui/widget/{name}: {count} warnings")
