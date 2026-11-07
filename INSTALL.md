# Installing Cinnamon on Rocky Linux 10

## Current status

The repository publishes 104 RPMs. The install set is the 40 runtime package
names in `vm-test/install-set.txt`, and that file is the source of truth.
The wallpaper, branding, the X server, the display manager, and the Python
dependencies of the settings app all arrive through the dependency chain of
those names, with no manual steps. The last fresh-consumer verification
recorded in the project's test results is the 2026-11-07 run of the
104-RPM set, which passed under `gpgcheck=1` with SELinux enforcing
throughout and zero AVC denials on the Rocky Linux 10 test VM. The
harness in this repository (`vm-test/run-tests.sh`) sets SELinux to
permissive.

## Quick start (recommended)

The recommended method uses a local DNF repository. This lets dnf manage
dependencies and future updates.

1. Clone or copy the project to any directory on the target machine.

2. Run the repository setup script. The script installs `createrepo_c`
   and `gnupg2` if missing and generates repository metadata when
   `rpms/repodata/` is absent. A fresh clone has no metadata because
   the `repodata/` directory is not tracked in git, so a fresh clone
   exercises the generation path, and both self-installs work on a
   minimal image, `createrepo_c` from AppStream and `gnupg2` from
   BaseOS. A copy that carries `repodata/` skips generation instead.
   The procedure is correct on both paths. The script then verifies,
   with the `gpg` binary from `gnupg2`, that the repository's public
   GPG key at `keys/cinnamon-rocky10-public.asc` holds exactly the
   tracked key, imports it into the rpm keyring, and writes
   `/etc/yum.repos.d/cinnamon-rocky10.repo` with `gpgcheck=1`, so dnf
   verifies the signature of every package it installs against that key,
   the same model the EL base repositories use. It enables the CRB
   repository and validates that the repository is readable before
   finishing.

   ```
   sudo ./repo-setup/setup-repo.sh
   ```

   If the script is not in the current directory, point it at the project
   root.

   ```
   sudo ./repo-setup/setup-repo.sh /path/to/cinnamon-for-rocky10
   ```

3. Enable EPEL, then install the complete set in one command. The 40
   names below are exactly the runtime set in
   `vm-test/install-set.txt`; `gnome-icon-theme` comes from the EPEL
   repository, which this step enables.

   ```
   sudo dnf install -y epel-release
   ```

   ```
   sudo dnf install -y \
     cinnamon cinnamon-control-center cinnamon-desktop cinnamon-menus \
     cinnamon-rocky-defaults cinnamon-session cinnamon-settings-daemon \
     cjs cvt gdk-pixbuf-parsers gnome-icon-theme gnome-terminal \
     gtk-layer-shell libxcvt libXfont2 libxklavier lightdm \
     lightdm-gobject mint-cursor-themes mint-l-icons mint-l-theme \
     mint-themes mint-x-icons mint-y-icons mozjs115 muffin \
     muffin-clutter muffin-cogl nemo python3-pillow python3-setproctitle \
     python3-tinycss2 python3-webencodings python3-xapp \
     slick-greeter slick-greeter-cinnamon xapp-symbolic-icons xapps-lib \
     xorg-x11-drv-libinput xorg-x11-server-Xorg xorg-x11-server-common
   ```

   dnf resolves every remaining dependency from the local repository and
   the EL10 base repositories. The verified run pulled `gdm` (the
   alternative display manager, kept as a documented option),
   `rocky-backgrounds` (the wallpaper files), `rocky-logos` (the Rocky
   logo), `gsettings-desktop-schemas`, and `python3-psutil` automatically,
   and no second `dnf` command was needed.

4. No display manager step is needed. The set pulls in `lightdm` with the
   slick greeter and `gdm` as the documented alternative, and
   `cinnamon-rocky-defaults` makes lightdm the default display manager
   during the install. Verify the state dnf left behind.

   ```
   systemctl is-enabled lightdm
   systemctl get-default
   ```

   The output is `enabled` and `graphical.target`.

5. Reboot and log in at the lightdm login screen, the slick greeter. The
   login screen shows no session selector, and the active lightdm
   configuration sets no user-session, so the greeter decides which
   session starts. The set installs four sessions, Cinnamon on X11,
   Cinnamon (Wayland), GNOME, and GNOME on Wayland.

## Minimal server (no display manager)

The Quick start covers a machine that is becoming a desktop. This section
covers the same path from the other end. You start on a fresh minimal
Rocky Linux 10.2 server with no display manager, no X server, and no
desktop packages, and you end at the running Cinnamon desktop. That is
the verified minimal-server path. The start-state facts come from a
bare-metal minimal server (verified 2026-08-30), and
the install steps are the current set's single `dnf install`,
re-verified end-to-end on a fresh minimal VM on 2026-09-19.

A display manager is required to run a desktop, and a minimal server has
none to start. The procedure therefore has two halves. Steps 1 to 3
install the desktop, and the set's post-install step sets the display
manager and the default target. Steps 4 to 6 verify that state, boot the
machine, and log in. Until the reboot, the machine stays at the command
line.

1. Get the project onto the machine. Clone or copy
   `metalllinux/cinnamon-for-rocky10` to any directory, keeping
   `repo-setup/` and `rpms/` (the 104 RPMs) intact. A fresh clone has
   no `rpms/repodata/` directory because it is not tracked in git;
   the setup script in step 2 generates it when absent. Verify the
   transfer by comparing the sha256 sums of the RPMs on both sides.
   The bare-metal run diffed the manifests and the diff was empty.

2. Run the repository setup script from the project root.

   ```
   sudo ./repo-setup/setup-repo.sh
   ```

   The success marker is `=== Repository setup complete ===` with exit
   code 0.

3. Enable EPEL, then install the complete set in one command, the same
   command as Quick start step 3, which includes `gnome-icon-theme` from
   the EPEL repository.

   ```
   sudo dnf install -y epel-release
   ```

   ```
   sudo dnf install -y \
     cinnamon cinnamon-control-center cinnamon-desktop cinnamon-menus \
     cinnamon-rocky-defaults cinnamon-session cinnamon-settings-daemon \
     cjs cvt gdk-pixbuf-parsers gnome-icon-theme gnome-terminal \
     gtk-layer-shell libxcvt libXfont2 libxklavier lightdm \
     lightdm-gobject mint-cursor-themes mint-l-icons mint-l-theme \
     mint-themes mint-x-icons mint-y-icons mozjs115 muffin \
     muffin-clutter muffin-cogl nemo python3-pillow python3-setproctitle \
     python3-tinycss2 python3-webencodings python3-xapp \
     slick-greeter slick-greeter-cinnamon xapp-symbolic-icons xapps-lib \
     xorg-x11-drv-libinput xorg-x11-server-Xorg xorg-x11-server-common
   ```

   The set pulls in its own display manager and X server. `lightdm`,
   `xorg-x11-server-Xorg`, and the rest of the X server and greeter
   stack are in no Rocky 10.2 repository, so the local repository is
   their only source. The remaining graphics pull-in is the mesa
   Wayland stack.

4. Verify the state the install left behind.

   ```
   systemctl is-enabled lightdm
   systemctl is-enabled gdm
   systemctl get-default
   ```

   The `cinnamon-rocky-defaults` post-install step enables lightdm,
   disables GDM, and sets the default target to `graphical.target`. A
   minimal install defaults to `multi-user.target`, under which no display
   manager starts and the machine stays at the getty on tty1, so the
   target switch is what brings the login screen up at boot. The output
   is `enabled`, `disabled`, and `graphical.target`.

5. Reboot.

   ```
   sudo reboot
   ```

   `sudo systemctl start lightdm` brings the greeter up without a reboot.

6. Log in at the lightdm login screen, the slick greeter. The screen shows
   no session selector, and the set installs the Cinnamon session on X11,
   and Cinnamon (Wayland), GNOME, and GNOME on Wayland. The full-desktop
   end state was verified on the 2026-09-19 minimal-server run, which
   used GDM and the Cinnamon (Wayland) session, and `loginctl` reports
   that session as `Type=wayland`.

The X11 path is no longer a dead end. `xorg-x11-server-Xorg` is in no
Rocky 10.2 repository, but the set ships it, and lightdm runs it as its
X server, so the X11 session file that the `cinnamon` RPM ships,
`/usr/share/xsessions/cinnamon.desktop`, has an X server to run on.
X11 applications also work inside the Wayland sessions, through Xwayland.

## Manual repository setup

If you prefer not to use the setup script, follow these steps.

1. Install createrepo_c and gnupg2.
```
sudo dnf install -y createrepo_c gnupg2
```

2. Generate repository metadata in the rpms/ directory.
```
sudo createrepo_c /path/to/cinnamon-for-rocky10/rpms/
```

3. Verify the key file, then import the repository's public GPG key into
   the rpm keyring, from the project root. The check runs `gpg` from
   the `gnupg2` package, installed by step 1.
```
gpg --with-colons --show-keys keys/cinnamon-rocky10-public.asc
```
The output must show exactly two `fpr:` lines, the primary's
fingerprint `2274BFE1BF28C051CD98675BEBD13108EB7FEF99` and the signing
subkey's fingerprint `CD4958E1A421CBD6B56B7C5614CF2C0A8A47323C`. If the
file shows any other key, it is not the tracked key, and the import must
not run. The setup script performs this same check before its import.
```
sudo rpm --import keys/cinnamon-rocky10-public.asc
```
The key is at `keys/cinnamon-rocky10-public.asc`. The import fills the
rpm keyring, which dnf uses for the `gpgcheck=1` verification in step 4
and which the "Verifying the release" checks use for `rpm --checksig`.
Importing a key that is already present is a no-op, so a re-run is safe.

4. Create `/etc/yum.repos.d/cinnamon-rocky10.repo` with the following
   content, replacing the clone path in `baseurl=` with the absolute path
   of your clone. The block is the same file the setup script writes,
   with no `gpgkey=` line.
```
[cinnamon-rocky10]
name=Cinnamon for Rocky Linux 10 (local)
baseurl=file:///home/howard/cinnamon-for-rocky10/rpms
enabled=1
gpgcheck=1
metadata_expire=0
module_hotfixes=0
keepcache=0
```
The `gpgcheck=1` line turns on signature verification. dnf verifies every
package signature against the rpm keyring step 3 populated, and refuses
any package that does not verify. The setup script path is the
live-verified one, and this block is the same shape as what it writes for
the same clone path, so the manual steps produce the same repo file. If
you move the clone, update the `baseurl=` line.

5. Enable CRB and EPEL.
```
sudo dnf config-manager --set-enabled crb
sudo dnf install -y epel-release
```

6. Install the complete set with the single command from Quick start step
   3, then reboot. No display manager step is needed, the set includes
   lightdm and makes it the default display manager.

## Direct RPM install (fallback)

Without a repository, dnf still resolves dependency order when given all
the RPMs at once.
```
sudo dnf install ./rpms/*.rpm
```
This is the path the `vm-test/run-tests.sh` harness uses. The 2026-09-19
re-verification installed all 104 RPMs this way on the first attempt, with
no `--allowerasing` and no ordered-install fallback. Use this method only
if the repository method is not feasible. The packages still register in
the rpm database and in dnf history, so `dnf remove` works on them as
usual. What this method gives up is repository origin. dnf has no source
to update these packages from, so a newer version requires a repository
or a newer local build.

## Verifying the release

The released set is pinned to a git tag and carries two independent
checks, one for each failure mode that a plain install would not catch.
The first signed release, `v1.0.0`, pins the original 64-RPM set and
is signed with the original key (fingerprint
`1689676AF4D4F6FEC142B4429C0A8912FDA02785`). Every republish after it
gets a new tag, because the set is only ever published forward at a new
tag. The currently published release, `v1.0.1`, pins the 64-RPM set and is
signed with the tracked key (fingerprint
`2274BFE1BF28C051CD98675BEBD13108EB7FEF99`). The 104-RPM set in the
working tree is the next republish and is only ever published forward at
a new tag. Clone at the tag that pins the set you want to verify, so
both checks run against exactly what the tag pins.

```
git clone --depth 1 --branch v1.0.1 https://github.com/metalllinux/cinnamon-for-rocky10
cd cinnamon-for-rocky10
```

### The sha256 manifest, corruption and drift

The manifest is `rpms/SHA256SUMS`, a sha256 list of every RPM the tag
pins, generated from the signed bytes and committed to the repository.

```
cd rpms
sha256sum -c SHA256SUMS
cd ..
```

Every line must report `OK`. This check answers one question. Is the
copy you have, byte for byte, the set the tag released. It catches a
corrupted copy, a partial clone, and a `rpms/` directory that has drifted
from the manifest. What it cannot catch is a tree in which both the RPMs
and the manifest were changed together, because the check compares the
copy to the tree, and the tree is its own baseline.

### The GPG signature, origin tampering

Every RPM in the set is signed with the repository's private key. dnf
verifies the signature of every package it installs once the key is
imported, whether by `setup-repo.sh` in Quick start or by step 3 of the
manual path. An attacker without the private key cannot re-sign, so a set
that dnf accepts under `gpgcheck=1` is a set the key holder signed. You
can verify the same thing directly, without dnf. The `gpg` command
comes from the `gnupg2` package, which a fresh minimal install does not
carry, so install it first if it is missing.
```
sudo dnf install -y gnupg2
```

```
gpg --with-colons --show-keys keys/cinnamon-rocky10-public.asc
sudo rpm --import keys/cinnamon-rocky10-public.asc
for f in rpms/*.rpm; do rpm --checksig "$f"; done
```

The key file must show exactly two `fpr:` lines, the primary's
fingerprint `2274BFE1BF28C051CD98675BEBD13108EB7FEF99` and the signing
subkey's fingerprint `CD4958E1A421CBD6B56B7C5614CF2C0A8A47323C`. The
import must not run if it shows any other key. Every RPM must then
report `digests signatures OK`. Before trusting the key, compare the
primary fingerprint against the value published out-of-band on
metalinux.dev. The key file served by the repository is not an
independent source of trust.

### Why both

The division of labor is the point, and it is why a complete check runs
both. The manifest verifies the copy against the trusted baseline pinned
at the tag, and catches transfer corruption and drift. The signature
verifies the origin, and catches a tampered set that a matching manifest
would accept, because re-signing needs the private key. A set that passes
both is the set that was released, and the copy that arrived is the set
that was signed.

## Prerequisites

A fresh minimal Rocky Linux 10.2 system. The single `dnf install` resolves
every runtime dependency from the local repository and the EL10 base
repositories, so no manual dependency list is required. The verified runs
needed none. The setup script enables the CRB repository automatically,
and the manual path enables it in step 5.

## Installed packages

The 40 runtime packages in `vm-test/install-set.txt`, with the versions
published in `rpms/`, plus `gnome-icon-theme` from the EPEL repository.

| Package | Version | Purpose |
|---------|---------|---------|
| cinnamon | 6.7.4-4.el10 | Desktop shell. Bundles the Cinnamon Settings app and the cinnamon-wayland session |
| cinnamon-control-center | 6.7.2-2.el10 | System Settings app (32 panels) |
| cinnamon-desktop | 6.7.2-3.el10 | Desktop library. The 2.el10 rebuild composites photo wallpapers on Wayland |
| cinnamon-menus | 6.7.0-2.el10 | Menu configuration |
| cinnamon-rocky-defaults | 1.0-9.el10 | Rocky branding. Sets the Gemstone Skies wallpaper and the Rocky logo, and makes lightdm the default display manager |
| cinnamon-session | 6.7.3-2.el10 | Session manager |
| cinnamon-settings-daemon | 6.7.2-4.el10 | Settings daemon |
| cjs | 6.4.0-2.el10 | Cinnamon JavaScript environment |
| cvt | 0.1.2-11.el10 | Video timing calculator, built and installed by the libxcvt build |
| gdk-pixbuf-parsers | 2.42.12-2.el10 | PNG and JPEG image loaders. EL10's gdk-pixbuf2 ships none, and photo wallpapers render black without them |
| gnome-icon-theme | 3.12.0-25.el10_1 | Icon theme. Provides the gnome icon theme and the preferences-desktop icons the settings app uses |
| gnome-terminal | 3.54.5-1.el10 | Terminal. Newest release compatible with EL10's vte291 0.78.6 |
| gtk-layer-shell | 0.10.1-1.el10 | Wayland layer-shell library for the desktop background |
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
| mozjs115 | 115.29.0-1.el10 | SpiderMonkey JavaScript engine runtime |
| muffin | 6.7.4-4.el10 | Cinnamon window manager compositor, built with Wayland |
| muffin-clutter | 6.7.4-4.el10 | Muffin Clutter rendering library |
| muffin-cogl | 6.7.4-4.el10 | Muffin Cogl rendering library |
| nemo | 6.7.4-3.el10 | File manager and desktop icons |
| python3-pillow | 12.3.0-2.el10 | Settings app dependency (image handling) |
| python3-setproctitle | 1.3.7-2.el10 | Settings app dependency (process title) |
| python3-tinycss2 | 1.5.1-2.el10 | Settings app dependency (CSS parsing) |
| python3-webencodings | 0.5.1-2.el10 | Runtime dependency of tinycss2 |
| python3-xapp | 3.0.2-1.el10 | Settings app dependency (XApp API) |
| slick-greeter | 2.2.6-2.el10 | Login greeter for lightdm |
| slick-greeter-cinnamon | 2.2.6-2.el10 | Cinnamon variant of the slick greeter |
| xapp-symbolic-icons | 1.1.0-2.el10 | Symbolic icons for XApp applications |
| xapps-lib | 3.3.3-2.el10 | Shared Cinnamon application libraries |
| xorg-x11-drv-libinput | 1.5.0-2.el10 | libinput X input driver, hard dependency of Xorg |
| xorg-x11-server-common | 21.1.24-2.el10 | Shared X server files and configuration |
| xorg-x11-server-Xorg | 21.1.24-2.el10 | X server, run by lightdm for the greeter and the X11 session |

## Display manager session configuration

The `cinnamon` RPM ships both session files. Verify they exist after
installing.
```
ls /usr/share/wayland-sessions/cinnamon-wayland.desktop /usr/share/xsessions/cinnamon.desktop
```

Both sessions are runnable. lightdm runs Xorg as its X server, so the
X11 session has an X server, and the Wayland sessions run on the
compositor. The verified desktop run used the Cinnamon (Wayland)
session.

Restart the active display manager after installing the set.
```
sudo systemctl restart lightdm
```

## Switching to GDM

GDM is installed with the set, but lightdm is the default display
manager. To switch back to GDM:
```
sudo systemctl disable lightdm
sudo systemctl enable gdm
sudo reboot
```

## Troubleshooting

### Wallpaper renders black

Photo wallpapers need the PNG and JPEG image loaders and the
cinnamon-desktop compositing fix. The published set ships both
(`gdk-pixbuf-parsers`, `cinnamon-desktop-6.7.2-3.el10`), so a complete
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
