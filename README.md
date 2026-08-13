# Cinnamon for Rocky Linux 10

Bringing the Cinnamon Desktop to Rocky Linux 10.

## Status

**Build date:** 2026-08-13
**Target:** Rocky Linux 10.2 (Red Quartz)

| Component | Version | Build | Install |
|-----------|---------|-------|---------|
| mozjs115 | 115.29.0 | ✅ Built | ✅ Installs |
| cinnamon-desktop | 6.7.2 | ✅ Built | ✅ Installs |
| cjs | 6.4.0 | ✅ Built | ✅ Installs |
| muffin | 6.7.4-3 | ✅ Built | ✅ Installs |
| xapps-lib | 3.3.3 | ✅ Built | ✅ Installs |
| cinnamon-session | 6.7.3 | ✅ Built | ✅ Installs |
| cinnamon-settings-daemon | 6.7.2 | ✅ Built | ✅ Installs |
| cinnamon-control-center | 6.7.2 | ✅ Built | ✅ Installs |
| nemo | 6.7.4 | ✅ Built | ✅ Installs |
| cinnamon | 6.7.4 | ✅ Built | ✅ Installs |

**All 10 base packages install cleanly in a fresh Rocky Linux 10.2 VM.** RPMs in `rpms/` directory (48 total, including debuginfo and devel packages).

## Build notes

- Builds use `meson` + `ninja` with `-j2` (2 parallel jobs)
- muffin built X11-only (no Wayland, no native backend)
- mozjs115 115.29.0 built from Mozilla ESR source (ftp.mozilla.org), spec adapted from Fedora 44 with 10 patches
- cjs 6.4.0 pairs with mozjs115 115.29.0. cjs 140.0 upgrade blocked by GLib 2.86 and SpiderMonkey 140 API requirements (unavailable on EL10)
- All RPMs built on Rocky Linux 10.2 with CRB enabled

## Test results

VM testing was run on a clean Rocky Linux 10.2 VM (2 vCPU, 4096 MB RAM, libvirt/KVM).

| Phase | Result | Details |
|-------|--------|---------|
| RPM install | 10 of 10 base packages installed | All 10 base packages plus debuginfo/devel install on first attempt via `dnf install *.rpm` |
| Dependency verification | 0 circular dependencies | muffin-clutter circular dependency resolved in 6.7.4-3.el10 |
| Library verification | 7 of 7 binaries pass ldd | All tested binaries have zero missing shared libraries |
| Binary version checks | 1 of 7 confirmed | cjs 6.4.0 confirmed. Version checks for X11 binaries skipped (Xvfb unavailable in EL10 repos) |

**Summary:** 10 PASS, 0 FAIL, 6 SKIP. All SKIPs are environment limitations (Xvfb unavailable, binaries without --version flags), not code issues.

## Installation

See [INSTALL.md](INSTALL.md) for step-by-step RPM installation on a fresh Rocky Linux 10 system.

## Project structure

```
spec/              - RPM spec files (EL10 adapted)
rpms/              - Built RPM packages
src/               - Source code references
vm-test/           - VM testing harness and test scripts
INSTALL.md         - Installation instructions
```

## Development

This project is developed by [Team Chaotix](https://github.com/metalllinux/team-chaotix)
using opencode on Rocky Linux 10.2.

## License

Cinnamon components are under their respective upstream licenses (GPL-2.0, LGPL-2.0, MIT).
See individual component LICENSE files.
