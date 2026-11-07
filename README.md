# Cinnamon for Rocky Linux 10

The Cinnamon desktop for Rocky Linux 10. Built for a full desktop
experience with Rocky branding, the Rocky default wallpaper, and a working
terminal, not a bare shell install.

## Status

**Updated:** 2026-11-07
**Target:** Rocky Linux 10.2 (Red Quartz)
**State:** complete. All review findings resolved, all re-verifications PASS.
Ready for the release PR.

The repository publishes 104 RPMs. The install set is the 40 runtime
package names in `vm-test/install-set.txt` (source of truth). A fresh
Rocky Linux 10.2 VM installs the whole set with a single `dnf install`,
logs in through lightdm into the Cinnamon X11 session, and runs the full
desktop.

| Check | Result |
|-------|--------|
| Fresh-VM install | single `dnf install` of the 40 runtime names, zero manual steps |
| Signature verification | `gpgcheck=1`, every package verifies against the tracked key |
| lightdm login | Cinnamon (X11) session active, slick greeter |
| Desktop surfaces | desktop icons (Computer, Home, Trash) and System Settings |
| Window button availability | 33 Mint-L, 11 Mint-X, 20 Mint-Y |
| Enforcing-SELinux run | zero AVC denials throughout |

Two differences from the Fedora Cinnamon reference are intentional
branding choices. The panel shows the Rocky logo instead of the Fedora
logo, and the wallpaper is Rocky's time-based Gemstone Skies instead of
Fedora's blue tile. The theme set matches the reference. The set ships
the Mint-L, Mint-X, and Mint-Y icon and theme families, and the branding
override sets the icon theme to `Mint-Y-Aqua`.

## What the complete set adds

Since the initial 14-package build, the set has grown to 40 runtime
packages (104 RPMs). The table lists the packages the set carries and what
each provides; `vm-test/install-set.txt` is the complete 40-name list.

| Package | Version | What it provides |
|---------|---------|------------------|
| gnome-terminal | 3.54.5-1.el10 | The desktop terminal |
| cinnamon-rocky-defaults | 1.0-9.el10 | Rocky branding. The Gemstone Skies wallpaper and the Rocky logo on the menu button, pulled from `rocky-backgrounds` and `rocky-logos` by dependency |
| python3-pillow | 12.3.0-2.el10 | Settings app dependency (image handling) |
| python3-setproctitle | 1.3.7-2.el10 | Settings app dependency (process title) |
| python3-tinycss2 | 1.5.1-2.el10 | Settings app dependency (CSS parsing) |
| python3-webencodings | 0.5.1-2.el10 | Runtime dependency of tinycss2 |
| python3-xapp | 3.0.2-1.el10 | Settings app dependency (XApp API) |
| gdk-pixbuf-parsers | 2.42.12-2.el10 | PNG and JPEG image loaders. EL10's `gdk-pixbuf2` ships none, and photo wallpapers render black without them |
| cinnamon-desktop | 6.7.2-3.el10 | Rebuilt. A patch composites photo wallpapers on the Wayland background window |
| cinnamon | 6.7.4-4.el10 | Rebuilt. This release bundles the Cinnamon Settings app and declares the Python dependencies as RPM Requires |
| cvt | 0.1.2-11.el10 | Video timing calculator, built and installed by the libxcvt build |
| libxcvt | 0.1.2-11.el10 | Video timing calculation library, runtime dependency of Xorg |
| libXfont2 | 2.0.9-1.el10 | Font rendering library, runtime dependency of Xorg |
| libxklavier | 5.4-2.el10 | Keyboard layout library, dependency of the lightdm chain |
| lightdm | 1.33.1-1.el10 | Display manager, the default display manager of the set |
| lightdm-gobject | 1.33.1-1.el10 | GObject session management library used by the slick greeter |
| mint-cursor-themes | 1.0.2-1.el10 | Mint cursor themes |
| mint-l-icons | 1.8.0-1.el10 | Mint-L icon theme |
| mint-l-theme | 2.0.6-2.el10 | Mint-L GTK theme |
| mint-themes | 2.3.8-1.el10 | Mint theme collection. Provides the Mint-Y-Dark-Aqua theme the slick override uses |
| mint-x-icons | 1.7.5-1.el10 | Mint-X icon theme |
| mint-y-icons | 1.9.2-1.el10 | Mint-Y icons. Provides the Mint-Y-Aqua icon set the slick override uses |
| slick-greeter | 2.2.6-2.el10 | Login greeter for lightdm |
| slick-greeter-cinnamon | 2.2.6-2.el10 | Cinnamon variant of the slick greeter |
| xapp-symbolic-icons | 1.1.0-2.el10 | Symbolic icons for XApp applications |
| xorg-x11-drv-libinput | 1.5.0-2.el10 | libinput X input driver, hard dependency of Xorg |
| xorg-x11-server-common | 21.1.24-2.el10 | Shared X server files and configuration |
| xorg-x11-server-Xorg | 21.1.24-2.el10 | X server, run by lightdm for the greeter and the X11 session |

The `cinnamon-settings` package from the 14-package era is gone. The
settings app ships inside the `cinnamon` RPM now.

**Known issue (fixed in the published set).** The TimezoneMap GI
namespace is missing on Rocky 10, and the pre-6.7.4-4 settings app
("Control Center") crashed at startup with `ValueError: Namespace
TimezoneMap not available` before any window appeared. The published
`cinnamon` 6.7.4-4 makes the namespace optional (TASK-0038), so the app
starts and stays alive with no TimezoneMap error, verified at the
process level. When the namespace is absent, the Region/City selector
covers timezone selection.

**Known issue.** Screen brightness has no end-to-end effect on the
team's machines. The published `cinnamon-settings-daemon` 6.7.2-4 ships
`csd-backlight-helper`, the only brightness backend the settings
daemon's power plugin spawns for every brightness get and set, and the
helper runs and reports the absence of backlight hardware instead of
failing to spawn, verified at the D-Bus level on the team's test VM.
Brightness changes need a display with a real backlight, which the
team's virtual machines do not have, so the end-to-end path on real
backlight hardware is unverified.

**Known issue.** Opening the Power pane of Cinnamon Settings
("Control Center") prints a D-Bus `Unauthorized (36)` traceback at
`cs_power.py:883 on_my_value_changed`; the process survives and the
pane stays usable. The traceback is at pane startup, and the failing
`Set` writes back the profile the pane just read, so the displayed
profile is correct and the failure is cosmetic.

The power-profile D-Bus name is answered on Rocky 10 by the base-OS
`tuned-ppd` service, the PPD-to-TuneD translation daemon;
`power-profiles-daemon` is not installed. `tuned-ppd` gates profile
switching behind interactive polkit authentication for the action
`net.hadess.PowerProfiles.switch-profile`, and the unguarded `Set` in
the pane's startup self-trigger is rejected in sessions with no
attached polkit agent, which is where the traceback comes from. It
reproduces on both test VMs, Rocky 10.2 (Wayland) and the Fedora 45
reference (X11), with an identical error. Profile switching on a live
desktop goes through the same gate, so a click prompts for
authentication and succeeds with the user's password; that
live-desktop outcome is inferred from the service code, not tested,
because the team's test VMs cannot drive an interactive dialog. The
fix belongs upstream in `linuxmint/cinnamon` (guard the `Set` call
or suppress the startup self-trigger); no fix exists in this
environment, and the traceback persists on the published set until
upstream changes.

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
  the exact upstream commit and the build tarball sha256 it was built from,
  except the thirteen window-button and X-stack specs, which carry no
  rpmbuild-enforced source checksum. The six mint specs record the hash as
  an in-tree `# SHA256:` comment, and the seven X-stack specs record the
  exact Fedora 45 Koji build in their changelog instead. A clean-checkout
  rebuild from a fresh clone reproduces the published set (verified
  2026-09-19).
- Every source-built spec installs the component's license file under
  /usr/share/licenses/. The published set carries them in 44 of its
  104 RPMs, and the other 60 carry none. The License section lists the
  40 main packages that carry them, by package and the files each ships.

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
- 2026-11-07, fresh-consumer run on VM `cinnamon-5`. The 40 runtime names
  installed with one `dnf install` under `gpgcheck=1`, with SELinux
  enforcing throughout and zero AVC denials. lightdm login through the
  slick greeter into the Cinnamon X11 session. The desktop showed the
  Computer, Home, and Trash icons, System Settings opened, and window
  button availability came back 33 for Mint-L, 11 for Mint-X, and 20 for
  Mint-Y. The negative tamper test passed, and the sha256 manifest
  reported 104 of 104 lines OK.

## Signing and release verification

The 104 published RPMs are signed with a dedicated GPG key, and the
repository is configured with `gpgcheck=1`, so dnf verifies the signature of
every package it installs. The public key ships in the repository at
`keys/cinnamon-rocky10-public.asc` (fingerprint
`2274BFE1BF28C051CD98675BEBD13108EB7FEF99`), and
`repo-setup/setup-repo.sh` imports it into the rpm keyring as part of
repository setup. Each release is pinned to a git tag, and the sha256
manifest at `rpms/SHA256SUMS` records the signed set. The "Verifying the
release" section in INSTALL.md covers the two checks. The manifest
verifies your copy against the released set, and the signature verifies
the set against the key.

## Installation

See [INSTALL.md](INSTALL.md) for step-by-step installation on a fresh Rocky
Linux 10 system.

## Project structure

```
spec/              RPM spec files, patches, and vendored license files (canonical)
rpms/              the published RPM set (104 files)
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

The top-level `LICENSE` (GPL-2.0) covers this repository's own files
(specs, patches, scripts, docs) only. It does not cover the component
checkouts, which are under their upstream licenses. Most components
are GPL-2.0, and desktop, menus, and nemo are additionally
LGPL-2.0, while settings-daemon is additionally LGPL-2.1.
cjs is MIT or LGPL-2.0-or-later. xapps is GPL-3.0 and LGPL-3.0.
See each component's `COPYING` file, plus `COPYING.LIB` or
`COPYING.LESSER` where dual-licensed, for the full text.

Every source-built spec installs the component's license file under
/usr/share/licenses/. Of the 104 published RPMs, 44 carry them: the 40
main packages and four devel variants. The other 60 carry none. The
table lists the 40 main packages that carry them, by package and file.

| RPM | Files under /usr/share/licenses/ |
|-----|----------------------------------|
| cinnamon 6.7.4-4 | COPYING (GPL-2.0) |
| cinnamon-control-center 6.7.2-2 | COPYING (GPL-2.0) |
| cinnamon-desktop 6.7.2-3 | COPYING (GPL-2.0), COPYING.LIB (LGPL-2.0) |
| cinnamon-menus 6.7.0-2 | COPYING (GPL-2.0), COPYING.LIB (LGPL-2.0) |
| cinnamon-rocky-defaults 1.0-9 | LICENSE (GPL-2.0) |
| cinnamon-session 6.7.3-2 | COPYING (GPL-2.0) |
| cinnamon-settings-daemon 6.7.2-4 | COPYING (GPL-2.0), COPYING.LIB (LGPL-2.1) |
| cjs 6.4.0-2 | COPYING (MIT or LGPL-2.0-or-later) |
| gdk-pixbuf-parsers 2.42.12-2 | COPYING (LGPL-2.1) |
| gnome-terminal 3.54.5-1 | COPYING (GPL-3.0), COPYING.GFDL (GFDL 1.3) |
| gtk-layer-shell 0.10.1-1 | LICENSE_LGPL.txt (LGPL-3.0) |
| mozjs115 115.29.0-1 | LICENSE, license.html (MPL 2.0) |
| muffin 6.7.4-4 | COPYING (GPL-2.0) |
| muffin-clutter 6.7.4-4 | COPYING (GPL-2.0) |
| muffin-cogl 6.7.4-4 | COPYING (GPL-2.0) |
| nemo 6.7.4-3 | COPYING (GPL-2.0), COPYING.LIB (LGPL-2.0) |
| python3-pillow 12.3.0-2 | LICENSE (Pillow license) |
| python3-setproctitle 1.3.7-2 | LICENSE (BSD 3-Clause) |
| python3-tinycss2 1.5.1-2 | LICENSE (BSD 3-Clause) |
| python3-webencodings 0.5.1-2 | LICENSE (BSD 2-Clause) |
| python3-xapp 3.0.2-1 | COPYING (LGPL-2.0) |
| xapps-lib 3.3.3-2 | COPYING (GPL-3.0), COPYING.LESSER (LGPL-3.0) |
| cvt 0.1.2-11 | COPYING |
| libXfont2 2.0.9-1 | COPYING |
| libxcvt 0.1.2-11 | COPYING |
| libxklavier 5.4-2 | COPYING.LIB |
| lightdm 1.33.1-1 | COPYING.GPL3 |
| lightdm-gobject 1.33.1-1 | COPYING.LGPL2, COPYING.LGPL3 |
| mint-cursor-themes 1.0.2-1 | copyright |
| mint-l-icons 1.8.0-1 | copyright |
| mint-l-theme 2.0.6-2 | copyright |
| mint-themes 2.3.8-1 | copyright |
| mint-x-icons 1.7.5-1 | copyright |
| mint-y-icons 1.9.2-1 | copyright |
| slick-greeter 2.2.6-2 | COPYING, copyright |
| slick-greeter-cinnamon 2.2.6-2 | COPYING |
| xapp-symbolic-icons 1.1.0-2 | LICENSE, BSD-3-Clause.txt, CC-BY-4.0.txt, CC-BY-SA-4.0.txt, CC0.txt, GPL-3.0.txt, LGPL-3.0.txt, MIT.txt |
| xorg-x11-drv-libinput 1.5.0-2 | COPYING |
| xorg-x11-server-common 21.1.24-2 | COPYING |
| xorg-x11-server-Xorg 21.1.24-2 | COPYING |
