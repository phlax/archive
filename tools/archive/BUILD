load("@aspect_bazel_lib//lib:jq.bzl", "jq")
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("@rules_shell//shell:sh_test.bzl", "sh_test")

# Build-time transform of `@envoy_repo//:project` into the `want`/`excluded`
# version plan - a pure function of the Envoy release metadata, so it runs as
# a `jq()` action rather than at `reconcile` run time.
jq(
    name = "plan_inputs",
    srcs = ["@envoy_repo//:project"],
    filter_file = "jq/plan.jq",
    args = [
        "-L",
        "tools/archive/jq",
    ],
    data = ["jq/versions.jq"],
)

sh_test(
    name = "manifest_test",
    srcs = ["manifest_test.sh"],
    args = [
        "--jq-lib=$(rlocationpath jq/versions.jq)",
        "--jq-plan=$(rlocationpath jq/plan.jq)",
        "--jq-missing=$(rlocationpath jq/missing.jq)",
        "--jq-digest-lines=$(rlocationpath jq/digest_lines.jq)",
        "--jq-manifest=$(rlocationpath jq/manifest.jq)",
        "--jq-changed=$(rlocationpath jq/changed.jq)",
        "--testdata=$(rlocationpath testdata/existing-manifest.json)",
    ],
    data = [
        "jq/changed.jq",
        "jq/digest_lines.jq",
        "jq/manifest.jq",
        "jq/missing.jq",
        "jq/plan.jq",
        "jq/versions.jq",
        "testdata/existing-manifest.json",
        "testdata/have.json",
        "testdata/project.json",
        "testdata/v1.33.0-objects.json",
        "testdata/v1.34.0-objects.json",
        "testdata/v1.35.0-objects.json",
        "testdata/v1.36.0-objects.json",
        "testdata/v1.40.0-objects.json",
        "testdata/v1.99.0-objects-missing-md5.json",
        "@bazel_tools//tools/bash/runfiles",
        "@jq_toolchains//:resolved_toolchain",
    ],
    env = {"JQ_BIN": "$(JQ_BIN)"},
    toolchains = ["@jq_toolchains//:resolved_toolchain"],
)

sh_binary(
    name = "reconcile",
    srcs = ["reconcile.sh"],
    args = [
        "--plan-inputs=$(rlocationpath :plan_inputs)",
        "--rclone=$(rlocationpath @rclone//:rclone)",
        "--manifest-sh=$(rlocationpath manifest.sh)",
        "--jq-lib=$(rlocationpath jq/versions.jq)",
        "--jq-list-versions=$(rlocationpath jq/list_versions.jq)",
        "--jq-missing=$(rlocationpath jq/missing.jq)",
        "--jq-summary=$(rlocationpath jq/summary.jq)",
    ],
    data = [
        ":plan_inputs",
        "jq/list_versions.jq",
        "jq/missing.jq",
        "jq/summary.jq",
        "jq/versions.jq",
        "manifest.sh",
        "@bazel_tools//tools/bash/runfiles",
        "@jq_toolchains//:resolved_toolchain",
        "@rclone//:rclone",
    ],
    env = {"JQ_BIN": "$(JQ_BIN)"},
    toolchains = ["@jq_toolchains//:resolved_toolchain"],
    visibility = ["//visibility:public"],
)

sh_binary(
    name = "publish",
    srcs = ["publish.sh"],
    args = [
        "--rclone=$(rlocationpath @rclone//:rclone)",
        "--manifest-sh=$(rlocationpath manifest.sh)",
        "--jq-lib=$(rlocationpath jq/versions.jq)",
        "--jq-list-versions=$(rlocationpath jq/list_versions.jq)",
        "--jq-digest-lines=$(rlocationpath jq/digest_lines.jq)",
        "--jq-manifest=$(rlocationpath jq/manifest.jq)",
        "--jq-changed=$(rlocationpath jq/changed.jq)",
    ],
    data = [
        "jq/changed.jq",
        "jq/digest_lines.jq",
        "jq/list_versions.jq",
        "jq/manifest.jq",
        "jq/versions.jq",
        "manifest.sh",
        "@bazel_tools//tools/bash/runfiles",
        "@jq_toolchains//:resolved_toolchain",
        "@rclone//:rclone",
    ],
    env = {"JQ_BIN": "$(JQ_BIN)"},
    toolchains = ["@jq_toolchains//:resolved_toolchain"],
    visibility = ["//visibility:public"],
)
