# Release notes — Devuan KDE

## 1.0.0

First tagged release of the renamed, Plasma 6 toolkit.

### Renamed steps
All 34 step scripts moved to a `NN-camelCase.sh` convention so `run.sh` can
order them numerically and sort them correctly (`sort` would put `9-` after
`48-`). Every script gained machine-readable headers:

```bash
# DEVMKDE_DESC:    one-line human description
# DEVMKDE_DEFAULT: Y | N
# DEVMKDE_PHASE:   core | sysmgmt | optional | standalone
```

`12-kdeDebloat.sh` is the one name that reads oddly and stays that way — it is
a deliberate "remove what Plasma bundles" step, not a mistake.

### Two new steps
- `33-plasmaPerformance.sh` — animations, compositing, desktop icons, Baloo
  indexing limits and autostart trimming. Init-agnostic; it writes `kwinrc`,
  `plasmarc` and autostart files rather than assuming systemd.
- `48-plasmaAddons.sh` — verified Plasma 6 add-on packages, KRunner runners,
  extra image formats, KWallet-aware SSH, Flatpak apps, and user-supplied
  `kpackagetool6` kpackages.

### Plasma 6 correctness
Written against Plasma 6.3 / KDE Frameworks 6.13. The Plasma 5 spellings that
silently do nothing on Plasma 6 are all gone:

| Setting | Plasma 5 (broken) | Plasma 6 (correct) |
| --- | --- | --- |
| Accent | `accentColor=` in `kdeglobals` | `AccentColor=` in `[General]` |
| Accent follow | `AccentColorFromWallpaper=` | removed (always on) |
| Window blur | `kwineffectsrc` | `kwinrc [Plugins]` |
| Magic Lamp | `kwineffectsrc` | `kwinrc [Plugins]` |
| Alt-Tab | `CurrentDesktopLayout=` | `kwinrc [TabBox] LayoutName=coverswitch` |
| Custom shortcuts | `~/.config/khotkeysrc` | `~/.local/share/applications/<id>.desktop` + `kglobalshortcutsrc` |
| Global Theme | `metadata.desktop` | `metadata.json` |

The consistency suite fails the build if any of the old spellings come back.

### Privilege and package handling
- `priv` / `priv_n` / `priv_as` / `require_priv` in `scripts/lib/common.sh`
  resolve **sudo first, doas second**, overridable with `DEVMKDE_PRIV`.
  Every escalated call site in `scripts/` goes through them; there is no bare
  `sudo` left in the toolkit, including the generated cron checker, which now
  resolves its own helper because it ships without `lib/common.sh`.
- `apt_update`, `install_pkgs`, `purge_if_installed` and `install_deb_file`
  centralise routine apt work. Direct `apt-get` remains only for upgrades,
  autoremove, clean and environment-specific operations.
- `install_deb_file` handles `--repair` and rolls back cleanly.
- `DEVMKDE_ISO_BUILD` skips privilege requirements for ISO bakes.

### Panel
`47-plasmaPanel.sh` rebuilds the panel through the Plasma 6 D-Bus scripting API
(`org.kde.PlasmaShell.evaluateScript`) instead of hand-editing
`plasma-org.kde.plasma.desktop-appletsrc`, which is fragile and schema-fragile.
It backs the existing configuration up first and is reversible with
`--restore`.

Layout is a single floating bar on the bottom edge — launcher, pinned apps,
icon-only task manager, workspace pager, tray, clock — because a floating bar
reserves no screen space and one bar means one place to look. The clipboard
history and activity-bar applets are off by default; `--extras` puts them back,
and `--tray-panel` restores the old second, auto-hiding 340px tray/clock bar on
the top right. Also `--dodge-windows` (the bar dodges maximized windows instead
of staying on screen), `--dry-run` (print the JS payload and the backup path,
write nothing).

Which properties actually persist was established by applying the payload to a
live session and reading the two files Plasma wrote — not by reading the source
and not by reading the property back. Three things that source-reading alone
gets wrong:

- **Assign the property; `writeConfig` is inert for panel geometry.**
  `PanelView`'s setters write into `PanelView::config()`, i.e.
  `[PlasmaViews][Panel <id>]` in **`~/.config/plasmashellrc`**, while the
  scripting wrapper's `writeConfig` targets the containment group in
  `desktop-appletsrc`. An earlier version of this script led with
  `app.writeConfig("floating", true)` under a comment asserting the opposite,
  and every test passed while the bar stayed full width.
- **The geometry is in a second file.** `desktop-appletsrc` keeps
  `[Containments]`/`[Applets]` — which panels exist and what is on them;
  `plasmashellrc` keeps `floating`, `alignment`, `panelVisibility`,
  `panelLengthMode`, `thickness`, `offset` and the min/max length. Backing up
  only the first left `--restore` unable to undo half of what it claims.
- **The `hiding` getter is lossy, the setter is not.** Assigning
  `"windowsgobelow"` persists `panelVisibility=3` (always visible, reserves no
  space), but reading `.hiding` back answers `"none"` — the getter cannot tell
  `0` from `3`. This was briefly "fixed" by switching the app bar to `"none"`,
  which is `panelVisibility=0`: always visible *and* space reserved, the
  opposite of the intent. Panel properties have to be verified in
  `plasmashellrc`; D-Bus read-back cannot confirm them.

`opacity` is the one property that cannot be set through this API at all: every
string and every integer was tried on a live panel and no `panelOpacity` key was
ever written, while the property always read back `adaptive`. `Adaptive` is
Plasma's own default — translucent normally, opaque behind a maximized window —
so the script sets nothing rather than logging a translucency it cannot deliver.

Two more traps this payload hit, both invisible in a passing run: the JS heredoc
was **unquoted**, so the shell expanded the body first and a backticked word in
a comment ran as a command substitution; and the pinned-app substitution used
`|` as its `sed` delimiter while the URL list is joined with `||`, which aborts
the substitution and ships a bar with no launchers. Both are guarded now.

### Terminal and system info
- ButterBash is **fetched at a pinned commit** (full 40-char sha, tarball
  SHA256 verified) and wired into `.bashrc` as one marked, idempotent block.
  Upstream's `install.sh` is deliberately not run: it fetches its own current
  HEAD, which would make the pin decorative. The vendored copy that used to
  live in-tree is gone for the same reason — with a directory checked in, the
  pin is bypassed and the pin's presence implies nothing.
- `23-fastfetchConfig.sh` installs the bundled configs in `assets/fastfetch/`
  and reaches no network at all. The configs omit `resolution` and
  `terminalFont`: fastfetch 2.40.4 stops rendering modules after an empty one
  and silently truncates the rest.

### Session support
X11 and Wayland are both supported, with the differences detected rather than
assumed. This release removes the "X11 only" statement the README carried:
under Wayland `27-fancyPlasma.sh` skips the X11-only window-management tweaks
and says so, instead of writing keys nothing reads.

### Theming
- Palettes live in `themes/palettes.sh` as `palette_<id>()` functions; templates in
  `themes/_base/tpl/`. 12 palettes ship in-tree — `darkmatter`,
  `darkmatter-orange`, `mocha-red`, `mocha-blue`, `moe-dark`, `frappe`, `nord`,
  `dracula`, `tokyo-night`, `gruvbox`, `solarized`, `otto`.
- `14-plasmaTheme.sh` renders the selected palette into a Plasma 6 Global
  Theme (`contents/colors` is a **real copy, not a symlink** — Plasma 6
  kpackages do not support one there), Konsole profile, accent, icon theme and
  generated wallpaper.
- **`moe-dark` (Moe Dark)** installs the real **Moe v2.6** Global Theme from a
  pinned mirror through `scripts/lib/moe.sh`, verified by SHA256 at download
  time and sanitised before install: upstream's `contents/defaults` are reduced
  to the engine's own plus the Breeze task-switcher entries, and the components
  it names that are not installed are dropped, so the theme can never reference a
  decoration or widget style the machine does not have. Nothing is vendored —
  the assets land in `~/.cache/devuan-kde-setup/moe` at apply time.
- **[Fixed] the active color scheme did not survive a theme apply.**
  `[General] ColorScheme` was written with `kwriteconfig6`, which exits 0 and
  writes nothing for that key, and it was written *before* the look-and-feel
  applications that rewrite `kdeglobals` from the package's `contents/defaults`.
  A run logged "Plasma color scheme ... persisted" and left `kdeglobals` with no
  `ColorScheme` at all, so the next login came up on Plasma's default scheme with
  every generated colour reverted and nothing logged an error. The keys now go
  through `ini_set_key` (edit, then read back) and are re-asserted as the last
  thing `apply_palette` does — after the palette-specific Moe/Otto packages.
- **`otto` (OttoRed)** recolours an installed Otto theme through
  `scripts/lib/otto.sh`. Otto itself is not bundled and cannot be installed by
  a script: `store.kde.org` is behind an Anubis challenge, so it is a
  Discover/GUI step. With Otto absent the palette still applies standalone and
  reports what it could not find.
  - Recolours from copies, never in place: Global Theme → `OttoRed` with
    `contents/layouts/` and `contents/widgets/` stripped (shipping layouts in
    a Global Theme replaces the panel and would undo step 47), Kvantum `.conf`
    across all four colour notations, and Konsole section-aware.
  - **Kvantum SVGs are copied untouched** — recolouring Qt's SVG state cache
    produces a half-tinted theme, and Kvantum rebuilds it.
  - Every generated directory carries a `.devmkde-generated` marker and
    discovery skips it. Without the marker a rerun finds its own output: the
    generated wrapper declares the name `Otto Red`, so the second apply
    reported "Otto Global Theme applied" on a machine with no Otto, and the
    Kvantum copy's id ends in the palette name, so each run appended another
    suffix (`Otto-Dark-OttoRed`, `Otto-Dark-OttoRed-OttoRed`, …).
  - The generated wallpaper carries no ImageMagick contrast curve:
    `-function polynomial 6,-5,1` maps 0→1 and 1→2, which on a near-black
    palette does not add contrast but inverts the image into the highlights
    (measured 5.5% mean brightness without it, 74% with it).
- Catppuccin KDE is pinned to tag `v0.4.0`, commit
  `6606b5179cfc1e9ba5c3b6b70e15c468e2dddca2`, tarball SHA256
  `79ff6736afef26eb49a978392174801f2a6d28c7e328ac79499e10da8a55f1b9`.
- The Darkmatter GTK/xfwm4 theme and Zafiro icons are **fetched at install
  time**, never committed; the tree carries no binary assets.

### Testing
Three read-only tiers, `make check` or `./tests/run.sh`:

1. **Lint** — `bash -n`, `shellcheck` when installed, the
   `[ -n "$x" && "$x" = y ]` guard, and a check that every script sourcing
   `common.sh` can actually source it.
2. **Unit** — sandboxed tests for the privilege helpers (fake `sudo`/`doas`,
   never touching real escalation), the theme engine (rendered into a temp
   `THEME_HOME_DIR`, never the real `$HOME`), and the runner.
3. **Consistency / apt** — VERSION↔RELEASE.md, README↔scripts, no bare `sudo`,
   no Plasma 5 regressions, palette variable-set drift, 6-digit hex validation
   for every `C_*`, bundled-asset presence, the ButterBash pin being a full
   commit sha with a checksum, `contents/colors` never symlinked, and read-only
   `apt-cache` existence for all 220 referenced package names.
4. **Negative controls** (`tests/negative-controls.sh`) — 37 regressions are
   injected into a scratch copy of the repo and the tier that should catch each
   one is required to fail. A green suite on its own proves nothing: the
   cheapest way to all-green is to delete the assertion. Every new guard added
   this release came with its control, and two guards here were found to be
   **false greens** by that harness — they matched their own explanatory
   comments while the code they guarded was broken.

No tier needs root, apt mutation, X or network.

### Known limitations
- Live Plasma behaviour is validated by inspection and unit tests, not by
  running these scripts inside a Plasma session. Run `./run.sh --only <n>` on a
  throwaway VM before deploying to anything you care about.
- `48-plasmaAddons.sh` takes a **user-supplied** `kpackage` URL rather than
  shipping a list of store widgets: `store.kde.org` is bot-walled and
  arbitrary GitHub fetches could not be verified at release time.
- `shellcheck` and `lintian` are not installed on the build host, so those
  checks self-skip locally and only run in CI.