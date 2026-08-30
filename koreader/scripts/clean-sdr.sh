#!/bin/sh

# Help message
show_help() {
    echo "Usage: $0 [directory]"
    echo "Clean up orphaned .sdr sidecar folders that have no matching book file."
    echo "If no directory is specified, the current directory is used."
    echo ""
    echo "Options:"
    echo "  -h, --help    Show this help message"
    echo "  -d, --delete  Actually delete the orphaned folders (default is dry-run)"
}

# Parse options
DRY_RUN=true
TARGET_DIR="."

while [ "$#" -gt 0 ]; do
    case "$1" in
        -h|--help)
            show_help
            exit 0
            ;;
        -d|--delete)
            DRY_RUN=false
            shift
            ;;
        -*)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
        *)
            TARGET_DIR="$1"
            shift
            ;;
    esac
done

if [ ! -d "$TARGET_DIR" ]; then
    echo "Error: Directory '$TARGET_DIR' does not exist."
    exit 1
fi

echo "Scanning '$TARGET_DIR' for orphaned .sdr folders..."
if [ "$DRY_RUN" = true ]; then
    echo "Running in DRY-RUN mode. No folders will be deleted."
    echo "Use -d or --delete to actually delete them."
    echo "------------------------------------------------"
fi

# Use find to locate all .sdr directories
find "$TARGET_DIR" -type d -name "*.sdr" | {
    count=0
    while IFS= read -r sdr; do
        parent=$(dirname "$sdr")
        sdr_name=$(basename "$sdr")
        base="${sdr_name%.sdr}"

        has_document=false
        # Loop over all files matching base.*
        for file in "$parent/$base".*; do
            if [ -e "$file" ] && [ "$file" != "$sdr" ]; then
                has_document=true
                break
            fi
        done

        if [ "$has_document" = false ]; then
            if [ "$DRY_RUN" = true ]; then
                echo "[DRY-RUN] Would delete: $sdr"
            else
                echo "Deleting: $sdr"
                rm -rf "$sdr"
            fi
            count=$((count + 1))
        fi
    done

    if [ "$DRY_RUN" = true ]; then
        echo "------------------------------------------------"
        echo "Dry-run finished. Found $count orphaned folders."
    else
        echo "Cleanup finished. Removed $count orphaned folders."
    fi
}
