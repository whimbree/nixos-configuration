#!/usr/bin/env python3
"""Sync .sops.yaml creation_rules for sops-enabled MicroVMs.

Reads bastion/vm-registry.nix for every VM flagged `sops = true`, derives each
one's age public key from the microvm key seed, and rewrites the marker-delimited
block in .sops.yaml so each VM secret is encrypted to:

    admin + recovery + bastion + <the VM's derived key>

(admin/recovery/bastion are referenced as the anchors defined in the hand-written
`keys:` section; the derived key is embedded as a literal age1... recipient, since
derived keys are not stored as anchors.)

After rewriting the policy, it runs `sops updatekeys` on each VM secret file so the
on-disk ciphertext matches the new recipient set. Pass --policy-only to rewrite
.sops.yaml without touching any secret files.

Only the marker block is owned by this script; everything else in .sops.yaml is
hand-written and preserved.
"""

import argparse
import base64
import importlib.util
import json
import subprocess
import sys
from pathlib import Path

BEGIN = "# >>> sops-sync-recipients: managed block (do not edit by hand) >>>"
END = "# <<< sops-sync-recipients: managed block <<<"

ROOT = Path(__file__).resolve().parents[2]
REGISTRY = ROOT / "bastion" / "vm-registry.nix"
SEED_FILE = ROOT / "secrets" / "microvm-key-seed.yaml"
SOPS_YAML = ROOT / ".sops.yaml"


def _load_derive():
    """Import the sibling derive-age-key.py (hyphen in name blocks plain import)."""
    path = Path(__file__).resolve().parent / "derive-age-key.py"
    spec = importlib.util.spec_from_file_location("derive_age_key", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def sops_vms():
    """Return the sorted list of VM names flagged `sops = true` in the registry."""
    expr = (
        f"let r = (import {REGISTRY}).vms; "
        f"in builtins.filter (n: (r.${{n}}.sops or false)) (builtins.attrNames r)"
    )
    out = subprocess.run(
        ["nix", "eval", "--json", "--impure", "--expr", expr],
        check=True,
        capture_output=True,
        text=True,
    )
    return json.loads(out.stdout)


def decrypt_seed():
    """Return the raw seed bytes by decrypting the microvm key seed via sops."""
    if not SEED_FILE.exists():
        sys.exit(f"error: {SEED_FILE} not found; create the microvm key seed first")
    out = subprocess.run(
        ["sops", "-d", "--extract", '["microvm-key-seed"]', str(SEED_FILE)],
        check=True,
        capture_output=True,
        text=True,
    )
    return base64.b64decode(out.stdout.strip())


def render_block(vms, seed, derive):
    """Render the managed creation_rules block for the given VMs."""
    lines = [BEGIN]
    for vm in vms:
        identity = derive.derive_identity(seed, vm)
        pub = derive.identity_to_recipient(identity)
        lines += [
            f"  # {vm}: derived key (sops-vm-pubkey {vm})",
            f"  - path_regex: secrets/bastion/{vm}\\.yaml$",
            "    key_groups:",
            "      - age:",
            "          - *admin",
            "          - *recovery",
            "          - *bastion",
            f"          - {pub}",
        ]
    lines.append(END)
    return "\n".join(lines)


def splice(text, block):
    """Replace the BEGIN..END region in text with block. Markers must exist."""
    if BEGIN not in text or END not in text:
        sys.exit(
            f"error: markers not found in {SOPS_YAML}. Add these two lines inside\n"
            f"creation_rules (the generator fills between them):\n  {BEGIN}\n  {END}"
        )
    head, rest = text.split(BEGIN, 1)
    _, tail = rest.split(END, 1)
    return head + block + tail


def main(argv):
    ap = argparse.ArgumentParser(description="Sync .sops.yaml for sops MicroVMs.")
    ap.add_argument(
        "--policy-only",
        action="store_true",
        help="rewrite .sops.yaml only; do not run `sops updatekeys` on secrets",
    )
    args = ap.parse_args(argv)

    derive = _load_derive()
    vms = sops_vms()
    if not vms:
        print("no VMs flagged `sops = true` in the registry; nothing to do")
        # Still rewrite to an empty managed block so removals take effect.
    seed = decrypt_seed()

    block = render_block(vms, seed, derive)
    text = SOPS_YAML.read_text()
    new = splice(text, block)
    if new != text:
        SOPS_YAML.write_text(new)
        print(f"updated managed block in {SOPS_YAML} ({len(vms)} VM(s))")
    else:
        print(f"{SOPS_YAML} already up to date")

    if args.policy_only:
        print("--policy-only: skipping `sops updatekeys`")
        return 0

    for vm in vms:
        secret = ROOT / "secrets" / "bastion" / f"{vm}.yaml"
        if not secret.exists():
            print(f"  skip updatekeys: {secret} does not exist yet")
            continue
        print(f"  sops updatekeys {secret.relative_to(ROOT)}")
        subprocess.run(["sops", "updatekeys", "--yes", str(secret)], check=True)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
