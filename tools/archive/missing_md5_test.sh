#!/usr/bin/env bash
set -euo pipefail

filter="$1"
fixture="$2"
if "${JQ_BIN}" -r -f "${filter}" "${fixture}" > "${TEST_TMPDIR}/out" 2> "${TEST_TMPDIR}/err"; then
    echo "expected digest_lines.jq to fail for missing MD5" >&2
    exit 1
fi
grep -Fq "missing MD5 hash" "${TEST_TMPDIR}/err"
