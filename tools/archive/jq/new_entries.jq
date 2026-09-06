# Build `{version: meta}` entries for versions present in `have` but absent from
# the existing manifest. Digests are computed by the `:digests` genrule.

import "versions" as v;

($existing[0].versions // {}) as $existing_versions
| ($have[0]) as $have_versions
| ($digests[0] // {}) as $digests
| ($generated | rtrimstr("\n")) as $published
| reduce ($have_versions[] as $version | select(($existing_versions | has($version)) | not) | $version) as $version ({};
    ($digests[$version] // error("missing digest for \($version)")) as $digest
    | .[$version] = {
        minor: ($version | v::minor),
        digest: $digest.digest,
        objects: $digest.objects,
        published: $published
      }
  )
