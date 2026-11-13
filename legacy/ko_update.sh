#!/bin/sh
PACKAGE="legacy"
UPDATE_DIR="${1:-${KOREADER_DIR}.update}"
INSTALL_DIR="${2:-${KOREADER_DIR}}"

if [ -z "${INSTALL_DIR}" ] || [ ! -d "${UPDATE_DIR}" ]; then
    exit 1
fi

TMP_DIR="${TMPDIR:-/var/tmp}"
FBINK_BIN=""
if [ -x "${INSTALL_DIR}/fbink" ]; then
    FBINK_BIN="${TMP_DIR}/ko_update_fbink.$$"
    cp -pf "${INSTALL_DIR}/fbink" "${FBINK_BIN}" 2>/dev/null || FBINK_BIN=""
fi

fbink_msg() {
    if [ -n "${FBINK_BIN}" ] && [ -x "${FBINK_BIN}" ]; then
        "${FBINK_BIN}" -q -y "$1" -pmh "$2" >/dev/null 2>&1 || true
    fi
}

fbink_msg -7 "Updating KOReader"
sleep "${KO_UPDATE_SLEEP:-3}"

cp -rf "${UPDATE_DIR}/." "${INSTALL_DIR}/"
rc=$?
rm -rf "${UPDATE_DIR}"
sync

if [ "${rc}" -eq 0 ]; then
    fbink_msg -6 "Update successful :)"
else
    fbink_msg -6 "Update failed :("
fi

[ -n "${FBINK_BIN}" ] && rm -f "${FBINK_BIN}"
exit "${rc}"
