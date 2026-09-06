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

JQ_LIB_RLOCATION=""
JQ_PLAN_RLOCATION=""
JQ_MISSING_RLOCATION=""
JQ_DIGEST_LINES_RLOCATION=""
JQ_MANIFEST_RLOCATION=""
JQ_CHANGED_RLOCATION=""
TESTDATA_RLOCATION=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --jq-lib)
            JQ_LIB_RLOCATION="$2"
            shift 2
            ;;
        --jq-plan)
            JQ_PLAN_RLOCATION="$2"
            shift 2
            ;;
        --jq-missing)
            JQ_MISSING_RLOCATION="$2"
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
        --testdata)
            TESTDATA_RLOCATION="$2"
            shift 2
            ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 2
            ;;
    esac
done

JQ_LIB_DIR="$(dirname "$(rlocation "${JQ_LIB_RLOCATION}")")"
JQ_PLAN="$(rlocation "${JQ_PLAN_RLOCATION}")"
JQ_MISSING="$(rlocation "${JQ_MISSING_RLOCATION}")"
JQ_DIGEST_LINES="$(rlocation "${JQ_DIGEST_LINES_RLOCATION}")"
JQ_MANIFEST="$(rlocation "${JQ_MANIFEST_RLOCATION}")"
JQ_CHANGED="$(rlocation "${JQ_CHANGED_RLOCATION}")"
TESTDATA="$(dirname "$(rlocation "${TESTDATA_RLOCATION}")")"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "${WORKDIR}"' EXIT

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

# --- plan.jq ---------------------------------------------------------------

"${JQ_BIN}" -L "${JQ_LIB_DIR}" -f "${JQ_PLAN}" "${TESTDATA}/project.json" > "${WORKDIR}/plan_inputs.json"

"${JQ_BIN}" -e '
  .want == ["v1.40.0", "v1.39.0", "v1.36.0", "v1.35.0"]
  and .excluded == ["v1.34.0", "v1.33.0"]
' "${WORKDIR}/plan_inputs.json" >/dev/null || fail "plan.jq: unexpected want/excluded"

# --- missing.jq --------------------------------------------------------------

"${JQ_BIN}" -n -L "${JQ_LIB_DIR}" -f "${JQ_MISSING}" \
    --slurpfile plan_inputs "${WORKDIR}/plan_inputs.json" \
    --slurpfile have "${TESTDATA}/have.json" > "${WORKDIR}/plan.json"

"${JQ_BIN}" -e '
  .missing == []
  and .have == ["v1.40.0", "v1.39.0", "v1.36.0", "v1.35.0", "v1.34.0", "v1.33.0"]
' "${WORKDIR}/plan.json" >/dev/null || fail "missing.jq: unexpected plan (have already covers want)"

# Same inputs but with a `have` list missing one wanted version.
"${JQ_BIN}" '[.[] | select(. != "v1.36.0")]' "${TESTDATA}/have.json" > "${WORKDIR}/have-partial.json"
"${JQ_BIN}" -n -L "${JQ_LIB_DIR}" -f "${JQ_MISSING}" \
    --slurpfile plan_inputs "${WORKDIR}/plan_inputs.json" \
    --slurpfile have "${WORKDIR}/have-partial.json" > "${WORKDIR}/plan-partial.json"

"${JQ_BIN}" -e '.missing == ["v1.36.0"]' "${WORKDIR}/plan-partial.json" >/dev/null \
    || fail "missing.jq: expected v1.36.0 to be reported missing"

# --- digest_lines.jq ---------------------------------------------------------

actual_lines="$("${JQ_BIN}" -r -f "${JQ_DIGEST_LINES}" "${TESTDATA}/v1.40.0-objects.json")"
expected_lines="$(printf 'api/index.html bbb\nindex.html aaa')"
if [[ "${actual_lines}" != "${expected_lines}" ]]; then
    fail "digest_lines.jq: expected [${expected_lines}], got [${actual_lines}]"
fi

if "${JQ_BIN}" -r -f "${JQ_DIGEST_LINES}" "${TESTDATA}/v1.99.0-objects-missing-md5.json" > "${WORKDIR}/digest-lines-error.out" 2>"${WORKDIR}/digest-lines-error.err"; then
    fail "digest_lines.jq: expected an error for a missing MD5 hash"
fi
grep -Fq "missing MD5 hash" "${WORKDIR}/digest-lines-error.err" || fail "digest_lines.jq: expected a 'missing MD5 hash' error message"

# --- manifest.jq -------------------------------------------------------------

NEW_ENTRIES="${WORKDIR}/new-entries.json"
: > "${WORKDIR}/new-entries.jsonl"
for version in v1.40.0 v1.36.0 v1.35.0 v1.34.0 v1.33.0; do
    lines="$("${JQ_BIN}" -r -f "${JQ_DIGEST_LINES}" "${TESTDATA}/${version}-objects.json")"
    digest="sha256:$(printf '%s\n' "${lines}" | sha256sum | cut -d' ' -f1)"
    objects="$(printf '%s\n' "${lines}" | wc -l | tr -d ' ')"
    "${JQ_BIN}" -n -c \
        --arg version "${version}" \
        --arg minor "${version#v}" \
        --arg digest "${digest}" \
        --argjson objects "${objects}" \
        --arg published "2026-09-06T12:00:00Z" \
        '{version: $version, meta: {minor: ($minor | split(".") | .[0:2] | join(".")), digest: $digest, objects: $objects, published: $published}}' \
        >> "${WORKDIR}/new-entries.jsonl"
done
"${JQ_BIN}" -s 'map({(.version): .meta}) | add' "${WORKDIR}/new-entries.jsonl" > "${NEW_ENTRIES}"

"${JQ_BIN}" -n -L "${JQ_LIB_DIR}" -f "${JQ_MANIFEST}" \
    --slurpfile existing "${TESTDATA}/existing-manifest.json" \
    --slurpfile have "${TESTDATA}/have.json" \
    --slurpfile new_entries "${NEW_ENTRIES}" \
    --arg archive "gs://archive/envoy/docs" \
    --arg generated "2026-09-06T12:00:00Z" \
    --argjson stable_minors 4 > "${WORKDIR}/build-output.json"

"${JQ_BIN}" -e '.dropped == ["v1.38.0"]' "${WORKDIR}/build-output.json" >/dev/null \
    || fail "manifest.jq: expected v1.38.0 to be dropped"

"${JQ_BIN}" '.manifest' "${WORKDIR}/build-output.json" > "${WORKDIR}/updated.json"

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
' "${WORKDIR}/updated.json" >/dev/null || fail "manifest.jq: unexpected carry-forward/classification"

if [[ "$(tail -c 1 "${WORKDIR}/updated.json")" != "" ]]; then
    fail "manifest.jq: manifest is missing trailing newline"
fi

# --- changed.jq --------------------------------------------------------------

"${JQ_BIN}" '.generated = "different"' "${WORKDIR}/updated.json" > "${WORKDIR}/same.json"
if "${JQ_BIN}" -n -e -f "${JQ_CHANGED}" \
    --slurpfile existing "${WORKDIR}/same.json" \
    --slurpfile updated "${WORKDIR}/updated.json" >/dev/null; then
    fail "changed.jq: should ignore .generated"
fi

if ! "${JQ_BIN}" -n -e -f "${JQ_CHANGED}" \
    --slurpfile existing "${TESTDATA}/existing-manifest.json" \
    --slurpfile updated "${WORKDIR}/updated.json" >/dev/null; then
    fail "changed.jq: should detect a real difference"
fi

echo "PASS"
