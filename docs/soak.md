# Green-Nightly Soak Ledger (1.0 Gate)

<!-- soak_start_date: None -->
<!-- target_days: 30 -->

> "30 consecutive days of green nightlies" is a number someone can read, not a feeling.
> — *Milestone #212 (v0.9.0-rc) & Tracking criterion #213 (v1.0.0)*

## Live Gate Status

| Metric | Value |
|---|---|
| **Current Live Streak** | **0 consecutive green days** |
| **1.0 Soak Streak** | **0 / 30 qualifying days** |
| **Soak Start Date** | `Pending M4.1–M4.6 closure` |
| **Longest Streak** | 8 consecutive days |
| **Gate Status** | Pre-soak baseline (0 consecutive green days; soak start pending M4 closure) |
| **Ledger Integrity** | ✅ Valid (all red runs diagnosed) |
| **Latest Nightly** | `2026-09-01` (`37152bc`) — **FAIL** |

---

## Policy & Operating Rules

### 1. Qualifying Runs
- **What counts**: Nightly scheduled runs of the GUI-driven three-phase E2E workflow (`.github/workflows/e2e-gui.yml`) on `main`.
- **Proof of Green**: A passing run executes Windows 11 → wootc installer GUI (drive mode) → Linux Phase 2 boot → User Data Bridge verification → Phase 3 graduation → Windows return cleanly. Every green nightly automatically publishes an `auto-v*` pre-release on GitHub.
- **Auto-release as Ledger**: The GitHub Releases list serves as the immutable daily proof artifact corresponding to green rows.

### 2. Failure & Diagnosis Policy
- **Honest Streak Reset**: A failing (red) nightly resets the streak counter to 0 immediately.
- **Mandatory Diagnosis**: Every red nightly **must** link its root-cause diagnosis issue in the ledger. Unexplained reds are **streak-invalid**, not just streak-resetting: a soak with undiagnosed failures cannot be cited for the 1.0 gate.
- **Harness-Classified Flakes (M2.6)**: Infrastructure failures classified by the harness (`qga-channel-lost`, `serial-feed-lost`) trigger exactly one automated re-dispatch. If the retry goes green on its own, it is recorded as `FLAKE-RETRY` with its classification and does not break the green streak. Unclassified failures or failed retries are hard reds.

### 3. The 1.0 Gate Clock
- **Soak Start Gate**: The official soak clock begins when milestone items M4.1–M4.6 close. Prior runs form the pre-soak calibration baseline; only runs on or after the recorded `soak_start_date` count toward #213's 30-day criterion.
- **Merge Policy During Soak**: From soak start, only regression fixes and release-blocking changes merge to `main`. Feature work branches and waits.

---

## Ledger Table

| Date (UTC) | Commit SHA | Workflow Run | Image | Verdict | Auto-Release | Diagnosis / Issue | Notes |
|:---:|:---:|:---:|:---:|:---:|:---:|:---|:---|
| 2026-09-01 | `37152bc` | [33506006937](https://github.com/tuna-os/wootc/actions/runs/33506006937) | `bluefin:lts` | ❌ FAIL | - | [#320](https://github.com/tuna-os/wootc/pull/320) (fixes [#220](https://github.com/tuna-os/wootc/issues/220)) | QGA channel lost mid-run; classified and retried in #320 |
| 2026-08-31 | `37152bc` | [33402962420](https://github.com/tuna-os/wootc/actions/runs/33402962420) | `bluefin:lts` | ✅ PASS | [auto-v20260831-37152bc](https://github.com/tuna-os/wootc/releases/tag/auto-v20260831-37152bc) | - | Scheduled nightly |
| 2026-08-30 | `37152bc` | [33311173608](https://github.com/tuna-os/wootc/actions/runs/33311173608) | `bluefin:lts` | ✅ PASS | [auto-v20260830-37152bc](https://github.com/tuna-os/wootc/releases/tag/auto-v20260830-37152bc) | - | Scheduled nightly |
| 2026-08-29 | `d140476` | [33253514238](https://github.com/tuna-os/wootc/actions/runs/33253514238) | `bluefin:lts` | ✅ PASS | [auto-v20260829-d140476](https://github.com/tuna-os/wootc/releases/tag/auto-v20260829-d140476) | - | Scheduled nightly |
| 2026-08-28 | `d140476` | [33202311739](https://github.com/tuna-os/wootc/actions/runs/33202311739) | `bluefin:lts` | ✅ PASS | [auto-v20260828-d140476](https://github.com/tuna-os/wootc/releases/tag/auto-v20260828-d140476) | - | Scheduled nightly |
| 2026-08-27 | `d140476` | [33100870031](https://github.com/tuna-os/wootc/actions/runs/33100870031) | `bluefin:lts` | ✅ PASS | [auto-v20260827-d140476](https://github.com/tuna-os/wootc/releases/tag/auto-v20260827-d140476) | - | Scheduled nightly |
| 2026-08-26 | `d140476` | [32943463124](https://github.com/tuna-os/wootc/actions/runs/32943463124) | `bluefin:lts` | ✅ PASS | [auto-v20260826-d140476](https://github.com/tuna-os/wootc/releases/tag/auto-v20260826-d140476) | - | Scheduled nightly |
| 2026-08-25 | `05925ae` | [32822159218](https://github.com/tuna-os/wootc/actions/runs/32822159218) | `bluefin:lts` | ✅ PASS | [auto-v20260825-05925ae](https://github.com/tuna-os/wootc/releases/tag/auto-v20260825-05925ae) | - | Scheduled nightly |
| 2026-08-24 | `233e45e` | [32703039491](https://github.com/tuna-os/wootc/actions/runs/32703039491) | `bluefin:lts` | ✅ PASS | [auto-v20260824-233e45e](https://github.com/tuna-os/wootc/releases/tag/auto-v20260824-233e45e) | - | Scheduled nightly |
| 2026-08-23 | `d44c7f1` | [32625389233](https://github.com/tuna-os/wootc/actions/runs/32625389233) | `bluefin:lts` | ❌ FAIL | - | [#248](https://github.com/tuna-os/wootc/issues/248) | Bazzite Secure Boot MOK enrollment; fixed in #251/#272 |
| 2026-08-22 | `d8e1bde` | [32559347752](https://github.com/tuna-os/wootc/actions/runs/32559347752) | `bluefin:lts` | ✅ PASS | [auto-v20260822-0f49867](https://github.com/tuna-os/wootc/releases/tag/auto-v20260822-0f49867) | - | Scheduled nightly |
| 2026-08-21 | `ca2d705` | [32459085068](https://github.com/tuna-os/wootc/actions/runs/32459085068) | `bluefin:lts` | ❌ FAIL | - | [#220](https://github.com/tuna-os/wootc/issues/220) | GUI drive mode QGA channel timeout |
| 2026-08-20 | `ca2d705` | [32344282759](https://github.com/tuna-os/wootc/actions/runs/32344282759) | `bluefin:lts` | ❌ FAIL | - | [#220](https://github.com/tuna-os/wootc/issues/220) | GUI drive mode QGA channel timeout |
| 2026-08-19 | `378b22b` | [32227893583](https://github.com/tuna-os/wootc/actions/runs/32227893583) | `bluefin:lts` | ❌ FAIL | - | [#87](https://github.com/tuna-os/wootc/issues/87) | Walkthrough media asset accumulation in git tree |
| 2026-08-18 | `3d5810e` | [32111434628](https://github.com/tuna-os/wootc/actions/runs/32111434628) | `bluefin:lts` | ❌ FAIL | - | [#87](https://github.com/tuna-os/wootc/issues/87) | Walkthrough media asset accumulation in git tree |
| 2026-08-17 | `8386215` | [32006851861](https://github.com/tuna-os/wootc/actions/runs/32006851861) | `bluefin:lts` | ❌ FAIL | - | [#87](https://github.com/tuna-os/wootc/issues/87) | Walkthrough media asset accumulation in git tree |
| 2026-08-16 | `8386215` | [31933627989](https://github.com/tuna-os/wootc/actions/runs/31933627989) | `bluefin:lts` | ❌ FAIL | - | [#87](https://github.com/tuna-os/wootc/issues/87) | Walkthrough media asset accumulation in git tree |
| 2026-08-15 | `8386215` | [31871660755](https://github.com/tuna-os/wootc/actions/runs/31871660755) | `bluefin:lts` | ❌ FAIL | - | [#87](https://github.com/tuna-os/wootc/issues/87) | Walkthrough media asset accumulation in git tree |
| 2026-08-14 | `4c0e6c2` | [31782458569](https://github.com/tuna-os/wootc/actions/runs/31782458569) | `bluefin:lts` | ❌ FAIL | - | [#71](https://github.com/tuna-os/wootc/issues/71) | Podman v5 runner migration triage |
| 2026-08-13 | `284d4ee` | [31680770404](https://github.com/tuna-os/wootc/actions/runs/31680770404) | `bluefin:lts` | ❌ FAIL | - | [#71](https://github.com/tuna-os/wootc/issues/71) | Podman v5 runner migration triage |
| 2026-08-12 | `b660d16` | [31576887728](https://github.com/tuna-os/wootc/actions/runs/31576887728) | `bluefin:lts` | ❌ FAIL | - | [#71](https://github.com/tuna-os/wootc/issues/71) | Podman v5 runner migration triage |
| 2026-08-11 | `b8e37f4` | [31471261892](https://github.com/tuna-os/wootc/actions/runs/31471261892) | `bluefin:lts` | ❌ FAIL | - | [#71](https://github.com/tuna-os/wootc/issues/71) | Podman v5 runner migration triage |
| 2026-08-10 | `55f3780` | [31369510769](https://github.com/tuna-os/wootc/actions/runs/31369510769) | `bluefin:lts` | ❌ FAIL | - | [#71](https://github.com/tuna-os/wootc/issues/71) | Podman v5 runner migration triage |
| 2026-08-09 | `99fb74f` | [31301758460](https://github.com/tuna-os/wootc/actions/runs/31301758460) | `bluefin:lts` | ❌ FAIL | - | [#71](https://github.com/tuna-os/wootc/issues/71) | Podman v5 runner migration triage |
| 2026-08-08 | `ab00263` | [31246609805](https://github.com/tuna-os/wootc/actions/runs/31246609805) | `bluefin:lts` | ✅ PASS | - | - | Scheduled nightly |
| 2026-08-07 | `5995119` | [31160072559](https://github.com/tuna-os/wootc/actions/runs/31160072559) | `bluefin:lts` | ❌ FAIL | - | [#59](https://github.com/tuna-os/wootc/issues/59) | Hosted runner swtpm daemonization fix |
| 2026-08-06 | `c25c93c` | [31089571093](https://github.com/tuna-os/wootc/actions/runs/31089571093) | `bluefin:lts` | ❌ FAIL | - | [#59](https://github.com/tuna-os/wootc/issues/59) | Hosted runner swtpm daemonization fix |
| 2026-08-05 | `1a49955` | [30993412009](https://github.com/tuna-os/wootc/actions/runs/30993412009) | `bluefin:lts` | ✅ PASS | - | - | Scheduled nightly |
| 2026-08-04 | `e30a09c` | [30896688256](https://github.com/tuna-os/wootc/actions/runs/30896688256) | `bluefin:lts` | ❌ FAIL | - | [#28](https://github.com/tuna-os/wootc/issues/28) | ComposeFS Phase-2 UKI / initrd staging |
| 2026-08-03 | `e30a09c` | [30805816801](https://github.com/tuna-os/wootc/actions/runs/30805816801) | `bluefin:lts` | ❌ FAIL | - | [#28](https://github.com/tuna-os/wootc/issues/28) | ComposeFS Phase-2 UKI / initrd staging |
| 2026-08-02 | `8d964f4` | [30740994905](https://github.com/tuna-os/wootc/actions/runs/30740994905) | `bluefin:lts` | ✅ PASS | - | - | Scheduled nightly |
| 2026-08-01 | `04afce9` | [30692819051](https://github.com/tuna-os/wootc/actions/runs/30692819051) | `bluefin:lts` | ✅ PASS | - | - | Scheduled nightly |
| 2026-07-31 | `dd2634f` | [30620490003](https://github.com/tuna-os/wootc/actions/runs/30620490003) | `bluefin:lts` | ✅ PASS | - | - | Scheduled nightly |
| 2026-07-30 | `5e84f38` | [30530497117](https://github.com/tuna-os/wootc/actions/runs/30530497117) | `bluefin:lts` | ❌ FAIL | - | [#35](https://github.com/tuna-os/wootc/issues/35) | Early failure ledger harness transition (#3d7f9e2) |
| 2026-07-29 | `bf56522` | [30439943199](https://github.com/tuna-os/wootc/actions/runs/30439943199) | `bluefin:lts` | ❌ FAIL | - | [#35](https://github.com/tuna-os/wootc/issues/35) | Early failure ledger harness transition (#3d7f9e2) |
| 2026-07-28 | `39ae974` | [30346771735](https://github.com/tuna-os/wootc/actions/runs/30346771735) | `bluefin:lts` | ❌ FAIL | - | [#35](https://github.com/tuna-os/wootc/issues/35) | Early failure ledger harness transition (#3d7f9e2) |
| 2026-07-27 | `48f680f` | [30258357664](https://github.com/tuna-os/wootc/actions/runs/30258357664) | `bluefin:lts` | ❌ FAIL | - | [#35](https://github.com/tuna-os/wootc/issues/35) | Early failure ledger harness transition (#3d7f9e2) |
| 2026-07-26 | `1a40c11` | [30195835604](https://github.com/tuna-os/wootc/actions/runs/30195835604) | `bluefin:lts` | ❌ FAIL | - | [#35](https://github.com/tuna-os/wootc/issues/35) | Early failure ledger harness transition (#3d7f9e2) |
| 2026-07-25 | `e6b285c` | [30151895339](https://github.com/tuna-os/wootc/actions/runs/30151895339) | `bluefin:lts` | ❌ FAIL | - | [#35](https://github.com/tuna-os/wootc/issues/35) | Early failure ledger harness transition (#3d7f9e2) |

---

## Automation & Maintenance

- **Automated Updates**: The ledger is maintained by `.github/workflows/soak-ledger.yml`, which triggers automatically upon completion of each nightly `E2E GUI-driven (publish timelapse)` run.
- **Pages Dashboard**: Live web view is published to [`pages/soak/index.html`](https://tuna-os.github.io/wootc/soak/).
- **Tool CLI**: `python3 tools/soak-ledger/soak_ledger.py [update|check|summary]`.
