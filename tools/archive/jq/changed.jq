# Is the manifest meaningfully different from what's currently published,
# ignoring `.generated` (which always changes)? Invoke with `-e`: exit 0 (and
# print `true`) if changed, exit 1 (and print `false`) if not.
#
# Usage: jq -n -e -f changed.jq \
#          --slurpfile existing <existing.json> \
#          --slurpfile updated <updated.json>

($existing[0] // {} | del(.generated)) != ($updated[0] // {} | del(.generated))
