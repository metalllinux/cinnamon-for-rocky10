Name:           cinnamon-control-center
Version:        6.7.2
Release:        1.el10
Summary:        Cinnamon desktop control center

License:        GPLv2+
URL:            https://github.com/linuxmint/cinnamon-control-center
Source0:        https://github.com/linuxmint/cinnamon-control-center/archive/refs/tags/%{version}.tar.gz#/cinnamon-control-center-%{version}.tar.gz

BuildRequires:  meson >= 0.64.0
BuildRequires:  ninja-build
BuildRequires:  gcc
BuildRequires:  pkgconf-pkg-config
BuildRequires:  glib2-devel >= 2.44
BuildRequires:  gtk3-devel >= 3.16
BuildRequires:  cinnamon-desktop-devel >= 4.6.0
BuildRequires:  cinnamon-menus-devel
BuildRequires:  libnotify-devel >= 0.7.3
BuildRequires:  libX11-devel
BuildRequires:  polkit-gobject-devel >= 0.103
BuildRequires:  upower-glib-devel >= 0.99.8
BuildRequires:  gudev-devel
BuildRequires:  gnome-desktop-devel
BuildRequires:  libcanberra-devel
BuildRequires:  libsecret-devel
BuildRequires:  colord-devel
BuildRequires:  cups-devel
BuildRequires:  gsettings-desktop-schemas
BuildRequires:  accountsservice-devel
BuildRequires:  gtk-vnc-devel
BuildRequires:  libgdata-devel
BuildRequires:  modemmanager-devel
BuildRequires:  NetworkManager-libnm-devel
BuildRequires:  libnma-devel
BuildRequires:  cinnamon-settings-daemon-devel
BuildRequires:  xapps-devel
BuildRequires:  gettext

%description
Cinnamon control center provides the system settings application
for configuring the Cinnamon desktop environment.

%prep
%setup -q

%build
%meson \
    -Dnetworkmanager=false \
    -Dmodemmanager=false \
    -Dcolor=false \
    -Ddeprecated_warnings=false
%ninja_build

%install
%ninja_install
%find_lang %{name} --with-gnome

%post -p /sbin/ldconfig
%postun -p /sbin/ldconfig

%files -f %{name}.lang
%{_bindir}/cinnamon-control-center
%{_libdir}/libcinnamon-control-center.so.*
%{_datadir}/cinnamon-control-center
%{_datadir}/applications/cinnamon-control-center*.desktop
%{_datadir}/glib-2.0/schemas/org.cinnamon.control-center.*
%dir %{_libdir}/cinnamon-control-center
%{_libdir}/cinnamon-control-center/cc-panels
%{_mandir}/man1/cinnamon-control-center.1*

%changelog
* Sun Aug 10 2026 Team Chaotix <chaotix@metallinux.dev> - 6.7.2-1
- Initial port to Rocky Linux 10
- Disabled networkmanager, modemmanager, and color panels
