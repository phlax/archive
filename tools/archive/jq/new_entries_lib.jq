# Shared by new_entries.jq (production) and the missing-sidecar test.
#
# Builds `{version: meta}` entries for versions present in `have` but absent
# from the existing manifest, using each version's per-version sidecar
# written by `//tools/archive:publish` (or backfilled by
# `//tools/archive:backfill`) at
# gs://$META_BUCKET/envoy/docs/versions/<version>.json.

import "versions" as v;

def new_entries:
  ($existing[0].versions // {}) as $existing_versions
  | ($have[0]) as $have_versions
  | ($sidecars[0] // {}) as $sidecar_map
  | reduce ($have_versions[] as $version | select(($existing_versions | has($version)) | not) | $version) as $version ({};
      ($sidecar_map[$version] // error("no sidecar for \($version); run //tools/archive:backfill")) as $sidecar
      | .[$version] = {
          minor: ($version | v::minor),
          digest: $sidecar.digest,
          objects: $sidecar.objects,
          published: $sidecar.published
        }
    );
