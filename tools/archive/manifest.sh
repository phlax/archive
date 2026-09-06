#!/usr/bin/env bash

# Sourced by reconcile.sh, publish.sh and manifest_test.sh: the rclone I/O
# layer for the archive bucket and its manifest. All jq logic lives in
# tools/archive/jq/*.jq - this file only shells out to rclone/jq.
#
# Callers resolve RCLONE_BIN, JQ_BIN and any `.jq` script paths they need via
# Bazel runfiles (see @bazel_tools//tools/bash/runfiles) *before* sourcing
# this file, since none of the resolution here is runfiles-aware.

ARCHIVE_DOCS_PREFIX="envoy/docs"
ARCHIVE_MANIFEST_PATH="${ARCHIVE_DOCS_PREFIX}/versions.json"
ARCHIVE_CACHE_CONTROL="public, max-age=31536000, immutable"
MANIFEST_CACHE_CONTROL="public, max-age=300"
STABLE_MINORS=4

# Configure rclone's GCS auth from the environment only.
#
#   - GCP_KEY_PATH set: use the service account key. Fails if the file isn't
#     readable.
#   - GCP_KEY_PATH unset: anonymous access if the caller passes `true` (only
#     appropriate for read-only paths); otherwise a hard failure, since
#     falling back to anonymous on a write path would fail late (401) after
#     already doing destructive/expensive work.
archive_init_auth() {
    local allow_anonymous="${1:-false}"
    export RCLONE_CONFIG_GCS_TYPE="google cloud storage"
    if [[ -n "${GCP_KEY_PATH:-}" ]]; then
        if [[ ! -r "${GCP_KEY_PATH}" ]]; then
            printf 'ERROR: GCP_KEY_PATH is set but not readable: %s\n' "${GCP_KEY_PATH}" >&2
            return 1
        fi
        export RCLONE_CONFIG_GCS_SERVICE_ACCOUNT_FILE="${GCP_KEY_PATH}"
        unset RCLONE_CONFIG_GCS_ANONYMOUS || true
        printf 'rclone auth: service account (%s)\n' "${GCP_KEY_PATH}" >&2
    elif [[ "${allow_anonymous}" == true ]]; then
        export RCLONE_CONFIG_GCS_ANONYMOUS="${RCLONE_CONFIG_GCS_ANONYMOUS:-true}"
        printf 'rclone auth: anonymous (read-only)\n' >&2
    else
        printf 'ERROR: GCP_KEY_PATH is not set; refusing to fall back to anonymous access for a write path.\n' >&2
        return 1
    fi
}

archive_now() {
    if [[ -n "${ARCHIVE_GENERATED:-}" ]]; then
        printf '%s\n' "${ARCHIVE_GENERATED}"
    else
        date -u '+%Y-%m-%dT%H:%M:%SZ'
    fi
}

# The version-directory ("vX.Y.Z") prefixes under the archive bucket's docs
# prefix, semver-desc sorted.
archive_list_versions() {
    local bucket="$1"
    "${RCLONE_BIN}" --config /dev/null lsjson --dirs-only "gcs:${bucket}/${ARCHIVE_DOCS_PREFIX}/" \
        | "${JQ_BIN}" -L "${JQ_LIB_DIR}" -f "${JQ_LIST_VERSIONS}"
}

# The full recursive object listing (with MD5 hashes) for one version.
archive_list_objects() {
    local bucket="$1"
    local version="$2"
    "${RCLONE_BIN}" --config /dev/null lsjson --recursive --hash "gcs:${bucket}/${ARCHIVE_DOCS_PREFIX}/${version}"
}

archive_fetch_manifest() {
    local bucket="$1"
    if ! "${RCLONE_BIN}" --config /dev/null cat "gcs:${bucket}/${ARCHIVE_MANIFEST_PATH}" 2>/dev/null; then
        printf '{}\n'
    fi
}

archive_upload_manifest() {
    local bucket="$1"
    local manifest_file="$2"
    "${RCLONE_BIN}" --config /dev/null rcat \
        --header-upload "Cache-Control: ${MANIFEST_CACHE_CONTROL}" \
        "gcs:${bucket}/${ARCHIVE_MANIFEST_PATH}" < "${manifest_file}"
}
