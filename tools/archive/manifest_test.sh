#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=tools/archive/manifest.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/manifest.sh"

while [[ $# -gt 0 ]]; do
    case "$1" in
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

RCLONE_BIN=/bin/true
archive_init_tools
export ARCHIVE_GENERATED="2026-09-06T12:00:00Z"

TESTDATA="$(cd "$(dirname "${BASH_SOURCE[0]}")/testdata" && pwd)"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "${WORKDIR}"' EXIT

archive_list_objects() {
    local _bucket="$1"
    local version="$2"
    cat "${TESTDATA}/${version}-objects.json"
}

archive_create_manifest \
    archive \
    "${TESTDATA}/existing-manifest.json" \
    "${TESTDATA}/have.json" \
    "${WORKDIR}/updated.json" \
    "${WORKDIR}" \
    2> "${WORKDIR}/warnings.log"

if ! grep -Fq 'WARNING: v1.38.0 is recorded in the manifest but is not present in the archive bucket' "${WORKDIR}/warnings.log"; then
    echo "missing drop warning" >&2
    cat "${WORKDIR}/warnings.log" >&2
    exit 1
fi

expected_digest="sha256:$(printf 'api/index.html bbb\nindex.html aaa\n' | sha256sum | cut -d' ' -f1)"
actual_digest="$("${JQ_BIN}" -r '.versions["v1.40.0"].digest' "${WORKDIR}/updated.json")"
if [[ "${actual_digest}" != "${expected_digest}" ]]; then
    echo "digest mismatch: ${actual_digest} != ${expected_digest}" >&2
    exit 1
fi

"${JQ_BIN}" -e '
  .generated == "2026-09-06T12:00:00Z"
  and .archive == "gs://archive/envoy/docs"
  and .versions["v1.39.0"].digest == "sha256:old"
  and .versions["v1.39.0"].objects == 23
  and .versions["v1.39.0"].extra == "preserved"
  and (.versions | has("v1.38.0") | not)
  and .classification.latest == "v1.40.0"
  and (.classification.stable | keys_unsorted) == ["1.40", "1.39", "1.36", "1.35"]
  and (.classification.archived | keys_unsorted) == ["1.34", "1.33"]
' "${WORKDIR}/updated.json" >/dev/null

same_without_generated="$("${JQ_BIN}" '.generated = "different"' "${WORKDIR}/updated.json")"
printf '%s\n' "${same_without_generated}" > "${WORKDIR}/same.json"
if archive_manifest_changed "${WORKDIR}/same.json" "${WORKDIR}/updated.json"; then
    echo "manifest_changed should ignore generated" >&2
    exit 1
fi

if [[ "$(tail -c 1 "${WORKDIR}/updated.json")" != "" ]]; then
    echo "manifest is missing trailing newline" >&2
    exit 1
fi
