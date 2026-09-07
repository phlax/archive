load("@aspect_bazel_lib//lib:diff_test.bzl", "diff_test")
load("@aspect_bazel_lib//lib:jq.bzl", "jq")
load("@bazel_skylib//rules:common_settings.bzl", "string_flag")
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")
load("@rules_shell//shell:sh_test.bzl", "sh_test")
load(":archive_rules.bzl", "archive_no_cache_genrule", "archive_rclone_genrule", "string_flag_value")

ARCHIVE_JQ_ARGS = [
    "-L",
    "tools/archive/jq",
]

string_flag(
    name = "archive_bucket",
    build_setting_default = "envoy-cncf-archive",
    visibility = ["//visibility:public"],
)

string_flag(
    name = "meta_bucket",
    build_setting_default = "envoy-cncf-meta",
    visibility = ["//visibility:public"],
)

string_flag_value(
    name = "archive_bucket_value",
    flag = ":archive_bucket",
)

string_flag_value(
    name = "meta_bucket_value",
    flag = ":meta_bucket",
)

archive_rclone_genrule(
    name = "listing",
    outs = ["listing.json"],
    cmd = """
"$${RCLONE}" --config /dev/null lsjson --recursive --hash "gcs:$${ARCHIVE_BUCKET}/envoy/docs" > "$@"
""",
)

archive_rclone_genrule(
    name = "existing",
    outs = ["existing.json"],
    cmd = """
if ! "$${RCLONE}" --config /dev/null cat "gcs:$${META_BUCKET}/envoy/docs/versions.json" > "$@" 2>/dev/null; then
    printf '{}\n' > "$@"
fi
""",
)

archive_no_cache_genrule(
    name = "now",
    outs = ["now.txt"],
    cmd = "date -u +%Y-%m-%dT%H:%M:%SZ > \"$@\"",
)

jq(
    name = "plan_inputs",
    srcs = ["@envoy_repo//:project"],
    out = "plan_inputs.json",
    filter_file = "jq/plan.jq",
    args = ARCHIVE_JQ_ARGS,
    data = ["jq/versions.jq"],
)

jq(
    name = "have",
    srcs = [":listing"],
    out = "have.json",
    filter_file = "jq/have.jq",
    args = ARCHIVE_JQ_ARGS,
    data = ["jq/versions.jq"],
)

jq(
    name = "digest_lines",
    srcs = [":listing"],
    out = "digest_lines.txt",
    filter_file = "jq/digest_lines.jq",
    args = ["-r"],
)

archive_no_cache_genrule(
    name = "digests",
    srcs = [":digest_lines"],
    outs = ["digests.json"],
    cmd = """
work="$$(mktemp -d)"
trap 'rm -rf "$${work}"' EXIT
while read -r version relative md5; do
    [[ -n "$${version}" ]] || continue
    printf '%s %s\n' "$${relative}" "$${md5}" >> "$${work}/$${version}.lines"
done < "$(location :digest_lines)"
if ! compgen -G "$${work}/*.lines" >/dev/null; then
    printf '{}\n' > "$@"
    exit 0
fi
printf '{\n' > "$@"
sep=""
for lines in "$${work}"/*.lines; do
    version="$$(basename "$${lines}" .lines)"
    sort -o "$${lines}" "$${lines}"
    digest="$$(sha256sum "$${lines}" | cut -d' ' -f1)"
    objects="$$(wc -l < "$${lines}" | tr -d ' ')"
    if [[ -n "$${sep}" ]]; then printf ',\n' >> "$@"; fi
    printf '  "%s": {"digest": "sha256:%s", "objects": %s}' "$${version}" "$${digest}" "$${objects}" >> "$@"
    sep=1
done
printf '\n}\n' >> "$@"
""",
)

jq(
    name = "plan",
    srcs = [],
    out = "plan.json",
    filter_file = "jq/missing.jq",
    args = ARCHIVE_JQ_ARGS + [
        "-n",
        "--slurpfile",
        "plan_inputs",
        "$(location :plan_inputs)",
        "--slurpfile",
        "have",
        "$(location :have)",
    ],
    expand_args = True,
    data = [
        ":have",
        ":plan_inputs",
        "jq/versions.jq",
    ],
)

jq(
    name = "missing_txt",
    srcs = [":plan"],
    out = "missing.txt",
    filter_file = "jq/missing_txt.jq",
    args = ["-r"],
)

jq(
    name = "new_entries",
    srcs = [],
    out = "new_entries.json",
    filter_file = "jq/new_entries.jq",
    args = ARCHIVE_JQ_ARGS + [
        "-n",
        "--slurpfile",
        "existing",
        "$(location :existing)",
        "--slurpfile",
        "have",
        "$(location :have)",
        "--slurpfile",
        "digests",
        "$(location :digests)",
        "--rawfile",
        "generated",
        "$(location :now)",
    ],
    expand_args = True,
    data = [
        ":digests",
        ":existing",
        ":have",
        ":now",
        "jq/versions.jq",
    ],
)

jq(
    name = "manifest",
    srcs = [],
    out = "versions.json",
    filter_file = "jq/manifest.jq",
    args = ARCHIVE_JQ_ARGS + [
        "-n",
        "--slurpfile",
        "existing",
        "$(location :existing)",
        "--slurpfile",
        "have",
        "$(location :have)",
        "--slurpfile",
        "new_entries",
        "$(location :new_entries)",
        "--rawfile",
        "archive_bucket",
        "$(location :archive_bucket_value)",
        "--rawfile",
        "generated",
        "$(location :now)",
        "--argjson",
        "stable_minors",
        "4",
    ],
    expand_args = True,
    data = [
        ":archive_bucket_value",
        ":existing",
        ":have",
        ":new_entries",
        ":now",
        "jq/versions.jq",
    ],
)

jq(
    name = "dropped",
    srcs = [],
    out = "dropped.txt",
    filter_file = "jq/dropped.jq",
    args = ARCHIVE_JQ_ARGS + [
        "-n",
        "-r",
        "--slurpfile",
        "existing",
        "$(location :existing)",
        "--slurpfile",
        "have",
        "$(location :have)",
    ],
    expand_args = True,
    data = [
        ":existing",
        ":have",
        "jq/versions.jq",
    ],
)

jq(
    name = "changed",
    srcs = [],
    out = "changed.txt",
    filter_file = "jq/changed.jq",
    args = [
        "-n",
        "--slurpfile",
        "existing",
        "$(location :existing)",
        "--slurpfile",
        "manifest",
        "$(location :manifest)",
    ],
    expand_args = True,
    data = [
        ":existing",
        ":manifest",
    ],
)

jq(
    name = "summary",
    srcs = [],
    out = "summary.txt",
    filter_file = "jq/summary.jq",
    args = ARCHIVE_JQ_ARGS + [
        "-n",
        "-r",
        "--rawfile",
        "archive_bucket",
        "$(location :archive_bucket_value)",
        "--rawfile",
        "meta_bucket",
        "$(location :meta_bucket_value)",
        "--slurpfile",
        "plan_inputs",
        "$(location :plan_inputs)",
        "--slurpfile",
        "plan",
        "$(location :plan)",
        "--slurpfile",
        "existing",
        "$(location :existing)",
    ],
    expand_args = True,
    data = [
        ":archive_bucket_value",
        ":existing",
        ":meta_bucket_value",
        ":plan",
        ":plan_inputs",
        "jq/versions.jq",
    ],
)

sh_binary(
    name = "publish",
    srcs = ["publish.sh"],
    data = [
        ":archive_bucket_value",
        "runfiles.sh",
        "@rclone//:rclone",
    ],
    env = {
        "ARCHIVE_BUCKET_FILE": "$(rlocationpath :archive_bucket_value)",
        "RCLONE_BIN": "$(rlocationpath @rclone//:rclone)",
    },
    visibility = ["//visibility:public"],
)

sh_binary(
    name = "publish_manifest",
    srcs = ["publish_manifest.sh"],
    data = [
        ":changed",
        ":dropped",
        ":manifest",
        ":meta_bucket_value",
        "runfiles.sh",
        "@rclone//:rclone",
    ],
    env = {
        "CHANGED_FILE": "$(rlocationpath :changed)",
        "DROPPED_FILE": "$(rlocationpath :dropped)",
        "MANIFEST_FILE": "$(rlocationpath :manifest)",
        "META_BUCKET_FILE": "$(rlocationpath :meta_bucket_value)",
        "RCLONE_BIN": "$(rlocationpath @rclone//:rclone)",
    },
    visibility = ["//visibility:public"],
)

# Fixture transforms and golden-file tests.
jq(
    name = "plan_inputs_fixture",
    srcs = ["testdata/project.json"],
    out = "plan_inputs.fixture.json",
    filter_file = "jq/plan.jq",
    args = ARCHIVE_JQ_ARGS,
    data = ["jq/versions.jq"],
    testonly = True,
)

jq(
    name = "have_fixture",
    srcs = ["testdata/listing.json"],
    out = "have.fixture.json",
    filter_file = "jq/have.jq",
    args = ARCHIVE_JQ_ARGS,
    data = ["jq/versions.jq"],
    testonly = True,
)

jq(
    name = "digest_lines_fixture",
    srcs = ["testdata/listing.json"],
    out = "digest_lines.fixture.txt",
    filter_file = "jq/digest_lines.jq",
    args = ["-r"],
    testonly = True,
)

archive_no_cache_genrule(
    name = "digests_fixture",
    srcs = [":digest_lines_fixture"],
    outs = ["digests.fixture.json"],
    cmd = """
work="$$(mktemp -d)"
trap 'rm -rf "$${work}"' EXIT
while read -r version relative md5; do
    printf '%s %s\n' "$${relative}" "$${md5}" >> "$${work}/$${version}.lines"
done < "$(location :digest_lines_fixture)"
printf '{\n' > "$@"
sep=""
for lines in "$${work}"/*.lines; do
    version="$$(basename "$${lines}" .lines)"
    sort -o "$${lines}" "$${lines}"
    digest="$$(sha256sum "$${lines}" | cut -d' ' -f1)"
    objects="$$(wc -l < "$${lines}" | tr -d ' ')"
    if [[ -n "$${sep}" ]]; then printf ',\n' >> "$@"; fi
    printf '  "%s": {"digest": "sha256:%s", "objects": %s}' "$${version}" "$${digest}" "$${objects}" >> "$@"
    sep=1
done
printf '\n}\n' >> "$@"
""",
    testonly = True,
)

jq(
    name = "plan_fixture",
    srcs = [],
    out = "plan.fixture.json",
    filter_file = "jq/missing.jq",
    args = ARCHIVE_JQ_ARGS + [
        "-n",
        "--slurpfile",
        "plan_inputs",
        "$(location :plan_inputs_fixture)",
        "--slurpfile",
        "have",
        "$(location :have_fixture)",
    ],
    expand_args = True,
    data = [
        ":have_fixture",
        ":plan_inputs_fixture",
        "jq/versions.jq",
    ],
    testonly = True,
)

jq(
    name = "new_entries_fixture",
    srcs = [],
    out = "new_entries.fixture.json",
    filter_file = "jq/new_entries.jq",
    args = ARCHIVE_JQ_ARGS + [
        "-n",
        "--slurpfile",
        "existing",
        "$(location testdata/existing-manifest.json)",
        "--slurpfile",
        "have",
        "$(location :have_fixture)",
        "--slurpfile",
        "digests",
        "$(location :digests_fixture)",
        "--arg",
        "generated",
        "2026-09-06T12:00:00Z",
    ],
    expand_args = True,
    data = [
        ":digests_fixture",
        ":have_fixture",
        "jq/versions.jq",
        "testdata/existing-manifest.json",
    ],
    testonly = True,
)

jq(
    name = "manifest_fixture",
    srcs = [],
    out = "versions.fixture.json",
    filter_file = "jq/manifest.jq",
    args = ARCHIVE_JQ_ARGS + [
        "-n",
        "--slurpfile",
        "existing",
        "$(location testdata/existing-manifest.json)",
        "--slurpfile",
        "have",
        "$(location :have_fixture)",
        "--slurpfile",
        "new_entries",
        "$(location :new_entries_fixture)",
        "--arg",
        "archive_bucket",
        "archive",
        "--arg",
        "generated",
        "2026-09-06T12:00:00Z",
        "--argjson",
        "stable_minors",
        "4",
    ],
    expand_args = True,
    data = [
        ":have_fixture",
        ":new_entries_fixture",
        "jq/versions.jq",
        "testdata/existing-manifest.json",
    ],
    testonly = True,
)

jq(
    name = "dropped_fixture",
    srcs = [],
    out = "dropped.fixture.txt",
    filter_file = "jq/dropped.jq",
    args = ARCHIVE_JQ_ARGS + [
        "-n",
        "-r",
        "--slurpfile",
        "existing",
        "$(location testdata/existing-manifest.json)",
        "--slurpfile",
        "have",
        "$(location :have_fixture)",
    ],
    expand_args = True,
    data = [
        ":have_fixture",
        "jq/versions.jq",
        "testdata/existing-manifest.json",
    ],
    testonly = True,
)

jq(
    name = "changed_true_fixture",
    srcs = [],
    out = "changed_true.fixture.txt",
    filter_file = "jq/changed.jq",
    args = [
        "-n",
        "--slurpfile",
        "existing",
        "$(location testdata/existing-manifest.json)",
        "--slurpfile",
        "manifest",
        "$(location :manifest_fixture)",
    ],
    expand_args = True,
    data = [
        ":manifest_fixture",
        "testdata/existing-manifest.json",
    ],
    testonly = True,
)

jq(
    name = "changed_false_fixture",
    srcs = [],
    out = "changed_false.fixture.txt",
    filter_file = "jq/changed.jq",
    args = [
        "-n",
        "--slurpfile",
        "existing",
        "$(location testdata/manifest-same-generated.json)",
        "--slurpfile",
        "manifest",
        "$(location :manifest_fixture)",
    ],
    expand_args = True,
    data = [
        ":manifest_fixture",
        "testdata/manifest-same-generated.json",
    ],
    testonly = True,
)

jq(
    name = "summary_fixture",
    srcs = [],
    out = "summary.fixture.txt",
    filter_file = "jq/summary.jq",
    args = ARCHIVE_JQ_ARGS + [
        "-n",
        "-r",
        "--arg",
        "archive_bucket",
        "archive",
        "--arg",
        "meta_bucket",
        "meta",
        "--slurpfile",
        "plan_inputs",
        "$(location :plan_inputs_fixture)",
        "--slurpfile",
        "plan",
        "$(location :plan_fixture)",
        "--slurpfile",
        "existing",
        "$(location testdata/existing-manifest.json)",
    ],
    expand_args = True,
    data = [
        ":plan_fixture",
        ":plan_inputs_fixture",
        "jq/versions.jq",
        "testdata/existing-manifest.json",
    ],
    testonly = True,
)

[
    diff_test(
        name = name + "_test",
        file1 = ":" + name + "_fixture",
        file2 = "testdata/golden/" + golden,
    )
    for name, golden in {
        "changed_false": "changed_false.txt",
        "changed_true": "changed_true.txt",
        "digest_lines": "digest_lines.txt",
        "digests": "digests.json",
        "dropped": "dropped.txt",
        "have": "have.json",
        "manifest": "versions.json",
        "new_entries": "new_entries.json",
        "plan": "plan.json",
        "plan_inputs": "plan_inputs.json",
        "summary": "summary.txt",
    }.items()
]

sh_test(
    name = "missing_md5_test",
    srcs = ["missing_md5_test.sh"],
    args = [
        "$(rootpath jq/digest_lines.jq)",
        "$(rootpath testdata/listing-missing-md5.json)",
    ],
    data = [
        "jq/digest_lines.jq",
        "testdata/listing-missing-md5.json",
        "@jq_toolchains//:resolved_toolchain",
    ],
    env = {"JQ_BIN": "$(rootpath @jq_toolchains//:resolved_toolchain)"},
)
