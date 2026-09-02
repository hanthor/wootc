#!/usr/bin/env python3
"""test_soak_ledger.py — Unit tests for green-nightly soak ledger (M4.7 / #235).

Run: python3 tests/unit/test_soak_ledger.py
"""

import importlib.util
import os
import pathlib
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
REPO_ROOT = HERE.parent.parent
SCRIPT_PATH = REPO_ROOT / "tools" / "soak-ledger" / "soak_ledger.py"

spec = importlib.util.spec_from_file_location("soak_ledger", SCRIPT_PATH)
soak_ledger = importlib.util.module_from_spec(spec)
spec.loader.exec_module(soak_ledger)


def test_streak_computation_all_green():
    entries = [
        soak_ledger.LedgerEntry("2026-08-24", "233e45e", "101", "", "bluefin:lts", "PASS", "auto-v1"),
        soak_ledger.LedgerEntry("2026-08-25", "05925ae", "102", "", "bluefin:lts", "PASS", "auto-v2"),
        soak_ledger.LedgerEntry("2026-08-26", "d140476", "103", "", "bluefin:lts", "PASS", "auto-v3"),
        soak_ledger.LedgerEntry("2026-08-27", "d140476", "104", "", "bluefin:lts", "PASS", "auto-v4"),
    ]
    metrics = soak_ledger.compute_metrics(entries, soak_start_date=None, target_days=30)
    assert metrics["current_streak"] == 4, f"expected 4, got {metrics['current_streak']}"
    assert metrics["longest_streak"] == 4, f"expected 4, got {metrics['longest_streak']}"
    assert metrics["integrity_valid"] is True


def test_streak_reset_on_red():
    entries = [
        soak_ledger.LedgerEntry("2026-08-24", "233e45e", "101", "", "bluefin:lts", "PASS", "auto-v1"),
        soak_ledger.LedgerEntry("2026-08-25", "05925ae", "102", "", "bluefin:lts", "PASS", "auto-v2"),
        soak_ledger.LedgerEntry("2026-08-26", "d140476", "103", "", "bluefin:lts", "FAIL", "-", diagnosis="#220"),
        soak_ledger.LedgerEntry("2026-08-27", "d140476", "104", "", "bluefin:lts", "PASS", "auto-v4"),
    ]
    metrics = soak_ledger.compute_metrics(entries, soak_start_date=None, target_days=30)
    assert metrics["current_streak"] == 1, f"expected 1, got {metrics['current_streak']}"
    assert metrics["longest_streak"] == 2, f"expected 2, got {metrics['longest_streak']}"
    assert metrics["integrity_valid"] is True
    assert metrics["diagnosed_reds_count"] == 1


def test_unexplained_red_invalidates_integrity():
    entries = [
        soak_ledger.LedgerEntry("2026-08-24", "233e45e", "101", "", "bluefin:lts", "PASS", "auto-v1"),
        soak_ledger.LedgerEntry("2026-08-25", "05925ae", "102", "", "bluefin:lts", "FAIL", "-", diagnosis="-"),
    ]
    metrics = soak_ledger.compute_metrics(entries, soak_start_date="2026-08-24", target_days=30)
    assert metrics["current_streak"] == 0
    assert metrics["integrity_valid"] is False, "unexplained red must invalidate integrity"
    assert metrics["unexplained_reds_count"] == 1
    assert "INVALIDATED" in metrics["gate_status"]


def test_soak_start_date_filtering():
    entries = [
        soak_ledger.LedgerEntry("2026-08-20", "aaa1111", "101", "", "bluefin:lts", "PASS", "auto-v1"),
        soak_ledger.LedgerEntry("2026-08-21", "bbb2222", "102", "", "bluefin:lts", "PASS", "auto-v2"),
        soak_ledger.LedgerEntry("2026-08-22", "ccc3333", "103", "", "bluefin:lts", "PASS", "auto-v3"),
        soak_ledger.LedgerEntry("2026-08-23", "ddd4444", "104", "", "bluefin:lts", "PASS", "auto-v4"),
    ]
    # Soak start date is 2026-08-22 (2 qualifying days)
    metrics = soak_ledger.compute_metrics(entries, soak_start_date="2026-08-22", target_days=30)
    assert metrics["current_streak"] == 4, "overall live streak includes all consecutive green runs"
    assert metrics["soak_streak"] == 2, "soak streak only counts runs on/after soak start date"
    assert "2/30" in metrics["gate_status"]


def test_30_day_gate_met():
    entries = []
    for day in range(1, 32):
        entries.append(
            soak_ledger.LedgerEntry(
                f"2026-09-{day:02d}", f"sha{day:02d}", str(day), "", "bluefin:lts", "PASS", f"auto-v{day}"
            )
        )
    metrics = soak_ledger.compute_metrics(entries, soak_start_date="2026-09-01", target_days=30)
    assert metrics["soak_streak"] == 31
    assert "GATE MET" in metrics["gate_status"]


def test_flake_retry_preserves_streak():
    entries = [
        soak_ledger.LedgerEntry("2026-08-24", "233e45e", "101", "", "bluefin:lts", "PASS", "auto-v1"),
        soak_ledger.LedgerEntry("2026-08-25", "05925ae", "102", "", "bluefin:lts", "FLAKE-RETRY", "auto-v2", notes="qga-channel-lost retried"),
        soak_ledger.LedgerEntry("2026-08-26", "d140476", "103", "", "bluefin:lts", "PASS", "auto-v3"),
    ]
    metrics = soak_ledger.compute_metrics(entries, soak_start_date=None, target_days=30)
    assert metrics["current_streak"] == 3, "flake retry that succeeded must preserve streak"


def test_markdown_roundtrip_preserves_annotations():
    sample_md = """# Green-Nightly Soak Ledger (1.0 Gate)

<!-- soak_start_date: 2026-09-01 -->
<!-- target_days: 30 -->

| Date (UTC) | Commit SHA | Workflow Run | Image | Verdict | Auto-Release | Diagnosis / Issue | Notes |
|:---:|:---:|:---:|:---:|:---:|:---:|:---|:---|
| 2026-09-01 | `37152bc` | [33506006937](https://github.com/tuna-os/wootc/actions/runs/33506006937) | `bluefin:lts` | ❌ FAIL | - | [#220](https://github.com/tuna-os/wootc/issues/220) | QGA channel lost |
| 2026-08-31 | `37152bc` | [33402962420](https://github.com/tuna-os/wootc/actions/runs/33402962420) | `bluefin:lts` | ✅ PASS | [auto-v20260831-37152bc](https://github.com/tuna-os/wootc/releases/tag/auto-v20260831-37152bc) | - | Scheduled nightly |
"""
    meta, entries = soak_ledger.parse_existing_markdown(sample_md)
    assert meta["soak_start_date"] == "2026-09-01"
    assert meta["target_days"] == 30
    assert len(entries) == 2
    assert entries[0].diagnosis == "[#220](https://github.com/tuna-os/wootc/issues/220)"
    assert entries[0].notes == "QGA channel lost"
    assert entries[0].has_diagnosis is True


def main():
    test_streak_computation_all_green()
    test_streak_reset_on_red()
    test_unexplained_red_invalidates_integrity()
    test_soak_start_date_filtering()
    test_30_day_gate_met()
    test_flake_retry_preserves_streak()
    test_markdown_roundtrip_preserves_annotations()
    print("PASS (7 checks)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
