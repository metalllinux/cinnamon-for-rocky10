# Cinnamon for Rocky Linux 10

The Cinnamon desktop for Rocky Linux 10. Built for a full desktop
experience with Rocky branding, the Rocky default wallpaper, and a working
terminal, not a bare shell install.

## Status

**Updated:** 2026-09-19
**Target:** Rocky Linux 10.2 (Red Quartz)
**State:** complete. All review findings resolved, all re-verifications PASS.
Ready for the release PR.

The repository publishes 64 RPMs. The install set is the 22 runtime package
names in `vm-test/install-set.txt` (source of truth). A fresh Rocky Linux
10.2 VM installs the whole set with a single `dnf install`, logs in through
GDM into the Cinnamon Wayland session, and runs the full desktop.

| Check | Result |
|-------|--------|
| Fresh-VM install | single `dnf install` of the 22 runtime names, zero manual steps |
| GDM login | Cinnamon (Wayland) session active |
| Desktop surfaces | 5 of 5 (panel, wallpaper, terminal, settings, main menu) |
| Parity vs the Fedora Cinnamon reference | 11 of 11 |
| `run-tests.sh` end-to-end | all 64 RPMs in one `dnf install`, first attempt |
| Enforcing-SELinux smoke | five surfaces, zero AVC denials |

Three differences from the Fedora Cinnamon reference are intentional
branding choices. The panel shows the Rocky logo instead of the Fedora
logo, the wallpaper is Rocky's time-based Gemstone Skies instead of Fedora's
blue tile, and the theme set is the stock Cinnamon theme with Adwaita GTK
and gnome icons instead of Mint-Y.

## What the complete set adds

Since the initial 14-package build, the set gained eight new packages and
two rebuilt ones.

| Package | Version | What it provides |
|---------|---------|------------------|
| gnome-terminal | 3.54.5-1.el10 | The desktop terminal |
| cinnamon-rocky-defaults | 1.0-2.el10 | Rocky branding. The Gemstone Skies wallpaper and the Rocky logo on the menu button, pulled from `rocky-backgrounds` and `rocky-logos` by dependency |
| python3-pillow | 12.3.0-2.el10 | Settings app dependency (image handling) |
| python3-setproctitle | 1.3.7-2.el10 | Settings app dependency (process title) |
| python3-tinycss2 | 1.5.1-2.el10 | Settings app dependency (CSS parsing) |
| python3-webencodings | 0.5.1-2.el10 | Runtime dependency of tinycss2 |
| python3-xapp | 3.0.2-1.el10 | Settings app dependency (XApp API) |
| gdk-pixbuf-parsers | 2.42.12-2.el10 | PNG and JPEG image loaders. EL10's `gdk-pixbuf2` ships none, and photo wallpapers render black without them |
| cinnamon-desktop | 6.7.2-2.el10 | Rebuilt. A patch composites photo wallpapers on the Wayland background window |
| cinnamon | 6.7.4-3.el10 | Rebuilt. This release bundles the Cinnamon Settings app and declares the Python dependencies as RPM Requires, so the settings panel works out of the box |

The `cinnamon-settings` package from the 14-package era is gone. The
settings app ships inside the `cinnamon` RPM now.

`gnome-terminal` is built from source because no EL10 or EPEL repository
carries it. 3.54.5 is the newest release compatible with EL10's vte291
0.78.6. The Fedora reference runs 3.60.0, which needs vte 0.79.90, so the
version gap is a recorded deviation, not an oversight.

## Build notes

- All builds are meson and ninja on Rocky Linux 10.2 with CRB enabled.
- Muffin is built with Wayland enabled. The session runs as
  cinnamon-wayland, and GDM on EL10 is Wayland-only.
- mozjs115 115.29.0 is built from Mozilla ESR source. cjs stays at 6.4.0.
  The cjs 140.0 upgrade needs GLib 2.86 and SpiderMonkey 140 APIs that EL10
  does not ship.
- `spec/` is the canonical source for every published RPM. Each spec records
  the exact upstream commit and the build tarball sha256 it was built from.
  A clean-checkout rebuild from a fresh clone reproduces the published set
  (verified 2026-09-19).
- Every source-built package ships its license file under
  /usr/share/licenses/.

## Test results

Verified on fresh Rocky Linux 10.2 VMs (libvirt/KVM, VNC). Evidence lives
in `vm-test/evidence/` and `vm-test/parity/`.

- 2026-09-18, fresh VM `task0017-fresh-vm`. The 22 runtime names installed
  with one `dnf install` and zero manual steps. All five desktop surfaces
  passed. The panel with the default applet set, the Gemstone Skies
  wallpaper rendering day and night, gnome-terminal opening, the System
  Settings app opening, and the main menu opening. The parity inventory
  against the Fedora reference came back 11 of 11, with the three
  intentional branding divergences above.
- 2026-09-19, fresh VM `t17-revB`. `vm-test/run-tests.sh` end-to-end. All
  64 RPMs installed in one `dnf install` on the first attempt, 22 of 22
  names verified, GDM Wayland login, and the Super key opening the main
  menu. The same VM then rebooted under enforcing SELinux, and all five
  surfaces passed with zero AVC denials.
- 2026-09-19, clean-checkout rebuild from a fresh clone. All changed specs
  built, and the payloads matched the published set except build
  environment artifacts (LTO build-ids, pip direct_url paths).

## Signing and release verification

The 64 published RPMs are signed with a dedicated GPG key, and the
repository installs with `gpgcheck=1`, so dnf verifies the signature of
every package it installs. The public key ships in the repository at
`keys/cinnamon-rocky10-public.asc` (fingerprint
`1689676AF4D4F6FEC142B4429C0A8912FDA02785`), and
`repo-setup/setup-repo.sh` imports it into the rpm keyring as part of
repository setup. Each release is pinned to a git tag, and the sha256
manifest at `rpms/SHA256SUMS` records the signed set. The "Verifying the
release" section in INSTALL.md covers the two checks. The manifest
verifies your copy against the released set, and the signature verifies
the set against the key holder.

## Installation

See [INSTALL.md](INSTALL.md) for step-by-step installation on a fresh Rocky
Linux 10 system.

## Project structure

```
spec/              RPM spec files, patches, and vendored license files (canonical)
rpms/              the published RPM set (64 files)
src/               source code references
repo-setup/        local DNF repository setup script
tasks/             VM test harness library (GDM driver, a11y client, ukey input)
vm-test/           VM provisioning, run-tests.sh, install-set.txt, parity, evidence
INSTALL.md         installation instructions
```

## Development

This project is developed by [Team Chaotix](https://github.com/metalllinux/team-chaotix)
using opencode on Rocky Linux 10.2.

## License

Cinnamon components are under their respective upstream licenses (GPL-2.0,
LGPL-2.0, MIT). See individual component LICENSE files. Every source-built
package in this repository ships its license file under
/usr/share/licenses/.
