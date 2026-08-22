# winget packaging

`*.yaml.in` are templates for the [winget-pkgs](https://github.com/microsoft/winget-pkgs)
manifests of the generic installer, published as **`TunaOS.wootc`** (a
portable package: winget places `wootc.exe` on PATH; running it elevates
via UAC as usual).

`.github/workflows/winget-publish.yml` renders them on every **full**
release (pre-releases are skipped): it fills `{{VERSION}}` / `{{TAG}}` from
the release tag, `{{URL}}` with the release's `wootc.exe` asset, computes
`{{SHA256}}` from the actual bytes, and submits a PR to winget-pkgs with
[wingetcreate](https://github.com/microsoft/winget-create).

Requirements, both one-time:

- **`WINGET_TOKEN` repository secret** — a classic PAT with `public_repo`
  scope, used by wingetcreate to fork winget-pkgs and open the PR. Without
  it the workflow prints what it *would* submit and exits green.
- The **first** submission creates the package (same rendered manifests);
  Microsoft's moderation review of a new package can take a few days.
  Updates after that are routine.

Branded installers (Bazzite-Installer, Aurora-Installer, …) are deliberately
NOT auto-submitted: their winget identities belong to their projects
(`Bazzite.Installer` would sit in Bazzite's namespace), so each needs that
project's sign-off first. The same templates work — swap the identifier,
name, and asset.
