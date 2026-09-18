Name:           cinnamon-control-center
Version:        6.7.2
Release:        1.el10
Summary:        Cinnamon desktop control center

License:        GPLv2+
URL:            https://github.com/linuxmint/cinnamon-control-center
Source0:        %{name}-%{version}.tar.gz
# Source0 provenance (verified 2026-09-18 by full tree diff against upstream):
#   content = linuxmint/cinnamon-control-center @ acbe1b999a54 (2026-07-27,
#   "build: Remove desktop-file-links.py, bump meson requirement."). Upstream
#   does not tag release versions; fetchable content ref (top dir
#   cinnamon-control-center-acbe1b999a54):
#     https://github.com/linuxmint/cinnamon-control-center/archive/acbe1b999a54.tar.gz
#   sha256 of this build tarball (git archive, top dir cinnamon-control-center-6.7.2/):
#     c7a8c5a7e063effc4e316201c4adffad5d6d6149973f99060d839a7189cf6da5

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
# BuildRequires:  polkit-gobject-devel >= 0.103  # not available
# BuildRequires:  upower-glib-devel >= 0.99.8  # not available
# BuildRequires:  gudev-devel  # not available
# BuildRequires:  gnome-desktop-devel  # not available
BuildRequires:  libcanberra-devel
BuildRequires:  libsecret-devel
BuildRequires:  colord-devel
BuildRequires:  cups-devel
BuildRequires:  gsettings-desktop-schemas
BuildRequires:  accountsservice-devel
# BuildRequires:  gtk-vnc-devel  # not available
# BuildRequires:  libgdata-devel  # not available
# BuildRequires:  modemmanager-devel  # not available, disabled in meson
BuildRequires:  NetworkManager-libnm-devel
# BuildRequires:  libnma-devel  # not available
# BuildRequires:  cinnamon-settings-daemon-devel  # not packaged as devel
BuildRequires:  xapps-devel
BuildRequires:  gettext

%description
Cinnamon control center provides the system settings application
for configuring the Cinnamon desktop environment.

%package devel
Summary:        Development files for %{name}
Requires:       %{name} = %{version}-%{release}

%description devel
Development files for %{name}.

%prep
%setup -q

%build
meson setup builddir \
    --prefix=%{_prefix} \
    --libdir=%{_libdir} \
    --buildtype=plain \
    -Dnetworkmanager=false \
    -Dmodemmanager=false \
    -Dcolor=false \
    -Ddeprecated_warnings=false
ninja -C builddir -j2

%install
DESTDIR=%{buildroot} ninja -C builddir install
: %find_lang %{name} --with-gnome || :

%post -p /sbin/ldconfig
%postun -p /sbin/ldconfig

%files
%{_bindir}/cinnamon-control-center
%{_libdir}/libcinnamon-control-center.so.*
%{_libdir}/cinnamon-control-center-1/panels/*.so
%{_datadir}/cinnamon-control-center
%{_datadir}/applications/cinnamon-wacom-panel.desktop
%{_datadir}/glib-2.0/schemas/org.cinnamon.control-center.*
%{_datadir}/icons/hicolor/*/apps/cinnamon-preferences-desktop-display.*

%files devel
%{_includedir}/cinnamon-control-center-1
%{_libdir}/libcinnamon-control-center.so
%{_libdir}/pkgconfig/libcinnamon-control-center.pc

%changelog
* Sun Aug 10 2026 Team Chaotix <chaotix@metallinux.dev> - 6.7.2-1
- Initial port to Rocky Linux 10
- Disabled networkmanager, modemmanager, and color panels
