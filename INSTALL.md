# Installing Cinnamon RPMs on Fresh Rocky Linux 10

## Current status

**All 10 base packages install cleanly.** See the README for version details and test results.

## Prerequisites

1. Enable CRB (CodeReady Builder) repository:
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

## Quick install

All RPMs install in a single batch. dnf resolves the dependency order automatically:
```
sudo dnf install ./rpms/*.rpm
```

## Step-by-step install

If you prefer to install in dependency order:

1. Foundation libraries:
```
sudo dnf install ./rpms/mozjs115-115.29.0-1.el10.x86_64.rpm
sudo dnf install ./rpms/mozjs115-devel-115.29.0-1.el10.x86_64.rpm
sudo dnf install ./rpms/cinnamon-desktop-*.rpm
sudo dnf install ./rpms/xapps-lib-*.rpm
sudo dnf install ./rpms/cinnamon-menus-*.rpm
```

2. JavaScript engine and compositor:
```
sudo dnf install ./rpms/cjs-*.rpm
sudo dnf install ./rpms/muffin-*.rpm
```

3. Session and settings:
```
sudo dnf install ./rpms/cinnamon-session-*.rpm
sudo dnf install ./rpms/cinnamon-settings-daemon-*.rpm
```

4. Desktop components:
```
sudo dnf install ./rpms/cinnamon-control-center-*.rpm
sudo dnf install ./rpms/nemo-*.rpm
sudo dnf install ./rpms/cinnamon-*.rpm
```

5. Refresh library cache:
```
sudo ldconfig
```

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

### Missing libraries

Check for missing dependencies:
```
ldd /usr/lib64/libcinnamon-desktop.so.4 | grep "not found"
```

### mozjs115 runtime

The mozjs115 runtime RPM is built from Mozilla ESR source. It is not available in standard Rocky Linux 10 repositories. Install the `mozjs115-115.29.0-1.el10.x86_64.rpm` from the `rpms/` directory before installing cjs.
