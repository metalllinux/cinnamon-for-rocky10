# Installing Cinnamon RPMs on Fresh Rocky Linux 10

## Current status

**All 14 base packages install cleanly.** See the README for version details and test results.

## Quick start (recommended)

The recommended installation method uses a local DNF repository. This approach lets dnf manage
dependencies and future updates automatically.

1. Clone or copy the project to any directory on the target machine.

2. Run the repository setup script. The script installs `createrepo_c` if missing, generates
   repository metadata, and installs a `.repo` file to `/etc/yum.repos.d/`:

```
sudo ./repo-setup/setup-repo.sh
```

If the script is not in the current directory, point it at the project root:

```
sudo ./repo-setup/setup-repo.sh /path/to/cinnamon-for-rocky10
```

3. Install Cinnamon and its core components:

```
sudo dnf install cinnamon
```

This installs the shell and its hard dependencies (cjs, muffin, muffin-clutter,
muffin-cogl, cinnamon-desktop, xapps-lib, cinnamon-menus, mozjs115). Five additional
packages are not hard dependencies and must be installed separately:

```
sudo dnf install cinnamon-session cinnamon-settings-daemon cinnamon-control-center \
  nemo mozjs115-devel
```

Without these, the settings panel, session manager, and file manager will be missing.

4. Refresh the library cache:

```
sudo ldconfig
```

The setup script handles all prerequisites: enabling the CRB repository and installing
`createrepo_c`. It also validates that the repository is readable before finishing.

## Manual repository setup

If you prefer not to use the setup script, follow these steps:

1. Install createrepo_c:
```
sudo dnf install -y createrepo_c
```

2. Generate repository metadata in the rpms/ directory:
```
sudo createrepo_c /path/to/cinnamon-for-rocky10/rpms/
```

3. Create `/etc/yum.repos.d/cinnamon-rocky10.repo` with the following content, replacing the
   baseurl with the absolute path to your rpms/ directory:
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

4. Enable CRB:
```
sudo dnf config-manager --set-enabled crb
```

5. Install Cinnamon and its core components:
```
sudo dnf install cinnamon
```

6. Install remaining components (settings panel, session manager, file manager):
```
sudo dnf install cinnamon-session cinnamon-settings-daemon cinnamon-control-center \
  nemo mozjs115-devel
```

7. Refresh library cache:
```
sudo ldconfig
```

## Direct RPM install (fallback)

Without a repository, dnf still resolves dependency order when given all RPMs at once:
```
sudo dnf install ./rpms/*.rpm
```

This method works but skips repository features like `dnf remove` tracking and update
notifications. Use it only if the repository method is not feasible.

## Prerequisites

Before installing Cinnamon, enable the CRB repository and install base dependencies:

1. Enable CRB (CodeReady Builder):
```
sudo dnf config-manager --set-enabled crb
```

2. Install base dependencies:
```
sudo dnf install -y gtk3 glib2 graphene libX11 libXrandr libXdamage \
  libXext libXfixes libXi libXtst libICE libSM libxkbfile libwacom \
  pipewire libdrm pulseaudio-libs libcanberra systemd gobject-introspection \
  iso-codes xkeyboard-config cairo pango harfbuzz gdk-pixbuf2 \
  libxml2 dbus atk at-spi2-atk fontconfig mesa-libEGL json-glib \
  startup-notification readline
```

The setup script enables CRB automatically. The base dependency list is required regardless of
installation method.

## Installed packages

| Package | Version | Purpose |
|---------|---------|---------|
| mozjs115 | 115.29.0-1.el10 | SpiderMonkey JavaScript engine runtime |
| mozjs115-devel | 115.29.0-1.el10 | mozjs115 headers and pkg-config |
| cjs | 6.4.0-1.el10 | GNOME JavaScript environment |
| muffin | 6.7.4-3.el10 | Cinnamon window manager compositor |
| muffin-clutter | 6.7.4-3.el10 | Muffin Clutter rendering library |
| muffin-cogl | 6.7.4-3.el10 | Muffin Cogl rendering library |
| cinnamon-desktop | 6.7.2-1.el10 | Desktop library and applet framework |
| xapps-lib | 3.3.3-1.el10 | Shared Cinnamon application libraries |
| cinnamon-session | 6.7.3-1.el10 | Session manager |
| cinnamon-settings-daemon | 6.7.2-1.el10 | Settings daemon |
| cinnamon-control-center | 6.7.2-1.el10 | Settings panel |
| cinnamon-menus | 6.7.0-1.el10 | Menu configuration |
| nemo | 6.7.4-1.el10 | File manager |
| cinnamon | 6.7.4-1.el10 | Cinnamon desktop shell |

## GDM session configuration

Cinnamon creates a .desktop session file. Verify it exists after installing the cinnamon RPM:
```
ls /usr/share/xsessions/cinnamon.desktop
```

Restart GDM:
```
sudo systemctl restart gdm
```

Log out and select "Cinnamon" from the session menu.

## Troubleshooting

### SELinux denials

If Cinnamon fails to start with AVC denials:
```
sudo ausearch -m avc -ts recent
```

Temporarily set permissive mode:
```
sudo setenforce 0
```

Once troubleshooting is complete, restore enforcing mode:
```
sudo setenforce 1
```

### Repository not found

If dnf reports the cinnamon-rocky10 repository is not found:
- Verify the .repo file exists at `/etc/yum.repos.d/cinnamon-rocky10.repo`.
- Check that the `baseurl` path in the .repo file points to a directory containing `repodata/`.
- Run `dnf makecache` to refresh repository metadata.

### Missing libraries

Check for missing dependencies:
```
ldd /usr/lib64/libcinnamon-desktop.so.4 | grep "not found"
```

### mozjs115 runtime

The mozjs115 runtime RPM is built from Mozilla ESR source. It is not available in standard Rocky Linux 10 repositories. Install the `mozjs115-115.29.0-1.el10.x86_64.rpm` from the `rpms/` directory before installing cjs.
