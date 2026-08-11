# Installing Cinnamon RPMs on Fresh Rocky Linux 10

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
  libstartup-notification readline mozjs115-devel
```

## Install Order

Install RPMs in dependency order:

1. Foundation packages:
```
sudo dnf install ./rpms/mozjs115-devel-*.rpm
sudo dnf install ./rpms/cjs-*.rpm
sudo dnf install ./rpms/muffin-*.rpm
```

2. Shared libraries:
```
sudo dnf install ./rpms/cinnamon-desktop-*.rpm
sudo dnf install ./rpms/cinnamon-desktop-devel-*.rpm
sudo dnf install ./rpms/xapps-*.rpm
sudo dnf install ./rpms/cinnamon-session-*.rpm
```

3. Desktop components:
```
sudo dnf install ./rpms/cinnamon-settings-daemon-*.rpm
sudo dnf install ./rpms/cinnamon-control-center-*.rpm
sudo dnf install ./rpms/nemo-*.rpm
sudo dnf install ./rpms/cinnamon-*.rpm
```

4. Refresh library cache:
```
sudo ldconfig
```

## GDM Session Configuration

Cinnamon creates a .desktop session file. Verify it exists:
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
ldd /usr/local/lib64/libcinnamon-desktop.so.4 | grep "not found"
```

### mozjs115 not found
The mozjs115 library is extracted from Fedora 44 RPMs and installed
manually. If pkg-config cannot find it:
```
sudo cp /usr/lib64/pkgconfig/mozjs-115.pc /usr/lib64/pkgconfig/
```
