#!/usr/bin/env python3
"""
gen-steps.py — Generates step constants, splash tables, and harness lists from payload/steps.tsv.

Single source of truth: payload/steps.tsv (id, owner, label).
Generates:
  - app/steps_gen.go (Go structs, constants, InstallerStepLabels)
  - tests/e2e/steps.sh (Bash arrays for harness and failure ledger)
  - payload/deployer/deploy.sh (phase() splash case table)
"""

import os
import sys
import re

ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
TSV_PATH = os.path.join(ROOT_DIR, "payload", "steps.tsv")
GO_PATH = os.path.join(ROOT_DIR, "app", "steps_gen.go")
SH_PATH = os.path.join(ROOT_DIR, "tests", "e2e", "steps.sh")
DEPLOY_PATH = os.path.join(ROOT_DIR, "payload", "deployer", "deploy.sh")

SPLASH_RANGES = {
    "ntfs-mounted": (6, 12),
    "scratch-setup": (12, 18),
    "network-wait": (16, 18),
    "bundle-ingest": (18, 24),
    "registry-preflight": (18, 24),
    "fisherman": (26, 86),
    "verification": (88, 95),
    "reboot": (100, 100),
}

CUSTOM_PASCAL_MAP = {
    "check-pc": "CheckPC",
    "prepare-windows": "PrepareWindows",
    "setting-up": "SettingUp",
    "finding-files": "FindingFiles",
    "make-room": "MakeRoom",
    "download-linux": "DownloadLinux",
    "download-system": "DownloadSystem",
    "prepare-startup-menu": "PrepareStartupMenu",
    "prepare-linux": "PrepareLinux",
    "make-bootable": "MakeBootable",
    "save-settings": "SaveSettings",
    "save-bitlocker-key": "SaveBitLockerKey",
    "inspect-apps": "InspectApps",
    "check-signed-in-apps": "CheckSignedInApps",
    "cloud-drives": "CloudDrives",
    "collect-look-wifi": "CollectLookWifi",
    "finishing-up": "FinishingUp",
    "ntfs-mounted": "NtfsMounted",
    "scratch-setup": "ScratchSetup",
    "network-wait": "NetworkWait",
    "bundle-ingest": "BundleIngest",
    "registry-preflight": "RegistryPreflight",
    "fisherman": "Fisherman",
    "verification": "Verification",
    "reboot": "Reboot",
    "firstboot-evidence": "FirstbootEvidence",
}

def to_pascal_case(ident: str) -> str:
    if ident in CUSTOM_PASCAL_MAP:
        return CUSTOM_PASCAL_MAP[ident]
    words = re.split(r'[-_]', ident)
    return "".join(w.capitalize() for w in words if w)

def parse_steps_tsv(tsv_path: str):
    steps = []
    seen_ids = set()
    with open(tsv_path, "r", encoding="utf-8") as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split("\t")
            if len(parts) != 3:
                raise ValueError(f"Line {line_num}: expected 3 tab-separated columns (id, owner, label), got {len(parts)}: {line}")
            step_id, owner, label = parts[0].strip(), parts[1].strip(), parts[2].strip()
            if not step_id or not owner or not label:
                raise ValueError(f"Line {line_num}: empty field found: id={step_id!r}, owner={owner!r}, label={label!r}")
            if owner not in ("installer", "deployer", "firstboot"):
                raise ValueError(f"Line {line_num}: invalid owner '{owner}', must be installer|deployer|firstboot")
            if step_id in seen_ids:
                raise ValueError(f"Line {line_num}: duplicate step id '{step_id}'")
            seen_ids.add(step_id)
            steps.append({"id": step_id, "owner": owner, "label": label})
    return steps

def generate_go_code(steps) -> str:
    lines = [
        "// Code generated from payload/steps.tsv by gen-steps.py; DO NOT EDIT.",
        "",
        "package main",
        "",
        "// Step represents a step or phase in the unified step catalogue.",
        "type Step struct {",
        "\tID    string `json:\"id\"`",
        "\tOwner string `json:\"owner\"`",
        "\tLabel string `json:\"label\"`",
        "}",
        "",
        "// AllSteps contains all steps across installer, deployer, and firstboot owners.",
        "var AllSteps = []Step{"
    ]
    for s in steps:
        lines.append(f'\t{{ID: "{s["id"]}", Owner: "{s["owner"]}", Label: "{s["label"]}"}},')
    lines.extend([
        "}",
        "",
        "// InstallerStepLabels contains the ordered labels of Phase-1 installer steps.",
        "var InstallerStepLabels = []string{"
    ])
    for s in steps:
        if s["owner"] == "installer":
            lines.append(f'\t"{s["label"]}",')
    lines.extend([
        "}",
        "",
        "// Step ID constants",
        "const ("
    ])
    for s in steps:
        pname = to_pascal_case(s["id"])
        lines.append(f'\tStep{pname} = "{s["id"]}"')
    lines.extend([
        ")",
        "",
        "// Step Label constants",
        "const ("
    ])
    for s in steps:
        pname = to_pascal_case(s["id"])
        lines.append(f'\tStepLabel{pname} = "{s["label"]}"')
    lines.extend([
        ")",
        ""
    ])
    return "\n".join(lines)

def generate_sh_code(steps) -> str:
    lines = [
        "#!/usr/bin/env bash",
        "# Code generated from payload/steps.tsv by gen-steps.py; DO NOT EDIT.",
        "",
        "# Ordered list of installer step IDs",
        "INSTALLER_STEPS=("
    ]
    for s in steps:
        if s["owner"] == "installer":
            lines.append(f'    "{s["id"]}"')
    lines.extend([
        ")",
        "",
        "# Ordered list of deployer phase IDs",
        "DEPLOYER_PHASES=("
    ])
    for s in steps:
        if s["owner"] == "deployer":
            lines.append(f'    "{s["id"]}"')
    lines.extend([
        ")",
        "",
        "# Ordered list of firstboot step IDs",
        "FIRSTBOOT_STEPS=("
    ])
    for s in steps:
        if s["owner"] == "firstboot":
            lines.append(f'    "{s["id"]}"')
    lines.extend([
        ")",
        "",
        "# Allowed phase values across all owners (failure ledger, recovery verdict, telemetry)",
        "ALL_PHASES=("
    ])
    for s in steps:
        lines.append(f'    "{s["id"]}"')
    lines.extend([
        ")",
        "",
        "is_valid_phase() {",
        '    local candidate="$1"',
        '    for p in "${ALL_PHASES[@]}"; do',
        '        [ "$p" = "$candidate" ] && return 0',
        "    done",
        "    return 1",
        "}",
        ""
    ])
    return "\n".join(lines)

def generate_splash_table(steps) -> str:
    deployer_steps = [s for s in steps if s["owner"] == "deployer"]
    lines = [
        '    # BEGIN GENERATED SPLASH TABLE',
        '    case "$1" in'
    ]
    for s in deployer_steps:
        sid = s["id"]
        start_pct, ceil_pct = SPLASH_RANGES.get(sid, (0, 0))
        lines.append(f'        {sid + ")":<20} splash_set {start_pct:>2} {ceil_pct:>2} "{s["label"]}" ;;')
    lines.extend([
        '        *) : ;;',
        '    esac',
        '    # END GENERATED SPLASH TABLE'
    ])
    return "\n".join(lines)

def update_deploy_sh(deploy_content: str, splash_table: str) -> str:
    pattern = re.compile(
        r'([ \t]*# BEGIN GENERATED SPLASH TABLE\n.*?[ \t]*# END GENERATED SPLASH TABLE)',
        re.DOTALL
    )
    if pattern.search(deploy_content):
        return pattern.sub(splash_table, deploy_content)
    
    # Fallback: if markers not yet present, replace the existing case block in phase()
    old_case_pattern = re.compile(
        r'(phase\(\)\s*\{.*?)(    case "\$1" in\n.*?    esac)',
        re.DOTALL
    )
    match = old_case_pattern.search(deploy_content)
    if not match:
        raise ValueError("Could not find case table or markers in deploy.sh phase() function")
    return deploy_content[:match.start(2)] + splash_table + deploy_content[match.end(2):]

def main():
    check_mode = "--check" in sys.argv
    steps = parse_steps_tsv(TSV_PATH)

    go_code = generate_go_code(steps)
    sh_code = generate_sh_code(steps)

    with open(DEPLOY_PATH, "r", encoding="utf-8") as f:
        orig_deploy = f.read()
    splash_table = generate_splash_table(steps)
    new_deploy = update_deploy_sh(orig_deploy, splash_table)

    if check_mode:
        stale = []
        if not os.path.exists(GO_PATH) or open(GO_PATH, "r", encoding="utf-8").read() != go_code:
            stale.append(GO_PATH)
        if not os.path.exists(SH_PATH) or open(SH_PATH, "r", encoding="utf-8").read() != sh_code:
            stale.append(SH_PATH)
        if orig_deploy != new_deploy:
            stale.append(DEPLOY_PATH)
        if stale:
            print("ERROR: Generated step files are stale or out-of-sync:", file=sys.stderr)
            for path in stale:
                print(f"  - {os.path.relpath(path, ROOT_DIR)}", file=sys.stderr)
            print("Run 'just steps' (or python3 payload/gen-steps.py) to regenerate.", file=sys.stderr)
            sys.exit(1)
        print("Step catalogue freshness check passed.")
        sys.exit(0)

    with open(GO_PATH, "w", encoding="utf-8") as f:
        f.write(go_code)
    print(f"Wrote {os.path.relpath(GO_PATH, ROOT_DIR)}")

    with open(SH_PATH, "w", encoding="utf-8") as f:
        f.write(sh_code)
    print(f"Wrote {os.path.relpath(SH_PATH, ROOT_DIR)}")

    if new_deploy != orig_deploy:
        with open(DEPLOY_PATH, "w", encoding="utf-8") as f:
            f.write(new_deploy)
        print(f"Updated {os.path.relpath(DEPLOY_PATH, ROOT_DIR)}")
    else:
        print(f"{os.path.relpath(DEPLOY_PATH, ROOT_DIR)} already up to date")

if __name__ == "__main__":
    main()
