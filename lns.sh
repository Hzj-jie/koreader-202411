#!/bin/sh

# Consolidated lns.sh script.
# Run from repository root to create platform symlinks.

exclude_patterns() {
    # Exclude git/travis configs, workflows, and platform-specific/local dev files
    grep -E -v '\.gitmodules$|\.gitignore$|\.travis\.ya?ml$|\.git/|\.github/'
}

link_dir_contents() {
    src_dir="$1"
    dst_prefix="$2"

    # Create directories
    find "$src_dir" -type d | exclude_patterns | while read -r d ; do
        rel_d=$(echo "$d" | sed "s|^$src_dir/||")
        if [ -n "$rel_d" ] && [ "$rel_d" != "$src_dir" ]; then
            mkdir -p "$dst_prefix/$rel_d" 2>/dev/null
        fi
    done

    # Create symlinks
    find "$src_dir" -type f | exclude_patterns | while read -r f ; do
        rel_f=$(echo "$f" | sed "s|^$src_dir/||")
        if [ -n "$rel_f" ]; then
            rm -f "$dst_prefix/$rel_f"
            ln -rs "$f" "$dst_prefix/$rel_f"
        fi
    done
}

echo "Linking platforms..."

# --- 1. Linux ---
echo "Configuring linux/..."
link_dir_contents "koreader" "linux"
# Linux specific pruning
rm -rf linux/scripts
rm -rf linux/settings
rm -f linux/spinning_zsync
rm -rf linux/tools

# --- 2. PW2 ---
echo "Configuring pw2/..."
link_dir_contents "koreader" "pw2"
# PW2 specific: merge with kindle
link_dir_contents "kindle" "pw2"
rm -rf pw2/extensions

# --- 3. Legacy ---
echo "Configuring legacy/..."
link_dir_contents "koreader" "legacy"
# Legacy specific: merge with kindle
link_dir_contents "kindle" "legacy"
rm -rf legacy/extensions
# Legacy specific pruning (unsupported plugins and heavy assets)
rm -rf legacy/plugins/autodim.koplugin
rm -rf legacy/plugins/autofrontlight.koplugin
rm -rf legacy/plugins/autostandby.koplugin
rm -rf legacy/plugins/autosuspend.koplugin
rm -rf legacy/plugins/calibre.koplugin
rm -rf legacy/plugins/httpinspector.koplugin
rm -rf legacy/plugins/kosync.koplugin
rm -rf legacy/plugins/newsdownloader.koplugin
rm -rf legacy/plugins/opds.koplugin
rm -rf legacy/plugins/SSH.koplugin
rm -rf legacy/plugins/wallabag.koplugin
rm -rf legacy/plugins/weather.koplugin
rm -f legacy/settings/weather.lua
rm -rf legacy/web
rm -rf legacy/plugins/gestures.koplugin
rm -rf legacy/plugins/terminal.koplugin
rm -rf legacy/plugins/coverbrowser.koplugin

# --- 4. Kobo ---
echo "Configuring kobo/..."
link_dir_contents "koreader" "kobo"

echo "Platform linking complete!"
