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
  - Config files: `~/.config/kwinrc` (window manager/compositor — KWin
    effects and the Alt-Tab switcher live here under `[Plugins]` and
    `[TabBox]`), `~/.config/kdeglobals` (app style/colors/fonts — includes
    `ColorScheme` and `AccentColor` under `[General]`),
    `~/.config/kglobalshortcutsrc` (global keyboard shortcuts).
    There is **no** `khotkeysrc` on Plasma 6: KHotKeys was retired, and
    writing that file produces a success with no effect. Custom shortcuts are
    `~/.local/share/applications/<id>.desktop` entries with
    `X-KDE-GlobalAccel-CommandShortcut=true`, plus the matching
    `kglobalshortcutsrc` `[khotkeys]` group.
    Panel config is **two files**, and this is the single most useful thing to
    know before touching a panel:
    - `~/.config/plasma-org.kde.plasma.desktop-appletsrc` — `[Containments]`
      and `[Applets]`: which panels exist, at which edge, and what is on them.
    - `~/.config/plasmashellrc` — `[PlasmaViews][Panel <id>]`:
      `floating`, `alignment`, `panelVisibility`, `panelLengthMode`,
      `thickness`, `offset`, and `minLength`/`maxLength` under
      `[Horizontal <w>]`/`[Defaults]`. This is `PanelView::config()`
      (`shell/panelview.cpp`), and it is where the geometry lives.
    Both are backed up by `scripts/47-plasmaPanel.sh`; backing up only the
    first leaves `--restore` unable to undo floating, lengths or visibility.

    Prefer Plasma's own scripting D-Bus API over hand-editing either file:
    `qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript`,
    which is what `47-plasmaPanel.sh` does. Rules learned by running that
    payload against a live session — each of these contradicts what the source
    alone suggests:
    - **Assign the property.** The property setters are the persist. The
      scripting `writeConfig` targets the *containment* group, so
      `app.writeConfig("floating", true)` writes a key nothing reads.
    - **Verify in `plasmashellrc`, not through D-Bus.** The `hiding` getter is
      lossy: `"windowsgobelow"` persists `panelVisibility=3` but reads back
      `"none"`, indistinguishable from `0`.
    - **`opacity` cannot be set at all.** Every string and integer is ignored;
      `Adaptive` (Plasma's default) is what you get.
    - **`length` is the content width, not the panel width.** It is never
      clamped, so it reading 633px is not evidence the min/max bounds failed.
    - A new `Panel()` defaults to `top`, so a bottom bar must set
      `app.location` explicitly.
  - Writing config: `kwriteconfig6` (Plasma 6) or `kwriteconfig5` (Plasma 5)
    — check which is present, don't assume (`scripts/lib/common.sh`
    resolves it once into `$KWRITECONFIG`).
  - Konsole color schemes/profiles live in `~/.local/share/konsole/*.colorscheme|*.profile`
    (decimal `R,G,B` tuples); palette sources in `themes/` keep hex and the
    engine converts via `hex2rgb`. Plasma color scheme groups (window, button,
    selection, header, tooltips, view) live in
    `~/.local/share/color-schemes/*.colors`.
  - Global Themes (what `14-plasmaTheme.sh` and `46-applyThemes.sh` build)
    live in `~/.local/share/plasma/look-and-feel/<Name>/` and need
    `metadata.json` (KPackage `KPlugin` schema) — **not** the Plasma 5
    `metadata.desktop`. The `colors` entry is a *symlink* into
    `~/.local/share/color-schemes/`, which means three levels up from inside
    `look-and-feel/<Name>/`, not two.
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
- **Theme engine:** `scripts/lib/theme.sh` + `themes/palettes.sh`
  (`palette_<id>()` functions; the id is registered in `PALETTE_IDS`) of
  plain hex `C_BG`, `C_TEXT`, `C_ACCENT`, `C_0`..`C_15`, etc.), expanded
  through `themes/_base/tpl/` into a Konsole scheme/profile, a Plasma
  `.colors` file, and the kdeglobals accent. `applyThemes.sh` picks a
  palette; the current one is in
  `~/.local/state/devuan-kde-setup/current-theme`. Kit: **12 palettes** —
  darkmatter (default), darkmatter-orange, mocha-red, mocha-blue, moe-dark,
  frappe, nord, dracula, tokyo-night, gruvbox, solarized, otto. Keep `14-plasmaTheme.sh` and
  `46-applyThemes.sh` agreeing on the default; consistency test 5b fails the
  build if they drift.
  - The state path must be resolved **lazily** (`theme_state_dir`), never at
    source time: tests and sandboxes export `XDG_STATE_HOME` *after* sourcing
    `common.sh`, so a source-time constant points at the real
    `~/.local/state` and a dry run overwrites the live current-theme.
  - `C_*` values must stay valid 6-digit hex (consistency checks this for every
    palette, not just the selected one — a bad literal evaluates as black).
- **Palette keys are written LAST.** Every look-and-feel application rewrites
  `kdeglobals` from the package's `contents/defaults`, so
  `[General] ColorScheme`/`AccentColor` and `konsolerc DefaultProfile` are
  re-asserted by `persist_palette_keys` after every Plasma tool and every
  palette-specific package, through `ini_set_key` (which reads the value back).
  `kwriteconfig6` exits 0 while writing nothing for these keys, so its exit code
  is not evidence.
- **Otto integration:** `scripts/lib/otto.sh`, invoked by the theme engine only
  for `PALETTE_ID=otto`. Otto itself is not bundled — `store.kde.org` is behind
  Anubis, so it is a Discover/GUI install. Recolours *copies*, never the
  installed package: Global Theme (minus `contents/layouts/` and
  `contents/widgets/`, which would otherwise replace the panel), Kvantum `.conf`
  across all four colour notations with **SVGs left alone**, Konsole sections,
  and the decoration block in `contents/defaults`.
  - The marker filename is defined ONCE, as `DEVMKDE_GENERATED_MARKER` in
    `scripts/lib/common.sh` — three modules write or read it, and a divergence
    makes a generated wrapper look like the upstream theme it came from.
  - Every generated directory gets a `.devmkde-generated` marker and discovery
    skips marked or name-matched output. This is not optional bookkeeping: the
    generated wrapper declares the name `Otto Red`, so without it a rerun finds
    its own output as the "installed Otto", and the Kvantum copy's id ends in
    the palette name, so each run appends another suffix.
  - `contents/colors` is a **real copy**, never a symlink — same rule as
    `apply_global_theme`; Plasma 6 kpackages do not support one there.
  - No `-function polynomial` on the generated wallpaper: `6,-5,1` maps 0→1 and
    1→2, which turns a near-black gradient into a light grey one.
- Every apt action checks what's actually installed first — nothing is
  blindly force-purged, so scripts are safe to re-run.
- Config values that can't be verified against a real documented key are
  never guessed at silently — they're printed as a manual checklist
  instead. If you're not sure a KWin/kdeglobals key is real, say so
  rather than writing it speculatively.
- ISO: `iso/build.sh` + `iso/config/` (live-build; hooks/live/bake-devuan-
  kde.chroot runs the toolkit with `DEVMKDE_ISO_BUILD=1 DEVMKDE_ASSUME_YES=1`).
