#!/bin/sh
PACKAGE="kobo"
UPDATE_DIR="$1"
INSTALL_DIR="$2"

FBINK_BIN="${TMPDIR:-/tmp}/ko_update_fbink.$$"
cp -pf "${INSTALL_DIR}/fbink" "${FBINK_BIN}"
"${FBINK_BIN}" --cls
"${FBINK_BIN}" -q -y -7 -pmh "Updating KOReader"
sleep "${KO_UPDATE_SLEEP:-3}"

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
