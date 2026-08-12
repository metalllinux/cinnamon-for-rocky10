Name:           cinnamon-settings-daemon
Version:        6.7.2
Release:        1.el10
Summary:        Daemon handling Cinnamon settings

License:        GPLv2+
URL:            https://github.com/linuxmint/cinnamon-settings-daemon
Source0:        https://github.com/linuxmint/cinnamon-settings-daemon/archive/refs/tags/%{version}.tar.gz#/cinnamon-settings-daemon-%{version}.tar.gz

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
BuildRequires:  upower-glib-devel >= 0.99.11
BuildRequires:  libwacom-devel >= 0.7
BuildRequires:  colord-devel
BuildRequires:  cups-devel
BuildRequires:  nss-devel
BuildRequires:  polkit-gobject-devel >= 0.97
BuildRequires:  systemd-devel
BuildRequires:  gudev-devel
BuildRequires:  libX11-devel
BuildRequires:  libXext-devel
BuildRequires:  libXi-devel
BuildRequires:  lcms2-devel
BuildRequires:  dbus-devel
BuildRequires:  gettext

%description
Cinnamon settings daemon handles system-wide settings like keyboard,
mouse, display, power management, and other hardware configuration
for the Cinnamon desktop environment.

%prep
%setup -q

%build
%meson \
    -Duse_color=disabled \
    -Duse_cups=disabled \
    -Duse_smartcard=disabled \
    -Duse_gudev=disabled \
    -Duse_wacom=disabled \
    -Duse_polkit=disabled \
    -Duse_logind=disabled \
    -Ddeprecated_warnings=false
%ninja_build

%install
%ninja_install
%find_lang %{name} --with-gnome

%post -p /sbin/ldconfig
%postun -p /sbin/ldconfig

%files -f %{name}.lang
%{_bindir}/cinnamon-settings-daemon
%{_libexecdir}/cinnamon-settings-daemon
%{_datadir}/cinnamon-settings-daemon
%{_datadir}/dbus-1/services/org.cinnamon.settings_daemon.service
%{_datadir}/glib-2.0/schemas/org.cinnamon.settings-daemon.*
%{_datadir}/polkit-1/actions/org.cinnamon.settings-daemon.peripherals.wacom.policy
%dir %{_libdir}/cinnamon-settings-daemon-3.0
%{_libdir}/cinnamon-settings-daemon-3.0/plugins
%{_mandir}/man1/cinnamon-settings-daemon.1*

%changelog
* Sun Aug 10 2026 Team Chaotix <chaotix@metallinux.dev> - 6.7.2-1
- Initial port to Rocky Linux 10
- Disabled optional dependencies: color, cups, smartcard
