#!/usr/bin/env bash

ARCHIVE_DOCS_PREFIX="envoy/docs"
ARCHIVE_MANIFEST_PATH="${ARCHIVE_DOCS_PREFIX}/versions.json"
ARCHIVE_CACHE_CONTROL="public, max-age=31536000, immutable"
MANIFEST_CACHE_CONTROL="public, max-age=300"
STABLE_MINORS=4

RCLONE_BIN="${RCLONE_BIN:-rclone}"
JQ_BIN="${JQ_BIN:-jq}"

archive_resolve_tool() {
    local tool="$1"
    if command -v "${tool}" >/dev/null 2>&1; then
        command -v "${tool}"
        return 0
    fi
    local candidate
    for candidate in \
        "${tool}" \
        "${PWD}/${tool}" \
        "${RUNFILES_DIR:-}/${tool}" \
        "${RUNFILES_DIR:-}/${tool#../}" \
        "${RUNFILES_DIR:-}/${tool#external/}"; do
        if [[ -x "${candidate}" ]]; then
            printf '%s\n' "${candidate}"
            return 0
        fi
    done
    printf 'Unable to find executable: %s\n' "${tool}" >&2
    return 1
}

archive_init_tools() {
    RCLONE_BIN="$(archive_resolve_tool "${RCLONE_BIN}")"
    JQ_BIN="$(archive_resolve_tool "${JQ_BIN}")"
}

archive_init_auth() {
    export RCLONE_CONFIG_GCS_TYPE="google cloud storage"
    if [[ -n "${GCP_KEY_PATH:-}" ]]; then
        export RCLONE_CONFIG_GCS_SERVICE_ACCOUNT_FILE="${GCP_KEY_PATH}"
        unset RCLONE_CONFIG_GCS_ANONYMOUS || true
    else
        export RCLONE_CONFIG_GCS_ANONYMOUS="${RCLONE_CONFIG_GCS_ANONYMOUS:-true}"
    fi
}

archive_now() {
    if [[ -n "${ARCHIVE_GENERATED:-}" ]]; then
        printf '%s\n' "${ARCHIVE_GENERATED}"
    else
        date -u '+%Y-%m-%dT%H:%M:%SZ'
    fi
}

archive_list_versions() {
    local bucket="$1"
    "${RCLONE_BIN}" --config /dev/null lsjson --dirs-only "gcs:${bucket}/${ARCHIVE_DOCS_PREFIX}/" \
        | "${JQ_BIN}" '
          def semver: ltrimstr("v") | split(".") | map(tonumber);
          [ .[] | .Name | select(startswith("v")) ] | sort_by(semver) | reverse
        '
}

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

archive_count_objects() {
    "${JQ_BIN}" '[ .[] | select((.IsDir // false) | not) ] | length'
}

archive_digest_objects() {
    local lines_file="$1"
    local digest
    digest="$(sha256sum "${lines_file}" | cut -d' ' -f1)"
    printf 'sha256:%s\n' "${digest}"
}

archive_version_meta() {
    local version="$1"
    local objects_file="$2"
    local lines_file="$3"
    local published="$4"

    "${JQ_BIN}" -r '
      [
        .[]
        | select((.IsDir // false) | not)
        | select(.Path != null)
        | {path: .Path, md5: (.Hashes.MD5 // .Hashes.md5 // .MD5 // .Md5 // .md5)}
        | select(.md5 != null and .md5 != "")
        | "\(.path) \(.md5)"
      ]
      | sort
      | .[]
    ' "${objects_file}" > "${lines_file}"
    local objects lines digest minor
    objects="$(archive_count_objects < "${objects_file}")"
    lines="$(wc -l < "${lines_file}" | tr -d ' ')"
    if [[ "${lines}" != "${objects}" ]]; then
        printf 'ERROR: %s has %s objects but only %s MD5 hashes in the rclone listing\n' "${version}" "${objects}" "${lines}" >&2
        return 1
    fi
    digest="$(archive_digest_objects "${lines_file}")"
    minor="$("${JQ_BIN}" -n -r --arg version "${version}" '$version | ltrimstr("v") | split(".") | .[0:2] | join(".")')"

    "${JQ_BIN}" -n \
        --arg minor "${minor}" \
        --arg digest "${digest}" \
        --argjson objects "${objects}" \
        --arg published "${published}" \
        '{minor: $minor, digest: $digest, objects: $objects, published: $published}'
}

archive_build_manifest() {
    local existing_file="$1"
    local have_file="$2"
    local entries_file="$3"
    local archive_url="$4"
    local generated="$5"

    "${JQ_BIN}" -n \
        --slurpfile existing "${existing_file}" \
        --slurpfile have "${have_file}" \
        --slurpfile entries "${entries_file}" \
        --arg archive "${archive_url}" \
        --arg generated "${generated}" \
        --argjson stable_minors "${STABLE_MINORS}" '
      def semver: ltrimstr("v") | split(".") | map(tonumber);
      def minor: ltrimstr("v") | split(".") | .[0:2] | join(".");
      def sort_versions: sort_by(semver) | reverse;
      def classify($versions):
        ($versions | keys | sort_versions) as $all
        | (reduce $all[] as $v ({}; .[$v | minor] += [$v])) as $minors
        | ($minors | keys | sort_by(split(".") | map(tonumber)) | reverse) as $minor_names
        | ($minor_names[:$stable_minors]) as $stable_names
        | {
            latest: (if ($all | length) == 0 then null else $all[0] end),
            stable: (reduce $stable_names[] as $m ({}; .[$m] = $minors[$m])),
            archived: (reduce ($minor_names[] as $m | select(($stable_names | index($m)) | not) | $m) as $m ({}; .[$m] = $minors[$m]))
          };
      ($entries[0] // []) as $entry_list
      | (reduce $entry_list[] as $entry ({}; .[$entry.version] = $entry.meta)) as $versions
      | {
          generated: $generated,
          archive: $archive,
          versions: $versions,
          classification: classify($versions)
        }
    '
}

archive_manifest_changed() {
    local existing_file="$1"
    local updated_file="$2"
    ! "${JQ_BIN}" -n -e --slurpfile existing "${existing_file}" --slurpfile updated "${updated_file}" '
      ($existing[0] // {} | del(.generated)) == ($updated[0] // {} | del(.generated))
    ' >/dev/null
}

archive_create_manifest() {
    local archive_bucket="$1"
    local existing_file="$2"
    local have_file="$3"
    local output_file="$4"
    local workdir="$5"

    local entries_file="${workdir}/entries.jsonl"
    : > "${entries_file}"

    while read -r version; do
        if "${JQ_BIN}" -e --arg version "${version}" '(.versions // {}) | has($version)' "${existing_file}" >/dev/null; then
            "${JQ_BIN}" -c --arg version "${version}" '{version: $version, meta: .versions[$version]}' "${existing_file}" >> "${entries_file}"
        else
            local objects_file="${workdir}/${version}-objects.json"
            local lines_file="${workdir}/${version}-digest-lines.txt"
            archive_list_objects "${archive_bucket}" "${version}" > "${objects_file}"
            archive_version_meta "${version}" "${objects_file}" "${lines_file}" "$(archive_now)" \
                | "${JQ_BIN}" -c --arg version "${version}" '{version: $version, meta: .}' >> "${entries_file}"
        fi
    done < <("${JQ_BIN}" -r '.[]' "${have_file}")

    while read -r version; do
        if ! "${JQ_BIN}" -e --arg version "${version}" 'index($version)' "${have_file}" >/dev/null; then
            printf 'WARNING: %s is recorded in the manifest but is not present in the archive bucket, dropping the entry. This should not happen and may indicate bucket tampering.\n' "${version}" >&2
        fi
    done < <("${JQ_BIN}" -r '.versions // {} | keys[]' "${existing_file}")

    "${JQ_BIN}" -s '.' "${entries_file}" > "${workdir}/entries.json"
    archive_build_manifest \
        "${existing_file}" \
        "${have_file}" \
        "${workdir}/entries.json" \
        "gs://${archive_bucket}/${ARCHIVE_DOCS_PREFIX}" \
        "$(archive_now)" > "${output_file}"
}

archive_update_manifest() {
    local archive_bucket="$1"
    local meta_bucket="$2"
    local workdir
    workdir="$(mktemp -d)"
    trap 'rm -rf "${workdir}"' RETURN

    archive_fetch_manifest "${meta_bucket}" > "${workdir}/existing.json"
    archive_list_versions "${archive_bucket}" > "${workdir}/have.json"
    archive_create_manifest "${archive_bucket}" "${workdir}/existing.json" "${workdir}/have.json" "${workdir}/updated.json" "${workdir}"

    if ! archive_manifest_changed "${workdir}/existing.json" "${workdir}/updated.json"; then
        echo "Manifest is up to date, not updating"
        return 0
    fi

    "${RCLONE_BIN}" --config /dev/null rcat \
        --header-upload "Cache-Control: ${MANIFEST_CACHE_CONTROL}" \
        "gcs:${meta_bucket}/${ARCHIVE_MANIFEST_PATH}" < "${workdir}/updated.json"
    printf 'Manifest updated: gs://%s/%s\n' "${meta_bucket}" "${ARCHIVE_MANIFEST_PATH}"
}
