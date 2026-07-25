import os
import re

pattern = re.compile(r"--\s*luacheck:\s*globals\s+(.*)")

found_globals = set()
modified_files = []

for root, dirs, files in os.walk("."):
    if ".git" in root or "scratch" in root:
        continue
    for f in files:
        if f.endswith(".lua"):
            filepath = os.path.join(root, f)
            with open(filepath, "r", encoding="utf-8", errors="ignore") as fh:
                content = fh.read()
            
            matches = pattern.findall(content)
            if matches:
                for match in matches:
                    names = match.strip().split()
                    for name in names:
                        found_globals.add(name)
                
                # Remove the luacheck: globals line from content
                new_content = pattern.sub("", content)
                # Clean up any blank line left at line 1 if any
                lines = new_content.splitlines()
                if lines and lines[0].strip() == "":
                    lines.pop(0)
                new_content = "\n".join(lines) + "\n"
                
                with open(filepath, "w", encoding="utf-8") as fh:
                    fh.write(new_content)
                modified_files.append(filepath)

print("Found Globals:")
for g in sorted(found_globals):
    print(f'  "{g}",')

print(f"\nModified {len(modified_files)} files:")
for mf in modified_files:
    print(f"  {mf}")
