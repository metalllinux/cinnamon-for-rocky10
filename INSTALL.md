# Installing Cinnamon on Rocky Linux 10

## Current status

The repository publishes 64 RPMs. The install set is the 22 runtime package
names in `vm-test/install-set.txt`, and that file is the source of truth.
A fresh Rocky Linux 10.2 VM installs the whole set with a single `dnf
install`. The wallpaper, branding, and the Python dependencies of the
settings app all arrive through the dependency chain, with no manual steps.
The set is verified end-to-end on a fresh VM (single install, GDM Wayland
login, five desktop surfaces), re-verified by `vm-test/run-tests.sh` and by
an enforcing-SELinux smoke test with zero AVC denials. See the README for
the full test results.

## Quick start (recommended)

The recommended method uses a local DNF repository. This lets dnf manage
dependencies and future updates.

1. Clone or copy the project to any directory on the target machine.

2. Run the repository setup script. The script installs `createrepo_c` if
   missing, generates repository metadata when `rpms/repodata/` is absent
   (a fresh clone ships valid metadata, so generation is skipped), writes
   `/etc/yum.repos.d/cinnamon-rocky10.repo`, enables the CRB repository,
   and validates that the repository is readable before finishing.

   ```
   sudo ./repo-setup/setup-repo.sh
   ```

   If the script is not in the current directory, point it at the project
   root.

   ```
   sudo ./repo-setup/setup-repo.sh /path/to/cinnamon-for-rocky10
   ```

3. Install the complete set in one command. The 22 names below are exactly
   the runtime set in `vm-test/install-set.txt`.

   ```
   sudo dnf install -y \
     cinnamon cinnamon-control-center cinnamon-desktop cinnamon-menus \
     cinnamon-rocky-defaults cinnamon-session cinnamon-settings-daemon \
     cjs gdk-pixbuf-parsers gnome-terminal gtk-layer-shell mozjs115 \
     muffin muffin-clutter muffin-cogl nemo \
     python3-pillow python3-setproctitle python3-tinycss2 \
     python3-webencodings python3-xapp xapps-lib
   ```

   dnf resolves every remaining dependency from the local repository and
   the EL10 base repositories. The verified run pulled `rocky-backgrounds`
   (the Gemstone Skies wallpaper files), `rocky-logos` (the Rocky logo),
   `gsettings-desktop-schemas`, and `python3-psutil` automatically, and no
   second `dnf` command was needed.

4. Install the display manager. The Cinnamon set does not include GDM, and
   the verified test environment installed `gdm` together with
   `gnome-shell`, which provides the greeter.

   ```
   sudo dnf install -y gdm gnome-shell
   sudo systemctl enable gdm
   sudo systemctl set-default graphical.target
   ```

5. Reboot and log in at the GDM greeter. Select the Cinnamon (Wayland)
   session. GDM on EL10 is Wayland-only, so that is the session the set
   provides.

## Minimal server (no display manager)

The Quick start covers a machine that is becoming a desktop. This section
covers the same path from the other end. You start on a fresh minimal
Rocky Linux 10.2 server with no display manager, no X server, and no
desktop packages, and you end at the running Cinnamon desktop. That is
the verified minimal-server path. The start-state facts and the GDM
behavior come from a bare-metal minimal server (verified 2026-08-30), and
the install steps are the current set's single `dnf install`,
re-verified end-to-end on a fresh minimal VM on 2026-09-19.

A display manager is required to run a desktop, and a minimal server has
none to start. The procedure therefore has two halves. Steps 1 to 3
install the desktop, step 4 adds the login path, and steps 5 to 6 boot it
and log in. Until step 4 changes the default target, the machine stays at
the command line.

1. Get the project onto the machine. Clone or copy
   `metalllinux/cinnamon-for-rocky10` to any directory, keeping
   `repo-setup/` and `rpms/` (the 64 RPMs and the `repodata/` directory)
   intact. Verify the transfer by comparing the sha256 sums of the RPMs
   on both sides. The bare-metal run diffed the manifests and the diff
   was empty.

2. Run the repository setup script from the project root.

   ```
   sudo ./repo-setup/setup-repo.sh
   ```

   The success marker is `=== Repository setup complete ===` with exit
   code 0.

3. Install the complete set, the 22 names from Quick start step 3.

   ```
   sudo dnf install -y \
     cinnamon cinnamon-control-center cinnamon-desktop cinnamon-menus \
     cinnamon-rocky-defaults cinnamon-session cinnamon-settings-daemon \
     cjs gdk-pixbuf-parsers gnome-terminal gtk-layer-shell mozjs115 \
     muffin muffin-clutter muffin-cogl nemo \
     python3-pillow python3-setproctitle python3-tinycss2 \
     python3-webencodings python3-xapp xapps-lib
   ```

   The set pulls in no display manager and no X server. dnf installs only
   the dependencies the set declares, none of the 22 names declares a
   display manager or an X server, and `xorg-x11-server-Xorg` is in no
   Rocky 10.2 repository. The graphics pull-in is the mesa Wayland stack
   plus X11 link-time libraries.

4. Install the display manager and switch the default target.

   ```
   sudo dnf install -y gdm gnome-shell
   sudo systemctl enable gdm
   sudo systemctl set-default graphical.target
   ```

   GDM enables itself in its post-install step. `systemctl is-enabled
   gdm` reports `enabled` immediately after the install (verified on the
   bare-metal server), so the `enable` line is a no-op kept for parity
   with the Quick start. The load-bearing line is `set-default
   graphical.target`. A minimal install defaults to `multi-user.target`,
   under which GDM, though enabled, never starts and the machine stays at
   the getty on tty1.

5. Reboot, or start GDM on the running system.

   ```
   sudo reboot
   ```

   `sudo systemctl start gdm` brings the greeter up without a reboot.

6. At the GDM greeter, select the "Cinnamon (Wayland)" session and log in.
   The verified end state is the full desktop. The panel, the wallpaper,
   the terminal, the settings app, and the main menu all work, and
   `loginctl` reports the session as `Type=wayland`.

The X11 path is a dead end on this target. `xorg-x11-server-Xorg` is in
no Rocky 10.2 repository, so the X11 session file that the `cinnamon` RPM
ships, `/usr/share/xsessions/cinnamon.desktop`, has no X server to run
on. The working session is "Cinnamon (Wayland)". X11 applications still
work inside it, through Xwayland, which the GDM install pulls in.

## Manual repository setup

If you prefer not to use the setup script, follow these steps.

1. Install createrepo_c.
```
sudo dnf install -y createrepo_c
```

2. Generate repository metadata in the rpms/ directory.
```
sudo createrepo_c /path/to/cinnamon-for-rocky10/rpms/
```

3. Create `/etc/yum.repos.d/cinnamon-rocky10.repo` with the following
   content, replacing the baseurl with the absolute path to your rpms/
   directory.
```
[cinnamon-rocky10]
name=Cinnamon for Rocky Linux 10 (local)
baseurl=file:///path/to/cinnamon-for-rocky10/rpms/
enabled=1
gpgcheck=0
metadata_expire=0
module_hotfixes=0
keepcache=0
```

4. Enable CRB.
```
sudo dnf config-manager --set-enabled crb
```

5. Install the complete set with the single command from Quick start step
   3, then install the display manager as in Quick start step 4 and
   reboot.

## Direct RPM install (fallback)

Without a repository, dnf still resolves dependency order when given all
the RPMs at once.
```
sudo dnf install ./rpms/*.rpm
```
This is the path the `vm-test/run-tests.sh` harness uses. The 2026-09-19
re-verification installed all 64 RPMs this way on the first attempt, with
no `--allowerasing` and no ordered-install fallback. Use this method only
if the repository method is not feasible. The packages still register in
the rpm database and in dnf history, so `dnf remove` works on them as
usual. What this method gives up is repository origin. dnf has no source
to update these packages from, so a newer version requires a repository
or a newer local build.

## Prerequisites

A fresh minimal Rocky Linux 10.2 system. The single `dnf install` resolves
every runtime dependency from the local repository and the EL10 base
repositories, so no manual dependency list is required. The verified runs
needed none. The setup script enables the CRB repository automatically,
and the manual path enables it in step 4.

## Installed packages

The 22 runtime packages in `vm-test/install-set.txt`, with the versions
published in `rpms/`.

| Package | Version | Purpose |
|---------|---------|---------|
| cinnamon | 6.7.4-3.el10 | Desktop shell. Bundles the Cinnamon Settings app and the cinnamon-wayland session |
| cinnamon-control-center | 6.7.2-1.el10 | System Settings app (32 panels) |
| cinnamon-desktop | 6.7.2-2.el10 | Desktop library. The 2.el10 rebuild composites photo wallpapers on Wayland |
| cinnamon-menus | 6.7.0-1.el10 | Menu configuration |
| cinnamon-rocky-defaults | 1.0-2.el10 | Rocky branding. Sets the Gemstone Skies wallpaper and the Rocky logo on the menu button |
| cinnamon-session | 6.7.3-1.el10 | Session manager |
| cinnamon-settings-daemon | 6.7.2-2.el10 | Settings daemon |
| cjs | 6.4.0-1.el10 | Cinnamon JavaScript environment |
| gdk-pixbuf-parsers | 2.42.12-2.el10 | PNG and JPEG image loaders. EL10's gdk-pixbuf2 ships none, and photo wallpapers render black without them |
| gnome-terminal | 3.54.5-1.el10 | Terminal. Newest release compatible with EL10's vte291 0.78.6 |
| gtk-layer-shell | 0.10.1-1.el10 | Wayland layer-shell library for the desktop background |
| mozjs115 | 115.29.0-1.el10 | SpiderMonkey JavaScript engine runtime |
| muffin | 6.7.4-3.el10 | Cinnamon window manager compositor, built with Wayland |
| muffin-clutter | 6.7.4-3.el10 | Muffin Clutter rendering library |
| muffin-cogl | 6.7.4-3.el10 | Muffin Cogl rendering library |
| nemo | 6.7.4-2.el10 | File manager and desktop icons |
| python3-pillow | 12.3.0-2.el10 | Settings app dependency (image handling) |
| python3-setproctitle | 1.3.7-2.el10 | Settings app dependency (process title) |
| python3-tinycss2 | 1.5.1-2.el10 | Settings app dependency (CSS parsing) |
| python3-webencodings | 0.5.1-2.el10 | Runtime dependency of tinycss2 |
| python3-xapp | 3.0.2-1.el10 | Settings app dependency (XApp API) |
| xapps-lib | 3.3.3-1.el10 | Shared Cinnamon application libraries |

## GDM session configuration

The `cinnamon` RPM ships both session files. Verify they exist after
installing.
```
ls /usr/share/wayland-sessions/cinnamon-wayland.desktop /usr/share/xsessions/cinnamon.desktop
```

Use the Wayland session. GDM on EL10 is Wayland-only, so the greeter offers
"Cinnamon (Wayland)" even though the X11 session file is present.

Restart GDM after installing the set.
```
sudo systemctl restart gdm
```

## Troubleshooting

### Wallpaper renders black

Photo wallpapers need the PNG and JPEG image loaders and the
cinnamon-desktop compositing fix. The published set ships both
(`gdk-pixbuf-parsers`, `cinnamon-desktop-6.7.2-2.el10`), so a complete
install should not hit this. If you installed a partial set, check both
packages.
```
rpm -q gdk-pixbuf-parsers cinnamon-desktop
```

### SELinux denials

The set ran an enforcing-SELinux smoke test on 2026-09-19 with zero AVC
denials, so the shipped policy covers the default session. If you see
denials after adding software of your own, inspect them.
```
sudo ausearch -m avc -ts recent
```

Set permissive mode temporarily to confirm the desktop itself is not the
cause.
```
sudo setenforce 0
```

Restore enforcing mode when you are done.
```
sudo setenforce 1
```

### Repository not found

If dnf reports the cinnamon-rocky10 repository is not found:
- Verify the .repo file exists at `/etc/yum.repos.d/cinnamon-rocky10.repo`.
- Check that the `baseurl` path in the .repo file points to a directory containing `repodata/`.
- Run `dnf makecache` to refresh repository metadata.

### Missing libraries

Check for missing shared libraries:
```
ldd /usr/lib64/libcinnamon-desktop.so.4 | grep "not found"
```
