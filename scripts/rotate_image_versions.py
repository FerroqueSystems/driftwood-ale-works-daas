#!/usr/bin/env python3
"""Edits environments/citrix-azure/rotation.auto.tfvars.json for the monthly
Patch-Tuesday image/machine-catalog rotation (see
.github/workflows/citrix-image-rotation.yml). Caps how many simultaneous
entries "build" will stage in image_versions (--max-entries, default 5) -
purely a soft guardrail against unbounded catalog sprawl, since cutover and
decommission both operate per-label regardless of how many entries exist.
Tune the default up or down as the team's build cadence changes.
"""
import argparse
import json
import sys


def load(path):
    with open(path) as f:
        return json.load(f)


def save(path, data):
    with open(path, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")


def cmd_build(args, data):
    versions = data["image_versions"]
    if len(versions) >= args.max_entries and args.label not in versions:
        sys.exit(
            f"refusing to add '{args.label}': {len(versions)} entries already "
            f"present ({', '.join(versions)}) - max_entries is {args.max_entries}. "
            "Decommission an outgoing build first, or raise --max-entries."
        )
    # Preserve machine_count/machine_naming_scheme/catalog_name if this label
    # already exists (e.g. re-running build to refresh an already-live
    # catalog's image/total_machines) - changing naming_scheme or a machine
    # catalog's name after creation forces Citrix to destroy and recreate it,
    # and machine_count must stay whatever it already was (only a brand new
    # label starts at machine_count 0 - staged, not yet serving sessions,
    # ramped up via a later cutover).
    existing = versions.get(args.label, {})
    versions[args.label] = {
        "gallery_image_version": args.gallery_version,
        "total_machines": args.total_machines,
        "machine_count": existing.get("machine_count", 0),
        "machine_naming_scheme": existing.get("machine_naming_scheme", args.naming_scheme),
        "catalog_name": existing.get("catalog_name", f"{args.catalog_name_prefix}-{args.label}"),
    }


def cmd_cutover(args, data):
    versions = data["image_versions"]
    if args.new_label not in versions:
        sys.exit(f"'{args.new_label}' not found - run the build action first")
    versions[args.new_label]["machine_count"] = args.machine_count
    if args.old_label:
        if args.old_label not in versions:
            sys.exit(f"'{args.old_label}' not found in {list(versions)}")
        versions[args.old_label]["machine_count"] = 0


def cmd_decommission(args, data):
    versions = data["image_versions"]
    if args.label not in versions:
        sys.exit(f"'{args.label}' not found in {list(versions)}")
    if versions[args.label]["machine_count"] != 0:
        sys.exit(
            f"refusing to decommission '{args.label}': machine_count is "
            f"{versions[args.label]['machine_count']}, not 0 - run the cutover "
            "action first and confirm sessions have drained"
        )
    del versions[args.label]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("file", help="path to rotation.auto.tfvars.json")
    sub = parser.add_subparsers(dest="action", required=True)

    build = sub.add_parser("build", help="add a new build label, staged with machine_count=0")
    build.add_argument("--label", required=True)
    build.add_argument("--gallery-version", required=True)
    build.add_argument("--total-machines", type=int, required=True)
    build.add_argument(
        "--naming-scheme",
        required=True,
        help="MCS machine account naming scheme for a brand new label - ignored if --label already exists",
    )
    build.add_argument(
        "--catalog-name-prefix",
        required=True,
        help="machine catalog is named '<prefix>-<label>' for a brand new label - ignored if --label already exists",
    )
    build.add_argument(
        "--max-entries",
        type=int,
        default=5,
        help="refuse to stage a brand new label once image_versions already has this many entries (default 5) - existing labels can always be re-built/cut over/decommissioned regardless of this cap",
    )
    build.set_defaults(func=cmd_build)

    cutover = sub.add_parser("cutover", help="ramp the new label up, the old label down to 0")
    cutover.add_argument("--new-label", required=True)
    cutover.add_argument("--machine-count", type=int, required=True)
    cutover.add_argument("--old-label", required=False)
    cutover.set_defaults(func=cmd_cutover)

    decommission = sub.add_parser("decommission", help="remove a fully-drained (machine_count=0) label")
    decommission.add_argument("--label", required=True)
    decommission.set_defaults(func=cmd_decommission)

    args = parser.parse_args()
    data = load(args.file)
    args.func(args, data)
    save(args.file, data)
    print(json.dumps(data, indent=2))


if __name__ == "__main__":
    main()
