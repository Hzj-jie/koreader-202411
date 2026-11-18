#!/bin/bash
set -eo pipefail

if [ -z "$1" ]; then
  echo "Usage: $0 <target_host> <target_folder>"
  echo "Error: Missing target host."
  exit 1
fi

if [ -z "$2" ]; then
  echo "Usage: $0 <target_host> <target_folder>"
  echo "Error: Missing target folder."
  exit 2
fi

TARGET="$1"
TARGET_DIR="${2%/}"

REMOTE_PATHS=()
while IFS= read -r item || [ -n "${item}" ]; do
  case "${item}" in
    "" | "#"*) continue ;;
  esac
  REMOTE_PATHS+=("${TARGET_DIR}/koreader/${item}")
done < "$(dirname "${BASH_SOURCE[0]}")/koreader/data/removed-files.txt"

ssh "root@${TARGET}" rm -rf -- "${REMOTE_PATHS[@]}"
