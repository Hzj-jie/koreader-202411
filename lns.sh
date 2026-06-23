#!/bin/sh

# Consolidated lns.sh script.
# Run from repository root to create platform symlinks.

exclude_patterns() {
    # Exclude git/travis configs, workflows, stylua.toml, and platform-specific/local dev files
    grep -E -v '\.gitmodules$|\.gitignore$|\.travis\.ya?ml$|stylua\.toml$|\.git/|\.github/'
}

link_dir_contents() {
    src_dir="$1"
    dst_prefix="$2"
    custom_excludes="$3"

    # Create directories
    find "$src_dir" -type d | exclude_patterns | while read -r d ; do
        rel_d=$(echo "$d" | sed "s|^$src_dir/||")
        if [ -n "$rel_d" ] && [ "$rel_d" != "$src_dir" ]; then
            if [ -n "$custom_excludes" ] && echo "$rel_d" | grep -E -q "$custom_excludes"; then
                continue
            fi
            mkdir -p "$dst_prefix/$rel_d" 2>/dev/null
        fi
    done

    # Create symlinks
    find "$src_dir" -type f | exclude_patterns | while read -r f ; do
        rel_f=$(echo "$f" | sed "s|^$src_dir/||")
        if [ -n "$rel_f" ]; then
            if [ -n "$custom_excludes" ] && echo "$rel_f" | grep -E -q "$custom_excludes"; then
                continue
            fi
            rm -f "$dst_prefix/$rel_f"
            ln -rs "$f" "$dst_prefix/$rel_f"
        fi
    done
}

echo "Linking platforms..."

# Clean target directories of all existing symlinks first
for d in linux pw2 legacy kobo; do
    if [ -d "$d" ]; then
        echo "Cleaning existing symlinks in $d/..."
        find "$d" -type l -exec rm -f {} +
    fi
done

# --- 1. Linux ---
echo "Configuring linux/..."
# Linux specific pruning: scripts, settings, spinning_zsync
LINUX_EXCLUDES="^scripts/|^scripts$|^settings/|^settings$|^spinning_zsync$"
link_dir_contents "koreader" "linux" "$LINUX_EXCLUDES"

# Recreate test and spec symlinks for linux tests
mkdir -p linux/spec/unit 2>/dev/null
ln -rsf "origin/test" "linux/test"
ln -rsf "linux/spec" "linux/spec/front"
ln -rsf "linux/base/spec" "linux/spec/base"
ln -rsf "linux/test" "linux/spec/unit/data"
ln -rsf "origin.linux/data/tessdata" "linux/data/tessdata"


# --- 2. PW2 ---
echo "Configuring pw2/..."
PW2_EXCLUDES="^extensions/|^extensions$|plugins/kochess\.koplugin/engines/stockfish_pc|/spec/|/spec$|plugins/legacy_terminal\.koplugin"
link_dir_contents "koreader" "pw2" "$PW2_EXCLUDES"
# PW2 specific: merge with kindle
link_dir_contents "kindle" "pw2" "$PW2_EXCLUDES"

# --- 3. Legacy ---
echo "Configuring legacy/..."
LEGACY_EXCLUDES="^extensions/|^extensions$|^web/|^web$|settings/weather\.lua|plugins/autodim\.koplugin|plugins/autofrontlight\.koplugin|plugins/autostandby\.koplugin|plugins/autosuspend\.koplugin|plugins/calibre\.koplugin|plugins/httpinspector\.koplugin|plugins/kosync\.koplugin|plugins/newsdownloader\.koplugin|plugins/opds\.koplugin|plugins/SSH\.koplugin|plugins/wallabag\.koplugin|plugins/weather\.koplugin|plugins/gestures\.koplugin|plugins/terminal\.koplugin|plugins/coverbrowser\.koplugin|plugins/kochess\.koplugin/engines/stockfish_pc|plugins/AnnotationSync\.koplugin|/spec/|/spec$"
link_dir_contents "koreader" "legacy" "$LEGACY_EXCLUDES"
# Legacy specific: merge with kindle
link_dir_contents "kindle" "legacy" "$LEGACY_EXCLUDES"

# --- 4. Kobo ---
echo "Configuring kobo/..."
KOBO_EXCLUDES="plugins/kochess\.koplugin/engines/stockfish_pc|/spec/|/spec$|plugins/legacy_terminal\.koplugin"
link_dir_contents "koreader" "kobo" "$KOBO_EXCLUDES"

echo "Platform linking complete!"
