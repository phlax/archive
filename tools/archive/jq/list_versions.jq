# rclone `lsjson --dirs-only` output (the `envoy/docs/` prefix listing in the
# archive bucket) -> sorted (desc) array of "vX.Y.Z" version-directory names.
#
# Usage: jq -L tools/archive/jq -f list_versions.jq

import "versions" as v;

[.[] | .Name | select(startswith("v"))] | v::sort_versions
