# Devuan KDE - project instructions

Post-install polish for a Devuan 6 (Excalibur) / Debian 13 (Trixie) box where
KDE Plasma 6 is already installed. The toolkit does not install Plasma. It
trims the distro task, installs missing desktop pieces, and applies a
Graphite Amber visual identity to Plasma, Konsole, LightDM/SDDM, GRUB and Plymouth.

## Entry points

- `run.sh` discovers `scripts/[0-9][0-9]-*.sh`, groups them by phase, and
  reads `# DEVMKDE_DESC:`, `# DEVMKDE_DEFAULT:` and `# DEVMKDE_PHASE:` headers.
- `install.sh` is the unattended wrapper: `--full --yes`, then `--verify`.
- `scripts/verifySetup.sh` is the read-only end-state audit. Run it after
  changing a step. `run.sh --verify` wraps it.

## Conventions

- Run as a normal user. Privileged calls go through `priv()` in
  `scripts/lib/common.sh`. It prefers sudo, falls back to doas, and honors
  `DEVMKDE_PRIV=sudo|doas`. Do not write bare sudo in new steps.
- Devuan uses OpenRC or sysvinit. Never introduce systemd units or calls.
- Install only missing packages through `install_pkgs`. Keep apt operations
  explicit and idempotent.
- Back up before destructive config writes. Re-running any step must be safe.
- `themes/` holds templates and palette functions. Themes are rendered at
  apply time, not downloaded by the runner.
- `VERSION` and the latest heading in `RELEASE.md` must agree.
  `make release-preflight` checks that before a tag.

## Verification

- `bash -n` on changed shell files.
- `bash scripts/verifySetup.sh` on a target system.
- `bash run.sh --list` and `bash run.sh --list-utilities` after adding scripts.
