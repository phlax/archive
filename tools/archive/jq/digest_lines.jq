# A single recursive `rclone lsjson --hash` listing of envoy/docs -> sorted
# raw lines: "<version> <relative-path> <Hashes.MD5>". The relative path is
# relative to that version's prefix; these lines are the input to sha256sum.

[
  .[]
  | select((.IsDir // false) | not)
  | (.Path // "") as $path
  | ($path | split("/")) as $parts
  | select(($parts | length) > 1)
  | ($parts[0]) as $version
  | select($version | test("^v[0-9]+\\.[0-9]+\\.[0-9]+$"))
  | ($parts[1:] | join("/")) as $relative
  | if (.Hashes.MD5 // null) == null then
      error("missing MD5 hash for \($path // "<unknown>")")
    else
      "\($version) \($relative) \(.Hashes.MD5)"
    end
]
| sort
| .[]
