#!/usr/bin/env python3
"""Converts a flat HCL vars file (terraform .tfvars or Packer .pkrvars.hcl -
no resource/module blocks, just top-level `key = value` assignments) to JSON,
for pasting into a GitHub secret (TERRAFORM_TFVARS_JSON, PACKER_BUILD_VARS_JSON).

Usage:
    python3 scripts/hcl_vars_to_json.py environments/citrix-azure/terraform.tfvars
    python3 scripts/hcl_vars_to_json.py packer/images/win11-azure.pkrvars.hcl

Requires: pip install python-hcl2

python-hcl2 (8.1.2) has two quirks this cleans up before printing:
- string values come back with their literal quote marks still attached
  (e.g. '"eastus"' instead of 'eastus')
- standalone comments get collected into a "__comments__" key, which would
  otherwise land in the JSON as a bogus, undeclared Terraform/Packer variable
"""
import json
import sys

import hcl2


def clean(value):
    if isinstance(value, str) and len(value) >= 2 and value[0] == '"' and value[-1] == '"':
        return json.loads(value)
    if isinstance(value, list):
        return [clean(v) for v in value]
    if isinstance(value, dict):
        return {k: clean(v) for k, v in value.items() if k != "__comments__"}
    return value


def main():
    if len(sys.argv) != 2:
        sys.exit(f"usage: {sys.argv[0]} <path-to-tfvars-or-pkrvars-file>")

    with open(sys.argv[1]) as f:
        data = hcl2.load(f)

    print(json.dumps(clean(data)))


if __name__ == "__main__":
    main()
