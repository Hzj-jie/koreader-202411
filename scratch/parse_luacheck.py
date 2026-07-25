import re

with open("scratch/luacheck_output.txt") as f:
    content = f.read()

blocks = re.split(r"\n(?=Checking )", content)
unit_specs = {}

for block in blocks:
    lines = block.splitlines()
    if not lines:
        continue
    header = lines[0]
    if "linux/spec/" in header and "unit/" in header:
        # Get actual spec file name
        fname = header.split()[1].split("unit/")[-1]
        warnings = [l for l in lines[1:] if l.strip().startswith("linux/spec/")]
        if warnings:
            unit_specs[fname] = len(warnings)

print(f"Remaining unit spec files with warnings: {len(unit_specs)}")
for name, count in sorted(unit_specs.items(), key=lambda x: x[1], reverse=True):
    print(f"  linux/spec/unit/{name}: {count} warnings")
