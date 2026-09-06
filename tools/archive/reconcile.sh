#!/usr/bin/env bash
set -euo pipefail

# Resolve relative to this script for direct execution and Bazel runfiles.
# shellcheck source=tools/archive/manifest.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/manifest.sh"

ARCHIVE_BUCKET=""
META_BUCKET=""
PROJECT_JSON=""
OUTPUT=""
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
        --project-json)
            PROJECT_JSON="$2"
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

if [[ -z "${ARCHIVE_BUCKET}" || -z "${PROJECT_JSON}" ]]; then
    echo "Usage: $0 --archive-bucket <bucket> --project-json <path> [--meta-bucket <bucket>] [--output <path>] [--dry-run]" >&2
    exit 2
fi

archive_init_tools
archive_init_auth

if [[ ! -f "${PROJECT_JSON}" ]]; then
    echo "Envoy project data not found: ${PROJECT_JSON}. This is provided by @envoy_repo//:project and resolved from runfiles, so this must be run with bazel run." >&2
    exit 1
fi

TMPDIR="$(mktemp -d)"
trap 'rm -rf "${TMPDIR}"' EXIT

archive_list_versions "${ARCHIVE_BUCKET}" > "${TMPDIR}/have.json"

"${JQ_BIN}" '
  def semver: ltrimstr("v") | split(".") | map(tonumber);
  def minor: ltrimstr("v") | split(".") | .[0:2] | join(".");
  def sort_versions: sort_by(semver) | reverse;
  .stable_versions as $stable
  | [
      .releases[]
      | if startswith("v") then . else "v" + . end
      | select((minor) as $minor | $stable | index($minor))
    ]
  | sort_versions
' "${PROJECT_JSON}" > "${TMPDIR}/want.json"

"${JQ_BIN}" '
  def semver: ltrimstr("v") | split(".") | map(tonumber);
  def minor: ltrimstr("v") | split(".") | .[0:2] | join(".");
  def sort_versions: sort_by(semver) | reverse;
  .stable_versions as $stable
  | [
      .releases[]
      | if startswith("v") then . else "v" + . end
      | select(((minor) as $minor | $stable | index($minor)) | not)
    ]
  | sort_versions
' "${PROJECT_JSON}" > "${TMPDIR}/excluded.json"

"${JQ_BIN}" -n \
    --slurpfile want "${TMPDIR}/want.json" \
    --slurpfile have "${TMPDIR}/have.json" '
  def semver: ltrimstr("v") | split(".") | map(tonumber);
  def sort_versions: sort_by(semver) | reverse;
  ($have[0]) as $have_versions
  | [ $want[0][] as $version | select(($have_versions | index($version)) | not) | $version ] | sort_versions
' > "${TMPDIR}/missing.json"

have_count="$("${JQ_BIN}" 'length' "${TMPDIR}/have.json")"
want_count="$("${JQ_BIN}" 'length' "${TMPDIR}/want.json")"
missing_count="$("${JQ_BIN}" 'length' "${TMPDIR}/missing.json")"
missing_versions="$("${JQ_BIN}" -r 'join(" ")' "${TMPDIR}/missing.json")"
excluded_count="$("${JQ_BIN}" 'length' "${TMPDIR}/excluded.json")"
excluded_versions="$("${JQ_BIN}" -r 'join(" ")' "${TMPDIR}/excluded.json")"

printf 'archive: gs://%s/%s\n' "${ARCHIVE_BUCKET}" "${ARCHIVE_DOCS_PREFIX}"
printf 'have: %s\n' "${have_count}"
printf 'want: %s\n' "${want_count}"
printf 'missing (%s): %s\n' "${missing_count}" "${missing_versions:-'-'}"
printf 'excluded (%s): %s\n' "${excluded_count}" "${excluded_versions:-'-'}"

if [[ -n "${META_BUCKET}" ]]; then
    archive_fetch_manifest "${META_BUCKET}" > "${TMPDIR}/existing.json"
    recorded_count="$("${JQ_BIN}" '.versions // {} | length' "${TMPDIR}/existing.json")"
    unrecorded="$("${JQ_BIN}" -n -r \
        --slurpfile have "${TMPDIR}/have.json" \
        --slurpfile existing "${TMPDIR}/existing.json" '
      def semver: ltrimstr("v") | split(".") | map(tonumber);
      def sort_versions: sort_by(semver) | reverse;
      ($existing[0].versions // {} | keys) as $recorded
      | [ $have[0][] as $version | select(($recorded | index($version)) | not) | $version ] | sort_versions | join(" ")
    ')"
    printf 'manifest: gs://%s/%s\n' "${META_BUCKET}" "${ARCHIVE_MANIFEST_PATH}"
    printf 'manifest versions: %s\n' "${recorded_count}"
    if [[ -n "${unrecorded}" ]]; then
        unrecorded_count="$(wc -w <<< "${unrecorded}" | tr -d ' ')"
        printf 'manifest is out of date, missing (%s): %s\n' "${unrecorded_count}" "${unrecorded}"
    fi
fi

if [[ -n "${OUTPUT}" ]]; then
    "${JQ_BIN}" -n \
        --slurpfile missing "${TMPDIR}/missing.json" \
        --slurpfile have "${TMPDIR}/have.json" \
        '{missing: $missing[0], have: $have[0]}' > "${OUTPUT}"
    printf 'plan written: %s\n' "${OUTPUT}"
fi

if [[ "${DRY_RUN}" == true ]]; then
    echo "Dry run, nothing to do"
fi
