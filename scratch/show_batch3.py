import re

batch3_files = [
    "background_runner_spec.lua", "filemanagerbookinfo_spec.lua", "autoturn_spec.lua",
    "kosync_spec.lua", "commonrequire.lua", "fontlist_spec.lua", "socketutil_spec.lua",
    "uimanager_bench.lua", "languagesupport_spec.lua", "widget_virtualkeyboard_spec.lua",
    "keepalive_spec.lua", "network_manager_spec.lua", "readerdevicestatus_spec.lua",
    "autowarmth_spec.lua", "benchmark.lua", "clock_spec.lua", "terminal_spec.lua",
    "version_spec.lua", "background_task_plugin_spec.lua", "logger_spec.lua",
    "opds_spec.lua", "readerfooter_spec.lua"
]

with open("scratch/luacheck_output.txt") as f:
    content = f.read()

blocks = re.split(r"\n(?=Checking )", content)
for block in blocks:
    lines = block.splitlines()
    if not lines:
        continue
    header = lines[0]
    if header.startswith("Checking linux/spec/unit/"):
        fname = header.split()[1].replace("linux/spec/unit/", "")
        if fname in batch3_files:
            print(header)
            for l in lines[1:]:
                if l.strip().startswith("linux/spec/unit/"):
                    print(l)
            print()
