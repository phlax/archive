#!/usr/bin/env bash
set -euo pipefail

# --- begin runfiles.bash initialization v3 ---
if [[ ! -d "${RUNFILES_DIR:-/dev/null}" && ! -f "${RUNFILES_MANIFEST_FILE:-/dev/null}" ]]; then
    if [[ -f "$0.runfiles_manifest" ]]; then
        export RUNFILES_MANIFEST_FILE="$0.runfiles_manifest"
    elif [[ -f "$0.runfiles/MANIFEST" ]]; then
        export RUNFILES_MANIFEST_FILE="$0.runfiles/MANIFEST"
    elif [[ -f "$0.runfiles/bazel_tools/tools/bash/runfiles/runfiles.bash" ]]; then
        export RUNFILES_DIR="$0.runfiles"
    fi
fi
if [[ -f "${RUNFILES_DIR:-/dev/null}/bazel_tools/tools/bash/runfiles/runfiles.bash" ]]; then
    # shellcheck disable=SC1090
    source "${RUNFILES_DIR}/bazel_tools/tools/bash/runfiles/runfiles.bash"
elif [[ -f "${RUNFILES_MANIFEST_FILE:-/dev/null}" ]]; then
    # shellcheck disable=SC1090
    source "$(grep -m1 "^bazel_tools/tools/bash/runfiles/runfiles.bash " "${RUNFILES_MANIFEST_FILE}" | cut -d ' ' -f2-)"
else
    echo "ERROR: cannot find @bazel_tools//tools/bash/runfiles:runfiles.bash" >&2
    exit 1
fi
# --- end runfiles.bash initialization v3 ---

ARCHIVE_BUCKET=""
META_BUCKET=""
VERSION=""
TARBALL=""
DRY_RUN=false
RCLONE_RLOCATION=""
MANIFEST_SH_RLOCATION=""
JQ_LIB_RLOCATION=""
JQ_LIST_VERSIONS_RLOCATION=""
JQ_DIGEST_LINES_RLOCATION=""
JQ_MANIFEST_RLOCATION=""
JQ_CHANGED_RLOCATION=""

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
        --rclone)
            RCLONE_RLOCATION="$2"
            shift 2
            ;;
        --manifest-sh)
            MANIFEST_SH_RLOCATION="$2"
            shift 2
            ;;
        --jq-lib)
            JQ_LIB_RLOCATION="$2"
            shift 2
            ;;
        --jq-list-versions)
            JQ_LIST_VERSIONS_RLOCATION="$2"
            shift 2
            ;;
        --jq-digest-lines)
            JQ_DIGEST_LINES_RLOCATION="$2"
            shift 2
            ;;
        --jq-manifest)
            JQ_MANIFEST_RLOCATION="$2"
            shift 2
            ;;
        --jq-changed)
            JQ_CHANGED_RLOCATION="$2"
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

RCLONE_BIN="$(rlocation "${RCLONE_RLOCATION}")"
JQ_LIB_DIR="$(dirname "$(rlocation "${JQ_LIB_RLOCATION}")")"
JQ_LIST_VERSIONS="$(rlocation "${JQ_LIST_VERSIONS_RLOCATION}")"
JQ_DIGEST_LINES="$(rlocation "${JQ_DIGEST_LINES_RLOCATION}")"
JQ_MANIFEST="$(rlocation "${JQ_MANIFEST_RLOCATION}")"
JQ_CHANGED="$(rlocation "${JQ_CHANGED_RLOCATION}")"

# shellcheck source=tools/archive/manifest.sh
source "$(rlocation "${MANIFEST_SH_RLOCATION}")"

# Hard-fail before doing anything - including extracting the tarball - if
# there is no usable service account key. This is a write path: falling back
# to anonymous would only fail late (401, after upload is attempted).
archive_init_auth false

# Build (or update) the manifest in the meta bucket after publishing. Existing
# entries are carried forward untouched; only versions in `have` that aren't
# already recorded get a freshly computed entry.
archive_update_manifest() {
    local archive_bucket="$1"
    local meta_bucket="$2"
    local workdir="$3"

    archive_fetch_manifest "${meta_bucket}" > "${workdir}/existing.json"
    archive_list_versions "${archive_bucket}" > "${workdir}/have.json"

    local new_entries_jsonl="${workdir}/new-entries.jsonl"
    : > "${new_entries_jsonl}"

    while read -r have_version; do
        if "${JQ_BIN}" -e --arg version "${have_version}" '(.versions // {}) | has($version)' "${workdir}/existing.json" >/dev/null; then
            continue
        fi

        local objects_file="${workdir}/${have_version}-objects.json"
        local lines_file="${workdir}/${have_version}-digest-lines.txt"
        archive_list_objects "${archive_bucket}" "${have_version}" > "${objects_file}"
        "${JQ_BIN}" -r -f "${JQ_DIGEST_LINES}" "${objects_file}" > "${lines_file}"

        local objects lines digest minor
        objects="$("${JQ_BIN}" '[ .[] | select((.IsDir // false) | not) ] | length' "${objects_file}")"
        lines="$(wc -l < "${lines_file}" | tr -d ' ')"
        if [[ "${lines}" != "${objects}" ]]; then
            printf 'ERROR: %s has %s objects but only %s MD5 hashes in the rclone listing\n' "${have_version}" "${objects}" "${lines}" >&2
            return 1
        fi
        digest="sha256:$(sha256sum "${lines_file}" | cut -d' ' -f1)"
        minor="$("${JQ_BIN}" -n -r --arg version "${have_version}" '$version | ltrimstr("v") | split(".") | .[0:2] | join(".")')"

        "${JQ_BIN}" -n -c \
            --arg version "${have_version}" \
            --arg minor "${minor}" \
            --arg digest "${digest}" \
            --argjson objects "${objects}" \
            --arg published "$(archive_now)" \
            '{version: $version, meta: {minor: $minor, digest: $digest, objects: $objects, published: $published}}' \
            >> "${new_entries_jsonl}"
    done < <("${JQ_BIN}" -r '.[]' "${workdir}/have.json")

    "${JQ_BIN}" -s 'map({(.version): .meta}) | add // {}' "${new_entries_jsonl}" > "${workdir}/new-entries.json"

    local build_output="${workdir}/build-output.json"
    local updated_file="${workdir}/updated.json"
    "${JQ_BIN}" -n -L "${JQ_LIB_DIR}" -f "${JQ_MANIFEST}" \
        --slurpfile existing "${workdir}/existing.json" \
        --slurpfile have "${workdir}/have.json" \
        --slurpfile new_entries "${workdir}/new-entries.json" \
        --arg archive "gs://${archive_bucket}/${ARCHIVE_DOCS_PREFIX}" \
        --arg generated "$(archive_now)" \
        --argjson stable_minors "${STABLE_MINORS}" > "${build_output}"

    "${JQ_BIN}" '.manifest' "${build_output}" > "${updated_file}"

    while read -r dropped_version; do
        [[ -n "${dropped_version}" ]] || continue
        printf 'WARNING: %s is recorded in the manifest but is not present in the archive bucket, dropping the entry. This should not happen and may indicate bucket tampering.\n' "${dropped_version}" >&2
    done < <("${JQ_BIN}" -r '.dropped[]' "${build_output}")

    if ! "${JQ_BIN}" -n -e -f "${JQ_CHANGED}" --slurpfile existing "${workdir}/existing.json" --slurpfile updated "${updated_file}" >/dev/null; then
        echo "Manifest is up to date, not updating"
        return 0
    fi

    archive_upload_manifest "${meta_bucket}" "${updated_file}"
    printf 'Manifest updated: gs://%s/%s\n' "${meta_bucket}" "${ARCHIVE_MANIFEST_PATH}"
}

TMPDIR="$(mktemp -d)"
trap 'rm -rf "${TMPDIR}"' EXIT
DOCS_DIR="${TMPDIR}/docs"
mkdir -p "${DOCS_DIR}"
tar --no-same-owner -xzf "${TARBALL}" -C "${DOCS_DIR}"
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
published="$("${JQ_BIN}" '[ .[] | select((.IsDir // false) | not) ] | length' "${TMPDIR}/published-objects.json")"
if [[ "${published}" != "${files}" ]]; then
    printf 'ERROR: %s published %s objects, expected %s\n' "${VERSION}" "${published}" "${files}" >&2
    exit 1
fi
printf 'Published %s (%s objects)\n' "${VERSION}" "${published}"

archive_update_manifest "${ARCHIVE_BUCKET}" "${META_BUCKET}" "${TMPDIR}"
