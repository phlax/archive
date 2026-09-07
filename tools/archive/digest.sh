#!/usr/bin/env bash

# Shared content-digest helpers for the archive write side (`publish.sh`,
# `backfill.sh`).
#
# The digest is a sha256 over the sorted lines "<relative-path>
# <sha256-hex-of-file>" for every regular file in a docs tree, where
# <relative-path> is relative to the tree root. Because it is computed from
# the files themselves rather than anything the storage backend happens to
# expose, it can be recomputed by anyone with a copy of the tree.

# archive_tree_digest <dir> -> prints "sha256:<hex>" for the tree.
archive_tree_digest() {
    local dir="$1"
    local count
    count="$(find "${dir}" -type f | wc -l | tr -d ' ')"
    if [[ "${count}" -eq 0 ]]; then
        echo "ERROR: cannot compute digest, no regular files under ${dir}" >&2
        return 1
    fi
    local hex
    hex="$(cd "${dir}" && find . -type f -print0 | sort -z | xargs -0 sha256sum | sed 's|  \./|  |' | awk '{print $2 " " $1}' | LC_ALL=C sort | sha256sum | cut -d' ' -f1)"
    printf 'sha256:%s\n' "${hex}"
}

# archive_tree_objects <dir> -> count of regular files.
archive_tree_objects() {
    local dir="$1"
    find "${dir}" -type f | wc -l | tr -d ' '
}

# archive_write_sidecar <version> <dir> <out-file> -> writes the sidecar JSON
# for <dir> to <out-file>.
archive_write_sidecar() {
    local version="$1" dir="$2" out="$3"
    local digest objects published
    digest="$(archive_tree_digest "${dir}")"
    objects="$(archive_tree_objects "${dir}")"
    published="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '{"version": "%s", "digest": "%s", "objects": %s, "published": "%s"}\n' \
        "${version}" "${digest}" "${objects}" "${published}" > "${out}"
}
