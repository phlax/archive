# Human-readable reconcile summary lines.

import "versions" as v;

def list_or_dash: if length == 0 then "-" else join(" ") end;
def chomp: rtrimstr("\n");

($plan_inputs[0]) as $inputs
| ($plan[0]) as $plan
| ($existing[0].versions // {} | keys) as $recorded
| ([$plan.have[] as $version | select(($recorded | index($version)) | not) | $version] | v::sort_versions) as $unrecorded
| ($archive_bucket | chomp) as $archive
| ($meta_bucket | chomp) as $meta
| [
    "archive: gs://\($archive)/envoy/docs",
    "have: \($plan.have | length)",
    "want: \($inputs.want | length)",
    "missing (\($plan.missing | length)): \($plan.missing | list_or_dash)",
    "excluded (\($inputs.excluded | length)): \($inputs.excluded | list_or_dash)",
    "manifest: gs://\($meta)/envoy/docs/versions.json",
    "manifest versions: \($recorded | length)"
  ]
  + (if ($unrecorded | length) > 0 then
      ["manifest is out of date, missing (\($unrecorded | length)): \($unrecorded | join(" "))"]
    else
      []
    end)
| .[]
