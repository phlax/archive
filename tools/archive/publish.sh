#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=tools/archive/manifest.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/manifest.sh"

ARCHIVE_BUCKET=""
META_BUCKET=""
VERSION=""
TARBALL=""
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --archive-bucket)
            ARCHIVE_BUCKET="$2"
            shift 2
            ;;
        --meta-bucket)
            META_BUCKET="$2"
            shift 2
            ;;
        --version)
            VERSION="$2"
            shift 2
            ;;
        --tarball)
            TARBALL="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --rclone-bin)
            RCLONE_BIN="$2"
            shift 2
            ;;
        --jq-bin)
            JQ_BIN="$2"
            shift 2
            ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 2
            ;;
    esac
done

if [[ -z "${ARCHIVE_BUCKET}" || -z "${META_BUCKET}" || -z "${VERSION}" || -z "${TARBALL}" ]]; then
    echo "Usage: $0 --archive-bucket <bucket> --meta-bucket <bucket> --version <vX.Y.Z> --tarball <path> [--dry-run]" >&2
    exit 2
fi
if [[ ! -f "${TARBALL}" ]]; then
    echo "Tarball not found: ${TARBALL}" >&2
    exit 1
fi

archive_init_tools
archive_init_auth

TMPDIR="$(mktemp -d)"
trap 'rm -rf "${TMPDIR}"' EXIT
DOCS_DIR="${TMPDIR}/docs"
mkdir -p "${DOCS_DIR}"
tar -xzf "${TARBALL}" -C "${DOCS_DIR}"
files="$(find "${DOCS_DIR}" -type f | wc -l | tr -d ' ')"
printf 'Publishing %s (%s files)\n' "${VERSION}" "${files}"

if [[ "${DRY_RUN}" == true ]]; then
    printf 'Dry run, not uploading to gs://%s/%s/%s\n' "${ARCHIVE_BUCKET}" "${ARCHIVE_DOCS_PREFIX}" "${VERSION}"
    exit 0
fi

# Copy only missing objects. The archive bucket is immutable, so re-runs must be
# resumable without overwriting already published files.
"${RCLONE_BIN}" --config /dev/null copy \
    --ignore-existing \
    --header-upload "Cache-Control: ${ARCHIVE_CACHE_CONTROL}" \
    "${DOCS_DIR}" \
    "gcs:${ARCHIVE_BUCKET}/${ARCHIVE_DOCS_PREFIX}/${VERSION}"

archive_list_objects "${ARCHIVE_BUCKET}" "${VERSION}" > "${TMPDIR}/published-objects.json"
published="$(archive_count_objects < "${TMPDIR}/published-objects.json")"
if [[ "${published}" != "${files}" ]]; then
    printf 'ERROR: %s published %s objects, expected %s\n' "${VERSION}" "${published}" "${files}" >&2
    exit 1
fi
printf 'Published %s (%s objects)\n' "${VERSION}" "${published}"

archive_update_manifest "${ARCHIVE_BUCKET}" "${META_BUCKET}"
