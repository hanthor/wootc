#!/usr/bin/env python3
"""soak_ledger.py — Green-nightly soak ledger for the wootc 1.0 gate (M4.7 / #235).

Tracks consecutive days of green nightly GUI E2E runs, computes the live streak,
maintains the ledger in `docs/soak.md`, and generates the Pages dashboard.

Usage:
  python3 tools/soak-ledger/soak_ledger.py update [--repo OWNER/REPO] [--token TOKEN] [--doc PATH] [--pages PATH]
  python3 tools/soak-ledger/soak_ledger.py check [--doc PATH] [--strict]
  python3 tools/soak-ledger/soak_ledger.py summary [--doc PATH]
"""

import argparse
import datetime
import json
import os
import re
import sys
import urllib.error
import urllib.request
from typing import Any, Dict, List, Optional, Tuple


DEFAULT_DOC_PATH = "docs/soak.md"
DEFAULT_PAGES_PATH = "pages/soak/index.html"
DEFAULT_JSON_PATH = "pages/soak/ledger.json"
DEFAULT_TARGET_DAYS = 30
DEFAULT_REPO = "tuna-os/wootc"


def fetch_json(url: str, token: Optional[str] = None) -> Any:
    """Fetch JSON from GitHub API with optional auth token."""
    headers = {
        "Accept": "application/vnd.github+json",
        "User-Agent": "wootc-soak-ledger",
    }
    if token:
        headers["Authorization"] = f"Bearer {token}"

    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as err:
        print(f"HTTP error {err.code} fetching {url}: {err.reason}", file=sys.stderr)
        raise
    except Exception as err:
        print(f"Error fetching {url}: {err}", file=sys.stderr)
        raise


def fetch_all_runs(repo: str, token: Optional[str] = None, max_pages: int = 5) -> List[Dict[str, Any]]:
    """Fetch workflow runs for e2e-gui.yml."""
    runs = []
    page = 1
    while page <= max_pages:
        url = f"https://api.github.com/repos/{repo}/actions/workflows/e2e-gui.yml/runs?per_page=100&page={page}"
        data = fetch_json(url, token)
        page_runs = data.get("workflow_runs", [])
        if not page_runs:
            break
        runs.extend(page_runs)
        if len(page_runs) < 100:
            break
        page += 1
    return runs


def fetch_all_releases(repo: str, token: Optional[str] = None, max_pages: int = 5) -> List[Dict[str, Any]]:
    """Fetch releases from GitHub."""
    releases = []
    page = 1
    while page <= max_pages:
        url = f"https://api.github.com/repos/{repo}/releases?per_page=100&page={page}"
        page_releases = fetch_json(url, token)
        if not page_releases or not isinstance(page_releases, list):
            break
        releases.extend(page_releases)
        if len(page_releases) < 100:
            break
        page += 1
    return releases


class LedgerEntry:
    def __init__(
        self,
        date: str,
        commit_sha: str,
        run_id: str,
        run_url: str,
        image: str,
        verdict: str,
        release_tag: str = "-",
        release_url: str = "",
        diagnosis: str = "-",
        notes: str = "-",
        event: str = "schedule",
    ):
        self.date = date  # YYYY-MM-DD
        self.commit_sha = commit_sha[:7] if len(commit_sha) >= 7 else commit_sha
        self.run_id = str(run_id)
        self.run_url = run_url
        self.image = image
        self.verdict = verdict.upper()  # PASS, FAIL, FLAKE-RETRY, CANCELLED
        self.release_tag = release_tag
        self.release_url = release_url
        self.diagnosis = diagnosis
        self.notes = notes
        self.event = event

    @property
    def is_green(self) -> bool:
        return self.verdict in ("PASS", "SUCCESS", "FLAKE-RETRY")

    @property
    def is_red(self) -> bool:
        return self.verdict in ("FAIL", "FAILURE")

    @property
    def has_diagnosis(self) -> bool:
        if not self.is_red:
            return True
        d = self.diagnosis.strip()
        if not d or d in ("-", "None", "TBD", "TODO", "unexplained"):
            return False
        return bool(re.search(r"#\d+|https?://|diagnos|infra|flake|bug|issue", d, re.I))

    def to_dict(self) -> Dict[str, Any]:
        return {
            "date": self.date,
            "commit_sha": self.commit_sha,
            "run_id": self.run_id,
            "run_url": self.run_url,
            "image": self.image,
            "verdict": self.verdict,
            "release_tag": self.release_tag,
            "release_url": self.release_url,
            "diagnosis": self.diagnosis,
            "notes": self.notes,
            "event": self.event,
            "is_green": self.is_green,
            "has_diagnosis": self.has_diagnosis,
        }


def parse_existing_markdown(content: str) -> Tuple[Dict[str, Any], List[LedgerEntry]]:
    """Parse existing docs/soak.md to extract metadata and table rows."""
    metadata: Dict[str, Any] = {
        "soak_start_date": None,
        "target_days": DEFAULT_TARGET_DAYS,
    }

    m_start = re.search(r"<!--\s*soak_start_date:\s*([^\s>]+)\s*-->", content)
    if m_start:
        val = m_start.group(1).strip()
        if val not in ("None", "null", "-", "pending", "TBD"):
            metadata["soak_start_date"] = val

    m_target = re.search(r"<!--\s*target_days:\s*(\d+)\s*-->", content)
    if m_target:
        metadata["target_days"] = int(m_target.group(1))

    entries: List[LedgerEntry] = []
    in_table = False
    for line in content.splitlines():
        line = line.strip()
        if line.startswith("|") and ("Date" in line or "date" in line) and ("Verdict" in line or "verdict" in line):
            in_table = True
            continue
        if in_table:
            if not line.startswith("|") or line.startswith("|---") or line.startswith("|:--"):
                continue
            cols = [c.strip() for c in line.strip("|").split("|")]
            if len(cols) < 5:
                continue

            # Date
            date_col = cols[0]
            m_date = re.search(r"\d{4}-\d{2}-\d{2}", date_col)
            if not m_date:
                continue
            entry_date = m_date.group(0)

            # Commit SHA
            sha_col = cols[1]
            m_sha = re.search(r"`?([0-9a-fA-F]{7,40})`?", sha_col)
            entry_sha = m_sha.group(1)[:7] if m_sha else sha_col

            # Run link
            run_col = cols[2]
            m_run = re.search(r"\[(?:#)?(\d+)\]\((https://[^\)]+)\)", run_col)
            if m_run:
                run_id = m_run.group(1)
                run_url = m_run.group(2)
            else:
                m_run_id = re.search(r"\d+", run_col)
                run_id = m_run_id.group(0) if m_run_id else "-"
                run_url = f"https://github.com/{DEFAULT_REPO}/actions/runs/{run_id}" if run_id != "-" else ""

            # Image
            image_col = cols[3] if len(cols) > 3 else "bluefin:lts"
            image_col = image_col.replace("`", "")

            # Verdict
            verdict_col = cols[4] if len(cols) > 4 else "PASS"
            if "PASS" in verdict_col.upper() or "GREEN" in verdict_col.upper() or "✅" in verdict_col:
                verdict = "PASS"
            elif "FLAKE" in verdict_col.upper():
                verdict = "FLAKE-RETRY"
            elif "FAIL" in verdict_col.upper() or "RED" in verdict_col.upper() or "❌" in verdict_col:
                verdict = "FAIL"
            elif "CANCEL" in verdict_col.upper():
                verdict = "CANCELLED"
            else:
                verdict = verdict_col.strip()

            # Release
            rel_col = cols[5] if len(cols) > 5 else "-"
            m_rel = re.search(r"\[([^\]]+)\]\((https://[^\)]+)\)", rel_col)
            if m_rel:
                rel_tag = m_rel.group(1)
                rel_url = m_rel.group(2)
            else:
                rel_tag = rel_col if rel_col not in ("-", "None", "") else "-"
                rel_url = ""

            # Diagnosis
            diag_col = cols[6] if len(cols) > 6 else "-"

            # Notes
            notes_col = cols[7] if len(cols) > 7 else "-"

            entries.append(
                LedgerEntry(
                    date=entry_date,
                    commit_sha=entry_sha,
                    run_id=run_id,
                    run_url=run_url,
                    image=image_col,
                    verdict=verdict,
                    release_tag=rel_tag,
                    release_url=rel_url,
                    diagnosis=diag_col,
                    notes=notes_col,
                )
            )

    return metadata, entries


def process_raw_data(
    runs: List[Dict[str, Any]],
    releases: List[Dict[str, Any]],
    existing_entries: Optional[List[LedgerEntry]] = None,
) -> List[LedgerEntry]:
    """Combine workflow runs and releases into structured LedgerEntry items."""
    rel_by_date_sha: Dict[str, Dict[str, Any]] = {}
    rel_by_date: Dict[str, Dict[str, Any]] = {}
    rel_by_sha: Dict[str, Dict[str, Any]] = {}

    for r in releases:
        tag = r.get("tag_name", "")
        sha = r.get("target_commitish", "")
        # auto-vYYYYMMDD-<sha>
        m_tag = re.match(r"auto-v(\d{8})-([0-9a-fA-F]+)", tag)
        if m_tag:
            rel_date, tag_sha = m_tag.group(1), m_tag.group(2)
            rel_by_date_sha[f"{rel_date}:{tag_sha[:7]}"] = r
            rel_by_date[rel_date] = r
            rel_by_sha[tag_sha[:7]] = r
        if sha:
            rel_by_sha[sha[:7]] = r

    existing_map: Dict[str, LedgerEntry] = {}
    if existing_entries:
        for e in existing_entries:
            if e.run_id and e.run_id != "-":
                existing_map[f"run:{e.run_id}"] = e
            existing_map[f"date_sha:{e.date}:{e.commit_sha}"] = e
            existing_map[f"date:{e.date}"] = e

    runs_by_day: Dict[str, List[Dict[str, Any]]] = {}
    for r in runs:
        status = r.get("status")
        conclusion = r.get("conclusion")
        if status != "completed" or conclusion is None:
            continue
        created = r.get("created_at", "")[:10]
        if not created:
            continue
        runs_by_day.setdefault(created, []).append(r)

    processed_entries: List[LedgerEntry] = []

    for day in sorted(runs_by_day.keys()):
        day_runs = runs_by_day[day]
        scheduled = [r for r in day_runs if r.get("event") == "schedule"]
        target_run = scheduled[-1] if scheduled else day_runs[-1]

        run_id = str(target_run.get("id"))
        run_url = target_run.get("html_url", "")
        sha = target_run.get("head_sha", "")[:7]
        conclusion = (target_run.get("conclusion") or "").lower()
        event = target_run.get("event", "schedule")

        if conclusion == "success":
            verdict = "PASS"
        elif conclusion == "cancelled":
            verdict = "CANCELLED"
        else:
            verdict = "FAIL"

        # Match auto-release
        date_compact = day.replace("-", "")
        rel = (
            rel_by_date_sha.get(f"{date_compact}:{sha}")
            or rel_by_date.get(date_compact)
            or rel_by_sha.get(sha)
            or rel_by_sha.get(target_run.get("head_sha", ""))
        )
        rel_tag = "-"
        rel_url = ""
        if rel and verdict == "PASS":
            rel_tag = rel.get("tag_name", "-")
            rel_url = rel.get("html_url", "")

        image = "bluefin:lts"

        prev = (
            existing_map.get(f"run:{run_id}")
            or existing_map.get(f"date_sha:{day}:{sha}")
            or existing_map.get(f"date:{day}")
        )
        diagnosis = prev.diagnosis if (prev and prev.diagnosis != "-") else "-"
        notes = prev.notes if (prev and prev.notes != "-") else ("Scheduled nightly" if event == "schedule" else "Manual acceptance run")

        processed_entries.append(
            LedgerEntry(
                date=day,
                commit_sha=sha,
                run_id=run_id,
                run_url=run_url,
                image=image,
                verdict=verdict,
                release_tag=rel_tag,
                release_url=rel_url,
                diagnosis=diagnosis,
                notes=notes,
                event=event,
            )
        )

    return processed_entries


def compute_metrics(
    entries: List[LedgerEntry],
    soak_start_date: Optional[str] = None,
    target_days: int = DEFAULT_TARGET_DAYS,
) -> Dict[str, Any]:
    """Compute current streak, soak streak, longest streak, and check integrity."""
    sorted_entries = sorted(entries, key=lambda e: (e.date, int(e.run_id) if e.run_id.isdigit() else 0))

    current_streak = 0
    soak_streak = 0
    longest_streak = 0
    temp_streak = 0
    unexplained_reds: List[LedgerEntry] = []
    diagnosed_reds: List[LedgerEntry] = []

    for e in sorted_entries:
        if e.is_green:
            temp_streak += 1
            if temp_streak > longest_streak:
                longest_streak = temp_streak
        elif e.is_red:
            temp_streak = 0
            if e.has_diagnosis:
                diagnosed_reds.append(e)
            else:
                unexplained_reds.append(e)

    current_streak = 0
    for e in reversed(sorted_entries):
        if e.is_green:
            current_streak += 1
        else:
            break

    if soak_start_date:
        qualifying_entries = [e for e in sorted_entries if e.date >= soak_start_date]
        soak_streak = 0
        for e in reversed(qualifying_entries):
            if e.is_green:
                soak_streak += 1
            else:
                break
    else:
        soak_streak = 0

    integrity_valid = len(unexplained_reds) == 0

    if not soak_start_date:
        gate_status = f"Pre-soak baseline ({current_streak} consecutive green days; soak start pending M4 closure)"
    elif soak_streak >= target_days and integrity_valid:
        gate_status = f"GATE MET ({soak_streak}/{target_days} consecutive qualifying green days)"
    elif not integrity_valid:
        gate_status = f"STREAK INVALIDATED ({len(unexplained_reds)} unexplained red runs pending diagnosis)"
    else:
        gate_status = f"Gate running ({soak_streak}/{target_days} consecutive qualifying green days)"

    latest_entry = sorted_entries[-1] if sorted_entries else None

    return {
        "current_streak": current_streak,
        "soak_streak": soak_streak,
        "target_days": target_days,
        "longest_streak": longest_streak,
        "soak_start_date": soak_start_date,
        "integrity_valid": integrity_valid,
        "unexplained_reds_count": len(unexplained_reds),
        "unexplained_reds": [e.to_dict() for e in unexplained_reds],
        "diagnosed_reds_count": len(diagnosed_reds),
        "gate_status": gate_status,
        "total_entries": len(sorted_entries),
        "latest_date": latest_entry.date if latest_entry else "-",
        "latest_verdict": latest_entry.verdict if latest_entry else "-",
        "latest_sha": latest_entry.commit_sha if latest_entry else "-",
    }


def render_markdown(
    entries: List[LedgerEntry],
    metrics: Dict[str, Any],
    repo: str = DEFAULT_REPO,
) -> str:
    """Render full docs/soak.md markdown content."""
    soak_start = metrics.get("soak_start_date") or "Pending M4.1–M4.6 closure"
    soak_start_meta = metrics.get("soak_start_date") or "None"
    target_days = metrics.get("target_days", DEFAULT_TARGET_DAYS)
    current_streak = metrics.get("current_streak", 0)
    soak_streak = metrics.get("soak_streak", 0)
    longest_streak = metrics.get("longest_streak", 0)
    gate_status = metrics.get("gate_status", "")
    integrity_valid = metrics.get("integrity_valid", True)
    unexplained_count = metrics.get("unexplained_reds_count", 0)

    lines = [
        "# Green-Nightly Soak Ledger (1.0 Gate)",
        "",
        f"<!-- soak_start_date: {soak_start_meta} -->",
        f"<!-- target_days: {target_days} -->",
        "",
        "> \"30 consecutive days of green nightlies\" is a number someone can read, not a feeling.",
        "> — *Milestone #212 (v0.9.0-rc) & Tracking criterion #213 (v1.0.0)*",
        "",
        "## Live Gate Status",
        "",
        "| Metric | Value |",
        "|---|---|",
        f"| **Current Live Streak** | **{current_streak} consecutive green days** |",
        f"| **1.0 Soak Streak** | **{soak_streak} / {target_days} qualifying days** |",
        f"| **Soak Start Date** | `{soak_start}` |",
        f"| **Longest Streak** | {longest_streak} consecutive days |",
        f"| **Gate Status** | {gate_status} |",
        f"| **Ledger Integrity** | {'✅ Valid (all red runs diagnosed)' if integrity_valid else f'❌ INVALID ({unexplained_count} unexplained reds — every failure must link an issue)'} |",
        f"| **Latest Nightly** | `{metrics.get('latest_date')}` (`{metrics.get('latest_sha')}`) — **{metrics.get('latest_verdict')}** |",
        "",
        "---",
        "",
        "## Policy & Operating Rules",
        "",
        "### 1. Qualifying Runs",
        "- **What counts**: Nightly scheduled runs of the GUI-driven three-phase E2E workflow (`.github/workflows/e2e-gui.yml`) on `main`.",
        "- **Proof of Green**: A passing run executes Windows 11 → wootc installer GUI (drive mode) → Linux Phase 2 boot → User Data Bridge verification → Phase 3 graduation → Windows return cleanly. Every green nightly automatically publishes an `auto-v*` pre-release on GitHub.",
        "- **Auto-release as Ledger**: The GitHub Releases list serves as the immutable daily proof artifact corresponding to green rows.",
        "",
        "### 2. Failure & Diagnosis Policy",
        "- **Honest Streak Reset**: A failing (red) nightly resets the streak counter to 0 immediately.",
        "- **Mandatory Diagnosis**: Every red nightly **must** link its root-cause diagnosis issue in the ledger. Unexplained reds are **streak-invalid**, not just streak-resetting: a soak with undiagnosed failures cannot be cited for the 1.0 gate.",
        "- **Harness-Classified Flakes (M2.6)**: Infrastructure failures classified by the harness (`qga-channel-lost`, `serial-feed-lost`) trigger exactly one automated re-dispatch. If the retry goes green on its own, it is recorded as `FLAKE-RETRY` with its classification and does not break the green streak. Unclassified failures or failed retries are hard reds.",
        "",
        "### 3. The 1.0 Gate Clock",
        "- **Soak Start Gate**: The official soak clock begins when milestone items M4.1–M4.6 close. Prior runs form the pre-soak calibration baseline; only runs on or after the recorded `soak_start_date` count toward #213's 30-day criterion.",
        "- **Merge Policy During Soak**: From soak start, only regression fixes and release-blocking changes merge to `main`. Feature work branches and waits.",
        "",
        "---",
        "",
        "## Ledger Table",
        "",
        "| Date (UTC) | Commit SHA | Workflow Run | Image | Verdict | Auto-Release | Diagnosis / Issue | Notes |",
        "|:---:|:---:|:---:|:---:|:---:|:---:|:---|:---|",
    ]

    sorted_entries = sorted(entries, key=lambda e: (e.date, int(e.run_id) if e.run_id.isdigit() else 0), reverse=True)

    for e in sorted_entries:
        run_link = f"[{e.run_id}]({e.run_url})" if e.run_url else e.run_id
        sha_link = f"`{e.commit_sha}`"

        if e.verdict == "PASS":
            verdict_badge = "✅ PASS"
        elif e.verdict == "FLAKE-RETRY":
            verdict_badge = "🟡 FLAKE-RETRY"
        elif e.verdict == "CANCELLED":
            verdict_badge = "⚪ CANCELLED"
        else:
            verdict_badge = "❌ FAIL"

        rel_link = f"[{e.release_tag}]({e.release_url})" if e.release_url else e.release_tag
        diag = e.diagnosis if e.diagnosis else "-"
        notes = e.notes if e.notes else "-"

        lines.append(
            f"| {e.date} | {sha_link} | {run_link} | `{e.image}` | {verdict_badge} | {rel_link} | {diag} | {notes} |"
        )

    lines.extend([
        "",
        "---",
        "",
        "## Automation & Maintenance",
        "",
        "- **Automated Updates**: The ledger is maintained by `.github/workflows/soak-ledger.yml`, which triggers automatically upon completion of each nightly `E2E GUI-driven (publish timelapse)` run.",
        "- **Pages Dashboard**: Live web view is published to [`pages/soak/index.html`](https://tuna-os.github.io/wootc/soak/).",
        "- **Tool CLI**: `python3 tools/soak-ledger/soak_ledger.py [update|check|summary]`.",
        "",
    ])

    return "\n".join(lines)


def render_html(
    entries: List[LedgerEntry],
    metrics: Dict[str, Any],
    repo: str = DEFAULT_REPO,
) -> str:
    """Render pages/soak/index.html dashboard."""
    current_streak = metrics.get("current_streak", 0)
    target_days = metrics.get("target_days", DEFAULT_TARGET_DAYS)
    soak_streak = metrics.get("soak_streak", 0)
    gate_status = metrics.get("gate_status", "")
    soak_start = metrics.get("soak_start_date") or "Pending M4 closure"
    integrity_valid = metrics.get("integrity_valid", True)
    progress_pct = min(100, int((soak_streak / target_days) * 100)) if target_days > 0 else 0

    sorted_entries = sorted(entries, key=lambda e: (e.date, int(e.run_id) if e.run_id.isdigit() else 0), reverse=True)

    rows_html = []
    for e in sorted_entries:
        badge_class = "pass" if e.is_green else ("cancel" if e.verdict == "CANCELLED" else "fail")
        rel_html = f'<a href="{e.release_url}">{e.release_tag}</a>' if e.release_url else e.release_tag
        run_html = f'<a href="{e.run_url}">#{e.run_id}</a>' if e.run_url else e.run_id
        rows_html.append(f"""
        <tr>
          <td>{e.date}</td>
          <td><code>{e.commit_sha}</code></td>
          <td>{run_html}</td>
          <td><code>{e.image}</code></td>
          <td><span class="badge {badge_class}">{e.verdict}</span></td>
          <td>{rel_html}</td>
          <td>{e.diagnosis}</td>
        </tr>""")

    return f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>wootc — Green-Nightly Soak Ledger (1.0 Gate)</title>
  <style>
    :root {{ color-scheme: dark; }}
    body {{
      max-width: 1080px; margin: 2rem auto; padding: 0 1rem;
      background: #0d1117; color: #e6edf3;
      font: 15px/1.6 system-ui, -apple-system, sans-serif;
    }}
    h1 {{ font-size: 1.75rem; margin-bottom: .25rem; color: #f0f6fc; }}
    .sub {{ color: #9198a1; margin-top: 0; font-size: 1.05rem; }}
    a {{ color: #7dd3fc; text-decoration: none; }}
    a:hover {{ text-decoration: underline; }}
    .grid {{
      display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
      gap: 1rem; margin: 1.5rem 0;
    }}
    .card {{
      background: #161b22; border: 1px solid #30363d; border-radius: 8px;
      padding: 1rem 1.25rem;
    }}
    .card .label {{ font-size: .85rem; color: #8b949e; text-transform: uppercase; letter-spacing: .05em; }}
    .card .val {{ font-size: 1.6rem; font-weight: 700; margin-top: .25rem; color: #58a6ff; }}
    .progress-bar {{
      width: 100%; height: 12px; background: #21262d; border-radius: 6px;
      overflow: hidden; margin: .5rem 0;
    }}
    .progress-fill {{
      height: 100%; background: #238636; width: {progress_pct}%;
      transition: width .3s ease;
    }}
    table {{
      width: 100%; border-collapse: collapse; margin-top: 1.5rem; font-size: .9rem;
    }}
    th, td {{
      padding: .6rem .75rem; text-align: left; border-bottom: 1px solid #21262d;
    }}
    th {{ background: #161b22; color: #8b949e; font-weight: 600; }}
    tr:hover td {{ background: #161b22; }}
    code {{ background: #1f242c; padding: .1rem .35rem; border-radius: 4px; font-size: .85em; }}
    .badge {{
      display: inline-block; padding: .15rem .5rem; border-radius: 12px;
      font-size: .75rem; font-weight: 600; text-transform: uppercase;
    }}
    .badge.pass {{ background: #238636; color: #fff; }}
    .badge.fail {{ background: #da3633; color: #fff; }}
    .badge.cancel {{ background: #6e7681; color: #fff; }}
    .rules {{
      background: #161b22; border-left: 4px solid #388bfd; padding: 1rem;
      border-radius: 0 8px 8px 0; margin: 1.5rem 0; font-size: .9rem;
    }}
  </style>
</head>
<body>
  <h1>wootc — Green-Nightly Soak Ledger</h1>
  <p class="sub">30 consecutive days of green nightlies: the verifiable gate for v1.0.0 (#213 criterion 3).</p>

  <div class="grid">
    <div class="card">
      <div class="label">Live Streak</div>
      <div class="val" style="color: #3fb950;">{current_streak} Days</div>
      <div style="font-size: .85rem; color: #8b949e;">Consecutive green runs</div>
    </div>
    <div class="card">
      <div class="label">1.0 Soak Progress</div>
      <div class="val">{soak_streak} / {target_days}</div>
      <div class="progress-bar"><div class="progress-fill"></div></div>
      <div style="font-size: .8rem; color: #8b949e;">Target: 30 days</div>
    </div>
    <div class="card">
      <div class="label">Soak Clock</div>
      <div class="val" style="font-size: 1.15rem; margin-top: .5rem; color: #c9d1d9;">{soak_start}</div>
      <div style="font-size: .8rem; color: #8b949e;">Starts on M4 closure</div>
    </div>
    <div class="card">
      <div class="label">Ledger Integrity</div>
      <div class="val" style="font-size: 1.15rem; margin-top: .5rem; color: {'#3fb950' if integrity_valid else '#f85149'};">
        {'Valid' if integrity_valid else 'Invalid (Needs Diagnosis)'}
      </div>
      <div style="font-size: .8rem; color: #8b949e;">All failures diagnosed</div>
    </div>
  </div>

  <div class="rules">
    <strong>Soak Gate Rules:</strong>
    A green nightly (Windows 11 → GUI drive → Linux Phase 2 → return) cuts an <code>auto-v*</code> pre-release and increments the streak.
    A red nightly resets the streak to 0 and must link a diagnosis issue — unexplained reds invalidate the entire soak's credibility.
  </div>

  <h2>Nightly Runs History</h2>
  <table>
    <thead>
      <tr>
        <th>Date (UTC)</th>
        <th>SHA</th>
        <th>Workflow Run</th>
        <th>Image</th>
        <th>Verdict</th>
        <th>Auto-Release</th>
        <th>Diagnosis / Issue</th>
      </tr>
    </thead>
    <tbody>
      {''.join(rows_html)}
    </tbody>
  </table>

  <p style="margin-top: 2rem; color: #8b949e; font-size: .85rem;">
    <a href="../">← Walkthrough Gallery</a> ·
    <a href="https://github.com/{repo}">wootc on GitHub</a> ·
    <a href="https://github.com/{repo}/blob/main/docs/soak.md">docs/soak.md</a> ·
    <a href="ledger.json">ledger.json</a>
  </p>
</body>
</html>
"""


def cmd_update(args: argparse.Namespace) -> int:
    """Update docs/soak.md and pages/soak/index.html."""
    repo = args.repo or os.environ.get("GITHUB_REPOSITORY") or DEFAULT_REPO
    token = args.token or os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
    doc_path = args.doc or DEFAULT_DOC_PATH
    pages_path = args.pages or DEFAULT_PAGES_PATH
    json_path = args.json or DEFAULT_JSON_PATH

    existing_entries: List[LedgerEntry] = []
    metadata: Dict[str, Any] = {}

    if os.path.isfile(doc_path):
        with open(doc_path, "r", encoding="utf-8") as f:
            metadata, existing_entries = parse_existing_markdown(f.read())

    if args.runs_json and os.path.isfile(args.runs_json):
        with open(args.runs_json, "r", encoding="utf-8") as f:
            runs_data = json.load(f)
            runs = runs_data.get("workflow_runs", runs_data)
    else:
        print(f"Fetching workflow runs from GitHub API for {repo}...")
        try:
            runs = fetch_all_runs(repo, token)
        except Exception as err:
            print(f"Warning: Failed to fetch runs from API: {err}", file=sys.stderr)
            runs = []

    if args.releases_json and os.path.isfile(args.releases_json):
        with open(args.releases_json, "r", encoding="utf-8") as f:
            releases = json.load(f)
    else:
        print(f"Fetching releases from GitHub API for {repo}...")
        try:
            releases = fetch_all_releases(repo, token)
        except Exception as err:
            print(f"Warning: Failed to fetch releases from API: {err}", file=sys.stderr)
            releases = []

    if runs:
        entries = process_raw_data(runs, releases, existing_entries)
    else:
        entries = existing_entries

    if not entries:
        print("No ledger entries found or fetched.", file=sys.stderr)
        return 1

    soak_start = args.soak_start or metadata.get("soak_start_date")
    target_days = args.target_days or metadata.get("target_days", DEFAULT_TARGET_DAYS)

    metrics = compute_metrics(entries, soak_start_date=soak_start, target_days=target_days)

    md_content = render_markdown(entries, metrics, repo=repo)
    os.makedirs(os.path.dirname(os.path.abspath(doc_path)), exist_ok=True)
    with open(doc_path, "w", encoding="utf-8") as f:
        f.write(md_content)
    print(f"Updated {doc_path} (Live Streak: {metrics['current_streak']} days)")

    html_content = render_html(entries, metrics, repo=repo)
    os.makedirs(os.path.dirname(os.path.abspath(pages_path)), exist_ok=True)
    with open(pages_path, "w", encoding="utf-8") as f:
        f.write(html_content)
    print(f"Updated {pages_path}")

    ledger_data = {
        "metrics": metrics,
        "entries": [e.to_dict() for e in entries],
        "generated_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    }
    os.makedirs(os.path.dirname(os.path.abspath(json_path)), exist_ok=True)
    with open(json_path, "w", encoding="utf-8") as f:
        json.dump(ledger_data, f, indent=2)
    print(f"Updated {json_path}")

    return 0


def cmd_check(args: argparse.Namespace) -> int:
    """Validate docs/soak.md formatting and integrity."""
    doc_path = args.doc or DEFAULT_DOC_PATH
    if not os.path.isfile(doc_path):
        print(f"Error: {doc_path} not found.", file=sys.stderr)
        return 1

    with open(doc_path, "r", encoding="utf-8") as f:
        content = f.read()

    metadata, entries = parse_existing_markdown(content)
    if not entries:
        print(f"Error: No table entries parsed from {doc_path}.", file=sys.stderr)
        return 1

    metrics = compute_metrics(
        entries,
        soak_start_date=metadata.get("soak_start_date"),
        target_days=metadata.get("target_days", DEFAULT_TARGET_DAYS),
    )

    print(f"Ledger check: {len(entries)} entries found in {doc_path}")
    print(f"Live streak: {metrics['current_streak']} days")
    print(f"Longest streak: {metrics['longest_streak']} days")
    print(f"Integrity status: {'VALID' if metrics['integrity_valid'] else 'INVALID'}")

    if not metrics["integrity_valid"]:
        print(f"WARNING: {metrics['unexplained_reds_count']} red runs lack a diagnosis issue!", file=sys.stderr)
        for r in metrics["unexplained_reds"]:
            print(f"  - {r['date']} (SHA {r['commit_sha']}, Run {r['run_id']})", file=sys.stderr)
        if args.strict:
            return 2

    return 0


def cmd_summary(args: argparse.Namespace) -> int:
    """Print one-line summary of streak and gate status."""
    doc_path = args.doc or DEFAULT_DOC_PATH
    if not os.path.isfile(doc_path):
        print("Soak ledger: not initialized")
        return 1

    with open(doc_path, "r", encoding="utf-8") as f:
        metadata, entries = parse_existing_markdown(f.read())

    if not entries:
        print("Soak ledger: empty")
        return 1

    metrics = compute_metrics(
        entries,
        soak_start_date=metadata.get("soak_start_date"),
        target_days=metadata.get("target_days", DEFAULT_TARGET_DAYS),
    )

    print(
        f"Soak streak: {metrics['current_streak']} days green | "
        f"1.0 Gate: {metrics['soak_streak']}/{metrics['target_days']} | "
        f"Status: {metrics['gate_status']}"
    )
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="wootc green-nightly soak ledger")
    subparsers = parser.add_subparsers(dest="command")

    p_update = subparsers.add_parser("update", help="Fetch runs and update docs/soak.md + pages dashboard")
    p_update.add_argument("--repo", default=None, help="GitHub repository (owner/repo)")
    p_update.add_argument("--token", default=None, help="GitHub API token")
    p_update.add_argument("--doc", default=DEFAULT_DOC_PATH, help="Path to docs/soak.md")
    p_update.add_argument("--pages", default=DEFAULT_PAGES_PATH, help="Path to pages/soak/index.html")
    p_update.add_argument("--json", default=DEFAULT_JSON_PATH, help="Path to pages/soak/ledger.json")
    p_update.add_argument("--soak-start", default=None, help="Soak start date (YYYY-MM-DD)")
    p_update.add_argument("--target-days", type=int, default=DEFAULT_TARGET_DAYS, help="Target consecutive days")
    p_update.add_argument("--runs-json", default=None, help="Offline JSON file of workflow runs")
    p_update.add_argument("--releases-json", default=None, help="Offline JSON file of releases")

    p_check = subparsers.add_parser("check", help="Validate docs/soak.md integrity")
    p_check.add_argument("--doc", default=DEFAULT_DOC_PATH, help="Path to docs/soak.md")
    p_check.add_argument("--strict", action="store_true", help="Fail if any red run is unexplained")

    p_summary = subparsers.add_parser("summary", help="Print summary line")
    p_summary.add_argument("--doc", default=DEFAULT_DOC_PATH, help="Path to docs/soak.md")

    args = parser.parse_args()
    if not args.command:
        parser.print_help()
        return 1

    if args.command == "update":
        return cmd_update(args)
    elif args.command == "check":
        return cmd_check(args)
    elif args.command == "summary":
        return cmd_summary(args)
    return 0


if __name__ == "__main__":
    sys.exit(main())
