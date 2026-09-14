# System context: Devuan/Debian + KDE Plasma

This machine was set up with `devuan-kde-setup`, a post-install polish
toolkit. Keep the following in mind when suggesting commands or diagnosing
issues on this system:

## Package management
- **APT-based** (Debian/Devuan), not Arch/Fedora/Nix. Use `apt`/`apt-get`,
  never `pacman`, `dnf`, or `nix-env`.
- `apt-get install -y <pkg>` for installs, `apt-get purge -y <pkg>` to
  remove, `apt-get autoremove --purge -y` to clean up orphaned deps.
- Flatpak is available (via Discover or `flatpak install flathub <app>`)
  as a secondary source if a package isn't in Debian's repos.

## Init system
- **Devuan** ships without systemd by default (sysvinit or OpenRC,
  user's choice at install time) — **do not assume `systemctl` works.**
  Check for it first: `command -v systemctl && [ -d /run/systemd/system ]`.
  If that's false, use `service <name> start|stop|restart` and
  `update-rc.d <name> defaults` instead of `systemctl enable`.
- If this is plain **Debian** rather than Devuan, systemd is the default
  and `systemctl` is safe to assume.
- Check `/etc/devuan_version` (Devuan) vs `/etc/debian_version` (Debian)
  to tell which one you're on.

## Desktop environment
- **KDE Plasma** (Plasma **5.27** on Devuan Excalibur; Plasma 6 on newer
  Debian) — not GNOME, Cinnamon, or XFCE. Desktop-specific commands should
  target KDE's own tools:
  - Config files: `~/.config/kwinrc` (window manager/compositor),
    `~/.config/kdeglobals` (app style/colors/fonts — includes `ColorScheme`
    and `accentColor`),
    `~/.config/kglobalshortcutsrc` (global keyboard shortcuts),
    `~/.config/khotkeysrc` (KHotkeys custom shortcuts — top-level
    `[Data]` `DataCount=<N>` plus `Data_<n>` groups and `Data_<n>_<i>`
    children; uuid lives in kglobalshortcutsrc `[khotkeys]`),
    `~/.config/plasma-org.kde.plasma.desktop-appletsrc` (panel layout —
    fragile to hand-edit; prefer Plasma's own scripting D-Bus API,
    `qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript`).
  - Writing config: `kwriteconfig6` (Plasma 6) or `kwriteconfig5` (Plasma 5)
    — check which is present, don't assume (`scripts/lib/common.sh`
    resolves it once into `$KWRITECONFIG`).
  - Konsole color schemes/profiles live in `~/.local/share/konsole/*.colorscheme|*.profile`
    (decimal `R,G,B` tuples); palette sources in `themes/` keep hex and the
    engine converts via `hex2rgb`. Plasma color scheme groups (window, button,
    selection, header, tooltips) live in `~/.local/share/color-schemes/*.colors`.
  - Applying live: `plasma-apply-colorscheme`, `plasma-apply-desktoptheme`,
    `plasma-apply-lookandfeel`, `plasma-apply-cursortheme`.
  - File manager is **Dolphin** (KIO-based — trash/network shares/thumbnails
    work through KIO, not gvfs); terminal is the `DefaultProfile` in
    `~/.config/konsolerc`.
  - Global shortcuts are **not** gsettings/dconf (that's GNOME/Cinnamon) —
    they're `kglobalaccel`, backed by `kglobalshortcutsrc` plus a matching
    `.desktop` file with `X-KDE-GlobalAccel-CommandShortcut=true`.

## This toolkit's own conventions (for consistency if extending it)
- Scripts live in `scripts/`, each independently runnable, and **all of
  them source `scripts/lib/common.sh`** (helpers: `require_not_root`,
  `run_as_user`/`ACTUAL_USER`, `init_system`/`start_service`/`service_restart`,
  `apt_update`/`install_pkgs`/`purge_if_installed`, `verify_download`/
  `sha256_verify`, `ask`, `kwrite_user`, `log_*`). `$KWRITECONFIG` is
  resolved once there.
- `run.sh` drives scripts in order. Its `SCRIPTS` array uses the 4-field
  format `script|desc|default(Y/N)|section`, sections are `core`,
  `sysmgmt`, `optional`, addressed with `--phase <section>` / `--full`;
  `install.sh` wraps it. Env honored: `DEVMKDE_ASSUME_YES=1` (prompts take
  defaults), `DEVMKDE_SKIP_APT_UPDATE=1`, `DEVMKDE_ISO_BUILD=1` (allow
  root inside a build chroot).
- **Theme engine:** `scripts/lib/theme.sh` + `themes/<name>/palette.sh`
  (plain hex `C_BG`, `C_TEXT`, `C_ACCENT`, `C_0`..`C_15`, etc.) expanded
  through `themes/_base/tpl/` into a Konsole scheme/profile, a Plasma
  `.colors` file, and the kdeglobals accent. `applyThemes.sh` picks a
  palette; the current one is in
  `~/.local/state/devuan-kde-setup/current-theme`. Kit: 8 palettes
  (mocha-red default, mocha-blue, frappe, nord, dracula, tokyo-night,
  gruvbox, solarized).
- Every apt action checks what's actually installed first — nothing is
  blindly force-purged, so scripts are safe to re-run.
- Config values that can't be verified against a real documented key are
  never guessed at silently — they're printed as a manual checklist
  instead. If you're not sure a KWin/kdeglobals key is real, say so
  rather than writing it speculatively.
- ISO: `iso/build.sh` + `iso/config/` (live-build; hooks/live/bake-devuan-
  kde.chroot runs the toolkit with `DEVMKDE_ISO_BUILD=1 DEVMKDE_ASSUME_YES=1`).
