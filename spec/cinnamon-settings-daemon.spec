Name:           cinnamon-settings-daemon
Version:        6.7.2
Release:        2.el10
Summary:        Daemon handling Cinnamon settings

License:        GPLv2+
URL:            https://github.com/linuxmint/cinnamon-settings-daemon
Source0:        %{name}-%{version}.tar.gz
# Source0 provenance (verified 2026-09-18 by full tree diff against upstream):
#   content = linuxmint/cinnamon-settings-daemon @ 18bb726dc21a (2026-07-12,
#   "csd-xsettings-manager.c: Fix fcitx support for xwayland clients.").
#   Upstream does not tag release versions; fetchable content ref (top dir
#   cinnamon-settings-daemon-18bb726dc21a):
#     https://github.com/linuxmint/cinnamon-settings-daemon/archive/18bb726dc21a.tar.gz
#   sha256 of this build tarball (git archive, top dir cinnamon-settings-daemon-6.7.2/):
#     1141da2de844de68ac6ddbd24a9cb48295c0790507e09b46ff24f1048c10cd93

Requires:       gtk-layer-shell

BuildRequires:  meson >= 0.56.0
BuildRequires:  ninja-build
BuildRequires:  gcc
BuildRequires:  pkgconf-pkg-config
BuildRequires:  glib2-devel >= 2.40
BuildRequires:  gtk3-devel >= 3.14
BuildRequires:  libcanberra-devel
BuildRequires:  cinnamon-desktop-devel >= 4.8.0
BuildRequires:  fontconfig-devel
BuildRequires:  libnotify-devel >= 0.7.3
# BuildRequires:  upower-glib-devel >= 0.99.11  # not available
BuildRequires:  libwacom-devel >= 0.7
BuildRequires:  colord-devel
BuildRequires:  cups-devel
BuildRequires:  nss-devel
# BuildRequires:  polkit-gobject-devel >= 0.97  # not available, feature disabled
BuildRequires:  systemd-devel
# BuildRequires:  gudev-devel  # not available, feature disabled
BuildRequires:  libX11-devel
BuildRequires:  libXext-devel
BuildRequires:  libXi-devel
BuildRequires:  lcms2-devel
BuildRequires:  dbus-devel
BuildRequires:  gtk-layer-shell-devel
BuildRequires:  wayland-devel
BuildRequires:  gettext

%description
Cinnamon settings daemon handles system-wide settings like keyboard,
mouse, display, power management, and other hardware configuration
for the Cinnamon desktop environment.

%prep
%setup -q

%build
meson setup builddir \
    --prefix=%{_prefix} \
    --libdir=%{_libdir} \
    --buildtype=plain \
    -Duse_color=disabled \
    -Duse_cups=disabled \
    -Duse_smartcard=disabled \
    -Duse_gudev=disabled \
    -Duse_wacom=disabled \
    -Duse_polkit=disabled \
    -Duse_logind=disabled \
    -Dgtk_layer_shell=true
ninja -C builddir -j2

%install
DESTDIR=%{buildroot} ninja -C builddir install
: %find_lang %{name} --with-gnome || :

%post -p /sbin/ldconfig
%postun -p /sbin/ldconfig

%files
/etc/xdg/autostart/cinnamon-settings-daemon-*.desktop
%{_libexecdir}/csd-*
%{_bindir}/csd-*
%{_libdir}/cinnamon-settings-daemon/csd-*
%{_datadir}/cinnamon-settings-daemon-3.0
%{_datadir}/dbus-1/system-services/org.cinnamon.SettingsDaemon.DateTimeMechanism.service
%{_datadir}/dbus-1/system.d/org.cinnamon.SettingsDaemon.DateTimeMechanism.conf
%{_datadir}/glib-2.0/schemas/org.cinnamon.settings-daemon.*
%{_datadir}/icons/hicolor/*/apps/csd-*.*
%{_datadir}/polkit-1/actions/org.cinnamon.settings*.policy

%changelog
* Wed Sep 16 2026 Team Chaotix <chaotix@metallinux.dev> - 6.7.2-2
- Enable the gtk-layer-shell Wayland backend for the csd-background plugin
  (-Dgtk_layer_shell=true) so the desktop wallpaper renders natively on
  Cinnamon Wayland instead of falling back to the X11 backend, which does
  not composite and leaves the desktop black (TASK-0017 item 2.1).

* Sun Aug 10 2026 Team Chaotix <chaotix@metallinux.dev> - 6.7.2-1
- Initial port to Rocky Linux 10
- Disabled optional dependencies: color, cups, smartcard
