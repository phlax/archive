# Build (or update) the archive manifest.
#
# `existing` (may be `{}`) is the manifest currently in the meta bucket.
# `have` is the sorted list of versions present in the archive bucket.
# `new_entries` is a `{version: meta}` object for versions in `have` that are
# not already recorded in `existing` (freshly computed, eg by digest_lines.jq
# + version_meta in manifest.sh).
#
# Existing entries are carried forward untouched for any version still in
# `have` - published docs are immutable, so a recorded digest is never
# recomputed. `dropped` lists versions recorded in `existing` that are no
# longer in `have`, for the caller to warn about.
#
# Usage: jq -n -L tools/archive/jq -f manifest.jq \
#          --slurpfile existing <existing.json> \
#          --slurpfile have <have.json> \
#          --slurpfile new_entries <new_entries.json> \
#          --arg archive <archive-url> \
#          --arg generated <timestamp> \
#          --argjson stable_minors <n>

import "versions" as v;

($existing[0] // {}) as $existing_manifest
| ($existing_manifest.versions // {}) as $existing_versions
| ($have[0]) as $have_versions
| ($new_entries[0] // {}) as $new
| (reduce $have_versions[] as $ver ({};
      .[$ver] = (if ($existing_versions | has($ver)) then $existing_versions[$ver] else $new[$ver] end)
    )) as $versions
| ([$existing_versions | keys[] as $ver | select(($have_versions | index($ver)) | not) | $ver]) as $dropped
| {
    manifest: {
      generated: $generated,
      archive: $archive,
      versions: $versions,
      classification: ($versions | v::classify($stable_minors))
    },
    dropped: $dropped
  }
