#!/usr/bin/env python3
"""Drains and powers off a Citrix DaaS machine catalog's machines - used by
.github/workflows/citrix-image-rotation.yml's promote-to-prod-and-drain job
to retire the outgoing Prod catalog after a cutover, without deleting
anything (actual decommission stays a separate, later, manual step).

Uses the Citrix Cloud DaaS REST API directly, not the citrix/citrix
Terraform provider - the provider has no per-machine (or per-catalog)
maintenance-mode support (confirmed against its resource docs; see
citrix/terraform-provider-citrix issues #176 and #219, both still open as
of this writing). The only whole-object option
(citrix_delivery_group.in_maintenance_mode) is too coarse for this purpose -
it would freeze the entire delivery group, including the machines just cut
over to, not just the outgoing catalog's machines.

IMPORTANT - lowest-confidence part of this repo's automation: the OAuth
token endpoint (get_token) is a well-documented, standard Citrix Cloud flow
and can be trusted. The Machines list/maintenance-mode/power-action
endpoints (resolve_catalog_id, list_machines, set_maintenance_mode,
power_off) could not be verified against live Citrix API reference docs in
the session that wrote this script - treat their exact paths/payloads as
best-available design, not confirmed fact, and validate against a real
Citrix Cloud tenant (or at least a non-prod catalog) before trusting this
against real production sessions.

Uses a dedicated Citrix Cloud API client (CITRIX_MAINTENANCE_CLIENT_ID/
CITRIX_MAINTENANCE_CLIENT_SECRET), deliberately separate from both the
Terraform provider's own client (citrix_client_id/CITRIX_CLIENT_SECRET) and
the Cloud Connectors' registration client (cloud_connector_client_id/
_secret) - same reasoning modules/cloud-connectors already established:
this script can drain and power off live production VDAs, a bigger blast
radius than either of those, so it shouldn't share a secret whose rotation
would also break something unrelated.

Stdlib only (urllib.request/json) - matches rotate_image_versions.py's
existing zero-third-party-dependency style, no new pip install step needed
in CI.
"""
import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request

API_BASE = "https://api.cloud.com"


def _request(method, url, token=None, customer_id=None, body=None):
    data = json.dumps(body).encode("utf-8") if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Accept", "application/json")
    if body is not None:
        req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", f"CwsAuth Bearer={token}")
    if customer_id:
        req.add_header("Citrix-CustomerId", customer_id)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            raw = resp.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", errors="replace")
        sys.exit(f"Citrix API call failed: {method} {url} -> HTTP {e.code}: {detail}")
    except urllib.error.URLError as e:
        sys.exit(f"Citrix API call failed: {method} {url} -> {e}")


def get_token(customer_id, client_id, client_secret):
    """Standard Citrix Cloud OAuth2 client-credentials flow - high confidence,
    well-documented and already the same mechanism the citrix/citrix
    Terraform provider itself uses."""
    url = f"{API_BASE}/cctrustoauth2/{customer_id}/tokens/clients"
    body = f"grant_type=client_credentials&client_id={client_id}&client_secret={client_secret}".encode("utf-8")
    req = urllib.request.Request(url, data=body, method="POST")
    req.add_header("Content-Type", "application/x-www-form-urlencoded")
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            result = json.loads(resp.read())
    except urllib.error.HTTPError as e:
        sys.exit(f"Citrix Cloud auth failed: HTTP {e.code}: {e.read().decode('utf-8', errors='replace')}")
    return result["access_token"]


def resolve_catalog_id(token, customer_id, catalog_name):
    """MEDIUM confidence on this endpoint's exact path/shape - verify against
    a live tenant before relying on it."""
    result = _request("GET", f"{API_BASE}/cvadapis/{customer_id}/MachineCatalogs", token, customer_id)
    for catalog in result.get("Items", []):
        if catalog.get("Name") == catalog_name:
            return catalog["Id"]
    sys.exit(f"Machine catalog '{catalog_name}' not found via the DaaS REST API")


def list_machines(token, customer_id, catalog_id):
    """LOW-MEDIUM confidence on the filter param name/shape - verify against
    the DaaS REST API reference before relying on it."""
    result = _request(
        "GET", f"{API_BASE}/cvadapis/{customer_id}/Machines?catalog={catalog_id}", token, customer_id
    )
    return result.get("Items", [])


def set_maintenance_mode(token, customer_id, machine_id, enabled):
    _request(
        "PATCH",
        f"{API_BASE}/cvadapis/{customer_id}/Machines/{machine_id}",
        token,
        customer_id,
        body={"InMaintenanceMode": enabled},
    )


def get_session_count(token, customer_id, machine_id):
    result = _request("GET", f"{API_BASE}/cvadapis/{customer_id}/Machines/{machine_id}", token, customer_id)
    return result.get("SessionCount", 0)


def power_off(token, customer_id, machine_id):
    """LOW confidence - the least-verified call in this script. Uses
    Citrix's own power-action mechanism rather than stopping the Azure VM
    directly via `az vm deallocate`/Stop-AzVM, deliberately: this
    environment's delivery groups have autoscale enabled, and Citrix's own
    autoscale engine is liable to fight (or flag a state mismatch against)
    a VM that was stopped out-of-band instead of through the broker."""
    _request(
        "POST",
        f"{API_BASE}/cvadapis/{customer_id}/Machines/{machine_id}/PowerAction",
        token,
        customer_id,
        body={"Action": "Shutdown"},
    )


def cmd_drain(args):
    client_id = os.environ.get("CITRIX_MAINTENANCE_CLIENT_ID")
    client_secret = os.environ.get("CITRIX_MAINTENANCE_CLIENT_SECRET")
    if not client_id or not client_secret:
        sys.exit("CITRIX_MAINTENANCE_CLIENT_ID and CITRIX_MAINTENANCE_CLIENT_SECRET must be set")

    token = get_token(args.customer_id, client_id, client_secret)
    catalog_id = resolve_catalog_id(token, args.customer_id, args.catalog_name)
    machines = list_machines(token, args.customer_id, catalog_id)

    if not machines:
        print(f"No machines found in catalog '{args.catalog_name}' - nothing to drain.")
        write_github_output({"still_occupied_count": 0, "still_occupied_machines": ""})
        return

    print(f"Setting maintenance mode on {len(machines)} machine(s) in '{args.catalog_name}'...")
    for machine in machines:
        set_maintenance_mode(token, args.customer_id, machine["Id"], True)

    pending = {m["Id"]: m["Name"] for m in machines}
    drained = []
    deadline = time.monotonic() + args.timeout_minutes * 60
    while pending and time.monotonic() < deadline:
        # Re-fetch a token each iteration - simplest way to avoid the ~1hr
        # token expiry edge case on a long-running drain, at the cost of a
        # few extra HTTP calls.
        token = get_token(args.customer_id, client_id, client_secret)
        for machine_id, name in list(pending.items()):
            session_count = get_session_count(token, args.customer_id, machine_id)
            if session_count == 0:
                print(f"{name} has drained (0 sessions) - powering off.")
                power_off(token, args.customer_id, machine_id)
                drained.append(name)
                del pending[machine_id]
            else:
                print(f"{name} still has {session_count} session(s) - waiting.")
        if pending:
            time.sleep(args.poll_interval_seconds)

    still_occupied = list(pending.values())
    if still_occupied:
        print(
            f"Timed out after {args.timeout_minutes} minute(s) with {len(still_occupied)} "
            f"machine(s) still occupied: {', '.join(still_occupied)} - left running, no "
            "forced logoff. Needs manual follow-up."
        )
    else:
        print("All machines drained and powered off.")

    write_github_output(
        {
            "still_occupied_count": len(still_occupied),
            "still_occupied_machines": ",".join(still_occupied),
        }
    )


def write_github_output(values):
    gh_output = os.environ.get("GITHUB_OUTPUT")
    if not gh_output:
        return
    with open(gh_output, "a") as f:
        for key, value in values.items():
            f.write(f"{key}={value}\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="action", required=True)

    drain = sub.add_parser(
        "drain",
        help="set maintenance mode on every machine in a catalog, power off each as it drains, within a bounded wait",
    )
    drain.add_argument("--customer-id", required=True)
    drain.add_argument("--catalog-name", required=True)
    drain.add_argument("--timeout-minutes", type=int, default=45)
    drain.add_argument("--poll-interval-seconds", type=int, default=60)
    drain.set_defaults(func=cmd_drain)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
