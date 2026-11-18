#!/bin/sh
PACKAGE="legacy"
UPDATE_DIR="$1"
INSTALL_DIR="$2"

FBINK_BIN="${TMPDIR:-/var/tmp}/ko_update_fbink.$$"
cp -pf "${INSTALL_DIR}/fbink" "${FBINK_BIN}"
"${FBINK_BIN}" -q -y -7 -pmh "Updating KOReader"
sleep "${KO_UPDATE_SLEEP:-3}"

if [ -r "${UPDATE_DIR}/data/removed-files.txt" ]; then
    while IFS= read -r item || [ -n "${item}" ]; do
        case "${item}" in
            "" | "#"*) continue ;;
        esac
        rm -rf -- "${INSTALL_DIR}/${item}"
    done < "${UPDATE_DIR}/data/removed-files.txt"
fi

cp -rf "${UPDATE_DIR}/." "${INSTALL_DIR}/"
rc=$?
rm -rf "${UPDATE_DIR}"
sync

if [ "${rc}" -eq 0 ]; then
    "${FBINK_BIN}" -q -y -6 -pmh "Update successful :)"
else
    "${FBINK_BIN}" -q -y -6 -pmh "Update failed :("
fi

rm -f "${FBINK_BIN}"
exit "${rc}"
