#!/usr/bin/env bash
# Download rosbag data from Azure Blob Storage using azcopy.
#
# Required environment variables (set via OSMO credentials):
#   AZURE_STORAGE_ACCOUNT  — Storage account name
#   AZURE_STORAGE_SAS      — SAS token (with read + list permissions)
#
# Optional environment variables:
#   AZURE_BLOB_CONTAINER   — Container name (default: datasets)
#   AZURE_BLOB_PREFIX      — Blob prefix to download (default: houston_recordings/)
#   BLOB_DEST_DIR          — Local destination (default: /data/rosbags)
set -euo pipefail

CONTAINER="${AZURE_BLOB_CONTAINER:-datasets}"
PREFIX="${AZURE_BLOB_PREFIX:-houston_recordings/}"
DEST="${BLOB_DEST_DIR:-/data/rosbags}"

if [ -z "${AZURE_STORAGE_ACCOUNT:-}" ] || [ -z "${AZURE_STORAGE_SAS:-}" ]; then
    echo "ERROR: AZURE_STORAGE_ACCOUNT and AZURE_STORAGE_SAS must be set."
    exit 1
fi

SOURCE_URL="https://${AZURE_STORAGE_ACCOUNT}.blob.core.windows.net/${CONTAINER}/${PREFIX}?${AZURE_STORAGE_SAS}"

echo "Downloading rosbag data from Azure Blob Storage..."
echo "  Account:   ${AZURE_STORAGE_ACCOUNT}"
echo "  Container: ${CONTAINER}"
echo "  Prefix:    ${PREFIX}"
echo "  Dest:      ${DEST}"

mkdir -p "${DEST}"

azcopy copy "${SOURCE_URL}" "${DEST}" --recursive --log-level ERROR

echo "Download complete — $(find "${DEST}" -type f | wc -l) files in ${DEST}"
