#!/bin/bash
set -e

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Change directory to koreader source
cd "$SCRIPT_DIR/koreader"

TEMPLATE_DIR="l10n/templates"
DOMAIN="koreader"
POT_FILE="$TEMPLATE_DIR/$DOMAIN.pot"

echo "Extracting strings using xgettext..."
mkdir -p "$TEMPLATE_DIR"

# Find files to translate
LUA_FILES="reader.lua $(find frontend -iname "*.lua" | sort) $(find plugins -iname "*.lua" | sort) $(find tools -iname "*.lua" | sort)"

xgettext --from-code=utf-8 \
  --keyword=gettext \
  --keyword=C_:1c,2 --keyword=N_:1,2 --keyword=NC_:1c,2,3 \
  --add-comments=@translators \
  $LUA_FILES \
  -o "$POT_FILE"

echo "Merging template into PO files (without backups or fuzzy matching)..."
for po_file in l10n/*/koreader.po; do
  if [ -f "$po_file" ]; then
    echo "Updating $po_file..."
    msgmerge --update --backup=off --no-fuzzy-matching "$po_file" "$POT_FILE"
  fi
done

echo "Done!"
