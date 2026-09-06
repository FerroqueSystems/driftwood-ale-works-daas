#!/usr/bin/env python3
"""Edits environments/citrix-azure/rotation.auto.tfvars.json for the monthly
Patch-Tuesday image/machine-catalog rotation (see
.github/workflows/citrix-image-rotation.yml). catalog_rotation is nested per
environment ("dev"/"test"/"prod") - each environment's rotation state
(staged/live build labels, machine counts) is independent, even though the
same "YYMM-N" label means the same underlying gallery_image_version in every
environment (one shared Packer build feeds all three; each environment cuts
over to it on its own schedule). Caps how many simultaneous entries "build"
will stage PER ENVIRONMENT (--max-entries, default 5) - purely a soft
guardrail against unbounded catalog sprawl within one environment; cutover
and decommission both operate per-label regardless of how many entries
exist, and one environment's entry count never affects another's cap.
"""
import argparse
import json
import sys

ENVIRONMENTS = ["dev", "test", "prod"]


def load(path):
    with open(path) as f:
        return json.load(f)


def save(path, data):
    with open(path, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")


def cmd_build(args, data):
    env_versions = data["catalog_rotation"].setdefault(args.env, {})
    if len(env_versions) >= args.max_entries and args.label not in env_versions:
        sys.exit(
            f"refusing to add '{args.label}' to {args.env}: {len(env_versions)} "
            f"entries already present in {args.env} "
            f"({', '.join(env_versions)}) - max_entries is {args.max_entries}. "
            "Decommission an outgoing build first, or raise --max-entries."
        )
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
    del env_versions[args.label]


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
    build.add_argument(
        "--max-entries",
        type=int,
        default=5,
        help="refuse to stage a brand new label once this environment already has this many entries (default 5, applied per environment) - existing labels can always be re-built/cut over/decommissioned regardless of this cap",
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

    args = parser.parse_args()
    data = load(args.file)
    data.setdefault("catalog_rotation", {env: {} for env in ENVIRONMENTS})
    args.func(args, data)
    save(args.file, data)
    print(json.dumps(data, indent=2))


if __name__ == "__main__":
    main()
