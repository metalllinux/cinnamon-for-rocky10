# Cinnamon for Rocky Linux 10

Bringing the Cinnamon Desktop to Rocky Linux 10.

## Status

**Build date:** 2026-08-11
**Target:** Rocky Linux 10.2 (Red Quartz)

| Component | Version | Status |
|-----------|---------|--------|
| cinnamon-desktop | 6.7.2 | Built, RPMs available |
| cjs | 6.4.0 | Built, installed |
| muffin | 6.7.4 | Built, installed |
| xapps | — | Pending |
| cinnamon-session | — | Pending |
| cinnamon-settings-daemon | — | Pending |
| cinnamon-control-center | — | Pending |
| nemo | — | Pending |
| cinnamon | — | Pending |

## Build notes

- Builds use `meson` + `ninja` with `-j2` (2 parallel jobs)
- muffin built X11-only (no Wayland, no native backend)
- mozjs115 headers extracted from Fedora 44 RPM
- All RPMs built on Rocky Linux 10.2 with CRB enabled

## Installation

See [INSTALL.md](INSTALL.md) for step-by-step RPM installation on a fresh Rocky Linux 10 system.

## Project structure

```
spec/              - RPM spec files (EL10 adapted)
rpms/              - Built RPM packages
src/               - Source code references
INSTALL.md         - Installation instructions
```

## Development

This project is developed by [Team Chaotix](https://github.com/metalllinux/team-chaotix)
using opencode on Rocky Linux 10.2.

## License

Cinnamon components are under their respective upstream licenses (GPL-2.0, LGPL-2.0, MIT).
See individual component LICENSE files.
