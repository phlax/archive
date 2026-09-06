sh_test(
    name = "manifest_test",
    srcs = ["manifest_test.sh"],
    args = ["--jq-bin=$(rootpath @envoy//tools/jq)"],
    data = [
        "manifest.sh",
        "testdata/existing-manifest.json",
        "testdata/have.json",
        "testdata/v1.33.0-objects.json",
        "testdata/v1.34.0-objects.json",
        "testdata/v1.35.0-objects.json",
        "testdata/v1.36.0-objects.json",
        "testdata/v1.40.0-objects.json",
        "@envoy//tools/jq",
    ],
)

sh_binary(
    name = "reconcile",
    srcs = ["reconcile.sh"],
    args = [
        "--project-json=$(rootpath @envoy_repo//:project)",
        "--rclone-bin=$(rootpath @rclone_linux_amd64//:rclone)",
        "--jq-bin=$(rootpath @envoy//tools/jq)",
    ],
    data = [
        "manifest.sh",
        "@envoy//tools/jq",
        "@envoy_repo//:project",
        "@rclone_linux_amd64//:rclone",
    ],
    visibility = ["//visibility:public"],
)

sh_binary(
    name = "publish",
    srcs = ["publish.sh"],
    args = [
        "--rclone-bin=$(rootpath @rclone_linux_amd64//:rclone)",
        "--jq-bin=$(rootpath @envoy//tools/jq)",
    ],
    data = [
        "manifest.sh",
        "@envoy//tools/jq",
        "@rclone_linux_amd64//:rclone",
    ],
    visibility = ["//visibility:public"],
)
