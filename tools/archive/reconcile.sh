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
PLAN_INPUTS=""
OUTPUT=""
DRY_RUN=false
RCLONE_RLOCATION=""
MANIFEST_SH_RLOCATION=""
JQ_LIB_RLOCATION=""
JQ_LIST_VERSIONS_RLOCATION=""
JQ_MISSING_RLOCATION=""
JQ_SUMMARY_RLOCATION=""

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
        --plan-inputs)
            PLAN_INPUTS="$2"
            shift 2
            ;;
        --output)
            OUTPUT="$2"
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
        --jq-missing)
            JQ_MISSING_RLOCATION="$2"
            shift 2
            ;;
        --jq-summary)
            JQ_SUMMARY_RLOCATION="$2"
            shift 2
            ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 2
            ;;
    esac
done

if [[ -z "${ARCHIVE_BUCKET}" || -z "${PLAN_INPUTS}" ]]; then
    echo "Usage: $0 --archive-bucket <bucket> --plan-inputs <path> [--meta-bucket <bucket>] [--output <path>] [--dry-run]" >&2
    exit 2
fi

RCLONE_BIN="$(rlocation "${RCLONE_RLOCATION}")"
JQ_LIB_DIR="$(dirname "$(rlocation "${JQ_LIB_RLOCATION}")")"
JQ_LIST_VERSIONS="$(rlocation "${JQ_LIST_VERSIONS_RLOCATION}")"
JQ_MISSING="$(rlocation "${JQ_MISSING_RLOCATION}")"
JQ_SUMMARY="$(rlocation "${JQ_SUMMARY_RLOCATION}")"
PLAN_INPUTS_PATH="$(rlocation "${PLAN_INPUTS}")"

# shellcheck source=tools/archive/manifest.sh
source "$(rlocation "${MANIFEST_SH_RLOCATION}")"

archive_init_auth true

if [[ ! -f "${PLAN_INPUTS_PATH}" ]]; then
    echo "Plan inputs not found: ${PLAN_INPUTS_PATH}. This is built by //tools/archive:plan_inputs and resolved from runfiles, so this must be run with bazel run." >&2
    exit 1
fi

TMPDIR="$(mktemp -d)"
trap 'rm -rf "${TMPDIR}"' EXIT

archive_list_versions "${ARCHIVE_BUCKET}" > "${TMPDIR}/have.json"

"${JQ_BIN}" -n -L "${JQ_LIB_DIR}" -f "${JQ_MISSING}" \
    --slurpfile plan_inputs "${PLAN_INPUTS_PATH}" \
    --slurpfile have "${TMPDIR}/have.json" > "${TMPDIR}/plan.json"

if [[ -n "${OUTPUT}" ]]; then
    cp "${TMPDIR}/plan.json" "${OUTPUT}"
    "${JQ_BIN}" -r '.missing[]' "${TMPDIR}/plan.json" > "${OUTPUT}.missing.txt"
    printf 'plan written: %s\n' "${OUTPUT}"
fi

if [[ -n "${META_BUCKET}" ]]; then
    archive_fetch_manifest "${META_BUCKET}" > "${TMPDIR}/existing.json"
    "${JQ_BIN}" -n -r -L "${JQ_LIB_DIR}" -f "${JQ_SUMMARY}" \
        --arg archive_url "gs://${ARCHIVE_BUCKET}/${ARCHIVE_DOCS_PREFIX}" \
        --arg meta_url "gs://${META_BUCKET}/${ARCHIVE_MANIFEST_PATH}" \
        --argjson has_meta true \
        --slurpfile plan_inputs "${PLAN_INPUTS_PATH}" \
        --slurpfile plan "${TMPDIR}/plan.json" \
        --slurpfile existing "${TMPDIR}/existing.json"
else
    "${JQ_BIN}" -n -r -L "${JQ_LIB_DIR}" -f "${JQ_SUMMARY}" \
        --arg archive_url "gs://${ARCHIVE_BUCKET}/${ARCHIVE_DOCS_PREFIX}" \
        --arg meta_url "" \
        --argjson has_meta false \
        --slurpfile plan_inputs "${PLAN_INPUTS_PATH}" \
        --slurpfile plan "${TMPDIR}/plan.json" \
        --slurpfile existing <(printf '{}\n')
fi

if [[ "${DRY_RUN}" == true ]]; then
    echo "Dry run, nothing to do"
fi
