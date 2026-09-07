# A single recursive `rclone lsjson --hash` listing of envoy/docs -> sorted
# raw lines: "<version> <relative-path> <Hashes.CRC32C>". The relative path is
# relative to that version's prefix; these lines are the input to sha256sum.
#
# CRC32C is used instead of MD5 because GCS does not populate MD5 for
# composite objects (created by parallel composite uploads, which
# `gcloud storage rsync` performs for larger files), while CRC32C is always
# present.

def digest_lines:
[
  .[]
  | select((.IsDir // false) | not)
  | (.Path // "") as $path
  | ($path | split("/")) as $parts
  | select(($parts | length) > 1)
  | ($parts[0]) as $version
  | select($version | test("^v[0-9]+\\.[0-9]+\\.[0-9]+$"))
  | ($parts[1:] | join("/")) as $relative
  | if (.Hashes.CRC32C // null) == null then
      error("missing CRC32C hash for \($path // "<unknown>")")
    else
      "\($version) \($relative) \(.Hashes.CRC32C)"
    end
]
| sort
| .[];
