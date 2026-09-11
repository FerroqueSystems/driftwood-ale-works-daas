#!/usr/bin/env python3
"""Edits environments/citrix-azure/rotation.auto.tfvars.json for the GitFlow-
driven image/machine-catalog rotation (see
.github/workflows/citrix-image-rotation.yml). catalog_rotation is nested per
environment ("dev"/"test"/"prod") - each environment's rotation state
(staged/live build labels, machine counts) is independent, even though the
same label means the same underlying gallery_image_version in every
environment (one shared Packer build feeds all three; each environment cuts
over to it on its own schedule - dev automatically on every push to a
working branch, test on merge to develop, prod on merge to main).

There is no cap on how many entries can accumulate in one environment
(there used to be a per-environment --max-entries hard block; retired since
GitFlow-triggered builds can create many more labels per day than the old
~monthly cadence did, and a hard block would just break iterative dev work).
Use `check-outstanding` instead - it warns (never blocks) when too many
labels are outstanding system-wide, as a nudge to decommission drained
builds rather than a gate.
"""
import argparse
import json
import os
import sys

ENVIRONMENTS = ["dev", "test", "prod"]


def load(path):
    with open(path) as f:
        return json.load(f)


def save(path, data):
    with open(path, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")


def write_github_output(values):
    gh_output = os.environ.get("GITHUB_OUTPUT")
    if not gh_output:
        return
    with open(gh_output, "a") as f:
        for key, value in values.items():
            f.write(f"{key}={value}\n")


def cmd_build(args, data):
    env_versions = data["catalog_rotation"].setdefault(args.env, {})
    # Preserve machine_count/machine_naming_scheme/catalog_name if this
    # (env, label) pair already exists (e.g. re-running build to refresh an
    # already-live catalog's image/total_machines) - changing naming_scheme
    # or a machine catalog's name after creation forces Citrix to destroy
    # and recreate it, and machine_count must stay whatever it already was
    # (only a brand new label starts at machine_count 0 - staged, not yet
    # serving sessions, ramped up via a later cutover).
    existing = env_versions.get(args.label, {})
    env_versions[args.label] = {
        "gallery_image_version": args.gallery_version,
        "total_machines": args.total_machines,
        "machine_count": existing.get("machine_count", 0),
        "machine_naming_scheme": existing.get("machine_naming_scheme", args.naming_scheme),
        "catalog_name": existing.get("catalog_name", f"{args.catalog_name_prefix}-{args.label}"),
    }


def cmd_cutover(args, data):
    env_versions = data["catalog_rotation"].get(args.env, {})
    if args.new_label not in env_versions:
        sys.exit(f"'{args.new_label}' not found in {args.env} - run the build action first")
    env_versions[args.new_label]["machine_count"] = args.machine_count
    if args.old_label:
        if args.old_label not in env_versions:
            sys.exit(f"'{args.old_label}' not found in {args.env} ({list(env_versions)})")
        env_versions[args.old_label]["machine_count"] = 0


def cmd_decommission(args, data):
    env_versions = data["catalog_rotation"].get(args.env, {})
    if args.label not in env_versions:
        sys.exit(f"'{args.label}' not found in {args.env} ({list(env_versions)})")
    if env_versions[args.label]["machine_count"] != 0:
        sys.exit(
            f"refusing to decommission '{args.label}' in {args.env}: machine_count is "
            f"{env_versions[args.label]['machine_count']}, not 0 - run the cutover "
            "action first and confirm sessions have drained"
        )
    removed = env_versions.pop(args.label)
    # The workflow needs this to delete the underlying Azure Compute Gallery
    # image version - read from the rotation state (which has always
    # recorded it authoritatively) rather than re-derived from the label
    # string, so this stays correct even for any older label that predates
    # the current "YYMM-N" convention.
    write_github_output({"gallery_image_version": removed["gallery_image_version"]})


def cmd_current_live(args, data):
    env_versions = data["catalog_rotation"].get(args.env, {})
    live = {
        label: v
        for label, v in env_versions.items()
        if v["machine_count"] > 0 and label != args.exclude
    }
    if len(live) > 1:
        sys.exit(
            f"more than one label is live in {args.env} simultaneously ({list(live)}) - "
            "this shouldn't happen outside a mid-cutover race, refusing to guess"
        )
    if not live:
        if args.required:
            sys.exit(f"nothing is currently live in {args.env} - nothing to promote")
        return
    label, v = next(iter(live.items()))
    write_github_output(
        {
            "label": label,
            "gallery_image_version": v["gallery_image_version"],
            "catalog_name": v["catalog_name"],
        }
    )


def cmd_check_outstanding(args, data):
    labels = sorted({label for env_map in data["catalog_rotation"].values() for label in env_map})
    print(f"{len(labels)} distinct image label(s) outstanding across dev/test/prod: {', '.join(labels) or '(none)'}")
    if len(labels) <= args.threshold:
        return
    msg = (
        f"{len(labels)} distinct image labels are currently outstanding across dev/test/prod "
        f"(threshold {args.threshold}): {', '.join(labels)} - consider decommissioning drained builds."
    )
    print(f"::warning::{msg}")
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a") as f:
            f.write(f"\n**Outstanding image labels warning:** {msg}\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("file", help="path to rotation.auto.tfvars.json")
    sub = parser.add_subparsers(dest="action", required=True)

    build = sub.add_parser("build", help="add a new build label to one environment, staged with machine_count=0")
    build.add_argument("--env", required=True, choices=ENVIRONMENTS)
    build.add_argument("--label", required=True)
    build.add_argument("--gallery-version", required=True)
    build.add_argument("--total-machines", type=int, required=True)
    build.add_argument(
        "--naming-scheme",
        required=True,
        help="MCS machine account naming scheme for a brand new (env, label) pair - ignored if it already exists",
    )
    build.add_argument(
        "--catalog-name-prefix",
        required=True,
        help="machine catalog is named '<prefix>-<label>' for a brand new (env, label) pair - ignored if it already exists",
    )
    build.set_defaults(func=cmd_build)

    cutover = sub.add_parser("cutover", help="ramp the new label up, the old label down to 0, within one environment")
    cutover.add_argument("--env", required=True, choices=ENVIRONMENTS)
    cutover.add_argument("--new-label", required=True)
    cutover.add_argument("--machine-count", type=int, required=True)
    cutover.add_argument("--old-label", required=False)
    cutover.set_defaults(func=cmd_cutover)

    decommission = sub.add_parser("decommission", help="remove a fully-drained (machine_count=0) label from one environment")
    decommission.add_argument("--env", required=True, choices=ENVIRONMENTS)
    decommission.add_argument("--label", required=True)
    decommission.set_defaults(func=cmd_decommission)

    current_live = sub.add_parser(
        "current-live",
        help="find the label currently live (machine_count > 0) in one environment, for promoting it into another",
    )
    current_live.add_argument("--env", required=True, choices=ENVIRONMENTS)
    current_live.add_argument(
        "--exclude",
        default=None,
        help="ignore this label even if live - used when looking up an outgoing label to phase out, so promoting a label into an environment it's already live in doesn't treat itself as the thing to drain",
    )
    current_live.add_argument(
        "--required",
        action="store_true",
        help="exit non-zero if nothing is live - use when looking up a source to promote from (must exist); omit when looking up an outgoing label to phase out (may legitimately be none)",
    )
    current_live.set_defaults(func=cmd_current_live)

    check_outstanding = sub.add_parser(
        "check-outstanding",
        help="warn (never block) if more than --threshold distinct image labels are outstanding across all environments",
    )
    check_outstanding.add_argument("--threshold", type=int, default=5)
    check_outstanding.set_defaults(func=cmd_check_outstanding)

    args = parser.parse_args()
    data = load(args.file)
    data.setdefault("catalog_rotation", {env: {} for env in ENVIRONMENTS})
    args.func(args, data)
    # current-live/check-outstanding are read-only - never write the file
    # back for those (avoids an unnecessary, unchanged git diff).
    if args.action not in ("current-live", "check-outstanding"):
        save(args.file, data)
    print(json.dumps(data, indent=2))


if __name__ == "__main__":
    main()
