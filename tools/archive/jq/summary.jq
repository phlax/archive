# Human-readable `reconcile` summary lines, so bash does one `jq -r` instead
# of several. All transform logic (recorded/unrecorded, formatting empty
# lists as "-") lives here rather than in reconcile.sh.
#
# Usage: jq -n -r -L tools/archive/jq -f summary.jq \
#          --arg archive_url <gs://...> \
#          --arg meta_url <gs://...>            (ignored unless $has_meta) \
#          --argjson has_meta <true|false> \
#          --slurpfile plan_inputs <plan_inputs.json> \
#          --slurpfile plan <plan.json> \
#          --slurpfile existing <existing.json>  (ignored unless $has_meta)

import "versions" as v;

def list_or_dash: if length == 0 then "-" else join(" ") end;

($plan_inputs[0]) as $inputs
| ($plan[0]) as $plan
| [
    "archive: \($archive_url)",
    "have: \($plan.have | length)",
    "want: \($inputs.want | length)",
    "missing (\($plan.missing | length)): \($plan.missing | list_or_dash)",
    "excluded (\($inputs.excluded | length)): \($inputs.excluded | list_or_dash)"
  ]
+ (
    if $has_meta then
      ($existing[0].versions // {} | keys) as $recorded
      | ([$plan.have[] as $version | select(($recorded | index($version)) | not) | $version] | v::sort_versions) as $unrecorded
      | [
          "manifest: \($meta_url)",
          "manifest versions: \($recorded | length)"
        ]
        + (
            if ($unrecorded | length) > 0 then
              ["manifest is out of date, missing (\($unrecorded | length)): \($unrecorded | join(" "))"]
            else
              []
            end
          )
    else
      []
    end
  )
| .[]
