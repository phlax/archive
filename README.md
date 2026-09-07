# Envoy Proxy archive

This is an archive for the [Envoy Proxy](https://www.envoyproxy.io) documentation.

The built docs live in Google Cloud Storage, and the archive bucket is the
source of truth for what is published.

## Buckets

| | contents | retention | cache-control |
|---|---|---|---|
| `gs://$GCS_ARCHIVE_BUCKET` | `envoy/docs/vX.Y.Z/**` | immutable | `public, max-age=31536000, immutable` |
| `gs://$GCS_META_BUCKET` | `envoy/docs/versions.json` | none (mutable) | `public, max-age=300` |

Both are public read. `versions.json` is a manifest of what is published - it
is derived data and can be regenerated from a listing of the archive bucket at
any time.

Required repo configuration:

- Secret `GCS_ARCHIVE_KEY` — base64 encoded JSON key for a service account with
  `roles/storage.objectCreator` and `roles/storage.objectViewer` on the archive
  bucket, and `roles/storage.objectUser` on the meta bucket. It is consumed via
  `envoyproxy/toolshed/actions/gcp/setup`.
- Variable `GCS_ARCHIVE_BUCKET` — the name of the archive bucket.
- Variable `GCS_META_BUCKET` — the name of the meta bucket.

Authentication currently uses this long-lived service account key, matching the
existing envoy docs publishing setup. Migrating to OIDC/Workload Identity
Federation is a TODO.

## Syncing the archive

`.github/workflows/envoy-sync.yaml` runs a stateless sync - it holds no state in
git, and makes no commits.

`.github/workflows/ci.yaml` runs the `tools/archive` tests and a read-only
reconcile on every pull request.

The read side is a Bazel graph:

1. `//tools/archive:listing` and `//tools/archive:existing` are uncached local
   `genrule`s that use the pinned `@rclone//:rclone` binary to read the public
   buckets anonymously.
2. `//tools/archive:plan_inputs`, `:have`, `:plan`, `:missing_txt`,
   `:new_entries`, `:manifest`, `:changed`, `:dropped`, and `:summary` are
   `@aspect_bazel_lib` `jq()` actions. The jq programs live under
   `tools/archive/jq/` and share `versions.jq` for semver helpers.
3. `bazel build //tools/archive:plan` writes `bazel-bin/tools/archive/plan.json`.
   `bazel build //tools/archive:manifest` writes
   `bazel-bin/tools/archive/versions.json`.

The bucket names are Bazel `string_flag`s, defaulting to the public buckets
`envoy-cncf-archive` and `envoy-cncf-meta`. CI overrides them from repository
variables:

```console
$ bazel build \
    --//tools/archive:archive_bucket="$GCS_ARCHIVE_BUCKET" \
    --//tools/archive:meta_bucket="$GCS_META_BUCKET" \
    //tools/archive:plan //tools/archive:manifest //tools/archive:summary
```

The write side is deliberately small: `//tools/archive:publish` extracts one
docs tarball and uploads it with `rclone copy --ignore-existing`, and
`//tools/archive:publish_manifest` uploads `versions.json` only when
`changed.txt` says it changed. Both require `GCP_KEY_PATH` to point at a readable
service-account key.

To see what would be done without publishing anything, run the workflow with
`dry-run: true` (scheduled runs are dry runs), or locally build the read-side
targets and inspect the summary:

```console
$ bazel build //tools/archive:plan //tools/archive:missing_txt //tools/archive:summary
$ cat bazel-bin/tools/archive/summary.txt
```

### Manifest

`versions.json` records, for each published version, its minor version, the
number of objects published, when it was published, and a `digest`:

```console
$ sha256sum <<< "$(<relative-object-path> <md5-hex> for each object, sorted)"
```

The object path is relative to the version prefix, and the MD5 hex digest comes
from `rclone lsjson --hash`, so the digest can be recomputed by anyone with read
access to the bucket, without downloading the docs. Entries for versions that
are already recorded are never recomputed - published docs are immutable, and
the recorded digest is what they are verified against.

The manifest also carries the stable/archived classification of the published
versions, so the website can consume it in place of `versions.yaml`.

## `docs/`

The `docs/` directory holds the pre-migration copy of the archive in git. It is
no longer read or written by any workflow, and is scheduled for removal - do not
add anything that depends on it.
