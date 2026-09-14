# devuan-kde-setup — ISO build (scaffold)

This directory produces a Devuan **Excalibur** amd64 ISO that ships KDE
Plasma with the toolkit's post-install state **already baked in**, so a
fresh install (or live session) lands in the "done" state instead of
requiring the post-install run.

## Building

```sh
sudo iso/build.sh            # whole flow, scratch dir iso/_build/
sudo iso/build.sh --clean    # wipe scratch + any built ISO
```

Prerequisites on the *build host* (not necessarily this machine):
- Devuan's `live-build` fork + `debootstrap` (`apt-get install live-build debootstrap`), `rsync`
- root, network access to `deb.devuan.org`, ~10 GB free disk
- a Linux vfat/xfs tolerant scratch disk is fine; ext4 default works

Output lands in `iso/.build/devuan-kde-latest.iso` (override name with
`ISO_NAME=...`).

**Status: scaffold.** The config tree (auto/config, package lists, bake
hook, includes) is structurally faithful to standard live-build practice,
but this box has neither live-build nor disk budget to burn a real ISO, so
**expect to iterate on a build host** — that's this directory's whole
purpose.

## What gets baked in

1. `iso/config/auto/config` — live-build options (Excalibur, amd64,
   main/contrib/non-free, i386-hybrid image). 
2. `iso/config/package-lists/kde.chroot` — a lean, hand-picked Plasma +
   app set (not the monolithic task package) matching the toolkit's
   debloat-first posture.
3. `iso/config/hooks/live/bake-devuan-kde.chroot` — runs the toolkit's own
   `run.sh --phase core` + `scripts/exportToSkel.sh` **inside the chroot**
   with `DEVMKDE_ASSUME_YES=1 DEVMKDE_ISO_BUILD=1`, so prompts are auto-
   answered and root-only helpers tolerate a plain-root build chroot. The
   resulting per-user config is exported to `/etc/skel` for every future
   user (live `devuan` user or one created later during a permanent
   install). Steps needing a live desktop harmlessly no-op.
4. `iso/build.sh` injects the toolkit itself into
   `config/includes.chroot/root/devuan-kde` before `lb build`, which is
   what lets the hooks call it. It also bundles `refractainstaller` in the
   ISO so burning/installing is a supported path.

## Installing / burning the ISO

- **Live session:** boot the ISO, log in, run `sudo refractainstaller` 
  from the live desktop for a full permanent install; the baked skel becomes
  every new user's starting home.
- **USB/CDFS:** `sudo cp iso/.build/*.iso /dev/sdX` or
  `sudo dd if=iso/.build/*.iso of=/dev/sdX bs=4M status=progress oflag=sync`.
- After a permanent install, rebake/refresh anything later-territory with
  the standard post-install toolkit run if desired.

## Why `iso.yml.pending`

See `iso.yml.pending` at the repo root: a placeholder for wiring a CI job
to build the ISO on a self-hosted runner. It stays `.pending` until the
build has been proven on a real host and the Excalibur baseline is locked.

## Notes for the build host

- Use Devuan's **own** live-build fork — Debian's upstream variant may
  mis-handle `excalibur`/Devuan mirrors.
- If `lb config` barfs on a knob, the `auto/config` file is the only place
  to fix it; `lb --help` documents current options on your fork version.
- The bake hook clones nothing — it uses the injected toolkit copy, so the
  ISO build is offline-safe apart from apt/source fetches.