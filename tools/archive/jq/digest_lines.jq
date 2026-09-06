# rclone `lsjson --hash` output (array of file objects) -> sorted
# "<Path> <Hashes.MD5>" lines (invoke with `-r`).
#
# Only `.Hashes.MD5` is accepted - rclone's gcs backend always populates it,
# so a missing value indicates something is wrong with the listing and the
# digest would silently be computed over incomplete data. Fail loudly instead.

[
  .[]
  | select((.IsDir // false) | not)
  | select(.Path != null)
  | if (.Hashes.MD5 // null) == null then
      error("missing MD5 hash for \(.Path // "<unknown>")")
    else
      "\(.Path) \(.Hashes.MD5)"
    end
]
| sort
| .[]
