import sys
import re

targets = sys.argv[1:]

with open("scratch/luacheck_output.txt") as f:
    content = f.read()

blocks = re.split(r"\n(?=Checking )", content)
for block in blocks:
    lines = block.splitlines()
    if not lines:
        continue
    header = lines[0]
    for target in targets:
        if target in header and "linux/spec/" in header and "unit/" in header:
            print(header)
            for l in lines[1:]:
                if l.strip().startswith("linux/spec/"):
                    print(l)
            print()
            break
